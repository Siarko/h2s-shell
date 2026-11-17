#!/usr/bin/env bash
# The lock test bed: runs the real shell in an invisible, isolated compositor and drives
# its lock screen with a virtual keyboard and pointer. See README.md.
#
#   tests/lock/run.sh               every test in tests/lock/tests/, several at a time
#   tests/lock/run.sh relock wrong-password
#                                   the named ones (file names without .sh)
#   tests/lock/run.sh -j 3 …        at most 3 tests at a time (LOCKTEST_JOBS=3 too); -j 1
#                                   runs them one after another, their output as it comes
#   LOCKTEST_KEEP=1 tests/lock/run.sh
#                                   keep logs and screenshots even when all pass
#   LOCKTEST_EXTRA_TESTS=<dir> tests/lock/run.sh <name>…
#                                   tests from another directory too (a module's repository:
#                                   <dir>/<name>.sh, written as these are); a name is looked
#                                   for here first. Without names: these and that dir's
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

# ---- Tests that run alone ------------------------------------------------------------
# With more than one job, these run one at a time after all the others have finished, on
# a machine with nothing else of the run going on: what they check IS a timing that a
# loaded machine (five stacks of two compositors and a Qt shell each) cannot keep. The
# reason for each; a test goes here only when its subject is timing, not because it
# flaked — a flake on a condition the test should have waited for is fixed in the test.
declare -A SERIAL=(
    [reload-window]="a logind signal sent 0 and 0.4 s into a reload: on a loaded machine a reload takes longer, and the moments it means (early in the build, late in it) are no longer the ones it hits (the margin it checks is ~2.9 s, loaded or not)"
)
# (`supervisor` left this list once the launcher's look round /proc after a death stopped
# forking per process: 1.5 s -> 0.04 s, and 5/5 in a parallel run of the restart tests)

# Started first in a parallel run, the longest first, so that the run does not end
# waiting for one long test started last (seconds in a parallel run, rounded). Only an
# order: a test missing here runs anyway, after these.
LONG_TESTS=(
    restart-locked-retry restart-no-restore two-outputs restart-no-restore-generic
    methods-fprintd restart-crash-locked fingerprint-timeout marker-stale
    restart-crash-finger reload-explicit restart-launcher modules-launcher idle scale
)

# ---- Jobs -----------------------------------------------------------------------------
# How many tests run at once: -j N (or -jN, --jobs N) before the test names, else
# LOCKTEST_JOBS, else one fewer than the cores, at most 4: each test is two compositors and
# a Qt shell, and with 5 at once on 6 cores (load 12) the launcher's restart tests no longer
# fit their schedule; at 4 the load stays near 8 and a full run takes some five minutes.
jobs=${LOCKTEST_JOBS:-}
args=()
while [ $# -gt 0 ]; do
    case "$1" in
        -j | --jobs) jobs=${2:-missing}; shift; [ $# -gt 0 ] && shift ;;
        -j?*) jobs=${1#-j}; shift ;;
        --jobs=*) jobs=${1#--jobs=}; jobs=${jobs:-missing}; shift ;;
        --) shift; args+=("$@"); break ;;
        *) args+=("$1"); shift ;;
    esac
done
set -- "${args[@]+"${args[@]}"}"
if [ -z "$jobs" ]; then
    jobs=$(( $(nproc 2> /dev/null || echo 2) - 1 ))
    [ "$jobs" -gt 4 ] && jobs=4
    [ "$jobs" -lt 1 ] && jobs=1
fi

# ---- Cleanup, whatever ends the run --------------------------------------------------
probe=""
ARTIFACTS=""
declare -A RUNNING=()   # pid of a running test's timeout -> the test's name
declare -A RUNTIME=()   # name of a running test -> its private runtime dir
declare -A TAIL=()      # name of a running test -> the pid of the tail showing its log (-j 1)

# sweep <variable> <value>: kills every process of ours whose initial environment holds
# exactly <variable>=<value>. After each test with the test's own marker (LOCKTEST_TEST_ID:
# a sibling test's processes do not carry it), at the end and when interrupted with the
# run's (LOCKTEST_RUN_ID: every process of every test carries it). Anything carrying a
# marker is ours, wherever it ended up (a child that left its process group, a shell
# helper re-parented to a subreaper). Nothing of the real session carries either.
# PAM helpers' children (pam_exec scripts) do not carry it — pam_exec gives them PAM's
# environment only — and are stopped by their process group being killed, and by their
# own orphan check (pam/wait-finger.sh).
sweep() {
    local variable=${1:-} value=${2:-} environ pid found=""
    [ -n "$variable" ] && [ -n "$value" ] || return 0
    for environ in /proc/[0-9]*/environ; do
        pid=${environ#/proc/}
        pid=${pid%/environ}
        [ "$pid" = $$ ] && continue
        [ -O "$environ" ] && { tr "\0" "\n" < "$environ"; } 2> /dev/null \
            | grep -qxF -- "$variable=$value" || continue
        found="$found $pid"
    done
    [ -n "$found" ] || return 0
    echo "    swept leftover processes:$found"
    kill -KILL $found 2> /dev/null
}

# Stops every running test: timeout, the test's bash and the stack they started. timeout
# forwards a TERM to its process group (the test's bash, whose EXIT trap stops the
# stack's own groups); what is left after that is killed.
stop_tests() {
    local pid alive
    [ ${#RUNNING[@]} -gt 0 ] || return 0
    for pid in "${!RUNNING[@]}"; do kill -TERM "$pid" 2> /dev/null; done
    for _ in $(seq 1 60); do
        alive=0
        for pid in "${!RUNNING[@]}"; do kill -0 "$pid" 2> /dev/null && alive=1; done
        [ $alive = 0 ] && break
        sleep 0.2
    done
    for pid in "${!RUNNING[@]}"; do
        kill -KILL -- "-$pid" 2> /dev/null
        wait "$pid" 2> /dev/null
    done
    RUNNING=()
}

on_signal() {
    trap '' INT TERM HUP
    local name
    echo >&2
    echo "run.sh: interrupted, stopping the test bed" >&2
    stop_tests
    for name in "${!TAIL[@]}"; do kill "${TAIL[$name]}" 2> /dev/null; done
    sweep LOCKTEST_RUN_ID "${LOCKTEST_RUN_ID:-}"
    for name in "${!RUNTIME[@]}"; do
        [ -n "${RUNTIME[$name]}" ] && rm -rf "${RUNTIME[$name]}"
    done
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
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || setup_error "the number of jobs (-j / LOCKTEST_JOBS) must be a positive whole number, not '$jobs'"

# Paths are substituted into PAM stacks (sed, split at whitespace by PAM): only plain
# characters are allowed in the temp dir
temp_base=${TMPDIR:-/tmp}
[[ "$temp_base" =~ ^/[A-Za-z0-9._/+-]*$ ]] \
    || setup_error "TMPDIR ($temp_base) must be an absolute path of letters, digits and ._/+- only"

# ---- Tools, the launcher and its Quickshell (resolve.sh, shared with tests/run-unit.sh) ----
# Resolved once here and handed to every test in its environment
LOCKTEST_NEED=lock
source "$LOCKTEST_DIR/resolve.sh"

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
    tests=()
    declare -A named=()
    # Each once: a test's artifacts dir and marker are named after it
    for name in "$@"; do
        [ -n "${named[$name]:-}" ] || tests+=("$name")
        named[$name]=1
    done
else
    tests=()
    for file in "$LOCKTEST_DIR"/tests/*.sh ${LOCKTEST_EXTRA_TESTS:+"$LOCKTEST_EXTRA_TESTS"/*.sh}; do
        [ -f "$file" ] && tests+=("$(basename "$file" .sh)")
    done
fi
# The file of each test: here, else in LOCKTEST_EXTRA_TESTS
declare -A TEST_FILE=()
for name in "${tests[@]}"; do
    [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || setup_error "no test $name (tests/lock/tests/$name.sh)"
    # A test's logs go to a directory of its name in the run's artifacts dir, beside the
    # run's own
    case "$name" in
        tools | shell | shells | .started) setup_error "a test cannot be called $name: the run keeps something of its own under that name in its artifacts dir" ;;
    esac
    if [ -f "$LOCKTEST_DIR/tests/$name.sh" ]; then
        TEST_FILE[$name]=$LOCKTEST_DIR/tests/$name.sh
    elif [ -n "${LOCKTEST_EXTRA_TESTS:-}" ] && [ -f "$LOCKTEST_EXTRA_TESTS/$name.sh" ]; then
        TEST_FILE[$name]=$(cd "$LOCKTEST_EXTRA_TESTS" && pwd -P)/$name.sh
    else
        setup_error "no test $name (tests/lock/tests/$name.sh${LOCKTEST_EXTRA_TESTS:+, $LOCKTEST_EXTRA_TESTS/$name.sh})"
    fi
done

ARTIFACTS=$(mktemp -d "$temp_base/h2s-locktest.XXXXXX") || setup_error "cannot create the artifacts dir"
LOCKTEST_RUN_ID=$(basename "$ARTIFACTS")-$$

# With the system's tools, the set tools.nix would have built is made here, for this run:
# links to the programs found on PATH, the protocol bindings and the keymaps (resolve.sh)
if [ "$LOCKTEST_TOOL_SOURCE" = system ]; then
    make_system_tools "$ARTIFACTS/tools"
    LOCKTEST_TOOLS=$ARTIFACTS/tools
fi

# ---- The shell under test: a copy of the checkout, one per test -----------------------
# Quickshell reloads the shell on any file written in its folder, and a reload while
# locked unlocks. So the shell runs from a copy: whatever is written to the checkout
# meanwhile (by you, by another tool) cannot disturb a test. The copy is the checkout as
# it is at the start of the run, without the test bed itself (tests/lock), git data and
# build results — and with pam/ replaced: the shipped configs check the real account
# (pam_unix), and the shell falls back to them when the methods script fails or lists no
# password. In the copy every one of them denies, so a typed test string can never reach
# the system's password check.
#
# It is made once (shell/, never run from) and copied again for each test (shells/<name>,
# a few MB, some 20 ms): tests edit their copy on purpose (edit-while-locked,
# reload-while-locked, reload-window, restart-locked-retry), and with tests running side
# by side an edit in a shared copy would reload or break every other test's shell.
shell_template=$ARTIFACTS/shell
mkdir -p "$shell_template" "$ARTIFACTS/shells" || setup_error "cannot create $shell_template"
for entry in "$LOCKTEST_REPO"/* "$LOCKTEST_REPO"/.[!.]*; do
    [ -e "$entry" ] || continue
    case "$(basename "$entry")" in .git | result | result-*) continue ;; esac
    cp -a "$entry" "$shell_template/" || setup_error "cannot copy $entry into $shell_template"
done
rm -rf "$shell_template/tests/lock"
[ -f "$shell_template/shell.qml" ] && [ -x "$shell_template/scripts/lock-auth-methods.sh" ] \
    || setup_error "the copy of the checkout lacks shell.qml or scripts/lock-auth-methods.sh"
rm -rf "$shell_template/pam"
mkdir -p "$shell_template/pam"
for config in password fingerprint u2f; do
    {
        echo "# Written by tests/lock/run.sh: the copy under test must never check the real account"
        echo "auth     required $LOCKTEST_PAM_MODULES/pam_deny.so"
        echo "account  required $LOCKTEST_PAM_MODULES/pam_deny.so"
    } > "$shell_template/pam/$config"
done

# logind's inhibitors held by a process carrying <variable>=<value> (a test's marker, or
# the run's), from the real system bus (read only): the shell under test must never add
# one. Told apart from the real shell's (which has the same name) by the PID column.
marked_inhibitors() {
    local variable=$1 value=$2 pid
    [ -n "$variable" ] && [ -n "$value" ] || return 0
    for pid in $(systemd-inhibit --list --no-pager --no-legend 2> /dev/null \
        | awk '{ for (i = 1; i + 2 <= NF; i++) if ($i ~ /^[0-9]+$/ && $(i + 2) ~ /^[0-9]+$/) { print $(i + 2); break } }'); do
        { tr "\0" "\n" < "/proc/$pid/environ"; } 2> /dev/null \
            | grep -qxF -- "$variable=$value" && echo "$pid"
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

# No core files: some tests crash the shell on purpose (restart-crash-*, modules), and a
# core of Quickshell is some 15 MB kept outside the run's directories. Inherited by every
# process of every test. (Where crashes go to systemd-coredump, it still writes its journal
# entry for each; it stores no core for a process whose limit is 0.)
ulimit -c 0 2> /dev/null

started=$SECONDS
declare -A results=()
declare -A test_started=()
inhibitor_leak=""
total=${#tests[@]}
launched=0

# With one job a test's output shows as it comes (as it always did); with more, each test's
# output is printed as one block when it has finished, and a line when one starts
serial_output() { [ "$jobs" = 1 ]; }

# test_id <name>: the marker every process of that test carries beside the run's
test_id() { echo "$LOCKTEST_RUN_ID/$1"; }

# start_test <name>: in the background; RUNNING, RUNTIME (and TAIL) say it runs
start_test() {
    local name=$1 runtime pid copy=$ARTIFACTS/shells/$1
    launched=$((launched + 1))
    serial_output && { echo; echo "== $name"; }
    mkdir -p "$ARTIFACTS/$name"
    test_started[$name]=$SECONDS
    # The test's private runtime dir: created and removed here, so that it goes even when
    # the test is killed. Short: Unix socket paths are limited to 107 bytes.
    # (Straight into RUNTIME: an interrupt right after must find it to remove it)
    RUNTIME[$name]=$(mktemp -d /tmp/lt.XXXXXX) || { setup_failed "$name" "cannot create a runtime dir"; return; }
    runtime=${RUNTIME[$name]}
    chmod 700 "$runtime"
    cp -a "$shell_template" "$copy" || { setup_failed "$name" "cannot copy the shell to $copy"; return; }
    # The test gets nothing of the caller's environment but what is named here: where
    # programs and temp files are, who runs it, the time zone, the locale data and the data
    # dirs (NixOS finds its locales and the shell its icons and fonts through them), and the
    # two settings a caller may give a test (lib.sh reads them). No display, no bus, no seat,
    # no agent socket, no toolkit setting of the session: lib.sh then sets the test's own,
    # and still unsets the session's variables by name, should this list ever grow.
    # Everything of the test runs with no new privileges: setuid programs (pkexec,
    # unix_chkpwd) cannot gain any, so nothing the shell starts can reach polkit or the
    # real password database
    env -i PATH="$PATH" ${TMPDIR:+TMPDIR="$TMPDIR"} ${USER:+USER="$USER"} ${LOGNAME:+LOGNAME="$LOGNAME"} \
        ${TZ:+TZ="$TZ"} ${LOCALE_ARCHIVE:+LOCALE_ARCHIVE="$LOCALE_ARCHIVE"} \
        ${XDG_DATA_DIRS:+XDG_DATA_DIRS="$XDG_DATA_DIRS"} \
        ${LOCKTEST_QT_LOGGING:+LOCKTEST_QT_LOGGING="$LOCKTEST_QT_LOGGING"} \
        ${LOCKTEST_PROCESS_TIMEOUT:+LOCKTEST_PROCESS_TIMEOUT="$LOCKTEST_PROCESS_TIMEOUT"} \
        LOCKTEST_DIR="$LOCKTEST_DIR" LOCKTEST_SHELL="$copy" LOCKTEST_TOOLS="$LOCKTEST_TOOLS" \
        LOCKTEST_PAM_MODULES="$LOCKTEST_PAM_MODULES" LOCKTEST_LAUNCHER="$LOCKTEST_LAUNCHER" \
        LOCKTEST_QS="$LOCKTEST_QS" LOCKTEST_ARTIFACTS="$ARTIFACTS/$name" LOCKTEST_RUN_ID="$LOCKTEST_RUN_ID" \
        LOCKTEST_TEST_ID="$(test_id "$name")" LOCKTEST_RUNTIME="$runtime" \
        "$SETPRIV" --no-new-privs timeout -k 10 "$PER_TEST_TIMEOUT" bash -c '
            source "$LOCKTEST_DIR/lib.sh"
            source "$2"
            [ "$FAILURES" -eq 0 ]' _ "$name" "${TEST_FILE[$name]}" > "$ARTIFACTS/$name/test.log" 2>&1 < /dev/null &
    pid=$!
    RUNNING[$pid]=$name
    if serial_output; then
        tail -n +1 -f --pid="$pid" "$ARTIFACTS/$name/test.log" 2> /dev/null &
        TAIL[$name]=$!
    else
        echo "-- $name started ($launched/$total, ${#RUNNING[@]} running)"
    fi
}

# setup_failed <name> <why>: a test that could not be started
setup_failed() {
    local name=$1
    echo "    FAIL (setup) $2" >> "$ARTIFACTS/$name/test.log"
    [ -n "${RUNTIME[$name]:-}" ] && rm -rf "${RUNTIME[$name]}"
    unset "RUNTIME[$name]"
    results[$name]=FAIL
    serial_output || { echo; echo "== $name"; }
    cat "$ARTIFACTS/$name/test.log"
    echo "== $name: FAIL ($((SECONDS - ${test_started[$name]})) s)"
}

# finish_test <pid> <status>: the test whose timeout was <pid> ended with <status>
finish_test() {
    local pid=$1 status=$2 name leaked swept log
    name=${RUNNING[$pid]}
    unset "RUNNING[$pid]"
    log=$ARTIFACTS/$name/test.log
    if [ -n "${TAIL[$name]:-}" ]; then
        wait "${TAIL[$name]}" 2> /dev/null
        unset "TAIL[$name]"
    fi
    # Before the sweep: anything of the test that holds an inhibitor
    leaked=$(marked_inhibitors LOCKTEST_TEST_ID "$(test_id "$name")")
    [ -n "$leaked" ] && inhibitor_leak="$inhibitor_leak $name:$(echo $leaked | tr ' ' ',')"
    swept=$(sweep LOCKTEST_TEST_ID "$(test_id "$name")")
    [ -n "${RUNTIME[$name]:-}" ] && rm -rf "${RUNTIME[$name]}"
    unset "RUNTIME[$name]"
    if serial_output; then
        [ -n "$swept" ] && echo "$swept"
    else
        [ -n "$swept" ] && echo "$swept" >> "$log"
    fi
    if [ "$status" = 124 ] || [ "$status" = 137 ]; then
        if serial_output; then
            echo "    FAIL (setup) timed out after ${PER_TEST_TIMEOUT} s" | tee -a "$log"
        else
            echo "    FAIL (setup) timed out after ${PER_TEST_TIMEOUT} s" >> "$log"
        fi
    fi
    results[$name]=$(classify "$name" "$status")
    # The test's copy of the shell: only worth keeping when asked to
    [ "${LOCKTEST_KEEP:-0}" = 1 ] || [ -z "$name" ] || rm -rf "${ARTIFACTS:?}/shells/$name"
    if ! serial_output; then
        echo
        echo "== $name"
        cat "$log"
    fi
    echo "== $name: ${results[$name]} ($((SECONDS - ${test_started[$name]})) s)"
}

# Waits for one running test to end and finishes it
reap_one() {
    local done_pid="" status
    wait -n -p done_pid "${!RUNNING[@]}"
    status=$?
    # Not one of ours (cannot happen: the list names them), or nothing to wait for
    [ -n "$done_pid" ] && [ -n "${RUNNING[$done_pid]:-}" ] || return 0
    finish_test "$done_pid" "$status"
}

# run_tests <limit> <name>...: at most <limit> at a time, in this order
run_tests() {
    local limit=$1 name
    shift
    for name in "$@"; do
        while [ ${#RUNNING[@]} -ge "$limit" ]; do reap_one; done
        start_test "$name"
    done
    while [ ${#RUNNING[@]} -gt 0 ]; do reap_one; done
}

if [ "$jobs" = 1 ]; then
    run_tests 1 "${tests[@]}"
else
    # The long ones first, then the rest in order; the SERIAL ones alone at the end
    declare -A asked=() placed=()
    for name in "${tests[@]}"; do asked[$name]=1; done
    parallel=()
    alone=()
    for name in "${LONG_TESTS[@]}" "${tests[@]}"; do
        [ -n "${asked[$name]:-}" ] && [ -z "${placed[$name]:-}" ] || continue
        placed[$name]=1
        if [ -n "${SERIAL[$name]:-}" ]; then alone+=("$name"); else parallel+=("$name"); fi
    done
    echo "running ${#tests[@]} tests, $jobs at a time${alone[0]:+; then alone: ${alone[*]}}"
    run_tests "$jobs" "${parallel[@]+"${parallel[@]}"}"
    run_tests 1 "${alone[@]+"${alone[@]}"}"
fi

# Whatever of the run is still there (nothing should be: each test's was swept)
leaked=$(marked_inhibitors LOCKTEST_RUN_ID "$LOCKTEST_RUN_ID")
[ -n "$leaked" ] && inhibitor_leak="$inhibitor_leak end-of-run:$(echo $leaked | tr ' ' ',')"
sweep LOCKTEST_RUN_ID "$LOCKTEST_RUN_ID"

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
if [ "$LOCKTEST_LAUNCHER_FROM" = stand-in ]; then
    # Every test started its shell through it. The supervisor, the restart and `ipc` it ran
    # are the copy's scripts/launch.sh, as always; the packaged command itself was not there
    echo "  NOTE  launcher: the test bed's stand-in (tests/lock/launcher.sh) in every test, there being no h2s-shell command here: what a packaged h2s-shell adds (the programs it puts on PATH, its Quickshell) was not tested"
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
