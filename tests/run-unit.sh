#!/usr/bin/env bash
# Runs the unit suites (tests.qml) in a private, headless compositor, so that nothing shows
# on the screen: PointerInputTest and LockViewTest open a small window, and in the real
# session it would appear there, under your pointer.
#
#   tests/run-unit.sh            the suites of this checkout
#   tests/run-unit.sh <log>      the output also saved to <log>
#
# The compositor is a headless labwc (wlroots' headless backend, no input devices) in a
# private runtime dir, with D-Bus addresses that lead nowhere, a private HOME and XDG
# directories (Config is read-only under the runner anyway), no new privileges. The tools
# are found as the lock test bed finds them (tests/lock/resolve.sh: labwc from
# tests/lock/tools.nix, Quickshell from the h2s-shell launcher, or LOCKTEST_QS).
#
# Exit status: 0 when every suite passed, 1 when a check FAILed, a suite timed out, a
# TypeError / ReferenceError was printed, Quickshell exited non-zero (a crash after a
# partial summary included) or fewer suites reported than tests.qml registers, 2 when the
# runner could not be set up.
set -uo pipefail

LOCKTEST_DIR=$(cd "$(dirname "$(readlink -f "$0")")/lock" && pwd)
REPO=$(cd "$LOCKTEST_DIR/../.." && pwd)
PROBE_TIMEOUT=5
probe=""
work=""
output_copy=${1:-}

cleanup() {
    [ -n "${labwc_pid:-}" ] && { kill -TERM -- "-$labwc_pid" 2> /dev/null; sleep 0.3; kill -KILL -- "-$labwc_pid" 2> /dev/null; }
    [ -n "$probe" ] && rm -rf "$probe"
    [ -n "$work" ] && rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

setup_error() {
    echo "run-unit.sh: $*" >&2
    exit 2
}

[ "$(id -u)" != 0 ] || setup_error "do not run as root"
temp_base=${TMPDIR:-/tmp}
source "$LOCKTEST_DIR/resolve.sh"

# Short: a Unix socket path is limited to 107 bytes
work=$(mktemp -d /tmp/ut.XXXXXX) || setup_error "cannot create a temp dir"
chmod 700 "$work"
mkdir -p "$work/run" "$work/home" "$work/labwc" "$work/xdg/config" "$work/xdg/cache" "$work/xdg/data" "$work/xdg/state"
chmod 700 "$work/run"
echo '<?xml version="1.0"?><labwc_config/>' > "$work/labwc/rc.xml"

isolated=(env -i PATH="$LOCKTEST_TOOLS/bin:$PATH" HOME="$work/home" XDG_RUNTIME_DIR="$work/run"
    XDG_CONFIG_HOME="$work/xdg/config" XDG_CACHE_HOME="$work/xdg/cache" XDG_DATA_HOME="$work/xdg/data"
    XDG_STATE_HOME="$work/xdg/state" LANG=en_US.UTF-8
    DBUS_SESSION_BUS_ADDRESS="unix:path=$work/run/no-session-bus"
    DBUS_SYSTEM_BUS_ADDRESS="unix:path=$work/run/no-system-bus" LIBSEAT_BACKEND=disabled-for-test)

"${isolated[@]}" WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_HEADLESS_OUTPUTS=1 \
    "$SETPRIV" --no-new-privs setsid timeout 300 labwc -C "$work/labwc" > "$work/labwc.log" 2>&1 < /dev/null &
labwc_pid=$!
for _ in $(seq 1 100); do [ -S "$work/run/wayland-0" ] && break; sleep 0.1; done
[ -S "$work/run/wayland-0" ] || { cat "$work/labwc.log" >&2; setup_error "the headless compositor did not start"; }

started=$SECONDS
"${isolated[@]}" WAYLAND_DISPLAY=wayland-0 QT_QPA_PLATFORM=wayland \
    "$SETPRIV" --no-new-privs timeout 240 "$LOCKTEST_QS" -p "$REPO/tests.qml" > "$work/unit.log" 2>&1 < /dev/null
status=$?
[ -n "$output_copy" ] && cp "$work/unit.log" "$output_copy"
cat "$work/unit.log"

failed=0
summary=$(grep -E -- '^.*--- .*: [0-9]+/[0-9]+ passed' "$work/unit.log" | sed 's/^.*--- /--- /')
fails=$(grep -c -E '  FAIL: ' "$work/unit.log")
errors=$(grep -c -E 'TypeError|ReferenceError' "$work/unit.log")
echo
echo "Unit suites ($((SECONDS - started)) s, quickshell exit $status):"
echo "$summary" | sed 's/^/  /'
[ "$fails" -gt 0 ] && { echo "  $fails check(s) FAILED"; failed=1; }
[ "$errors" -gt 0 ] && { echo "  $errors TypeError/ReferenceError line(s)"; grep -E 'TypeError|ReferenceError' "$work/unit.log" | head -n 10 | sed 's/^/    /'; failed=1; }
[ "$status" = 124 ] && { echo "  quickshell timed out"; failed=1; }
# Any other non-zero status is a failure too: a crash (139: SIGSEGV) after a partial
# summary with no FAIL line in it must not pass
[ "$status" != 0 ] && [ "$status" != 124 ] && { echo "  quickshell exited with status $status"; failed=1; }
# Every suite tests.qml registers (`property var _name: SomethingTest {}`) must report
expected=$(grep -c -E '^[[:space:]]*property var _[A-Za-z0-9]+: [A-Za-z0-9]+Test \{\}' "$REPO/tests.qml")
reported=$(printf '%s\n' "$summary" | grep -c -- '^--- ')
[ "$reported" -lt "$expected" ] && { echo "  only $reported of the $expected suites in tests.qml reported"; failed=1; }
[ -n "$summary" ] || { echo "  no suite reported: quickshell did not run them"; failed=1; }
exit $failed
