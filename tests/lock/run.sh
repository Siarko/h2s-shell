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
# Exit status: 0 when every test passed (or failed exactly as expected, see below), 1
# when one failed (a test that could not start its stack counts as failed), 2 when the
# test bed itself could not be set up before any test ran, 130 when interrupted.
set -uo pipefail

LOCKTEST_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
LOCKTEST_REPO=$(cd "$LOCKTEST_DIR/../.." && pwd)
PER_TEST_TIMEOUT=${LOCKTEST_TEST_TIMEOUT:-150}
PROBE_TIMEOUT=5

# ---- Tests known to fail with today's code ----------------------------------------
# The one place to mark them: the reason, and the checks that are expected to fail (one
# description per line, as the test prints it after "FAIL ", without a trailing
# "(not within N s)"). Such a test counts as XFAIL — exit status 0 — only when it ran to
# its end (no setup failure, no time-out) and the checks that failed are some of these,
# at least one. Any other failure is a FAIL. Passing makes it XPASS, which fails the run,
# so the mark is removed by whoever fixes it rather than left behind.
# (none at present: `relock`, the regression behind the rework, passes since stage 2)
declare -A EXPECTED_TO_FAIL=(
)
declare -A EXPECTED_FAILING_CHECKS=(
)

# ---- Cleanup, whatever ends the run --------------------------------------------------
probe=""
ARTIFACTS=""
TEST_RUNTIME=""
TEST_PID=""
tail_pid=""

# Anything still carrying this run's marker in its environment is ours, wherever it
# ended up (a child that left its process group, a shell helper re-parented to a
# subreaper): stopped after every test. Nothing of the real session carries the marker.
# PAM helpers' children (pam_exec scripts) do not carry it — pam_exec gives them PAM's
# environment only — and are stopped by their process group being killed, and by their
# own orphan check (pam/wait-finger.sh).
sweep() {
    local environ pid found=""
    [ -n "${LOCKTEST_RUN_ID:-}" ] || return 0
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

# Stops the running test: timeout, the test's bash and the stack they started. timeout
# forwards a TERM to its process group (the test's bash, whose EXIT trap stops the
# stack's own groups); what is left after that is killed.
stop_test() {
    [ -n "$TEST_PID" ] || return 0
    kill -TERM "$TEST_PID" 2> /dev/null
    for _ in $(seq 1 60); do
        kill -0 "$TEST_PID" 2> /dev/null || break
        sleep 0.2
    done
    kill -KILL -- "-$TEST_PID" 2> /dev/null
    wait "$TEST_PID" 2> /dev/null
    TEST_PID=""
}

on_signal() {
    trap '' INT TERM HUP
    echo >&2
    echo "run.sh: interrupted, stopping the test bed" >&2
    stop_test
    [ -n "$tail_pid" ] && kill "$tail_pid" 2> /dev/null
    sweep
    [ -n "$TEST_RUNTIME" ] && rm -rf "$TEST_RUNTIME"
    [ -n "$probe" ] && rm -rf "$probe"
    if [ -n "$ARTIFACTS" ]; then
        if [ "${LOCKTEST_KEEP:-0}" = 1 ]; then
            echo "artifacts (logs, screenshots): $ARTIFACTS" >&2
        else
            rm -rf "$ARTIFACTS"
        fi
    fi
    exit 130
}
trap on_signal INT TERM HUP

setup_error() {
    echo "run.sh: $*" >&2
    [ -n "$probe" ] && rm -rf "$probe"
    [ -n "$ARTIFACTS" ] && rm -rf "$ARTIFACTS"
    exit 2
}

[ "$(id -u)" != 0 ] || setup_error "do not run as root"

# Paths are substituted into PAM stacks (sed, split at whitespace by PAM): only plain
# characters are allowed in the temp dir
temp_base=${TMPDIR:-/tmp}
[[ "$temp_base" =~ ^/[A-Za-z0-9._/+-]*$ ]] \
    || setup_error "TMPDIR ($temp_base) must be an absolute path of letters, digits and ._/+- only"

# ---- Tools ----------------------------------------------------------------------------
# Pinned in tools.nix; built (or fetched from the cache) once and reused from the store
echo "resolving tools (tools.nix)…"
command -v nix > /dev/null || setup_error "nix is needed to provide the test tools"
nix_log=$(mktemp "$temp_base/locktest-nix.XXXXXX") || setup_error "cannot create a temp file in $temp_base"
LOCKTEST_TOOLS=$(nix build --no-link --print-out-paths --impure -f "$LOCKTEST_DIR/tools.nix" 2> "$nix_log" | tail -n 1)
if [ -z "$LOCKTEST_TOOLS" ]; then
    cat "$nix_log" >&2
    rm -f "$nix_log"
    setup_error "nix could not build tests/lock/tools.nix (output above)"
fi
rm -f "$nix_log"
for tool in bin/labwc bin/Hyprland bin/hyprctl bin/grim bin/python3 bin/setpriv share/ltproto share/us.xkb; do
    [ -e "$LOCKTEST_TOOLS/$tool" ] || setup_error "the tool set lacks $tool ($LOCKTEST_TOOLS)"
done
SETPRIV=$LOCKTEST_TOOLS/bin/setpriv

# The pinned Hyprland is meant to be the system's: say so when it is not. Both are asked
# for their version only (`--version` prints and exits; no session is contacted).
hyprland_version() { env -i timeout 5 "$1" --version 2> /dev/null | head -n 1; }
system_hyprland=$(command -v Hyprland 2> /dev/null)
if [ -n "$system_hyprland" ]; then
    pinned_version=$(hyprland_version "$LOCKTEST_TOOLS/bin/Hyprland")
    system_version=$(hyprland_version "$system_hyprland")
    [ "$pinned_version" = "$system_version" ] \
        || echo "NOTE: the pinned Hyprland ($pinned_version) is not the system's ($system_version): move the pin in tools.nix"
fi

# The shell is started the way it is for real: through the h2s-shell launcher
LOCKTEST_LAUNCHER=${LOCKTEST_LAUNCHER:-$(command -v h2s-shell)}
[ -x "$LOCKTEST_LAUNCHER" ] || setup_error "no h2s-shell launcher on PATH (set LOCKTEST_LAUNCHER)"

# The Quickshell that launcher runs: asked of the launcher itself, by pointing it at a
# stand-in shell folder whose launch.sh only says which qs it would run. A launcher that
# ignored H2S_SHELL_DIR would start a real shell here, so the probe gets nothing of the
# session: an empty environment but PATH, a private HOME, an empty runtime dir (no
# Wayland socket to show anything on), D-Bus addresses that lead nowhere, no new
# privileges, its own process group, and a few seconds.
if [ -z "${LOCKTEST_QS:-}" ]; then
    probe=$(mktemp -d "$temp_base/locktest-probe.XXXXXX") || setup_error "cannot create a temp dir in $temp_base"
    mkdir -p "$probe/scripts" "$probe/home" "$probe/run" || setup_error "cannot fill the probe dir $probe"
    chmod 700 "$probe/run"
    printf '#!/bin/sh\ncommand -v qs\n' > "$probe/scripts/launch.sh"
    chmod +x "$probe/scripts/launch.sh"
    probe_output=$(env -i PATH="$PATH" HOME="$probe/home" XDG_RUNTIME_DIR="$probe/run" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$probe/run/no-session-bus" \
        DBUS_SYSTEM_BUS_ADDRESS="unix:path=$probe/run/no-system-bus" \
        LIBSEAT_BACKEND=disabled-for-test H2S_SHELL_DIR="$probe" \
        "$SETPRIV" --no-new-privs setsid --wait timeout -k 2 "$PROBE_TIMEOUT" "$LOCKTEST_LAUNCHER" \
        2> /dev/null < /dev/null)
    probe_status=$?
    rm -rf "$probe"
    probe=""
    if [ "$probe_status" = 124 ] || [ "$probe_status" = 137 ]; then
        setup_error "the launcher ($LOCKTEST_LAUNCHER) did not answer within ${PROBE_TIMEOUT} s when asked which qs it runs — does it honour H2S_SHELL_DIR? (or set LOCKTEST_QS)"
    fi
    if [ "$(printf '%s\n' "$probe_output" | wc -l)" != 1 ] || [[ "$probe_output" != /* ]] \
        || [ ! -f "$probe_output" ] || [ ! -x "$probe_output" ]; then
        setup_error "the launcher ($LOCKTEST_LAUNCHER) did not name an executable qs (status $probe_status, said: '${probe_output:0:200}'); set LOCKTEST_QS"
    fi
    LOCKTEST_QS=$probe_output
fi
[ -x "${LOCKTEST_QS:-}" ] || setup_error "cannot find the qs the launcher uses (set LOCKTEST_QS)"

# PAM modules must belong to the libpam the process loads: taken from Quickshell's
quickshell_binary=$(dirname "$LOCKTEST_QS")/.quickshell-wrapped
[ -e "$quickshell_binary" ] || quickshell_binary=$LOCKTEST_QS
libpam=$(ldd "$quickshell_binary" 2> /dev/null | sed -n 's/.*libpam\.so\.0 => \([^ ]*\).*/\1/p' | head -n 1)
LOCKTEST_PAM_MODULES=${LOCKTEST_PAM_MODULES:-$(dirname "${libpam:-/nonexistent/lib/x}")/security}
[ -e "$LOCKTEST_PAM_MODULES/pam_exec.so" ] \
    || setup_error "no pam_exec.so beside Quickshell's libpam ($LOCKTEST_PAM_MODULES; set LOCKTEST_PAM_MODULES)"
[[ "$LOCKTEST_PAM_MODULES" =~ ^/[A-Za-z0-9._/+-]*$ ]] \
    || setup_error "the PAM module path ($LOCKTEST_PAM_MODULES) has characters a PAM stack cannot hold"

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

ARTIFACTS=$(mktemp -d "$temp_base/h2s-locktest.XXXXXX") || setup_error "cannot create the artifacts dir"
LOCKTEST_RUN_ID=$(basename "$ARTIFACTS")-$$

# ---- The shell under test: a copy of the checkout -------------------------------------
# Quickshell reloads the shell on any file written in its folder, and a reload while
# locked unlocks. So the shell runs from a copy made once per run: whatever is written
# to the checkout meanwhile (by you, by another tool) cannot disturb a test. The copy is
# the checkout as it is now, without the test bed itself (tests/lock), git data and
# build results — and with pam/ replaced: the shipped configs check the real account
# (pam_unix), and the shell falls back to them when the methods script fails or lists no
# password. In the copy every one of them denies, so a typed test string can never reach
# the system's password check.
LOCKTEST_SHELL=$ARTIFACTS/shell
mkdir -p "$LOCKTEST_SHELL" || setup_error "cannot create $LOCKTEST_SHELL"
for entry in "$LOCKTEST_REPO"/* "$LOCKTEST_REPO"/.[!.]*; do
    [ -e "$entry" ] || continue
    case "$(basename "$entry")" in .git | result | result-*) continue ;; esac
    cp -a "$entry" "$LOCKTEST_SHELL/" || setup_error "cannot copy $entry into $LOCKTEST_SHELL"
done
rm -rf "$LOCKTEST_SHELL/tests/lock"
[ -f "$LOCKTEST_SHELL/shell.qml" ] && [ -x "$LOCKTEST_SHELL/scripts/lock-auth-methods.sh" ] \
    || setup_error "the copy of the checkout lacks shell.qml or scripts/lock-auth-methods.sh"
rm -rf "$LOCKTEST_SHELL/pam"
mkdir -p "$LOCKTEST_SHELL/pam"
for config in password fingerprint u2f; do
    {
        echo "# Written by tests/lock/run.sh: the copy under test must never check the real account"
        echo "auth     required $LOCKTEST_PAM_MODULES/pam_deny.so"
        echo "account  required $LOCKTEST_PAM_MODULES/pam_deny.so"
    } > "$LOCKTEST_SHELL/pam/$config"
done

# logind's inhibitors held by a process of this run, from the real system bus (read
# only): the shell under test must never add one. Told apart from the real shell's
# (which has the same name) by the PID column.
run_inhibitors() {
    local pid
    for pid in $(systemd-inhibit --list --no-pager --no-legend 2> /dev/null \
        | awk '{ for (i = 1; i + 2 <= NF; i++) if ($i ~ /^[0-9]+$/ && $(i + 2) ~ /^[0-9]+$/) { print $(i + 2); break } }'); do
        { tr "\0" "\n" < "/proc/$pid/environ"; } 2> /dev/null \
            | grep -qx "LOCKTEST_RUN_ID=$LOCKTEST_RUN_ID" && echo "$pid"
    done
}

# The user's own config: a run must not write it
real_config=${XDG_CONFIG_HOME:-$HOME/.config}/h2s_shell/config.json
real_config_stamp() { stat -c '%Y %s' "$real_config" 2> /dev/null || echo absent; }
real_config_before=$(real_config_stamp)
touch "$ARTIFACTS/.started"

# classify <name> <status>: PASS / FAIL / XFAIL / XPASS, from the exit status and the log
classify() {
    local name=$1 status=$2 log=$ARTIFACTS/$1/test.log
    if [ -z "${EXPECTED_TO_FAIL[$name]:-}" ]; then
        [ "$status" = 0 ] && echo PASS || echo FAIL
        return
    fi
    [ "$status" = 0 ] && { echo XPASS; return; }
    # Only an ordinary failure (exit 1 with FAIL lines) can be the expected one
    if [ "$status" != 1 ] || grep -q '^    FAIL (setup)' "$log"; then
        echo FAIL
        return
    fi
    local failed
    failed=$(sed -n 's/^    FAIL //p' "$log" | sed 's/ (not within [0-9.]* s)$//')
    [ -n "$failed" ] || { echo FAIL; return; }
    local line
    while IFS= read -r line; do
        grep -qxF -- "$line" <<< "${EXPECTED_FAILING_CHECKS[$name]:-}" || { echo FAIL; return; }
    done <<< "$failed"
    echo XFAIL
}

started=$SECONDS
declare -A results=()
inhibitor_leak=""
for name in "${tests[@]}"; do
    echo
    echo "== $name"
    mkdir -p "$ARTIFACTS/$name"
    test_started=$SECONDS
    # The test's private runtime dir: created and removed here, so that it goes even when
    # the test is killed. Short: Unix socket paths are limited to 107 bytes.
    TEST_RUNTIME=$(mktemp -d /tmp/lt.XXXXXX) || { echo "    FAIL (setup) cannot create a runtime dir"; results[$name]=FAIL; continue; }
    chmod 700 "$TEST_RUNTIME"
    # Everything of the test runs with no new privileges: setuid programs (pkexec,
    # unix_chkpwd) cannot gain any, so nothing the shell starts can reach polkit or the
    # real password database
    env LOCKTEST_DIR="$LOCKTEST_DIR" LOCKTEST_SHELL="$LOCKTEST_SHELL" LOCKTEST_TOOLS="$LOCKTEST_TOOLS" \
        LOCKTEST_PAM_MODULES="$LOCKTEST_PAM_MODULES" LOCKTEST_LAUNCHER="$LOCKTEST_LAUNCHER" \
        LOCKTEST_QS="$LOCKTEST_QS" LOCKTEST_ARTIFACTS="$ARTIFACTS/$name" LOCKTEST_RUN_ID="$LOCKTEST_RUN_ID" \
        LOCKTEST_RUNTIME="$TEST_RUNTIME" \
        "$SETPRIV" --no-new-privs timeout -k 10 "$PER_TEST_TIMEOUT" bash -c '
            source "$LOCKTEST_DIR/lib.sh"
            source "$LOCKTEST_DIR/tests/$1.sh"
            [ "$FAILURES" -eq 0 ]' _ "$name" > "$ARTIFACTS/$name/test.log" 2>&1 < /dev/null &
    TEST_PID=$!
    tail -n +1 -f --pid="$TEST_PID" "$ARTIFACTS/$name/test.log" 2> /dev/null &
    tail_pid=$!
    wait "$TEST_PID"
    status=$?
    TEST_PID=""
    wait "$tail_pid" 2> /dev/null
    tail_pid=""
    # Before the sweep: anything of the run that holds an inhibitor
    leaked=$(run_inhibitors)
    [ -n "$leaked" ] && inhibitor_leak="$inhibitor_leak $name:$(echo $leaked | tr ' ' ',')"
    sweep
    rm -rf "$TEST_RUNTIME"
    TEST_RUNTIME=""
    if [ "$status" = 124 ] || [ "$status" = 137 ]; then
        echo "    FAIL (setup) timed out after ${PER_TEST_TIMEOUT} s" | tee -a "$ARTIFACTS/$name/test.log"
    fi
    results[$name]=$(classify "$name" "$status")
    echo "== $name: ${results[$name]} ($((SECONDS - test_started)) s)"
done

written_in_checkout=$(find "$LOCKTEST_REPO" -path "$LOCKTEST_REPO/tests/lock" -prune -o \
    -newer "$ARTIFACTS/.started" -print 2> /dev/null | head -n 5)

echo
echo "Summary ($((SECONDS - started)) s):"
failed=0
for name in "${tests[@]}"; do
    result=${results[$name]}
    case "$result" in
        XFAIL) echo "  XFAIL $name — expected for now: ${EXPECTED_TO_FAIL[$name]}" ;;
        XPASS) echo "  XPASS $name — passes now: remove it from EXPECTED_TO_FAIL in run.sh"; failed=1 ;;
        FAIL)
            if [ -n "${EXPECTED_TO_FAIL[$name]:-}" ]; then
                echo "  FAIL  $name — marked as expected to fail, but not (only) in the expected checks"
            else
                echo "  FAIL  $name"
            fi
            failed=1
            ;;
        *) echo "  PASS  $name" ;;
    esac
done
if [ -n "$inhibitor_leak" ]; then
    echo "  FAIL  isolation: a process of the run held an inhibitor on the real logind:$inhibitor_leak"
    failed=1
fi
if [ "$(real_config_stamp)" != "$real_config_before" ]; then
    # A warning only: the real shell writes it too (remembered state); that the test
    # shell used a private one is checked by harness.sh
    echo "  NOTE  $real_config changed during the run (the real shell, or a leak?)"
fi
if [ -n "$written_in_checkout" ]; then
    # The shell ran from a copy made at the start, so this did not disturb it; the
    # results are for the checkout as it was then
    echo "  NOTE  files in the checkout changed during the run; the results are for the copy taken at its start:"
    echo "$written_in_checkout" | sed 's/^/          /'
fi

if [ $failed = 1 ] || [ "${LOCKTEST_KEEP:-0}" = 1 ]; then
    echo "artifacts (logs, screenshots): $ARTIFACTS"
else
    rm -rf "$ARTIFACTS"
fi
exit $failed
