# shellcheck shell=bash
# The headless isolation the QML suites run in, shared by tests/run-unit.sh (the shell's
# suites, tests.qml) and tests/run-modules.sh (modules' suites, tests-modules.qml). Sourced;
# the caller sets HEADLESS_NAME (its name, for messages) and REPO (the shell's tree, the
# config root Quickshell is started in) first.
#
# The compositor is a headless labwc (wlroots' headless backend, no input devices) in a
# private runtime dir, with D-Bus addresses that lead nowhere, a private HOME and XDG
# directories (Config is read-only under the runners anyway), no new privileges. The tools
# are found by tests/lock/resolve.sh, shared with the lock test bed: labwc and setpriv from
# the pinned tests/lock/tools.nix where there is a `nix` command, else from PATH
# (H2S_TEST_TOOLS=nix or =system says which); Quickshell is LOCKTEST_QS, else the one the
# h2s-shell launcher runs, else qs or quickshell on PATH. The run's first lines say what was
# taken; a missing tool is a set-up error (exit 2) that names it.
#
#   headless_setup                         the private dirs and the compositor (exit 2 on failure)
#   headless_run <root.qml> <copy> [VAR=value…]
#                                          Quickshell on that root file, with those variables
#                                          added; its output printed (and copied to <copy>
#                                          unless ""); HEADLESS_LOG, HEADLESS_STATUS set
#   headless_verdict <title> <expected> <where> [exactly [<suite name>…]]
#                                          the summary; returns 1 on any FAIL line, a
#                                          TypeError / ReferenceError, a non-zero exit of
#                                          Quickshell (a crash after a partial summary
#                                          included), a time-out, or fewer suites reporting
#                                          than <expected> (<where> says where they are
#                                          registered, or "selected"); with `exactly` (a
#                                          selection was run) also on more suites reporting
#                                          than <expected>, and on a named suite (TestCase's
#                                          suiteName) not reporting; 0 otherwise

LOCKTEST_DIR=$REPO/tests/lock
# Read by resolve.sh
# shellcheck disable=SC2034
PROBE_TIMEOUT=5
# What these runners use of the tools: the compositor, not the lock bed's whole set
# shellcheck disable=SC2034
LOCKTEST_NEED=unit
probe=""
work=""

headless_cleanup() {
    [ -n "${labwc_pid:-}" ] && { kill -TERM -- "-$labwc_pid" 2> /dev/null; sleep 0.3; kill -KILL -- "-$labwc_pid" 2> /dev/null; }
    [ -n "$probe" ] && rm -rf "$probe"
    [ -n "$work" ] && rm -rf "$work"
}
trap headless_cleanup EXIT
trap 'exit 130' INT TERM HUP

setup_error() {
    echo "$HEADLESS_NAME: $*" >&2
    exit 2
}

headless_setup() {
    [ "$(id -u)" != 0 ] || setup_error "do not run as root"
    # shellcheck disable=SC2034  # read by resolve.sh
    temp_base=${TMPDIR:-/tmp}
    # shellcheck source=lock/resolve.sh
    source "$LOCKTEST_DIR/resolve.sh"

    # Short: a Unix socket path is limited to 107 bytes
    work=$(mktemp -d /tmp/ut.XXXXXX) || setup_error "cannot create a temp dir"
    chmod 700 "$work"
    mkdir -p "$work/run" "$work/home" "$work/labwc" "$work/xdg/config" "$work/xdg/cache" "$work/xdg/data" "$work/xdg/state"
    chmod 700 "$work/run"
    echo '<?xml version="1.0"?><labwc_config/>' > "$work/labwc/rc.xml"

    isolated=(env -i PATH="${LOCKTEST_TOOLS:+$LOCKTEST_TOOLS/bin:}$PATH" HOME="$work/home" XDG_RUNTIME_DIR="$work/run"
        XDG_CONFIG_HOME="$work/xdg/config" XDG_CACHE_HOME="$work/xdg/cache" XDG_DATA_HOME="$work/xdg/data"
        XDG_STATE_HOME="$work/xdg/state" LANG=en_US.UTF-8
        DBUS_SESSION_BUS_ADDRESS="unix:path=$work/run/no-session-bus"
        DBUS_SYSTEM_BUS_ADDRESS="unix:path=$work/run/no-system-bus" LIBSEAT_BACKEND=disabled-for-test)

    "${isolated[@]}" WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_HEADLESS_OUTPUTS=1 \
        "$SETPRIV" --no-new-privs setsid timeout 300 "$LOCKTEST_LABWC" -C "$work/labwc" > "$work/labwc.log" 2>&1 < /dev/null &
    labwc_pid=$!
    for _ in $(seq 1 100); do [ -S "$work/run/wayland-0" ] && break; sleep 0.1; done
    [ -S "$work/run/wayland-0" ] || { cat "$work/labwc.log" >&2; setup_error "the headless compositor did not start"; }
}

headless_run() {
    local root=$1 output_copy=$2
    shift 2
    HEADLESS_LOG=$work/unit.log
    headless_started=$SECONDS
    "${isolated[@]}" "$@" WAYLAND_DISPLAY=wayland-0 QT_QPA_PLATFORM=wayland \
        "$SETPRIV" --no-new-privs timeout 240 "$LOCKTEST_QS" -p "$root" > "$HEADLESS_LOG" 2>&1 < /dev/null
    HEADLESS_STATUS=$?
    [ -n "$output_copy" ] && cp "$HEADLESS_LOG" "$output_copy"
    cat "$HEADLESS_LOG"
}

headless_verdict() {
    local title=$1 expected=$2 where=$3 status=$HEADLESS_STATUS failed=0 summary fails errors reported name
    shift 3
    summary=$(grep -E -- '^.*--- .*: [0-9]+/[0-9]+ passed' "$HEADLESS_LOG" | sed 's/^.*--- /--- /')
    fails=$(grep -c -E '  FAIL: ' "$HEADLESS_LOG")
    errors=$(grep -c -E 'TypeError|ReferenceError' "$HEADLESS_LOG")
    echo
    echo "$title ($((SECONDS - headless_started)) s, quickshell exit $status):"
    echo "$summary" | sed 's/^/  /'
    [ "$fails" -gt 0 ] && { echo "  $fails check(s) FAILED"; failed=1; }
    [ "$errors" -gt 0 ] && { echo "  $errors TypeError/ReferenceError line(s)"; grep -E 'TypeError|ReferenceError' "$HEADLESS_LOG" | head -n 10 | sed 's/^/    /'; failed=1; }
    [ "$status" = 124 ] && { echo "  quickshell timed out"; failed=1; }
    # Any other non-zero status is a failure too: a crash (139: SIGSEGV) after a partial
    # summary with no FAIL line in it must not pass
    [ "$status" != 0 ] && [ "$status" != 124 ] && { echo "  quickshell exited with status $status"; failed=1; }
    reported=$(printf '%s\n' "$summary" | grep -c -- '^--- ')
    [ "$reported" -lt "$expected" ] && { echo "  only $reported of the $expected suites $where reported"; failed=1; }
    # A selection: each of its suites, and no other. A suite left out by mistake and one run
    # by mistake are both a wrong answer to "run these"
    if [ "${1:-}" = exactly ]; then
        shift
        [ "$reported" -gt "$expected" ] && { echo "  $reported suites reported, $expected were $where"; failed=1; }
        for name in "$@"; do
            printf '%s\n' "$summary" | grep -q -F -- "--- $name: " || { echo "  $name did not report"; failed=1; }
        done
    fi
    [ -n "$summary" ] || { echo "  no suite reported: quickshell did not run them"; failed=1; }
    return $failed
}
