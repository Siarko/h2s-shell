# Helpers for the lock test bed: sourced by run.sh into a fresh bash for each test, then
# the test file is sourced after it. See README.md for the why of each safety measure.
#
# run.sh hands over, in the environment:
#   LOCKTEST_DIR           this directory
#   LOCKTEST_SHELL         the copy of the checkout the shell under test runs from
#   LOCKTEST_TOOLS         the tool set (bin/, share/): the store path tools.nix built, or
#                          the one run.sh made from the system's tools
#   LOCKTEST_PAM_MODULES   the PAM module directory matching Quickshell's libpam
#   LOCKTEST_LAUNCHER      the h2s-shell launcher (or the test bed's launcher.sh)
#   LOCKTEST_QS            the qs the launcher runs the shell with
#   LOCKTEST_ARTIFACTS     this test's directory for logs and screenshots
#   LOCKTEST_RUN_ID        a marker every process of the run carries, for the final sweep
#   LOCKTEST_TEST_ID       a marker every process of THIS test carries (tests run side by
#                          side): what a test looks for among processes, and what run.sh
#                          sweeps after it — never a sibling test's
#   LOCKTEST_RUNTIME       this test's private, short runtime dir (run.sh removes it)
#
# and of the caller's own environment only PATH, TMPDIR, USER, LOGNAME, TZ, LOCALE_ARCHIVE,
# XDG_DATA_DIRS, and two settings for a test:
#   LOCKTEST_QT_LOGGING    QT_LOGGING_RULES for the shell under test
#   LOCKTEST_PROCESS_TIMEOUT  the cap on each process of the stack, in seconds
#   LOCKTEST_SLOW          a factor for every check_within deadline (2 on a machine known
#                          to be slow; a whole number, 1 by default)
#
# run.sh starts this bash with no new privileges (setpriv --no-new-privs): everything
# below inherits that, so no setuid program (pkexec, unix_chkpwd) gains anything.

set -uo pipefail

# The password the "password" stack accepts. A test may set another before stack_start (a
# password with é in it); it is written into the stack's check script, so it may not hold
# characters the shell or sed would read: | & \ $ ` " ' or a newline (_write_pam_stacks).
LOCKTEST_PASSWORD="lt-test-pass-42"
# The answer the "password-question" stack wants to its second question
LOCKTEST_ANSWER="lt-answer-7"
# A cap on every process the test bed starts, should every other way of stopping it fail
LOCKTEST_PROCESS_TIMEOUT=${LOCKTEST_PROCESS_TIMEOUT:-300}
# The nested output's size: labwc's headless output is pinned to it, Hyprland's output is
# checked to be it (stack_start), and the tests' pointer coordinates are written for it
LOCKTEST_OUTPUT_SIZE=1920x1080
OUTPUT_WIDTH=1920 OUTPUT_HEIGHT=1080

# A check_within deadline only guards a hang: the check passes as soon as its condition
# holds, so a generous deadline costs nothing when all is well, and a tight one fails on a
# loaded machine for no fault of the shell. GUARD is the least any check_within waits
# (seconds; scaled by LOCKTEST_SLOW, as every deadline is). A check whose subject IS a time
# bound uses check_timed, which keeps its number — and such a test runs alone (run.sh,
# SERIAL), on a machine with nothing else going on.
LOCKTEST_SLOW=${LOCKTEST_SLOW:-1}
[[ "$LOCKTEST_SLOW" =~ ^[1-9][0-9]*$ ]] || LOCKTEST_SLOW=1
GUARD=$((10 * LOCKTEST_SLOW))

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
[ -n "${LOCKTEST_RUN_ID:-}" ] && [ -n "${LOCKTEST_TEST_ID:-}" ] || abort "no run and test markers from run.sh"
chmod 700 "$RUN"
mkdir -p "$WORK"/{home,xdg/config,xdg/cache,xdg/data,xdg/state,labwc,hypr,pam,finger,leds}
export XDG_RUNTIME_DIR=$RUN
export HOME=$WORK/home
export XDG_CONFIG_HOME=$WORK/xdg/config XDG_CACHE_HOME=$WORK/xdg/cache
export XDG_DATA_HOME=$WORK/xdg/data XDG_STATE_HOME=$WORK/xdg/state
export DBUS_SESSION_BUS_ADDRESS=unix:path=$RUN/no-session-bus
export DBUS_SYSTEM_BUS_ADDRESS=unix:path=$RUN/no-system-bus
export LIBSEAT_BACKEND=disabled-for-test
export PYTHONDONTWRITEBYTECODE=1
export LOCKTEST_RUN_ID LOCKTEST_TEST_ID
export PATH=$TOOLS/bin:$PATH
# run.sh hands over none of these (it starts the test with an empty environment and a list
# of what to keep); unset here too, so that a variable added to that list by mistake still
# does not reach the stack
unset WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE HYPRLAND_CMD NOTIFY_SOCKET \
    SWAYSOCK XDG_SESSION_ID XDG_SESSION_TYPE XDG_CURRENT_DESKTOP LABWC_PID QS_CONFIG_PATH \
    QS_CONFIG_NAME DESKTOP_STARTUP_ID XDG_ACTIVATION_TOKEN WAYLAND_SOCKET PIPEWIRE_REMOTE \
    PIPEWIRE_RUNTIME_DIR PULSE_SERVER
# The locale picks the Compose table (dead keys, Compose sequences): fixed, so that those
# tests do not depend on the caller's. No input method module is asked for: Qt picks its
# own, as in a session without one.
unset LC_ALL LC_CTYPE LANGUAGE QT_IM_MODULE QT_IM_MODULES GTK_IM_MODULE XMODIFIERS
export LANG=en_US.UTF-8

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

# check_within <seconds> <description> <command...>: the condition holds within the
# deadline — a guard against a hang, not a claim about time: <seconds> is scaled by
# LOCKTEST_SLOW and never less than GUARD
check_within() {
    local seconds description=$2
    seconds=$(awk -v seconds="$1" -v slow="$LOCKTEST_SLOW" -v guard="$GUARD" \
        'BEGIN { seconds *= slow; printf "%g", seconds < guard ? guard : seconds }')
    shift 2
    if wait_until "$seconds" "$@"; then pass "$description"; return 0; fi
    fail "$description (not within ${seconds} s)"
    return 1
}

# check_timed <seconds> <description> <command...>: the condition holds within exactly
# <seconds> — for a check whose subject is that time bound (the test belongs in run.sh's
# SERIAL then); everything else uses check_within
check_timed() {
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
# --fprintd <mode>                   the shell runs the REAL methods script (the run's copy),
#                                    which asks a stand-in fprintd in that mode (see
#                                    _write_fprintd_standin; fprintd_mode changes it) and finds
#                                    the test fingerprint stack as the "system-wide"
#                                    h2s-shell-fingerprint; implies --logind (the stand-in
#                                    gdbus is theirs)
# --keymap <name>                   the layout the virtual keyboard sends: us (the
#                                    default), us-intl (dead keys, AltGr), us-compose (a
#                                    Compose key on the right Alt) — compiled with the tool set
# --settings <json>                  the shell starts with these settings ({ "key": value },
#                                    SettingsSchema keys) in its one profile (write_settings)
# --session-bus                      a private session bus (dbus-daemon, no service
#                                    activation) for the shell instead of none, so its
#                                    notification server registers and notify() can send
# --window                           a stand-in desktop window (input/ltwindow.py: solid
#                                    magenta) before the shell starts; it logs each pointer
#                                    press and key it receives to window.log ("press <x> <y>",
#                                    "key <evdev code>")
# --no-lock-restore                  the nested Hyprland runs with misc:allow_session_lock_restore
#                                    off (Hyprland's default, and the owner's config today): a
#                                    lock client that died cannot be replaced
# --hyprland-debug                   the nested Hyprland writes its debug log (hyprland.log):
#                                    what it did with the lock and its surfaces
# --no-hyprland-ipc                  the shell runs without HYPRLAND_INSTANCE_SIGNATURE: as under
#                                    a compositor it cannot ask about its lock (the generic path)
# --reload-seam                      the shell's `locktest reload` IPC is enabled
#                                    (H2S_LOCK_TEST_RELOAD=1): a test asks for Quickshell.reload()
# --timings <json>                   LockRules.timings overrides for the shell
#                                    (H2S_LOCK_TEST_TIMINGS): what takes minutes, in seconds
# --launcher-timings "<k=s ...>"    the launcher's pauses (H2S_LAUNCHER_TEST_TIMINGS): first (1 s),
#                                    lockwait (15 s) — so restart tests run in seconds
# --shell-path <dir>                 put <dir> first on the shell's PATH (a stand-in program, such
#                                    as a hyprctl that hangs)
# --modules <list>                   H2S_SHELL_MODULE_PATH for the launcher: colon-separated, each a module
#                                    directory or a directory of modules (the launcher's discovery,
#                                    notes/plans/modules.md; tests/fixtures/modules holds the fixtures)
# --shell-env NAME=value            one more variable in the launcher's (so the shell's) environment
#                                    (a test seam such as H2S_SHELL_TEST_MODULE_CHECK_PATH); repeatable
# --data-dirs <list>                 the data dirs the launcher searches for modules (<dir>/h2s-shell/modules/*;
#                                    H2S_SHELL_MODULE_DATA_DIRS). Unset: none — never the caller's XDG_DATA_DIRS,
#                                    which the shell keeps for icons and fonts
#
# Always: the shell reads Caps Lock from $WORK/leds (H2S_LOCK_LEDS_DIR; caps_led writes it),
# never from the machine's /sys/class/leds — the real keyboard's state is not the test's.
stack_start() {
    local methods="password" methods_script="" logind=0 system_password=deny keymap=us settings="" session_bus=0
    local window=0 fprintd="" lock_restore=true reload_seam="" hyprland_logs=true hyprland_stdout=false
    local shell_env=() timings="" launcher_timings="" shell_path="" modules="" data_dirs="" extra_env=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --timings) timings=$2; shift 2 ;;
            --launcher-timings) launcher_timings=$2; shift 2 ;;
            --shell-path) shell_path=$2; shift 2 ;;
            --modules) modules=$2; shift 2 ;;
            --data-dirs) data_dirs=$2; shift 2 ;;
            --shell-env) extra_env+=("$2"); shift 2 ;;
            --methods) methods=$2; shift 2 ;;
            --methods-script) methods_script=$2; shift 2 ;;
            --logind) logind=1; shift ;;
            --system-password-stack) system_password=stack; shift ;;
            --fprintd) fprintd=$2; logind=1; shift 2 ;;
            --keymap) keymap=$2; shift 2 ;;
            --settings) settings=$2; shift 2 ;;
            --session-bus) session_bus=1; shift ;;
            --window) window=1; shift ;;
            --no-lock-restore) lock_restore=false; shift ;;
            --reload-seam) reload_seam=1; shift ;;
            --no-hyprland-ipc) shell_env=(-u HYPRLAND_INSTANCE_SIGNATURE); shift ;;
            --hyprland-debug) hyprland_logs=false; hyprland_stdout=true; shift ;;
            *) abort "stack_start: unknown option $1" ;;
        esac
    done
    local keymap_file=$TOOLS/share/keymaps/$keymap.xkb
    [ -f "$keymap_file" ] || abort "stack_start: no keymap $keymap (the tool set's share/keymaps)"
    [ -z "$settings" ] || write_settings "$settings"

    # Hyprland 0.57 cannot run on the headless backend alone (no allocator); nested in a
    # headless labwc it can. sway does not work as the parent.
    echo '<?xml version="1.0"?><labwc_config/>' > "$WORK/labwc/rc.xml"
    WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_HEADLESS_OUTPUTS=1 \
        spawn "$WORK/labwc.log" labwc -C "$WORK/labwc"
    wait_until 10 test -S "$RUN/wayland-0" || abort "labwc did not start (see labwc.log)"
    # Its headless output comes up at 1280x720, and the nested Hyprland's window — so its
    # output — follows it: pinned to the size the tests' coordinates are written for
    WAYLAND_DISPLAY=wayland-0 wlr-randr --output HEADLESS-1 --custom-mode "$LOCKTEST_OUTPUT_SIZE" \
        >> "$WORK/labwc.log" 2>&1 || abort "could not set labwc's output to $LOCKTEST_OUTPUT_SIZE (see labwc.log)"

    # The config must be Lua: Hyprland 0.57 reads hyprland.lua
    cat > "$WORK/hypr/hyprland.lua" << EOF
hl.monitor({ output = "", mode = "$LOCKTEST_OUTPUT_SIZE@60", position = "auto", scale = "1" })
hl.config({
    misc = { allow_session_lock_restore = $lock_restore, disable_hyprland_logo = true,
             force_default_wallpaper = 0, disable_autoreload = true,
             -- No banners across the top of the screen (screenshots look at it): the warning
             -- that it was not started by start-hyprland, a scale it adjusted
             disable_watchdog_warning = true, disable_scale_notification = true },
    xwayland = { enabled = false },
    animations = { enabled = false },
    ecosystem = { no_update_news = true, no_donation_nag = true },
    debug = { disable_logs = $hyprland_logs, enable_stdout_logs = $hyprland_stdout },
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
    # The first output (Hyprland's window in labwc) comes up at Aquamarine's 1280x720 —
    # the config's rule does not make its custom mode at start (observed); the same rule
    # given at runtime does
    hyprctl eval "hl.monitor({ output = \"WAYLAND-1\", mode = \"$LOCKTEST_OUTPUT_SIZE@60\", position = \"auto\", scale = \"1\" })" \
        > /dev/null 2>&1
    # The size of the output, as the compositor has it: the one fact the pointer's
    # coordinates are measured in (move_pointer). Read once, before a test adds outputs
    local size=""
    for _ in $(seq 1 30); do
        size=$(hyprctl -j monitors | python3 -I -c 'import json, sys; m = json.load(sys.stdin)[0]; print("%dx%d" % (m["width"], m["height"]))' 2> /dev/null)
        [ "$size" = "$LOCKTEST_OUTPUT_SIZE" ] && break
        sleep 0.1
    done
    [ "$size" = "$LOCKTEST_OUTPUT_SIZE" ] || abort "the nested output is ${size:-unknown}, not $LOCKTEST_OUTPUT_SIZE"
    OUTPUT_WIDTH=${size%x*} OUTPUT_HEIGHT=${size#*x}

    # Input before the shell: a lock client binds its keyboard when it starts, and a seat
    # that gains its first keyboard later loses the first key
    INPUT_FIFO=$WORK/input.fifo
    mkfifo "$INPUT_FIFO"
    # (-B: no bytecode beside the bindings — -I has Python ignore PYTHONDONTWRITEBYTECODE,
    # and a tool set made for the run, unlike the store's, can be written to)
    spawn "$WORK/input.log" python3 -I -B "$LOCKTEST_DIR/input/ltinput.py" \
        "$TOOLS/share" "$keymap_file" "$INPUT_FIFO"
    INPUT_PID=$SPAWNED_PID
    wait_until 10 grep -q ready "$WORK/input.log" || abort "the input client did not start (see input.log)"

    if [ "$window" = 1 ]; then
        spawn "$WORK/window.log" python3 -I -B "$LOCKTEST_DIR/input/ltwindow.py" "$TOOLS/share"
        wait_until 10 grep -q ready "$WORK/window.log" || abort "the stand-in window did not start (see window.log)"
    fi

    # The shell's session bus: none (an address that leads nowhere), or a private one
    local session_bus_address=$DBUS_SESSION_BUS_ADDRESS
    if [ "$session_bus" = 1 ]; then
        _start_session_bus
        session_bus_address=$LOCKTEST_SESSION_BUS
    fi

    _write_pam_stacks "$methods" "$methods_script"
    _write_system_pam "$system_password"

    local tools="" session_id=""
    if [ "$logind" = 1 ]; then
        _write_logind_standins
        tools=$WORK/standins
        session_id=$LOCKTEST_SESSION_ID
    fi
    if [ -n "$fprintd" ]; then
        mkdir -p "$WORK/fprintd"
        echo "$fprintd" > "$WORK/fprintd/mode"
        _write_fprintd_standin "$WORK/standins"
        _write_real_methods_script
    fi

    # The shell, as it is started for real: the launcher with H2S_SHELL_DIR pointing at
    # the run's copy of the checkout (run.sh), a plain start (never --restart, which stops
    # every h2s-shell it finds). The locale is fixed: it picks the Compose table, and the
    # tests of dead keys and Compose sequences must not depend on the caller's. No input
    # method module is asked for: Qt picks its own, as in a session without one (both set in
    # the isolation block at the top).
    # No helper (H2S_HELPER set and empty): the launcher would otherwise build the copy's at
    # each start; tests/run-helper.sh is where the helper is tested.
    LAUNCHER_ENV=("${shell_env[@]}" QT_LOGGING_RULES="${LOCKTEST_QT_LOGGING:-}" DBUS_SESSION_BUS_ADDRESS="$session_bus_address"
        H2S_LOCK_TOOLS="$tools" XDG_SESSION_ID="$session_id" H2S_LOCK_SYSTEM_PAM_DIR="$WORK/system-pam"
        H2S_LOCK_TEST_RELOAD="$reload_seam" H2S_SHELL_DIR="$LOCKTEST_SHELL" H2S_LOCK_AUTH_METHODS="$WORK/pam/methods.sh"
        H2S_LOCK_LEDS_DIR="$WORK/leds" H2S_LOCK_TEST_TIMINGS="$timings" QT_QPA_PLATFORM=wayland
        H2S_LAUNCHER_TEST_TIMINGS="$launcher_timings" H2S_SHELL_MODULE_PATH="$modules" H2S_SHELL_MODULE_DATA_DIRS="$data_dirs"
        H2S_HELPER="")
    [ -z "$shell_path" ] || LAUNCHER_ENV+=(PATH="$shell_path:$PATH")
    [ ${#extra_env[@]} -eq 0 ] || LAUNCHER_ENV+=("${extra_env[@]}")
    start_launcher
    # The shell under test reads the seams set above only from the test seam file run.sh
    # puts into its copy (tests/lock/README.md, "The test tree"); the checkout's own file
    # is constants and reads none, so without the swap the shell would run with the real
    # tools and the real /etc/pam.d. Its lock state names the seams in force: never none
    # here (H2S_LOCK_SYSTEM_PAM_DIR and H2S_LOCK_LEDS_DIR are always set)
    wait_until 10 _test_seams_in_force \
        || abort "the shell under test reads no test seam: its copy lacks the test seam file (tests/lock/run.sh puts it there)"
    log "stack up: Hyprland $HYPRLAND_INSTANCE_SIGNATURE, shell pid $SHELL_PID, methods: ${fprintd:+the real script, fprintd stand-in: }${fprintd:-${methods_script:-$methods}}${tools:+, logind stand-ins}"
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
    # The password goes into a sed replacement and a double-quoted bash string
    case "$LOCKTEST_PASSWORD" in
        "" | *'|'* | *'&'* | *'\'* | *'$'* | *'`'* | *'"'* | *"'"* | *$'\n'*)
            abort "LOCKTEST_PASSWORD holds a character the check script cannot hold" ;;
    esac
    bash_path=$(command -v bash)
    coreutils=$(dirname "$(dirname "$(readlink -f "$(command -v rm)")")")
    for file in password password-question fingerprint check-password.sh check-answer.sh wait-finger.sh finger-error.sh; do
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

# write_settings <json>: the shell's config.json in the private XDG_CONFIG_HOME, as the
# shell stores settings — one profile, "Full", always active, setting these keys
# ({ "lockscreen.screensaverEnabled": true, … }; SettingsSchema's keys, values as stored).
# Every other setting is the schema's default. Before stack_start (it takes --settings).
write_settings() {
    mkdir -p "$XDG_CONFIG_HOME/h2s_shell"
    python3 -I -c '
import json, sys
settings = json.loads(sys.argv[1])
profiles = [{"name": "Full", "enabled": True, "when": {}, "set": settings}]
json.dump({"profiles": json.dumps(profiles), "widgetPresets": "{}"}, open(sys.argv[2], "w"), indent=2)
' "$1" "$XDG_CONFIG_HOME/h2s_shell/config.json" || abort "write_settings: not a JSON object: $1"
}

# A private session bus (stack_start --session-bus): a dbus-daemon of the test's own, with
# no service directories (nothing is activated) and a socket in the private runtime dir.
# The real session bus is never reached: the address is this socket's.
_start_session_bus() {
    local config=$WORK/session-bus.conf
    cat > "$config" << EOF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:path=$RUN/test-session-bus</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
EOF
    spawn "$WORK/session-bus.log" dbus-daemon --nofork --nopidfile --config-file="$config"
    wait_until 5 test -S "$RUN/test-session-bus" || abort "the private session bus did not start (see session-bus.log)"
    LOCKTEST_SESSION_BUS=unix:path=$RUN/test-session-bus
}

# notify <app> <summary> <body>: a notification sent to the shell's server on the private
# session bus (stack_start --session-bus), leaving its display time to the server (-1, as
# notify-send without -t does)
notify() {
    [ -n "${LOCKTEST_SESSION_BUS:-}" ] || abort "notify needs stack_start --session-bus"
    DBUS_SESSION_BUS_ADDRESS=$LOCKTEST_SESSION_BUS gdbus call --session \
        --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.Notify "$1" 0 "" "$2" "$3" '[]' '{}' "int32 -1" > /dev/null
}
# Whether the shell's notification server has registered on the private bus
notification_server_up() {
    DBUS_SESSION_BUS_ADDRESS=$LOCKTEST_SESSION_BUS gdbus call --session --dest org.freedesktop.DBus \
        --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.NameHasOwner \
        org.freedesktop.Notifications 2> /dev/null | grep -q true
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
#                    `gdbus call … ListInhibitors` answers logind/inhibitors (none
#                    without it; logind_inhibitors writes it), and never ends while
#                    logind/hang exists (a bus that does not answer)
#                    `gdbus call … SetLockedHint <bool>` notes "call SetLockedHint <path>
#                    <bool>" in logind/log
#   systemd-inhibit  notes "hold <pid> <time>" in logind/log, runs the command it was given
#                    (the shell's `read -r release`) and notes "release <pid> <time>" when
#                    that ends; between logind_signal sleep and wake it refuses, as logind
#                    does ("refuse <pid> <time>", exit 1, the command not run)
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
preparing=$WORK/logind/preparing
# fprintd's calls (the methods script's) go to the fprintd stand-in, when there is one
case " \$* " in
    *" net.reactivated.Fprint "*)
        [ -x "$WORK/standins/gdbus-fprintd" ] && exec "$WORK/standins/gdbus-fprintd" "\$@"
        echo "Error: GDBus.Error:org.freedesktop.DBus.Error.ServiceUnknown: The name is not activatable" >&2
        exit 1
        ;;
esac
case "\$1" in
    call)
        # logind's PreparingForSleep (the shell asks once its monitor listens): logind/preparing
        case " \$* " in
            *" PreparingForSleep "*)
                echo "call PreparingForSleep \$(cat "\$preparing" 2> /dev/null)" >> "\$log"
                [ "\$(cat "\$preparing" 2> /dev/null)" = true ] && echo "(<true>,)" || echo "(<false>,)"
                exit 0
                ;;
            *".SetLockedHint "*)
                # The session's LockedHint (the shell reports its lock): noted with the
                # object path and the value, "()" as logind answers
                path=; for argument in "\$@"; do [ "\$previous" = --object-path ] && path=\$argument; previous=\$argument; done
                echo "call SetLockedHint \$path \$argument" >> "\$log"
                echo "()"
                exit 0
                ;;
            *".ListInhibitors "*)
                # logind's inhibitors (SleepLockNotice reads them): logind/inhibitors as
                # gdbus prints the list (logind_inhibitors writes it), none without it
                echo "call ListInhibitors" >> "\$log"
                [ -f "$WORK/logind/hang" ] && exec $coreutils/sleep 60
                cat "$WORK/logind/inhibitors" 2> /dev/null || echo "(@a(ssssuu) [],)"
                exit 0
                ;;
        esac
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
        # As gdbus monitor says once its match is in place
        echo "Monitoring signals from all objects owned by org.freedesktop.login1"
        echo "The name org.freedesktop.login1 is owned by :1.0"
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
# As logind's Inhibit() does (systemd v260 src/login/logind-dbus.c, method_inhibit): no new
# delay lock while the sleep it would delay is under way — from PrepareForSleep(true) until
# the wake (logind/preparing, written by logind_signal)
if [ "\$(cat "$WORK/logind/preparing" 2> /dev/null)" = true ]; then
    echo "refuse \$\$ \${EPOCHREALTIME/,/.}" >> "\$log"
    echo "Failed to inhibit: The operation inhibition has been requested for is already running" >&2
    exit 1
fi
echo "hold \$\$ \${EPOCHREALTIME/,/.}" >> "\$log"
"\$@"
status=\$?
echo "release \$\$ \${EPOCHREALTIME/,/.}" >> "\$log"
exit \$status
EOF
    chmod +x "$WORK/standins/gdbus" "$WORK/standins/systemd-inhibit"
}

# ---- fprintd stand-in (stack_start --fprintd, tests/methods-script.sh) ----------------
# The methods script asks fprintd over D-Bus with `gdbus call` (scripts/lock-auth-methods.sh).
# _write_fprintd_standin <dir> writes <dir>/gdbus-fprintd, which answers those calls as
# fprintd would in the mode named in $WORK/fprintd/mode (read at every call, so a test can
# change it), and notes each call in $WORK/fprintd/log ("call <method> user=<argument>").
#
#   enrolled           one reader, a finger enrolled: (['right-index-finger'],)
#   none               one reader, no finger enrolled (NoEnrolledPrints)
#   second             two readers, a finger enrolled on the second only
#   nodevice           no reader: (@ao [],)
#   absent             fprintd not installed (ServiceUnknown)
#   hang               the call never returns (fprintd stuck in activation)
#   denied             ListEnrolledFingers refused (PermissionDenied)
#   nobus              no system bus to connect to
#   malformed-devices  GetDevices answers something that is not a list of readers
#   malformed-fingers  ListEnrolledFingers answers something that is not a list of fingers
#   warning            as enrolled, with a GLib warning on gdbus's stderr at every call
#   gdbus-timeout      gdbus's own time-out: "Error: Timeout was reached", status 1
#   vanished           the reader listed by GetDevices is gone at ListEnrolledFingers
#                      (UnknownObject)
#   multiline          ListEnrolledFingers fails with an error message of two lines
_write_fprintd_standin() {
    local dir=$1 bash_path coreutils
    bash_path=$(command -v bash)
    coreutils=$(dirname "$(dirname "$(readlink -f "$(command -v rm)")")")/bin
    mkdir -p "$dir" "$WORK/fprintd"
    [ -e "$WORK/fprintd/mode" ] || echo enrolled > "$WORK/fprintd/mode"
    : >> "$WORK/fprintd/log"
    cat > "$dir/gdbus-fprintd" << EOF
#!$bash_path
# Stand-in for fprintd behind gdbus in the lock test bed (tests/lock/lib.sh): no bus is reached
mode=\$($coreutils/cat "$WORK/fprintd/mode" 2> /dev/null)
method="" path="" argument="(none)"
while [ \$# -gt 0 ]; do
    case "\$1" in
        --method) method=\${2##*.}; shift 2 ;;
        --object-path) path=\$2; shift 2 ;;
        --dest | --timeout) shift 2 ;;
        call | --system) shift ;;
        *) argument="'\$1'"; shift ;;
    esac
done
echo "call \$method user=\$argument path=\$path mode=\$mode" >> "$WORK/fprintd/log"
error() { echo "Error: GDBus.Error:\$1: \$2" >&2; exit 1; }
if [ "\$mode" = warning ]; then
    echo "(gdbus:\$\$): GLib-WARNING **: 12:00:00.000: a warning gdbus printed on a call that succeeded" >&2
    mode=enrolled
fi
case "\$mode" in
    hang) exec $coreutils/sleep 120 ;;
    gdbus-timeout) echo "Error: Timeout was reached" >&2; exit 1 ;;
    absent) error org.freedesktop.DBus.Error.ServiceUnknown "The name is not activatable" ;;
    nobus) echo "Error connecting: Could not connect: No such file or directory" >&2; exit 1 ;;
esac
case "\$method" in
    GetDevices)
        case "\$mode" in
            nodevice) echo "(@ao [],)" ;;
            second) echo "([objectpath '/net/reactivated/Fprint/Device/0', objectpath '/net/reactivated/Fprint/Device/1'],)" ;;
            malformed-devices) echo "(<'not a list'>,)" ;;
            *) echo "([objectpath '/net/reactivated/Fprint/Device/0'],)" ;;
        esac
        ;;
    ListEnrolledFingers)
        case "\$mode:\$path" in
            enrolled:* | second:*/1) echo "(['right-index-finger'],)" ;;
            denied:*) error net.reactivated.Fprint.Error.PermissionDenied "Not Authorized: net.reactivated.fprint.device.verify" ;;
            vanished:*) error org.freedesktop.DBus.Error.UnknownObject "No such interface “net.reactivated.Fprint.Device” on object at path \$path" ;;
            multiline:*) printf 'Error: GDBus.Error:net.reactivated.Fprint.Error.Internal: the first line\nand a second line\n' >&2; exit 1 ;;
            malformed-fingers:*) echo "(Right Index Finger,)" ;;
            *) error net.reactivated.Fprint.Error.NoEnrolledPrints "Failed to discover prints" ;;
        esac
        ;;
    *) error org.freedesktop.DBus.Error.UnknownMethod "No such method" ;;
esac
EOF
    chmod +x "$dir/gdbus-fprintd"
}
fprintd_mode() { echo "$1" > "$WORK/fprintd/mode"; log "fprintd stand-in: $1"; }

# The methods script the shell runs with stack_start --fprintd: the REAL one (the run's copy),
# with the seam that would replace it unset. It finds the test's stand-in system-wide configs
# (H2S_LOCK_SYSTEM_PAM_DIR) and asks the fprintd stand-in (H2S_LOCK_TOOLS).
_write_real_methods_script() {
    {
        echo "#!$(command -v bash)"
        echo "# Written by tests/lock/lib.sh: the shell's own methods script, not a test's"
        echo "unset H2S_LOCK_AUTH_METHODS"
        echo "exec \"$LOCKTEST_SHELL/scripts/lock-auth-methods.sh\""
    } > "$WORK/pam/methods.sh"
    chmod +x "$WORK/pam/methods.sh"
    # The fingerprint config the script will find "system-wide": the test stack
    cp "$WORK/pam/fingerprint" "$WORK/system-pam/h2s-shell-fingerprint"
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
    # logind's PreparingForSleep property follows, as logind sets it around the signal
    case "$1" in sleep) echo true > "$WORK/logind/preparing" ;; wake) echo false > "$WORK/logind/preparing" ;; esac
    LOGIND_SIGNAL_AT=${EPOCHREALTIME/,/.}
    echo "$line" >> "$WORK/logind/signals"
    log "logind stand-in: $1"
}

# released_after_signal_within <seconds>: the stand-in's first inhibitor release after the
# last logind_signal came less than <seconds> after it — from the stand-in's own record, not
# from a poll. Before sleep the shell releases only once the compositor confirmed the lock,
# so this times the lock too: logind sleeps at the latest InhibitDelayMaxSec (5 s) after
# PrepareForSleep, and the screen must be locked by then
released_after_signal_within() {
    awk -v since="${LOGIND_SIGNAL_AT:-0}" -v limit="$1" '
        $1 == "release" && $3 + 0 >= since + 0 { found = 1; exit !($3 - since < limit) }
        END { if (!found) exit 1 }' "$WORK/logind/log"
}
# The same, as a number for the log ("" when none)
release_seconds_after_signal() {
    awk -v since="${LOGIND_SIGNAL_AT:-0}" '$1 == "release" && $3 + 0 >= since + 0 { printf "%.2f", $3 - since; exit }' "$WORK/logind/log"
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
# logind_inhibitors <who> <why>...: the inhibitors the gdbus stand-in lists besides none —
# each a sleep delay inhibitor of this user's, held by <who> for <why> (pairs); with no
# arguments, none
logind_inhibitors() {
    local uid entries="" who why
    uid=$(id -u)
    while [ $# -ge 2 ]; do
        who=$1 why=$2
        shift 2
        entries="$entries${entries:+, }('sleep', '$who', '$why', 'delay', uint32 $uid, uint32 4242)"
    done
    if [ -n "$entries" ]; then echo "([$entries],)"; else echo "(@a(ssssuu) [],)"; fi > "$WORK/logind/inhibitors"
    log "logind stand-in: inhibitors ${entries:-none}"
}
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

# ---- The shell's process, under its supervisor ----------------------------------------
# The launcher (scripts/launch.sh) supervises the shell: it runs it as a child and starts it
# again when it dies. SUPERVISOR_PID is the launcher, SHELL_PID the shell process now.

# start_launcher: the launcher (and so the shell), as stack_start starts it — also again
# after a test let the first one go (supervisor_release) and the shell end. The launcher
# stays, as the shell's supervisor (scripts/launch.sh), and the shell runs as its child.
start_launcher() {
    # SIGHUP reset: a run started with it ignored (nohup, a detached ssh) would hand that on,
    # and bash cannot trap a signal ignored at its start (the supervisor scenario sends it)
    spawn "$WORK/shell.log" env --default-signal=HUP "${LAUNCHER_ENV[@]}" "$LOCKTEST_LAUNCHER"
    local timeout_pid=$SPAWNED_PID
    wait_until 10 pgrep -P "$timeout_pid" || abort "the launcher did not start"
    SUPERVISOR_PID=$(pgrep -P "$timeout_pid" | head -n 1)
    wait_until 10 _find_shell_pid || abort "the launcher did not start the shell"
    SHELL_PID=$(_find_shell_pid)
    _track_shell_group
    wait_until 30 shell_ipc lockscreen status || abort "the shell's IPC does not answer (see shell.log)"
}

# The shell process under the supervisor: a child running Quickshell's binary, of this run
_find_shell_pid() {
    local pid
    # A launcher that execs the shell instead of supervising it (before Stage 4): the
    # launcher's process is the shell
    if [ "$(readlink -f "/proc/${SUPERVISOR_PID:-0}/exe" 2> /dev/null)" = "$(_quickshell_binary)" ]; then
        echo "$SUPERVISOR_PID"
        return 0
    fi
    for pid in $(pgrep -P "${SUPERVISOR_PID:-0}" 2> /dev/null); do
        [ "$(readlink -f "/proc/$pid/exe" 2> /dev/null)" = "$(_quickshell_binary)" ] || continue
        [ "$(process_env "$pid" LOCKTEST_TEST_ID)" = "$LOCKTEST_TEST_ID" ] || continue
        echo "$pid"
        return 0
    done
    return 1
}
# The supervised shell runs in a process group of its own (its pid): stopped with the stack,
# like the groups spawn() made — what the shell started (a hung methods script) goes too
_track_shell_group() {
    [ "$(awk '{ print $5 }' "/proc/$SHELL_PID/stat" 2> /dev/null)" = "$SHELL_PID" ] \
        && [ "$(process_env "$SHELL_PID" LOCKTEST_TEST_ID)" = "$LOCKTEST_TEST_ID" ] \
        && PROCESS_GROUPS+=("$SHELL_PID")
    return 0
}
_shell_pid_other_than() { local pid; pid=$(_find_shell_pid) && [ "$pid" != "$1" ]; }

# wait_for_new_shell <old pid> <seconds>: the supervisor has started another shell process
# and its IPC answers; SHELL_PID is then that one
wait_for_new_shell() {
    wait_until "$2" _shell_pid_other_than "$1" || return 1
    SHELL_PID=$(_find_shell_pid)
    _track_shell_group
    wait_until 20 shell_ipc lockscreen status || return 1
    log "the supervisor started a new shell: pid $SHELL_PID"
}

# The checks a test makes before it signals a process: of this run, and what it says it is
# (a wrong pid could be a process of the real session). assert_shell_process <pid>: the
# shell under test; assert_supervisor_process <pid>: its launcher.
assert_shell_process() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$(process_env "$1" LOCKTEST_TEST_ID)" = "$LOCKTEST_TEST_ID" ] \
        && [ "$(readlink -f "/proc/$1/exe" 2> /dev/null)" = "$(_quickshell_binary)" ] \
        && [ "$(process_env "$1" XDG_RUNTIME_DIR)" = "$RUN" ] \
        || abort "pid $1 is not the shell under test: not signalling it"
}
assert_supervisor_process() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$(process_env "$1" LOCKTEST_TEST_ID)" = "$LOCKTEST_TEST_ID" ] \
        && tr '\0' ' ' < "/proc/$1/cmdline" 2> /dev/null | grep -q "$LOCKTEST_SHELL/scripts/launch\.sh" \
        || abort "pid $1 is not the launcher under test: not signalling it"
}

# supervisor_environment <pid>: the launcher's environment as it began, in `environment` —
# what a test hands a second launcher (`env -i "${environment[@]}" … --restart`) so that it
# runs as the first was started. Only when it names the private runtime dir: a launcher
# started without one would look for the shells to stop in the real session's.
supervisor_environment() {
    local entry private=""
    assert_supervisor_process "$1"
    environment=()
    { mapfile -d '' environment < "/proc/$1/environ"; } 2> /dev/null
    for entry in "${environment[@]}"; do [ "$entry" = "XDG_RUNTIME_DIR=$RUN" ] && private=1; done
    [ -n "$private" ] || abort "the launcher's environment (pid $1) could not be read, or does not name the private runtime dir: not starting another launcher with it"
}

# The supervisor lets the shell go: it no longer starts it again (what the launcher's own
# --restart does first). For tests about a shell that dies and stays dead.
supervisor_release() {
    assert_supervisor_process "$SUPERVISOR_PID"
    kill -USR1 "$SUPERVISOR_PID"
    log "the supervisor lets the shell go (SIGUSR1)"
}

# signal_shell <signal>: to the shell under test, after making sure it is that
signal_shell() {
    assert_shell_process "$SHELL_PID"
    kill -s "$1" "$SHELL_PID"
    log "sent SIG$1 to the shell (pid $SHELL_PID)"
}

# Watches the compositor's lock across a gap: one line per poll ("true"/"false"/"error")
# in $WORK/<name>.polls, every 50 ms, until stop_lock_watch. A poll that cannot reach the
# compositor says "error" (counted apart: it says nothing about the lock).
start_lock_watch() {
    LOCK_WATCH_FILE=$WORK/$1.polls
    : > "$LOCK_WATCH_FILE"
    (
        while :; do
            hyprctl -j locked 2> /dev/null | python3 -I -c '
import json, sys
try:
    print(str(json.load(sys.stdin)["locked"]).lower())
except Exception:
    print("error")' >> "$LOCK_WATCH_FILE"
            sleep 0.05
        done
    ) &
    LOCK_WATCH_PID=$!
}
stop_lock_watch() {
    [ -n "${LOCK_WATCH_PID:-}" ] && kill "$LOCK_WATCH_PID" 2> /dev/null
    wait "$LOCK_WATCH_PID" 2> /dev/null
    LOCK_WATCH_PID=""
    log "lock watch: $(grep -c true "$LOCK_WATCH_FILE") polls locked, $(grep -c false "$LOCK_WATCH_FILE") unlocked, $(grep -c error "$LOCK_WATCH_FILE") unanswered"
}
lock_watch_never_unlocked() { [ "$(grep -c false "$LOCK_WATCH_FILE")" = 0 ] && [ "$(grep -c true "$LOCK_WATCH_FILE")" -gt 0 ]; }

# The lock marker as it is on disk ($XDG_RUNTIME_DIR/h2s-shell-lock): its first word
# (locked / unlocked), "" when there is none
marker_file_word() { local word=""; [ -f "$RUN/h2s-shell-lock" ] && read -r word _ < "$RUN/h2s-shell-lock"; echo "$word"; }
marker_file_is() { [ "$(marker_file_word)" = "$1" ]; }

# Lines of the shell's log (all its processes write to shell.log) matching a pattern
shell_log_count() { grep -ac -- "$1" "$WORK/shell.log"; }

# A protocol error or a killed client, in the nested Hyprland's or the shell's log
protocol_errors() {
    grep -aiE 'protocol error|error 4 |invalid_destroy|invalid_unlock|duplicate_output|already_constructed|killing client|wl_display@1: error' \
        "$WORK/hyprland.log" "$WORK/shell.log" 2> /dev/null
}
no_protocol_errors() { [ -z "$(protocol_errors)" ]; }

# ---- Talking to the shell -----------------------------------------------------------

# shell_ipc <target> <function> [args...]. Addressed by process id inside the private
# runtime dir: the real shell is not in that registry, and has another pid anyway.
shell_ipc() {
    [ "$XDG_RUNTIME_DIR" = "$RUN" ] || abort "shell_ipc outside the private runtime dir"
    "$LOCKTEST_QS" ipc --pid "$SHELL_PID" call "$@"
}

# launcher_ipc <target> <function> [args...]: as the owner's keybind calls it — `h2s-shell
# ipc call …`, the launcher's ipc path (scripts/launch.sh: it tries again while the shell
# reloads or restarts) — inside the private runtime dir, where only this test's shells are
launcher_ipc() {
    [ "$XDG_RUNTIME_DIR" = "$RUN" ] || abort "launcher_ipc outside the private runtime dir"
    env "${LAUNCHER_ENV[@]}" "$LOCKTEST_LAUNCHER" ipc call "$@"
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
#   caps_lock            what the shell knows of Caps Lock: true / false / "" (unknown)
#   screensaver          the shell's screensaverVisible (idle, or locked)
#   marker               the lock marker as the shell last wrote it: locked / unlocked / "" (none yet)
#   marker_key_known     the marker carries this compositor session's key (the start probe answered)
#   restoring            a lock the marker asked to take back, not yet confirmed
#   restore_pending      the compositor refused to give that lock back (status "compositor-locked")
#   carried_held         a reload now would carry a compositor lock over
#   test_seams           the test seams in force in the shell, comma-separated (TestSeams.inForce)
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
    "caps_lock": lambda s: s["driver"]["capsLock"],
    "screensaver": lambda s: s["driver"]["screensaverVisible"],
    "marker": lambda s: s["driver"]["marker"],
    "marker_key_known": lambda s: s["driver"]["markerKeyKnown"],
    "restoring": lambda s: s["driver"]["restoring"],
    "restore_pending": lambda s: s["driver"]["restorePending"],
    "carried_held": lambda s: s["driver"]["carriedHeld"],
    "test_seams": lambda s: ",".join(s["driver"]["testSeams"]),
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
_test_seams_in_force() { [ -n "$(state_field test_seams 2> /dev/null)" ]; }
shell_status_is() { [ "$(shell_ipc lockscreen status)" = "$1" ]; }

# The compositor's own word on the lock
compositor_locked_is() {
    [ "$(hyprctl -j locked | python3 -I -c 'import json,sys; print(str(json.load(sys.stdin)["locked"]).lower())')" = "$1" ]
}
compositor_locked() { compositor_locked_is true; }
compositor_unlocked() { compositor_locked_is false; }

# The inhibitors on the REAL system bus (listed read-only) held by a process of this test
# (its marker; run.sh checks the run as a whole too), by PID: the shell under test must never
# add one. By PID, not by name: the real shell's inhibitor is called h2s-shell too.
run_inhibitors() {
    local pid
    for pid in $(env -u DBUS_SYSTEM_BUS_ADDRESS systemd-inhibit --list --no-pager --no-legend 2> /dev/null \
        | awk '{ for (i = 1; i + 2 <= NF; i++) if ($i ~ /^[0-9]+$/ && $(i + 2) ~ /^[0-9]+$/) { print $(i + 2); break } }'); do
        [ "$(process_env "$pid" LOCKTEST_TEST_ID)" = "$LOCKTEST_TEST_ID" ] && echo "$pid"
    done
}
# That the real list can be read at all (else the check above proves nothing)
real_inhibitor_list_readable() {
    env -u DBUS_SYSTEM_BUS_ADDRESS systemd-inhibit --list --no-pager --no-legend > /dev/null 2>&1
}

# The value of one variable in a process's environment
process_env() { { tr '\0' '\n' < "/proc/$1/environ"; } 2> /dev/null | sed -n "s/^$2=//p"; }

# Every live process of this test, by its marker in the environment (not a sibling test's:
# tests run side by side, from copies of the same tree)
run_processes() {
    local environ pid
    for environ in /proc/[0-9]*/environ; do
        [ -O "$environ" ] || continue
        pid=${environ#/proc/}
        pid=${pid%/environ}
        [ "$(process_env "$pid" LOCKTEST_TEST_ID)" = "$LOCKTEST_TEST_ID" ] && echo "$pid"
    done
}
# test_pgrep <pgrep options> <pattern>: pgrep, among this test's processes only — a sibling
# test runs the same programs from the same store paths
test_pgrep() {
    local pid found=1
    for pid in $(pgrep "$@"); do
        [ "$(process_env "$pid" LOCKTEST_TEST_ID)" = "$LOCKTEST_TEST_ID" ] || continue
        echo "$pid"
        found=0
    done
    return $found
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
# keys_text <text>: the keys that type <text> with Caps Lock off, whatever the locks are
# (with Caps Lock on, "abc" types "ABC"); same safety check as type_text
keys_text() {
    _password_stack_is_safe || abort "not typing: the shell's password config ($(state_field password_config 2> /dev/null)) is not a test stack"
    send_input "keys $1"
}
# press_key <keysym>: Return, BackSpace, Escape, Tab, space, dead_acute, Multi_key, KP_1,
# KP_Enter, Caps_Lock, Num_Lock, … (whatever the stack's keymap has)
press_key() { send_input "key $1"; }
# hold_key <keysym> <seconds>: held down, so that it auto-repeats
hold_key() { send_input "hold $1 $2"; }
# move_pointer [x y]: to that pixel of the output (its centre by default), then a small move
# (a surface counts only real motion: LockIoRules.pointerMoved). The coordinates are in
# OUTPUT_WIDTH × OUTPUT_HEIGHT, read from the compositor at stack_start
move_pointer() {
    send_input "abs ${1:-$((OUTPUT_WIDTH / 2))} ${2:-$((OUTPUT_HEIGHT / 2))} $OUTPUT_WIDTH $OUTPUT_HEIGHT" "move 5 5"
}

# Wakes the prompt by moving the pointer and waits for it to show: a test about
# authentication should not depend on how a waking key is handled (stage 3 tests that).
# Repeated, to a slightly different place each time: the first position a surface sees is
# no motion (the pointer entering, or the surface appearing under it), and a motion sent
# before the surface exists reaches nothing.
wake_prompt() {
    local attempt
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        move_pointer $((OUTPUT_WIDTH / 2 - 80 + attempt * 4)) $((OUTPUT_HEIGHT / 2 - 40))
        wait_until 0.5 state_is prompt_awake true && return 0
    done
    return 1
}

# unlock_for_test [seconds]: ends the lock by a legitimate route, for a test whose subject is
# not how the lock ends (Escape never unlocks): logind's Unlock through the stand-in when the
# stack has one (stack_start --logind or --fprintd), else the test password typed at the
# prompt (which adds a "right" to pam/check.log, and needs a stack whose password works).
# Waits up to <seconds> (10) for the compositor to unlock; non-zero if it did not. A test
# that only needs to stop while locked needs none of this: stopping the stack ends it.
unlock_for_test() {
    if [ -f "$WORK/logind/signals" ]; then
        logind_signal unlock
    else
        wait_until 5 _password_stack_is_safe || { log "unlock_for_test: the password config is not a test stack: not typing"; return 1; }
        wake_prompt || { log "unlock_for_test: the prompt did not wake"; return 1; }
        type_text "$LOCKTEST_PASSWORD"
        press_key Return
    fi
    wait_until "${1:-10}" compositor_unlocked
}

# ---- Evidence -----------------------------------------------------------------------

screenshot() { grim "$WORK/$1.png" 2> /dev/null && log "screenshot $1.png"; }
# screenshot_output_ppm <output> <name>: one output only, as <name>.ppm
screenshot_output_ppm() { grim -o "$1" -t ppm "$WORK/$2.ppm" 2> /dev/null; }

# wait_settled [output]: waits (a guard's time) until two screenshots in a row — of
# <output>, else of the whole screen — are the same: a fade has ended, and the next
# screenshot shows where things rest. A screen that never settles is a failure
wait_settled() {
    rm -f "$WORK/.settle.ppm" "$WORK/.settle-previous.ppm"
    wait_until "$GUARD" _screen_settled "${1:-}" && return 0
    fail "the screen${1:+ $1} settled (two screenshots in a row the same)"
    return 1
}
_screen_settled() {
    if [ -n "$1" ]; then grim -o "$1" -t ppm "$WORK/.settle.ppm"; else grim -t ppm "$WORK/.settle.ppm"; fi 2> /dev/null || return 1
    if [ -f "$WORK/.settle-previous.ppm" ] && cmp -s "$WORK/.settle.ppm" "$WORK/.settle-previous.ppm"; then
        rm -f "$WORK/.settle.ppm" "$WORK/.settle-previous.ppm"
        return 0
    fi
    mv -f "$WORK/.settle.ppm" "$WORK/.settle-previous.ppm"
    return 1
}

# What the password stack received, per check, in order: "length <bytes> sha256 <hex>"
# lines (pam/check-detail.log; never the text), and the line a string would give
password_details() { cat "$WORK/pam/check-detail.log" 2> /dev/null; }
password_detail_of() {
    local sum
    sum=$(printf '%s' "$1" | sha256sum)
    echo "length $(printf '%s' "$1" | wc -c) sha256 ${sum%% *}"
}
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

# reddish_above <count> <name>: more than <count> clearly red pixels in the prompt's area
# (reddish_pixels, a new screenshot <name>.ppm each time): for waiting on an error's colour
reddish_above() { [ "$(reddish_pixels "$2")" -gt "$1" ]; }

# relaunch_decided <lines before>: after a crash past Quickshell's 10 s, its in-place
# relaunch has either come back without its config path (`Launching config: ""` beyond the
# <lines before> there were) or come up and answers — whichever, the test knows which way
# it went
relaunch_decided() {
    lines_more_than "$1" 'Launching config: ""' "$WORK/shell.log" && return 0
    timeout 2 "$LOCKTEST_QS" ipc --pid "$SHELL_PID" call lockscreen status > /dev/null 2>&1
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
no_finger_waiters() { [ -z "$(finger_waiters)" ]; }

# lines_more_than <count> <regex> <file>: more than <count> lines of <file> match — for
# waiting on a log to grow (check_within re-runs a command, but the arguments it was given
# were expanded once)
lines_more_than() { [ "$(grep -c -- "$2" "$3" 2> /dev/null)" -gt "$1" ]; }

# finger_timeout <seconds>: (to a tenth) from the next round on, a round nobody answers ends after that
# long in PAM's Error, as pam_fprintd's own time-out does (wait-finger.sh, finger-error.sh);
# `finger_timeout 0` puts the default back (a plain failure after 120 s)
finger_timeout() {
    if [ "$1" = 0 ]; then rm -f "$WORK/finger/timeout"; else echo "$1" > "$WORK/finger/timeout"; fi
    if [ "$1" = 0 ]; then log "fingerprint stand-in: rounds wait 120 s, then fail (the default)"; else log "fingerprint stand-in: rounds time out after $1 s with an Error"; fi
}

# ---- The Caps Lock LED (stack_start points the shell's H2S_LOCK_LEDS_DIR at $WORK/leds) ----
# The nested compositor has no keyboard, so no LED: the test writes the one the shell reads.
# caps_led <1|0|none>: the LED on, off, or not there at all
caps_led() {
    case "$1" in
        none) rm -rf "$WORK/leds/test::capslock" ;;
        0 | 1) mkdir -p "$WORK/leds/test::capslock"; echo "$1" > "$WORK/leds/test::capslock/brightness" ;;
        *) abort "caps_led: 1, 0 or none" ;;
    esac
    log "Caps Lock LED: $1"
}
