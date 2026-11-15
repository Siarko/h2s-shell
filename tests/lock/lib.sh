# Helpers for the lock test bed: sourced by run.sh into a fresh bash for each test, then
# the test file is sourced after it. See README.md for the why of each safety measure.
#
# run.sh hands over, in the environment:
#   LOCKTEST_DIR           this directory
#   LOCKTEST_SHELL         the copy of the checkout the shell under test runs from
#   LOCKTEST_TOOLS         the store path tools.nix built (bin/, share/)
#   LOCKTEST_PAM_MODULES   the PAM module directory matching Quickshell's libpam
#   LOCKTEST_LAUNCHER      the h2s-shell launcher
#   LOCKTEST_QS            the qs the launcher runs the shell with
#   LOCKTEST_ARTIFACTS     this test's directory for logs and screenshots
#   LOCKTEST_RUN_ID        a marker every process of the run carries, for the final sweep
#   LOCKTEST_RUNTIME       this test's private, short runtime dir (run.sh removes it)
#
# run.sh starts this bash with no new privileges (setpriv --no-new-privs): everything
# below inherits that, so no setuid program (pkexec, unix_chkpwd) gains anything.

set -uo pipefail

LOCKTEST_PASSWORD="lt-test-pass-42"
# The answer the "password-question" stack wants to its second question
LOCKTEST_ANSWER="lt-answer-7"
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
RUN=${LOCKTEST_RUNTIME:-}
[ -n "$RUN" ] && [ -d "$RUN" ] && [ -O "$RUN" ] && [ -z "$(ls -A "$RUN")" ] \
    || abort "no fresh private runtime dir from run.sh (LOCKTEST_RUNTIME=$RUN)"
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
    QS_CONFIG_NAME DESKTOP_STARTUP_ID XDG_ACTIVATION_TOKEN WAYLAND_SOCKET PIPEWIRE_REMOTE \
    PIPEWIRE_RUNTIME_DIR PULSE_SERVER

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
    # The dir itself is run.sh's to remove (also when this bash is killed)
    rm -rf "${RUN:?}"/* 2> /dev/null
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
#
# --methods "password fingerprint"   the methods the shell is told of, each a test stack
#                                    of that name; `password=password-question` names
#                                    another stack for a method
# --methods-script <file>            a methods script of the test's own instead (a failing
#                                    one, one naming a stack that is not there); what it
#                                    names is checked before anything is typed
#                                    (_password_stack_is_safe)
# --logind                           stand-ins for `gdbus` and `systemd-inhibit` (the
#                                    shell takes them from H2S_LOCK_TOOLS), and a session id:
#                                    logind's signals are delivered with logind_signal,
#                                    the inhibitor's holds and releases recorded (see
#                                    _write_logind_standins)
# --system-password-stack            the test's "system-wide" h2s-shell-password (in
#                                    $WORK/system-pam, the shell's H2S_LOCK_SYSTEM_PAM_DIR)
#                                    is the test password stack, so the shell's password
#                                    FALLBACK can unlock; by default it is a config that
#                                    denies everything. Either way the fallback is a config of
#                                    this test's, never the system's (_password_stack_is_safe)
stack_start() {
    local methods="password" methods_script="" logind=0 system_password=deny
    while [ $# -gt 0 ]; do
        case "$1" in
            --methods) methods=$2; shift 2 ;;
            --methods-script) methods_script=$2; shift 2 ;;
            --logind) logind=1; shift ;;
            --system-password-stack) system_password=stack; shift ;;
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
    INPUT_PID=$SPAWNED_PID
    wait_until 10 grep -q ready "$WORK/input.log" || abort "the input client did not start (see input.log)"

    _write_pam_stacks "$methods" "$methods_script"
    _write_system_pam "$system_password"

    local tools="" session_id=""
    if [ "$logind" = 1 ]; then
        _write_logind_standins
        tools=$WORK/standins
        session_id=$LOCKTEST_SESSION_ID
    fi

    # The shell, as it is started for real: the launcher with H2S_SHELL_DIR pointing at
    # the run's copy of the checkout (run.sh), a plain start (never --restart, which stops
    # every h2s-shell it finds)
    H2S_LOCK_TOOLS=$tools XDG_SESSION_ID=$session_id H2S_LOCK_SYSTEM_PAM_DIR=$WORK/system-pam \
    H2S_SHELL_DIR=$LOCKTEST_SHELL H2S_LOCK_AUTH_METHODS=$WORK/pam/methods.sh QT_QPA_PLATFORM=wayland \
        spawn "$WORK/shell.log" "$LOCKTEST_LAUNCHER"
    local timeout_pid=$SPAWNED_PID
    wait_until 10 pgrep -P "$timeout_pid" || abort "the launcher did not start"
    SHELL_PID=$(pgrep -P "$timeout_pid" | head -n 1)
    wait_until 30 shell_ipc lockscreen status || abort "the shell's IPC does not answer (see shell.log)"
    log "stack up: Hyprland $HYPRLAND_INSTANCE_SIGNATURE, shell pid $SHELL_PID, methods: ${methods_script:-$methods}${tools:+, logind stand-ins}"
}

# The PAM stacks and the methods script the shell is pointed at (H2S_LOCK_AUTH_METHODS)
_write_pam_stacks() {
    local methods=$1 methods_script=${2:-} file
    local bash_path coreutils
    # Without a password method the shell falls back to a config of its own for the
    # password: typed test strings must only ever reach the test stack
    if [ -z "$methods_script" ]; then
        case " $methods " in
            *" password "* | *" password="*) ;;
            *) abort "the methods ($methods) must include password" ;;
        esac
    fi
    # The paths go into sed replacements and PAM lines: plain characters only
    local path
    for path in "$LOCKTEST_PAM_MODULES" "$WORK"; do
        [[ "$path" =~ ^/[A-Za-z0-9._/+-]*$ ]] || abort "a path with characters a PAM stack cannot hold: $path"
    done
    bash_path=$(command -v bash)
    coreutils=$(dirname "$(dirname "$(readlink -f "$(command -v rm)")")")
    for file in password password-question fingerprint check-password.sh check-answer.sh wait-finger.sh; do
        sed -e "s|@PAM_MODULES@|$LOCKTEST_PAM_MODULES|g" -e "s|@WORK@|$WORK|g" \
            -e "s|@BASH@|$bash_path|g" -e "s|@COREUTILS@|$coreutils/bin|g" \
            -e "s|@FINGER_DIR@|$WORK/finger|g" -e "s|@PASSWORD@|$LOCKTEST_PASSWORD|g" \
            -e "s|@ANSWER@|$LOCKTEST_ANSWER|g" -e "s|@QS_BINARY@|$(_quickshell_binary)|g" \
            "$LOCKTEST_DIR/pam/$file" > "$WORK/pam/$file"
    done
    chmod +x "$WORK/pam/"*.sh
    if [ -n "$methods_script" ]; then
        cp "$methods_script" "$WORK/pam/methods.sh"
        chmod +x "$WORK/pam/methods.sh"
        return
    fi
    local method name config
    {
        echo "#!$bash_path"
        echo "# Written by tests/lock/lib.sh: the methods this test offers"
        echo "cat << 'EOF'"
        for method in $methods; do
            name=${method%%=*}
            config=${method#*=}
            printf '%s\t%s\t%s\n' "$name" "$WORK/pam" "$config"
        done
        echo "EOF"
    } > "$WORK/pam/methods.sh"
    chmod +x "$WORK/pam/methods.sh"
}

# The directory the shell takes for the system's PAM configs (H2S_LOCK_SYSTEM_PAM_DIR): the
# shell's password fallback is chosen from it (LockIoRules.passwordFallback) — and on this
# machine the real /etc/pam.d may well hold a readable h2s-shell-password, or `login` would
# be chosen (NixOS). Here it is a directory of the test's own, holding either a config that
# denies everything or the test password stack; `login` is never there, so on NixOS without
# the file the fallback is a config PAM cannot start.
_write_system_pam() {
    mkdir -p "$WORK/system-pam"
    if [ "$1" = stack ]; then
        cp "$WORK/pam/password" "$WORK/system-pam/h2s-shell-password"
    else
        {
            echo "# Written by tests/lock/lib.sh: the test's stand-in for /etc/pam.d/h2s-shell-password; denies"
            echo "auth     required $LOCKTEST_PAM_MODULES/pam_deny.so"
            echo "account  required $LOCKTEST_PAM_MODULES/pam_deny.so"
        } > "$WORK/system-pam/h2s-shell-password"
    fi
}

# ---- logind stand-ins (stack_start --logind) -----------------------------------------
# The real system bus is cut off from the test bed, so logind's signals cannot reach the
# shell. Two stand-ins are named to it instead, by H2S_LOCK_TOOLS (its seam, like the
# methods one: scripts/lock-auth-methods.sh), nothing else in the shell knows:
#
#   gdbus            `gdbus call … GetSession <id>` answers this test's session path;
#                    `gdbus monitor …` prints, as gdbus would, every line appended to
#                    logind/signals after it started (logind_signal writes them), and
#                    notes each start in logind/log ("monitor <pid>")
#   systemd-inhibit  notes "hold <pid>" in logind/log, runs the command it was given (the
#                    shell's `read -r release`) and notes "release <pid>" when that ends
#
# The shell runs with XDG_SESSION_ID=$LOCKTEST_SESSION_ID.
LOCKTEST_SESSION_ID=lt1
LOCKTEST_SESSION_PATH=/org/freedesktop/login1/session/_lt1
_write_logind_standins() {
    local bash_path coreutils
    bash_path=$(command -v bash)
    coreutils=$(dirname "$(dirname "$(readlink -f "$(command -v rm)")")")/bin
    mkdir -p "$WORK/standins" "$WORK/logind"
    : > "$WORK/logind/signals"
    : > "$WORK/logind/log"
    cat > "$WORK/standins/gdbus" << EOF
#!$bash_path
# Stand-in for gdbus in the lock test bed (tests/lock/lib.sh): no bus is reached
log=$WORK/logind/log
signals=$WORK/logind/signals
case "\$1" in
    call)
        for argument in "\$@"; do last=\$argument; done
        echo "call GetSession \$last" >> "\$log"
        if [ "\$last" = "$LOCKTEST_SESSION_ID" ]; then
            echo "(objectpath '$LOCKTEST_SESSION_PATH',)"
            exit 0
        fi
        echo "Error: GDBus.Error:org.freedesktop.login1.NoSuchSession: No session '\$last' known" >&2
        exit 1
        ;;
    monitor)
        start=\$(( \$($coreutils/wc -l < "\$signals") + 1 ))
        echo "monitor \$\$" >> "\$log"
        exec $coreutils/tail -n +"\$start" -F "\$signals" 2> /dev/null
        ;;
esac
exit 1
EOF
    cat > "$WORK/standins/systemd-inhibit" << EOF
#!$bash_path
# Stand-in for systemd-inhibit in the lock test bed (tests/lock/lib.sh): no bus is reached
log=$WORK/logind/log
while [ "\${1#--}" != "\$1" ]; do shift; done
echo "hold \$\$" >> "\$log"
"\$@"
status=\$?
echo "release \$\$" >> "\$log"
exit \$status
EOF
    chmod +x "$WORK/standins/gdbus" "$WORK/standins/systemd-inhibit"
}

# logind_signal <lock|unlock|unlock-other|sleep|wake>: one line as `gdbus monitor` prints it
logind_signal() {
    local line
    case "$1" in
        lock) line="$LOCKTEST_SESSION_PATH: org.freedesktop.login1.Session.Lock ()" ;;
        unlock) line="$LOCKTEST_SESSION_PATH: org.freedesktop.login1.Session.Unlock ()" ;;
        unlock-other) line="/org/freedesktop/login1/session/_99: org.freedesktop.login1.Session.Unlock ()" ;;
        sleep) line="/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (true,)" ;;
        wake) line="/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (false,)" ;;
        *) abort "logind_signal: unknown signal $1" ;;
    esac
    echo "$line" >> "$WORK/logind/signals"
    log "logind stand-in: $1"
}
# logind_signals <signal>...: several at once, in one write — the monitor reads them in one
# go, so the shell handles them in the same pass of its event loop (e.g. `lock unlock`:
# the Unlock arrives before the compositor can have confirmed the lock)
logind_signals() {
    local name lines="" line
    for name in "$@"; do
        case "$name" in
            lock) line="$LOCKTEST_SESSION_PATH: org.freedesktop.login1.Session.Lock ()" ;;
            unlock) line="$LOCKTEST_SESSION_PATH: org.freedesktop.login1.Session.Unlock ()" ;;
            *) abort "logind_signals: unsupported signal $name" ;;
        esac
        lines="$lines$line"$'\n'
    done
    printf '%s' "$lines" >> "$WORK/logind/signals"
    log "logind stand-in: $* (one write)"
}
# The stand-in inhibitor's record: holds and releases, in order ("hold release hold")
inhibitor_record() { awk '$1 == "hold" || $1 == "release" { printf "%s ", $1 }' "$WORK/logind/log"; }
# Whether the stand-in inhibitor is held right now: more holds than releases
inhibitor_held() { [ "$(grep -c '^hold' "$WORK/logind/log")" -gt "$(grep -c '^release' "$WORK/logind/log")" ]; }
inhibitor_released() { ! inhibitor_held; }
logind_monitor_running() { grep -q '^monitor' "$WORK/logind/log" && pgrep -f "tail -n .* -F $WORK/logind/signals" > /dev/null; }

# The binary Quickshell's processes run (its PAM helper among them): the wrapper's target
_quickshell_binary() {
    local binary
    binary=$(dirname "$LOCKTEST_QS")/.quickshell-wrapped
    [ -e "$binary" ] || binary=$LOCKTEST_QS
    readlink -f "$binary"
}

# ---- Talking to the shell -----------------------------------------------------------

# shell_ipc <target> <function> [args...]. Addressed by process id inside the private
# runtime dir: the real shell is not in that registry, and has another pid anyway.
shell_ipc() {
    [ "$XDG_RUNTIME_DIR" = "$RUN" ] || abort "shell_ipc outside the private runtime dir"
    "$LOCKTEST_QS" ipc --pid "$SHELL_PID" call "$@"
}

# The JSON the shell's `lockscreen state` returns (LockRules.describe(state) plus the
# driver's own facts under `driver`), one fact by name. THE one place that knows where each
# fact lives in that JSON: tests ask for facts by these names, so a change in the shell's
# state shape is mended here. A name not in the table is taken as a dotted path
# (state_field phase.lastEnd). Booleans come out as true/false, nothing as "".
#
#   secure               the compositor confirmed the lock (WlSessionLock.secure)
#   locked               the shell's view says locked (locking or locked)
#   phase / session / last_end     the rules' phase: status, session number, how the last lock ended
#   armed                locked, confirmed, the methods known: a typed password is checked
#   prompt_awake / prompt_surface / prompt_screen   where the prompt shows (asleep: false / "" / "")
#   surfaces / surface_screens     the lock surface instances the rules know, and their screens
#   password_config      the password's PAM config, directory/name ("" while unknown)
#   password_status      idle / pending / verifying / asking / failed / unavailable
#   verifying / error / refusal / placeholder / question / field_epoch   as the prompt shows them
#   methods_status / methods_generation      the methods script's answer: unknown / detecting / known
#   fingerprint_available / fingerprint_status / fingerprint_waiting / fingerprint_conversation
#   sleep / inhibitor    the sleep region: awake / suspending / resuming; held / released
#   has_secret           a typed password is held by the rules right now
#   logind_session       the logind session path the shell follows ("" for none)
#   lock_scope           the per-lock adapters exist
#   inhibitor_running    a systemd-inhibit process of the shell runs
#   password_fallback    the rules' password fallback config, directory/name ("" for none)
#   fallback_known       the driver has looked at the machine for it (until then: the shipped one)
#   watch_files          Quickshell.watchFiles (off while locked: no reload)
#   unlocking / pending  an unlock decided before the compositor confirmed, and by what
#   notice               the prompt's notice line ("Waiting for the compositor…")
#   timers               the names of the rules' timers running, comma-separated
state_field() {
    shell_ipc lockscreen state | python3 -I -c '
import json, sys
state = json.load(sys.stdin)
def config_path(config):
    return config["directory"] + "/" + config["config"] if config else ""
def conversation(region):
    return region["conversation"]["id"] if region.get("conversation") else ""
facts = {
    "secure": lambda s: s["driver"]["secure"],
    "locked": lambda s: s["view"]["locked"],
    "phase": lambda s: s["phase"]["status"],
    "session": lambda s: s["phase"]["session"],
    "last_end": lambda s: s["phase"].get("lastEnd", ""),
    "armed": lambda s: s["phase"]["status"] == "locked" and s["methods"]["status"] == "known",
    "prompt_awake": lambda s: s["view"]["promptSurface"] is not None,
    "prompt_surface": lambda s: s["view"]["promptSurface"],
    "prompt_screen": lambda s: s["view"]["promptScreen"],
    "surfaces": lambda s: len(s["prompt"]["surfaces"]),
    "surface_screens": lambda s: ",".join(surface["screen"] for surface in s["prompt"]["surfaces"]),
    "password_config": lambda s: config_path(s["methods"]["configs"].get("password")),
    "password_status": lambda s: s["password"]["status"],
    "verifying": lambda s: s["view"]["busy"],
    "error": lambda s: s["view"]["error"],
    "refusal": lambda s: s["view"]["refusal"],
    "placeholder": lambda s: s["view"]["placeholder"],
    "question": lambda s: s["password"]["question"],
    "field_epoch": lambda s: s["view"]["fieldEpoch"],
    "methods_status": lambda s: s["methods"]["status"],
    "methods_generation": lambda s: s["methods"]["generation"],
    "fingerprint_available": lambda s: s["passive"]["fingerprint"]["config"] is not None,
    "fingerprint_status": lambda s: s["passive"]["fingerprint"]["status"],
    "fingerprint_waiting": lambda s: s["passive"]["fingerprint"]["status"] == "running",
    "fingerprint_conversation": lambda s: conversation(s["passive"]["fingerprint"]),
    "sleep": lambda s: s["sleep"]["status"],
    "inhibitor": lambda s: s["sleep"]["inhibitor"],
    "has_secret": lambda s: s["hasSecret"],
    "logind_session": lambda s: s["driver"]["logindSession"],
    "lock_scope": lambda s: s["driver"]["lockScope"],
    "inhibitor_running": lambda s: s["driver"]["inhibitorRunning"],
    "password_fallback": lambda s: config_path(s["settings"]["passwordFallback"]),
    "fallback_known": lambda s: s["driver"]["passwordFallbackKnown"],
    "watch_files": lambda s: s["driver"]["watchFiles"],
    "unlocking": lambda s: s["view"]["unlocking"],
    "pending": lambda s: (s["phase"].get("pending") or {}).get("reason", ""),
    "notice": lambda s: s["view"]["notice"],
    "timers": lambda s: ",".join(s["timers"]),
}
name = sys.argv[1]
if name in facts:
    value = facts[name](state)
else:
    value = state
    for key in name.split("."):
        value = value[key]
if value is None:
    value = ""
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

# The inhibitors on the REAL system bus (listed read-only) held by a process of this run,
# by PID: the shell under test must never add one. By PID, not by name: the real shell's
# inhibitor is called h2s-shell too.
run_inhibitors() {
    local pid
    for pid in $(env -u DBUS_SYSTEM_BUS_ADDRESS systemd-inhibit --list --no-pager --no-legend 2> /dev/null \
        | awk '{ for (i = 1; i + 2 <= NF; i++) if ($i ~ /^[0-9]+$/ && $(i + 2) ~ /^[0-9]+$/) { print $(i + 2); break } }'); do
        [ "$(process_env "$pid" LOCKTEST_RUN_ID)" = "$LOCKTEST_RUN_ID" ] && echo "$pid"
    done
}
# That the real list can be read at all (else the check above proves nothing)
real_inhibitor_list_readable() {
    env -u DBUS_SYSTEM_BUS_ADDRESS systemd-inhibit --list --no-pager --no-legend > /dev/null 2>&1
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

# Locks, and makes sure the shell will check a typed password against the test stack and
# nothing else: a shell whose methods script failed falls back to a config of its own.
# `lock_by_ipc --any-safe-config` accepts any config _password_stack_is_safe accepts (the
# tests of a failing methods script or a missing stack).
lock_by_ipc() {
    local check=_password_stack_is_ours_and_safe
    [ "${1:-}" = --any-safe-config ] && check=_password_stack_is_safe
    shell_ipc lockscreen lock > /dev/null
    wait_until 5 "$check" \
        || abort "the shell's password config is '$(state_field password_config 2> /dev/null)', not a test stack: nothing will be typed"
}
_password_stack_is_ours_and_safe() { _password_stack_is_ours && _password_stack_is_safe; }
_password_stack_is_ours() {
    local config
    config=$(state_field password_config) || return 1
    [ "$config" = "$WORK/pam/password" ] || [ "$config" = "$WORK/pam/password-question" ]
}
# Typed text may reach the password config the shell uses now, and — the next attempt after
# a config that cannot be used, or a detection that fails — its password FALLBACK. Both must
# be safe, and the fallback must be the one the shell chose after looking at the machine
# (it is chosen from H2S_LOCK_SYSTEM_PAM_DIR; were that seam lost, the real /etc/pam.d
# would be looked at, and this refuses).
_password_stack_is_safe() {
    local config fallback
    config=$(state_field password_config) || return 1
    _config_is_safe "$config" || return 1
    [ "$(state_field fallback_known)" = true ] || return 1
    fallback=$(state_field password_fallback) || return 1
    [ -z "$fallback" ] || _config_is_safe "$fallback"
}
# A config typed text may reach: a test stack; the test's stand-in for the system-wide
# config (the test stack, or one that denies everything); a config under this test's
# directory that does not exist (PAM cannot start it); or the run's copy of the shipped
# config, which run.sh rewrote to deny everything. Never anything else.
_config_is_safe() {
    local config=$1
    case "$config" in
        "$WORK/pam/password" | "$WORK/pam/password-question") return 0 ;;
        "$WORK/system-pam/h2s-shell-password")
            cmp -s "$config" "$WORK/pam/password" && return 0
            _denies_everything "$config"
            return
            ;;
        "$WORK/"*) [ ! -e "$config" ]; return ;;
        "$LOCKTEST_SHELL/pam/password") _denies_everything "$config"; return ;;
    esac
    return 1
}
# Every line of the config (comments and blank lines aside) is pam_deny
_denies_everything() {
    [ -f "$1" ] && grep -v '^#' "$1" | grep -v '^[[:space:]]*$' | grep -q . \
        && ! grep -v '^#' "$1" | grep -v '^[[:space:]]*$' | grep -qv 'pam_deny\.so$'
}

# ---- Input --------------------------------------------------------------------------

# send_input <command...>: hands lines to the input client, returns once the compositor
# has seen all of them. A dead client is reported as such, with its last words, and the
# write cannot block for long: opening a FIFO nobody reads would wait forever.
send_input() {
    local before
    _input_alive || abort "the input client is not running: $(_input_last_words)"
    before=$(_acknowledged)
    timeout 5 bash -c 'printf "%s\n" "${@:2}" > "$1"' _ "$INPUT_FIFO" "$@" \
        || abort "the input client did not take the input within 5 s ($(_input_alive && echo "alive" || echo "dead: $(_input_last_words)"))"
    local deadline=$((SECONDS + 15))
    until _acknowledged_at_least $((before + $#)); do
        _input_alive || abort "the input client died: $(_input_last_words)"
        [ "$SECONDS" -lt "$deadline" ] || abort "the input client stopped answering (see input.log)"
        sleep 0.05
    done
}
_acknowledged() { cat "$INPUT_FIFO.ack" 2> /dev/null | wc -l; }
_acknowledged_at_least() { [ "$(_acknowledged)" -ge "$1" ]; }
# The client runs under timeout (INPUT_PID): alive while that timeout has a child
_input_alive() { [ -n "${INPUT_PID:-}" ] && pgrep -P "$INPUT_PID" > /dev/null; }
_input_last_words() { tail -n 2 "$WORK/input.log" 2> /dev/null | tr '\n' ' '; }

# Typing goes only to a shell whose password check is safe (see lock_by_ipc)
type_text() {
    _password_stack_is_safe || abort "not typing: the shell's password config ($(state_field password_config 2> /dev/null)) is not a test stack"
    send_input "type $1"
}
press_key() { send_input "key $1"; }
move_pointer() { send_input "abs ${1:-960} ${2:-540} 1920 1080" "move 5 5"; }

# Wakes the prompt by moving the pointer and waits for it to show: a test about
# authentication should not depend on how a waking key is handled (stage 3 tests that).
# The motion is repeated: a lock surface ignores everything in its first 300 ms.
wake_prompt() {
    local attempt
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        move_pointer $((880 + attempt * 4)) 500
        wait_until 0.5 state_is prompt_awake true && return 0
    done
    return 1
}

# ---- Evidence -----------------------------------------------------------------------

screenshot() { grim "$WORK/$1.png" 2> /dev/null && log "screenshot $1.png"; }
# The same as a PPM (<name>.ppm), which plain Python reads
screenshot_ppm() { grim -t ppm "$WORK/$1.ppm" 2> /dev/null && log "screenshot $1.ppm"; }

# reddish_pixels <name>: takes a screenshot (kept as <name>.ppm, a format plain Python
# reads) and counts the clearly red pixels in the middle of the screen, where the prompt
# is. Red is how the prompt shows an error; the corner, where Hyprland puts its own red
# warning, is left out.
#
# The heuristic depends on the built-in theme's error colour being a clear red.
reddish_pixels() {
    grim -t ppm "$WORK/$1.ppm" 2> /dev/null || { echo -1; return; }
    python3 -I -c "$_PPM_READER"'
width, height, pixels = read_ppm(sys.argv[1])
count = 0
for y in range(height * 3 // 10, height * 7 // 10):
    row = y * width * 3
    for x in range(width * 3 // 10, width * 7 // 10):
        red, green, blue = pixels[row + x * 3], pixels[row + x * 3 + 1], pixels[row + x * 3 + 2]
        if red > 150 and red > green * 2 and red > blue * 2:
            count += 1
print(count)' "$WORK/$1.ppm"
}

# prompt_region_changes <name-a> <name-b>: of two screenshots taken with
# `grim -t ppm` (<name>.ppm), the number of pixels in the prompt's area (the middle of the
# screen, as for reddish_pixels) that differ clearly; -1 when one cannot be read
prompt_region_changes() {
    python3 -I -c "$_PPM_READER"'
try:
    width, height, first = read_ppm(sys.argv[1])
    other_width, other_height, second = read_ppm(sys.argv[2])
except Exception:
    print(-1)
    sys.exit()
if (width, height) != (other_width, other_height):
    print(-1)
    sys.exit()
count = 0
for y in range(height * 3 // 10, height * 7 // 10):
    row = y * width * 3
    for x in range(width * 3 // 10, width * 7 // 10):
        offset = row + x * 3
        if max(abs(first[offset + channel] - second[offset + channel]) for channel in range(3)) > 40:
            count += 1
print(count)' "$WORK/$1.ppm" "$WORK/$2.ppm"
}

# A binary PPM (P6) reader for the snippets above
_PPM_READER='
import sys
def read_ppm(path):
    data = open(path, "rb").read()
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
    return int(fields[1]), int(fields[2]), data[position:]
'

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
no_finger_waiters() { [ -z "$(finger_waiters)" ]; }

# lines_more_than <count> <regex> <file>: more than <count> lines of <file> match — for
# waiting on a log to grow (check_within re-runs a command, but the arguments it was given
# were expanded once)
lines_more_than() { [ "$(grep -c -- "$2" "$3" 2> /dev/null)" -gt "$1" ]; }
