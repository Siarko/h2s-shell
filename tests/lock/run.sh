#!/usr/bin/env bash
# The lock test bed: runs the real shell in an invisible, isolated compositor and drives
# its lock screen with a virtual keyboard and pointer. See README.md.
#
#   tests/lock/run.sh               every test in tests/lock/tests/
#   tests/lock/run.sh relock wrong-password
#                                   the named ones (file names without .sh)
#   LOCKTEST_KEEP=1 tests/lock/run.sh
#                                   keep logs and screenshots even when all pass
#
# Exit status: 0 when every test passed (or failed as expected, see below), 1 when one
# failed, 2 when the test bed itself could not be set up.
set -uo pipefail

LOCKTEST_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
LOCKTEST_REPO=$(cd "$LOCKTEST_DIR/../.." && pwd)
PER_TEST_TIMEOUT=${LOCKTEST_TEST_TIMEOUT:-150}

# ---- Tests known to fail with today's code ----------------------------------------
# The one place to mark them. Such a test failing counts as expected (XFAIL) and keeps
# the exit status 0; passing makes it XPASS, which fails the run, so the mark is removed
# by whoever fixes it rather than left behind.
declare -A EXPECTED_TO_FAIL=(
    [relock]="Quickshell 0.3.2 never notifies WlSessionLock's unlock, so the shell does not re-arm after the first unlock (docs/plans/lockscreen.md §1); stage 2 turns this green"
)

setup_error() { echo "run.sh: $*" >&2; exit 2; }

[ "$(id -u)" != 0 ] || setup_error "do not run as root"

# ---- Tools ----------------------------------------------------------------------------
# Pinned in tools.nix; built (or fetched from the cache) once and reused from the store
echo "resolving tools (tools.nix)…"
command -v nix > /dev/null || setup_error "nix is needed to provide the test tools"
LOCKTEST_TOOLS=$(nix build --no-link --print-out-paths --impure -f "$LOCKTEST_DIR/tools.nix" 2> "${TMPDIR:-/tmp}/locktest-nix.$$.log" | tail -n 1)
if [ -z "$LOCKTEST_TOOLS" ]; then
    cat "${TMPDIR:-/tmp}/locktest-nix.$$.log" >&2
    rm -f "${TMPDIR:-/tmp}/locktest-nix.$$.log"
    setup_error "nix could not build tests/lock/tools.nix (output above)"
fi
rm -f "${TMPDIR:-/tmp}/locktest-nix.$$.log"
for tool in bin/labwc bin/Hyprland bin/hyprctl bin/grim bin/python3 share/ltproto share/us.xkb; do
    [ -e "$LOCKTEST_TOOLS/$tool" ] || setup_error "the tool set lacks $tool ($LOCKTEST_TOOLS)"
done

# The shell is started the way it is for real: through the h2s-shell launcher
LOCKTEST_LAUNCHER=${LOCKTEST_LAUNCHER:-$(command -v h2s-shell)}
[ -x "$LOCKTEST_LAUNCHER" ] || setup_error "no h2s-shell launcher on PATH (set LOCKTEST_LAUNCHER)"

# The Quickshell that launcher runs: asked of the launcher itself, by pointing it at a
# stand-in shell folder whose launch.sh only says which qs it would run
if [ -z "${LOCKTEST_QS:-}" ]; then
    probe=$(mktemp -d "${TMPDIR:-/tmp}/locktest-probe.XXXXXX")
    mkdir -p "$probe/scripts"
    printf '#!/bin/sh\ncommand -v qs\n' > "$probe/scripts/launch.sh"
    chmod +x "$probe/scripts/launch.sh"
    LOCKTEST_QS=$(H2S_SHELL_DIR=$probe "$LOCKTEST_LAUNCHER" 2> /dev/null)
    rm -rf "$probe"
fi
[ -x "${LOCKTEST_QS:-}" ] || setup_error "cannot find the qs the launcher uses (set LOCKTEST_QS)"

# PAM modules must belong to the libpam the process loads: taken from Quickshell's
quickshell_binary=$(dirname "$LOCKTEST_QS")/.quickshell-wrapped
[ -e "$quickshell_binary" ] || quickshell_binary=$LOCKTEST_QS
libpam=$(ldd "$quickshell_binary" 2> /dev/null | sed -n 's/.*libpam\.so\.0 => \([^ ]*\).*/\1/p' | head -n 1)
LOCKTEST_PAM_MODULES=${LOCKTEST_PAM_MODULES:-$(dirname "${libpam:-/nonexistent/lib/x}")/security}
[ -e "$LOCKTEST_PAM_MODULES/pam_exec.so" ] \
    || setup_error "no pam_exec.so beside Quickshell's libpam ($LOCKTEST_PAM_MODULES; set LOCKTEST_PAM_MODULES)"

# ---- Tests ----------------------------------------------------------------------------
if [ $# -gt 0 ]; then
    tests=("$@")
else
    tests=()
    for file in "$LOCKTEST_DIR"/tests/*.sh; do tests+=("$(basename "$file" .sh)"); done
fi
for name in "${tests[@]}"; do
    [ -f "$LOCKTEST_DIR/tests/$name.sh" ] || setup_error "no test $name (tests/lock/tests/$name.sh)"
done

ARTIFACTS=$(mktemp -d "${TMPDIR:-/tmp}/h2s-locktest.XXXXXX") || setup_error "cannot create the artifacts dir"
LOCKTEST_RUN_ID=$(basename "$ARTIFACTS")-$$

# Anything still carrying this run's marker in its environment is ours, wherever it
# ended up (a PAM helper's orphan, a child that left its process group): stopped after
# every test. Nothing of the real session carries the marker.
sweep() {
    local environ pid found=""
    for environ in /proc/[0-9]*/environ; do
        pid=${environ#/proc/}
        pid=${pid%/environ}
        [ "$pid" = $$ ] && continue
        [ -O "$environ" ] && { tr "\0" "\n" < "$environ"; } 2> /dev/null \
            | grep -qx "LOCKTEST_RUN_ID=$LOCKTEST_RUN_ID" || continue
        found="$found $pid"
    done
    [ -n "$found" ] || return 0
    echo "    swept leftover processes:$found"
    kill -KILL $found 2> /dev/null
}

# logind's inhibitors named h2s-shell, from the real system bus (read only): the shell
# under test must never add one
real_inhibitors() { systemd-inhibit --list --no-pager 2> /dev/null | grep -c 'h2s-shell'; }
inhibitors_before=$(real_inhibitors)

# The user's own config, and the checkout: neither may be written by a run (the shell
# under test reloads on any file written in the checkout)
real_config=${XDG_CONFIG_HOME:-$HOME/.config}/h2s_shell/config.json
real_config_stamp() { stat -c '%Y %s' "$real_config" 2> /dev/null || echo absent; }
real_config_before=$(real_config_stamp)
touch "$ARTIFACTS/.started"

started=$SECONDS
declare -A results=()
for name in "${tests[@]}"; do
    echo
    echo "== $name"
    mkdir -p "$ARTIFACTS/$name"
    test_started=$SECONDS
    env LOCKTEST_DIR="$LOCKTEST_DIR" LOCKTEST_REPO="$LOCKTEST_REPO" LOCKTEST_TOOLS="$LOCKTEST_TOOLS" \
        LOCKTEST_PAM_MODULES="$LOCKTEST_PAM_MODULES" LOCKTEST_LAUNCHER="$LOCKTEST_LAUNCHER" \
        LOCKTEST_QS="$LOCKTEST_QS" LOCKTEST_ARTIFACTS="$ARTIFACTS/$name" LOCKTEST_RUN_ID="$LOCKTEST_RUN_ID" \
        timeout -k 10 "$PER_TEST_TIMEOUT" bash -c '
            source "$LOCKTEST_DIR/lib.sh"
            source "$LOCKTEST_DIR/tests/$1.sh"
            [ "$FAILURES" -eq 0 ]' _ "$name" 2>&1 | tee "$ARTIFACTS/$name/test.log"
    status=${PIPESTATUS[0]}
    sweep
    [ "$status" = 124 ] && echo "    FAIL timed out after ${PER_TEST_TIMEOUT} s"
    if [ -n "${EXPECTED_TO_FAIL[$name]:-}" ]; then
        if [ "$status" = 0 ]; then results[$name]=XPASS; else results[$name]=XFAIL; fi
    else
        if [ "$status" = 0 ]; then results[$name]=PASS; else results[$name]=FAIL; fi
    fi
    echo "== $name: ${results[$name]} ($((SECONDS - test_started)) s)"
done

inhibitors_after=$(real_inhibitors)
written_in_checkout=$(find "$LOCKTEST_REPO" -newer "$ARTIFACTS/.started" -print 2> /dev/null | head -n 5)

echo
echo "Summary ($((SECONDS - started)) s):"
failed=0
for name in "${tests[@]}"; do
    result=${results[$name]}
    case "$result" in
        XFAIL) echo "  XFAIL $name — expected for now: ${EXPECTED_TO_FAIL[$name]}" ;;
        XPASS) echo "  XPASS $name — passes now: remove it from EXPECTED_TO_FAIL in run.sh"; failed=1 ;;
        FAIL) echo "  FAIL  $name"; failed=1 ;;
        *) echo "  PASS  $name" ;;
    esac
done
if [ "$inhibitors_after" != "$inhibitors_before" ]; then
    echo "  FAIL  isolation: the real logind's h2s-shell inhibitors went from $inhibitors_before to $inhibitors_after"
    failed=1
fi
if [ "$(real_config_stamp)" != "$real_config_before" ]; then
    # A warning only: the real shell writes it too (remembered state); that the test
    # shell used a private one is checked by harness.sh
    echo "  NOTE  $real_config changed during the run (the real shell, or a leak?)"
fi
if [ -n "$written_in_checkout" ]; then
    echo "  FAIL  isolation: files in the checkout changed during the run (yours, or the test bed's?):"
    echo "$written_in_checkout" | sed 's/^/          /'
    failed=1
fi

if [ $failed = 1 ] || [ "${LOCKTEST_KEEP:-0}" = 1 ]; then
    echo "artifacts (logs, screenshots): $ARTIFACTS"
else
    rm -rf "$ARTIFACTS"
fi
exit $failed
