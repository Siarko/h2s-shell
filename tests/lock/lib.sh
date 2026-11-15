# Helpers for the lock test bed: sourced by run.sh into a fresh bash for each test, then
# the test file is sourced after it. See README.md for the why of each safety measure.
#
# run.sh hands over, in the environment:
#   LOCKTEST_DIR           this directory
#   LOCKTEST_REPO          the shell checkout under test
#   LOCKTEST_TOOLS         the store path tools.nix built (bin/, share/)
#   LOCKTEST_PAM_MODULES   the PAM module directory matching Quickshell's libpam
#   LOCKTEST_LAUNCHER      the h2s-shell launcher
#   LOCKTEST_QS            the qs the launcher runs the shell with
#   LOCKTEST_ARTIFACTS     this test's directory for logs and screenshots
#   LOCKTEST_RUN_ID        a marker every process of the run carries, for the final sweep

set -uo pipefail

LOCKTEST_PASSWORD="lt-test-pass-42"
# A cap on every process the test bed starts, should every other way of stopping it fail
LOCKTEST_PROCESS_TIMEOUT=${LOCKTEST_PROCESS_TIMEOUT:-300}

WORK=$LOCKTEST_ARTIFACTS
TOOLS=$LOCKTEST_TOOLS
FAILURES=0
PROCESS_GROUPS=()
SHELL_PID=""

log() { printf '    [%s] %s\n' "$(date +%T)" "$*"; }
pass() { printf '    PASS %s\n' "$*"; }
fail() { printf '    FAIL %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
# Setup that went wrong: nothing after it would mean anything
abort() { printf '    FAIL (setup) %s\n' "$*"; FAILURES=$((FAILURES + 1)); exit 1; }

# ---- Isolation ----------------------------------------------------------------------
# Everything below runs with these, set before anything is started. The runtime dir is
# private and short (Unix socket paths are limited to 107 bytes, and Hyprland nests its
# sockets three levels deep in it): every socket — the compositors', Quickshell's
# instance registry, hyprctl's — is looked for there, so nothing can find the real
# session's. D-Bus addresses point at sockets that do not exist: the shell's logind
# monitors and sleep inhibitor fail instead of reaching the real logind. libseat gets a
# backend that does not exist, so the nested compositor cannot open a seat, a DRM device
# or real input devices. HOME and the XDG directories are private, so the user's
# config.json is neither read nor written.
RUN=$(mktemp -d /tmp/lt.XXXXXX) || abort "cannot create a runtime dir"
chmod 700 "$RUN"
mkdir -p "$WORK"/{home,xdg/config,xdg/cache,xdg/data,xdg/state,labwc,hypr,pam,finger}
export XDG_RUNTIME_DIR=$RUN
export HOME=$WORK/home
export XDG_CONFIG_HOME=$WORK/xdg/config XDG_CACHE_HOME=$WORK/xdg/cache
export XDG_DATA_HOME=$WORK/xdg/data XDG_STATE_HOME=$WORK/xdg/state
export DBUS_SESSION_BUS_ADDRESS=unix:path=$RUN/no-session-bus
export DBUS_SYSTEM_BUS_ADDRESS=unix:path=$RUN/no-system-bus
export LIBSEAT_BACKEND=disabled-for-test
export PYTHONDONTWRITEBYTECODE=1
export LOCKTEST_RUN_ID
export PATH=$TOOLS/bin:$PATH
unset WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE HYPRLAND_CMD NOTIFY_SOCKET \
    SWAYSOCK XDG_SESSION_ID XDG_SESSION_TYPE XDG_CURRENT_DESKTOP LABWC_PID QS_CONFIG_PATH \
    QS_CONFIG_NAME DESKTOP_STARTUP_ID XDG_ACTIVATION_TOKEN

stack_stop() {
    local group
    for group in "${PROCESS_GROUPS[@]}"; do kill -TERM -- "-$group" 2> /dev/null; done
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        local alive=0
        for group in "${PROCESS_GROUPS[@]}"; do kill -0 -- "-$group" 2> /dev/null && alive=1; done
        [ $alive = 0 ] && break
        sleep 0.2
    done
    for group in "${PROCESS_GROUPS[@]}"; do kill -KILL -- "-$group" 2> /dev/null; done
    PROCESS_GROUPS=()
    rm -rf "$RUN"
}
trap stack_stop EXIT
trap 'exit 1' INT TERM

# spawn <log> <command...>: in a process group of its own (so it is stopped with all its
# children), with a hard time limit
spawn() {
    local output=$1
    shift
    setsid timeout "$LOCKTEST_PROCESS_TIMEOUT" "$@" > "$output" 2>&1 < /dev/null &
    PROCESS_GROUPS+=($!)
    SPAWNED_PID=$!
}

# wait_until <seconds> <command...>: true as soon as the command succeeds (seconds may
# be fractional). EPOCHREALTIME's separator follows the locale (a comma in Polish), so
# both are stripped to get microseconds.
wait_until() {
    local deadline
    deadline=$(( ${EPOCHREALTIME//[.,]/} + $(awk -v seconds="$1" 'BEGIN { printf "%d", seconds * 1000000 }') ))
    shift
    until "$@" > /dev/null 2>&1; do
        [ "${EPOCHREALTIME//[.,]/}" -ge "$deadline" ] && return 1
        sleep 0.1
    done
}

# check <description> <command...>
check() {
    local description=$1
    shift
    if "$@" > /dev/null 2>&1; then pass "$description"; return 0; fi
    fail "$description"
    return 1
}

# check_within <seconds> <description> <command...>
check_within() {
    local seconds=$1 description=$2
    shift 2
    if wait_until "$seconds" "$@"; then pass "$description"; return 0; fi
    fail "$description (not within ${seconds} s)"
    return 1
}

# ---- The stack ----------------------------------------------------------------------

# stack_start [--methods "password fingerprint"]
#   headless labwc (only a GPU allocator for the nested compositor)
#   └─ Hyprland, nested in it
#       ├─ ltinput.py   persistent virtual keyboard and pointer
#       └─ the shell under test, through the h2s-shell launcher
stack_start() {
    local methods="password"
    while [ $# -gt 0 ]; do
        case "$1" in
            --methods) methods=$2; shift 2 ;;
            *) abort "stack_start: unknown option $1" ;;
        esac
    done

    # Hyprland 0.57 cannot run on the headless backend alone (no allocator); nested in a
    # headless labwc it can. sway does not work as the parent.
    echo '<?xml version="1.0"?><labwc_config/>' > "$WORK/labwc/rc.xml"
    WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_HEADLESS_OUTPUTS=1 \
        spawn "$WORK/labwc.log" labwc -C "$WORK/labwc"
    wait_until 10 test -S "$RUN/wayland-0" || abort "labwc did not start (see labwc.log)"

    # The config must be Lua: Hyprland 0.57 reads hyprland.lua
    cat > "$WORK/hypr/hyprland.lua" << 'EOF'
hl.monitor({ output = "", mode = "1920x1080@60", position = "auto", scale = "1" })
hl.config({
    misc = { allow_session_lock_restore = true, disable_hyprland_logo = true,
             force_default_wallpaper = 0, disable_autoreload = true },
    xwayland = { enabled = false },
    animations = { enabled = false },
    ecosystem = { no_update_news = true, no_donation_nag = true },
})
EOF
    WAYLAND_DISPLAY=wayland-0 AQ_DRM_DEVICES=/nonexistent-drm \
    HYPRLAND_NO_SD_VARS=1 HYPRLAND_NO_SD_NOTIFY=1 HYPRLAND_NO_SD_TARGET=1 \
    HYPRLAND_NO_CRASHREPORTER=1 HYPRLAND_NO_RT=1 \
        spawn "$WORK/hyprland.log" Hyprland -c "$WORK/hypr/hyprland.lua"
    wait_until 15 test -S "$RUN/wayland-1" || abort "Hyprland did not start (see hyprland.log)"
    HYPRLAND_INSTANCE_SIGNATURE=$(ls "$RUN/hypr" | head -n 1)
    export HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY=wayland-1
    wait_until 10 hyprctl monitors || abort "hyprctl cannot reach the nested Hyprland"

    # Input before the shell: a lock client binds its keyboard when it starts, and a seat
    # that gains its first keyboard later loses the first key
    INPUT_FIFO=$WORK/input.fifo
    mkfifo "$INPUT_FIFO"
    spawn "$WORK/input.log" python3 -I "$LOCKTEST_DIR/input/ltinput.py" \
        "$TOOLS/share" "$TOOLS/share/us.xkb" "$INPUT_FIFO"
    wait_until 10 grep -q ready "$WORK/input.log" || abort "the input client did not start (see input.log)"

    _write_pam_stacks "$methods"

    # The shell, as it is started for real: the launcher with H2S_SHELL_DIR pointing at
    # the checkout, a plain start (never --restart, which stops every h2s-shell it finds)
    H2S_SHELL_DIR=$LOCKTEST_REPO H2S_LOCK_AUTH_METHODS=$WORK/pam/methods.sh QT_QPA_PLATFORM=wayland \
        spawn "$WORK/shell.log" "$LOCKTEST_LAUNCHER"
    local timeout_pid=$SPAWNED_PID
    wait_until 10 pgrep -P "$timeout_pid" || abort "the launcher did not start"
    SHELL_PID=$(pgrep -P "$timeout_pid" | head -n 1)
    wait_until 30 shell_ipc lockscreen status || abort "the shell's IPC does not answer (see shell.log)"
    log "stack up: Hyprland $HYPRLAND_INSTANCE_SIGNATURE, shell pid $SHELL_PID, methods: $methods"
}

# The PAM stacks and the methods script the shell is pointed at (H2S_LOCK_AUTH_METHODS)
_write_pam_stacks() {
    local methods=$1 file
    local bash_path coreutils
    bash_path=$(command -v bash)
    coreutils=$(dirname "$(dirname "$(readlink -f "$(command -v rm)")")")
    for file in password fingerprint check-password.sh wait-finger.sh; do
        sed -e "s|@PAM_MODULES@|$LOCKTEST_PAM_MODULES|g" -e "s|@WORK@|$WORK|g" \
            -e "s|@BASH@|$bash_path|g" -e "s|@COREUTILS@|$coreutils/bin|g" \
            -e "s|@FINGER_DIR@|$WORK/finger|g" -e "s|@PASSWORD@|$LOCKTEST_PASSWORD|g" \
            "$LOCKTEST_DIR/pam/$file" > "$WORK/pam/$file"
    done
    chmod +x "$WORK/pam/"*.sh
    local method
    {
        echo "#!$bash_path"
        echo "# Written by tests/lock/lib.sh: the methods this test offers"
        echo "cat << 'EOF'"
        for method in $methods; do
            printf '%s\t%s\t%s\n' "$method" "$WORK/pam" "$method"
        done
        echo "EOF"
    } > "$WORK/pam/methods.sh"
    chmod +x "$WORK/pam/methods.sh"
}

# ---- Talking to the shell -----------------------------------------------------------

# shell_ipc <target> <function> [args...]. Addressed by process id inside the private
# runtime dir: the real shell is not in that registry, and has another pid anyway.
shell_ipc() {
    [ "$XDG_RUNTIME_DIR" = "$RUN" ] || abort "shell_ipc outside the private runtime dir"
    "$LOCKTEST_QS" ipc --pid "$SHELL_PID" call "$@"
}

# The JSON the shell's `lockscreen state` returns, one field by dotted path
# (state_field auth.error); booleans come out as true/false
state_field() {
    shell_ipc lockscreen state | python3 -I -c '
import json, sys
value = json.load(sys.stdin)
for key in sys.argv[1].split("."):
    value = value[key]
print(str(value).lower() if isinstance(value, bool) else value)' "$1"
}
state_is() { [ "$(state_field "$1")" = "$2" ]; }
shell_status_is() { [ "$(shell_ipc lockscreen status)" = "$1" ]; }

# The compositor's own word on the lock
compositor_locked_is() {
    [ "$(hyprctl -j locked | python3 -I -c 'import json,sys; print(str(json.load(sys.stdin)["locked"]).lower())')" = "$1" ]
}
compositor_locked() { compositor_locked_is true; }
compositor_unlocked() { compositor_locked_is false; }

# logind's inhibitors named h2s-shell on the REAL system bus, listed read-only: the shell
# under test must never add one
real_inhibitors() {
    env -u DBUS_SYSTEM_BUS_ADDRESS systemd-inhibit --list --no-pager 2> /dev/null | grep -c 'h2s-shell'
}

# The value of one variable in a process's environment
process_env() { { tr '\0' '\n' < "/proc/$1/environ"; } 2> /dev/null | sed -n "s/^$2=//p"; }

# Every live process of this run, by the marker in its environment
run_processes() {
    local environ pid
    for environ in /proc/[0-9]*/environ; do
        [ -O "$environ" ] || continue
        pid=${environ#/proc/}
        pid=${pid%/environ}
        [ "$(process_env "$pid" LOCKTEST_RUN_ID)" = "$LOCKTEST_RUN_ID" ] && echo "$pid"
    done
}

# A one-line summary of where the lock stands, for the log
describe_lock() {
    log "compositor locked=$(hyprctl -j locked | tr -d ' \n') shell status=$(shell_ipc lockscreen status) state=$(shell_ipc lockscreen state)"
}

lock_by_ipc() { shell_ipc lockscreen lock > /dev/null; }

# ---- Input --------------------------------------------------------------------------

# send <command...>: hands lines to the input client, returns once it has acted on all
send_input() {
    local before
    before=$(_acknowledged)
    printf '%s\n' "$@" > "$INPUT_FIFO"
    wait_until 15 _acknowledged_at_least $((before + $#)) || abort "the input client stopped answering"
}
_acknowledged() { cat "$INPUT_FIFO.ack" 2> /dev/null | wc -l; }
_acknowledged_at_least() { [ "$(_acknowledged)" -ge "$1" ]; }

type_text() { send_input "type $1"; }
press_key() { send_input "key $1"; }
move_pointer() { send_input "abs ${1:-960} ${2:-540} 1920 1080" "move 5 5"; }

# Wakes the prompt by moving the pointer and waits for it to show: a test about
# authentication should not depend on how a waking key is handled (stage 3 tests that).
# The motion is repeated: a lock surface ignores everything in its first 300 ms.
wake_prompt() {
    local attempt
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        move_pointer $((880 + attempt * 4)) 500
        wait_until 0.5 state_is promptActive true && return 0
    done
    return 1
}

# ---- Evidence -----------------------------------------------------------------------

screenshot() { grim "$WORK/$1.png" 2> /dev/null && log "screenshot $1.png"; }

# reddish_pixels <name>: takes a screenshot (kept as <name>.ppm, a format plain Python
# reads) and counts the clearly red pixels in the middle of the screen, where the prompt
# is. Red is how the prompt shows an error; the corner, where Hyprland puts its own red
# warning, is left out.
reddish_pixels() {
    grim -t ppm "$WORK/$1.ppm" 2> /dev/null || { echo -1; return; }
    python3 -I -c '
import sys
data = open(sys.argv[1], "rb").read()
fields, position = [], 0
while len(fields) < 4:
    while data[position:position + 1].isspace():
        position += 1
    if data[position:position + 1] == b"#":
        position = data.index(b"\n", position)
        continue
    end = position
    while not data[end:end + 1].isspace():
        end += 1
    fields.append(data[position:end])
    position = end
position += 1
width, height = int(fields[1]), int(fields[2])
pixels = data[position:]
count = 0
for y in range(height * 3 // 10, height * 7 // 10):
    row = y * width * 3
    for x in range(width * 3 // 10, width * 7 // 10):
        red, green, blue = pixels[row + x * 3], pixels[row + x * 3 + 1], pixels[row + x * 3 + 2]
        if red > 150 and red > green * 2 and red > blue * 2:
            count += 1
print(count)' "$WORK/$1.ppm"
}

# ---- The fingerprint stand-in -------------------------------------------------------

# Live waiting conversations: waiting.<pid> files whose process still exists
finger_waiters() {
    local file
    for file in "$WORK"/finger/waiting.*; do
        [ -e "$file" ] || continue
        local pid=${file##*.}
        kill -0 "$pid" 2> /dev/null && echo "$pid"
    done
}
_one_finger_waiter() { [ "$(finger_waiters | wc -l)" -eq 1 ]; }

# finger <ok|fail>: answers the one live conversation, and waits until it has taken it.
# More than one live conversation is a failure of its own: the shell runs two at once.
finger() {
    if ! wait_until 10 _one_finger_waiter; then
        fail "exactly one fingerprint conversation waiting (found: $(finger_waiters | tr '\n' ' '))"
        return 1
    fi
    local pid
    pid=$(finger_waiters)
    echo "$1" > "$WORK/finger/result.$pid.tmp"
    mv "$WORK/finger/result.$pid.tmp" "$WORK/finger/result.$pid"
    wait_until 5 test ! -e "$WORK/finger/result.$pid" || { fail "conversation $pid did not take its answer"; return 1; }
    log "fingerprint: answered $1 to conversation $pid"
}
