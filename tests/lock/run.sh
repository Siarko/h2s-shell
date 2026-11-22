#!/usr/bin/env bash
# The lock test bed: runs the real shell in an invisible, isolated compositor and drives
# its lock screen with a virtual keyboard and pointer. See README.md.
#
#   tests/lock/run.sh               every test in tests/lock/tests/, several at a time
#   tests/lock/run.sh relock wrong-password
#                                   the named ones (file names without .sh)
#   tests/lock/run.sh -j 3 …        at most 3 tests at a time (LOCKTEST_JOBS=3 too); -j 1
#                                   runs them one after another, their output as it comes
#   LOCKTEST_RERUN=0 tests/lock/run.sh
#                                   no second run, alone, of a test that failed
#   LOCKTEST_KEEP=1 tests/lock/run.sh
#                                   keep logs and screenshots even when all pass
#   LOCKTEST_EXTRA_TESTS=<dir> tests/lock/run.sh <name>…
#                                   tests from another directory too (a module's repository:
#                                   <dir>/<name>.sh, written as these are); a name is looked
#                                   for here first. Without names: these and that dir's
#
# Each process a test's stack starts (the compositors, the input client, the launcher with
# its shells) runs under a memory cap of its own (H2S_TEST_MEMORY_MAX, 1536M by default, 0
# for none; tests/memory-cap.sh, said in the first lines), all of them within the run's
# memory budget (H2S_TEST_MEMORY_BUDGET); one stopped at either fails its test, which says
# "<scenario>: the process logging to <log> killed at the memory cap (<cap>)" (or "at the
# run's memory budget").
#
# One run at a time on a machine: a run holds /tmp/h2s-locktest.flock from its start to its
# end and waits, saying so, while another run has it (see "One run at a time", below).
#
# A test that failed is run once more at the end, alone: passing then it is FLAKY — still a
# failure of the run, and a line in ${XDG_CACHE_HOME:-~/.cache}/h2s-shell-tests/flaky.log
# (the date, the commit, the machine's load, the verdict, where its first log is kept).
#
# Exit status: 0 when every test passed (or failed exactly as expected, see below), 1
# when one failed (a test that could not start its stack, or ended well without a PASS
# line, counts as failed; so does a FLAKY one, and a scenario with a fixed sleep that does
# not say why: lint.sh), 2 when the test bed itself could not be set up before any test
# ran, 130 when interrupted.
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
# (none at present)
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
    modules-launcher restart-no-restore two-outputs notifications restart-crash-locked
    modules-discovery idle supervisor modules-hung restart-crash-finger logind
    screensaver-lock restart-locked-limit reload-explicit notifier-progress
)

# ---- Jobs -----------------------------------------------------------------------------
# How many tests run at once: -j N (or -jN, --jobs N) before the test names, else
# LOCKTEST_JOBS, else from the cores: a quarter of them, at least 4 and at most 8, and
# never more than one fewer than the cores. Each test is two compositors and a Qt shell:
# with 5 at once on 6 cores (load 12) the launcher's restart tests no longer fit their
# schedule, so a 6-core machine keeps 4; 32 threads take 8.
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
    cores=$(nproc 2> /dev/null || echo 2)
    jobs=$((cores / 4))
    [ "$jobs" -lt 4 ] && jobs=4
    [ "$jobs" -gt 8 ] && jobs=8
    [ "$jobs" -gt $((cores - 1)) ] && jobs=$((cores - 1))
    [ "$jobs" -lt 1 ] && jobs=1
fi

# ---- Cleanup, whatever ends the run --------------------------------------------------
probe=""
ARTIFACTS=""
lock_wait=""            # the pid of the flock waiting for another run to end, while it waits
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
        # Read whole, not piped into grep -q (an early match and tr's SIGPIPE under pipefail)
        [ -O "$environ" ] && grep -qxF -- "$variable=$value" <<< "$({ tr "\0" "\n" < "$environ"; } 2> /dev/null)" || continue
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
    [ -n "$lock_wait" ] && kill "$lock_wait" 2> /dev/null
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

# ---- One run at a time ---------------------------------------------------------------
# The tests depend on timing — a restart's schedule, an idle time-out, a prompt that must
# wake within seconds — and a run starts as many at once as the machine keeps on schedule
# (the jobs, above). Two runs side by side are twice that, and both fail for no reason of
# the shell's. So a run takes a lock for the whole machine, itself: nobody has to remember
# to, and the runners that share nothing but the processor (the unit, module and self-test
# runners) take none.
#
# The lock is flock(2) on LOCK_FILE, held by an open file of this bash until it exits. A
# caller that already wrapped the run in `flock /tmp/h2s-locktest.flock …` handed that open
# file on, lock and all: it is found among this process's open files and used, so the run
# does not wait for its own caller. (`flock -o`, which closes the file before it starts the
# command, would have the run wait for its caller for ever: not with -o.) Only this bash
# has the file: the tests, and the programs of the set-up that run code from elsewhere or
# can stay behind (the launcher asked for its Quickshell, nix, the tools' generators), are
# started without it — what outlived a run could otherwise keep the next one waiting.
# `{lock_fd}<&-` on a command closes it for that command alone.
# The file is made readable for everybody, whatever the umask: it is one file for all the
# users of a machine, and one made 0600 would end every other user's run right here.
# LOCKTEST_LOCK_FILE names another file — for tests/resolve-selftest.sh, which checks this
# without waiting for a real run.
LOCK_FILE=${LOCKTEST_LOCK_FILE:-/tmp/h2s-locktest.flock}
lock_fd=""
take_lock() {
    local link
    type -P flock > /dev/null || setup_error "flock not found on PATH (util-linux: one run of the lock test bed at a time)"
    [ -e "$LOCK_FILE" ] || (umask 022 && : >> "$LOCK_FILE") 2> /dev/null
    # (One of ours from before, made with a tight umask; another user's cannot be changed)
    [ -O "$LOCK_FILE" ] && chmod a+r "$LOCK_FILE" 2> /dev/null
    for link in /proc/$$/fd/*; do
        [ "$link" -ef "$LOCK_FILE" ] && { lock_fd=${link##*/}; break; }
    done
    if [ -z "$lock_fd" ]; then
        # (Read-only: enough for a lock, and a file another user made can be opened so)
        exec {lock_fd}< "$LOCK_FILE" || setup_error "cannot open the lock file $LOCK_FILE"
    fi
    flock -n "$lock_fd" && return 0
    echo "run.sh: waiting for another run of the lock test bed to end ($LOCK_FILE)…"
    # In the background and waited for: an interrupt must end the wait at once (bash runs a
    # trap only when the foreground command ends). It locks the same open file as this bash
    flock "$lock_fd" &
    lock_wait=$!
    wait "$lock_wait" || setup_error "could not take the lock $LOCK_FILE"
    lock_wait=""
}
take_lock

# Paths are substituted into PAM stacks (sed, split at whitespace by PAM): only plain
# characters are allowed in the temp dir
temp_base=${TMPDIR:-/tmp}
[[ "$temp_base" =~ ^/[A-Za-z0-9._/+-]*$ ]] \
    || setup_error "TMPDIR ($temp_base) must be an absolute path of letters, digits and ._/+- only"

# ---- Tools, the launcher and its Quickshell (resolve.sh, shared with tests/run-unit.sh) ----
# Resolved once here and handed to every test in its environment
LOCKTEST_NEED=lock
source "$LOCKTEST_DIR/resolve.sh" {lock_fd}<&-

# The memory cap on each process of the stack and the run's budget (tests/memory-cap.sh:
# H2S_TEST_MEMORY_MAX, 1536M by default, H2S_TEST_MEMORY_BUDGET; 0 for none): chosen here
# (or taken over from the runner that started this one: tests/run-all.sh), said once,
# handed to the tests with the caller's runtime dir and bus, through which lib.sh reaches
# the user's service manager from the test's private environment (lib.sh keeps them from
# the stack). The budget ends with the run, when this run made it
# shellcheck source=../memory-cap.sh
source "$LOCKTEST_DIR/../memory-cap.sh"
memory_cap_init {lock_fd}<&-
trap 'memory_cap_finish {lock_fd}<&-' EXIT

# The launcher under test starts with SIGHUP reset (lib.sh: a run started with it ignored,
# nohup, would hand that on, and bash cannot trap it): env's --default-signal, coreutils 8.31
env --default-signal=HUP "$BASH" -c : {lock_fd}<&- 2> /dev/null \
    || setup_error "env does not take --default-signal (coreutils 8.31 or later)"

# PAM modules must belong to the libpam the process loads: taken from Quickshell's
quickshell_binary=$(dirname "$LOCKTEST_QS")/.quickshell-wrapped
[ -e "$quickshell_binary" ] || quickshell_binary=$LOCKTEST_QS
libpam=$(ldd "$quickshell_binary" 2> /dev/null {lock_fd}<&- | sed -n 's/.*libpam\.so\.0 => \([^ ]*\).*/\1/p' | head -n 1)
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

# ---- No fixed sleeps without a reason (lint.sh) ---------------------------------------
# In this bed's own scenarios that run (a module's are its repository's to lint): a finding
# fails the run, after the tests, as a failing test would
own_files=()
for name in "${tests[@]}"; do
    [ "${TEST_FILE[$name]}" = "$LOCKTEST_DIR/tests/$name.sh" ] && own_files+=("${TEST_FILE[$name]}")
done
lint_findings=""
if [ ${#own_files[@]} -gt 0 ]; then
    lint_findings=$("$BASH" "$LOCKTEST_DIR/lint.sh" --selftest {lock_fd}<&- 2>&1) \
        && lint_findings="" \
        || lint_findings=$(grep -v '^PASS ' <<< "$lint_findings")
    lint_sleeps=$("$BASH" "$LOCKTEST_DIR/lint.sh" "${own_files[@]}" {lock_fd}<&- 2>&1)
    [ -n "$lint_sleeps" ] && lint_findings=${lint_findings:+$lint_findings$'\n'}$lint_sleeps
    [ -z "$lint_findings" ] || { echo "lint.sh: fixed sleeps without their reason (# fixed sleep: …):"; echo "$lint_findings" | sed 's/^/    /'; }
fi

ARTIFACTS=$(mktemp -d "$temp_base/h2s-locktest.XXXXXX") || setup_error "cannot create the artifacts dir"
LOCKTEST_RUN_ID=$(basename "$ARTIFACTS")-$$

# With the system's tools, the set tools.nix would have built is made here, for this run:
# links to the programs found on PATH, the protocol bindings and the keymaps (resolve.sh)
if [ "$LOCKTEST_TOOL_SOURCE" = system ]; then
    make_system_tools "$ARTIFACTS/tools" {lock_fd}<&-
    LOCKTEST_TOOLS=$ARTIFACTS/tools
fi

# ---- The shell under test: a copy of the checkout, one per test -----------------------
# In development mode (stack_start --dev) Quickshell reloads the shell on any file written
# in its folder, and a reload while locked unlocks. So the shell runs from a copy: whatever is written to the checkout
# meanwhile (by you, by another tool) cannot disturb a test. The copy is the checkout as
# it is at the start of the run, without the test bed itself (tests/lock), git data and
# build results — a test tree (tests/test-tree.sh): the test seam files in the production
# ones' place, so that the copy reads the seams the tests set (tools, PAM directory,
# timings, …) from its environment, which the checkout's own files never do
# (tests/lock/README.md, "The test tree"). And with pam/ replaced: the shipped configs
# check the real account (pam_unix), and the shell falls back to them when the methods
# script fails or lists no password. In the copy every one of them denies, so a typed test
# string can never reach the system's password check.
#
# It is made once (shell/, never run from) and copied again for each test (shells/<name>,
# a few MB, some 20 ms): tests edit their copy on purpose (edit-while-locked,
# reload-while-locked, reload-window, restart-locked-retry), and with tests running side
# by side an edit in a shared copy would reload or break every other test's shell.
shell_template=$ARTIFACTS/shell
mkdir -p "$shell_template" "$ARTIFACTS/shells" || setup_error "cannot create $shell_template"
tree_error=$("$LOCKTEST_DIR/../test-tree.sh" "$shell_template" 2>&1 > /dev/null {lock_fd}<&-) \
    || setup_error "cannot make the copy of the checkout: ${tree_error:-tests/test-tree.sh failed}"
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
    for pid in $(systemd-inhibit --list --no-pager --no-legend 2> /dev/null {lock_fd}<&- \
        | awk '{ for (i = 1; i + 2 <= NF; i++) if ($i ~ /^[0-9]+$/ && $(i + 2) ~ /^[0-9]+$/) { print $(i + 2); break } }'); do
        grep -qxF -- "$variable=$value" <<< "$({ tr "\0" "\n" < "/proc/$pid/environ"; } 2> /dev/null)" && echo "$pid"
    done
}

# The user's own config: a run must not write it
real_config=${XDG_CONFIG_HOME:-$HOME/.config}/h2s_shell/config.json
real_config_stamp() { stat -c '%Y %s' "$real_config" 2> /dev/null || echo absent; }
real_config_before=$(real_config_stamp)
touch "$ARTIFACTS/.started"

# classify <name> <status>: PASS / FAIL / XFAIL / XPASS / EMPTY, from the exit status and the log
classify() {
    local name=$1 status=$2 log=$ARTIFACTS/$1/test.log
    # A test that checked nothing cannot fail, so it does not pass either: one that ends
    # well without a PASS line is EMPTY, a failure
    if [ "$status" = 0 ] && ! grep -q '^    PASS ' "$log"; then
        echo EMPTY
        return
    fi
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

# A variable of this run's own that no test is handed: harness.sh checks that the shell
# under test lacks it, which shows the tests' environment is the list in start_test and not
# the caller's — also where the caller has none of the session's variables to look for
export LOCKTEST_CANARY=1

started=$SECONDS
declare -A results=()
declare -A test_started=()
declare -A failed_load=()
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
    # (A fresh copy: one left by an earlier run of this test, kept with LOCKTEST_KEEP=1, holds
    # that run's edits, and cp would copy into it)
    rm -rf "$copy"
    cp -a "$shell_template" "$copy" || { setup_failed "$name" "cannot copy the shell to $copy"; return; }
    # The test gets nothing of the caller's environment but what is named here: where
    # programs and temp files are, who runs it, the time zone, the locale data and the data
    # dirs (NixOS finds its locales and the shell its icons and fonts through them), and the
    # two settings a caller may give a test (lib.sh reads them). No display, no bus, no seat,
    # no agent socket, no toolkit setting of the session: lib.sh then sets the test's own,
    # and still unsets the session's variables by name, should this list ever grow.
    # LOCKTEST_CANARY (below) is not named: harness.sh fails when the shell has it.
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
        H2S_TEST_MEMORY_MAX="$H2S_TEST_MEMORY_MAX" H2S_TEST_MEMORY_MODE="$H2S_TEST_MEMORY_MODE" \
        H2S_TEST_SLICE="$H2S_TEST_SLICE" H2S_TEST_MEMORY_BUDGET="$H2S_TEST_MEMORY_BUDGET" \
        ${H2S_TEST_MEMORY_AS_FLOOR:+H2S_TEST_MEMORY_AS_FLOOR="$H2S_TEST_MEMORY_AS_FLOOR"} \
        ${MEMORY_CAP_USER_RUNTIME_DIR:+H2S_TEST_USER_RUNTIME_DIR="$MEMORY_CAP_USER_RUNTIME_DIR"} \
        ${MEMORY_CAP_USER_BUS:+H2S_TEST_USER_BUS="$MEMORY_CAP_USER_BUS"} \
        "$SETPRIV" --no-new-privs timeout -k 10 "$PER_TEST_TIMEOUT" bash -c '
            source "$LOCKTEST_DIR/lib.sh"
            source "$2"
            [ "$FAILURES" -eq 0 ]' _ "$name" "${TEST_FILE[$name]}" > "$ARTIFACTS/$name/test.log" 2>&1 < /dev/null {lock_fd}<&- &
    pid=$!
    RUNNING[$pid]=$name
    if serial_output; then
        tail -n +1 -f --pid="$pid" "$ARTIFACTS/$name/test.log" 2> /dev/null {lock_fd}<&- &
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
    # The machine's load when a test failed (for the flaky log, should it pass alone)
    [ "${results[$name]}" = FAIL ] && read -r failed_load[$name] _ < /proc/loadavg
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

# ---- A failed test, once more, alone -----------------------------------------------------
# A test that failed runs again at the end with nothing else of the run going on. Passing
# then, it is FLAKY: still a failure of the run — what fails one run in two is a defect of
# the test or of the shell, to be found — and a line in the flaky log, which a lead reads
# across runs and machines. Its first run's logs are kept beside the second's (<name>.first).
# Not for a test that checked nothing (EMPTY) or passed against its mark (XPASS): another
# run cannot change those.
declare -A flaky_first_log=()
again=()
if [ "${LOCKTEST_RERUN:-1}" != 0 ]; then
    for name in "${tests[@]}"; do
        [ "${results[$name]}" = FAIL ] && again+=("$name")
    done
fi
if [ ${#again[@]} -gt 0 ]; then
    echo
    echo "failed, so run once more, alone: ${again[*]}"
    for name in "${again[@]}"; do
        rm -rf "${ARTIFACTS:?}/$name.first"
        mv "$ARTIFACTS/$name" "$ARTIFACTS/$name.first"
        # Its copy of the shell, kept with LOCKTEST_KEEP=1, with the first run's edits in it
        rm -rf "${ARTIFACTS:?}/shells/$name.first"
        [ -e "$ARTIFACTS/shells/$name" ] && mv "$ARTIFACTS/shells/$name" "$ARTIFACTS/shells/$name.first"
        flaky_first_log[$name]=$ARTIFACTS/$name.first/test.log
    done
    total=${#again[@]}
    launched=0
    run_tests 1 "${again[@]}"
    flaky_log_dir=${XDG_CACHE_HOME:-${HOME:-/nonexistent}/.cache}/h2s-shell-tests
    commit=$(git -C "$LOCKTEST_REPO" rev-parse --short HEAD 2> /dev/null {lock_fd}<&-) || commit=unknown
    for name in "${again[@]}"; do
        case "${results[$name]}" in
            PASS | XFAIL)
                results[$name]=FLAKY
                if mkdir -p "$flaky_log_dir" 2> /dev/null; then
                    printf '%s %s commit=%s load=%s jobs=%s first-log=%s\n' \
                        "$(date +%Y-%m-%dT%H:%M:%S)" "$name" "$commit" "${failed_load[$name]:-?}" "$jobs" \
                        "${flaky_first_log[$name]}" >> "$flaky_log_dir/flaky.log"
                fi
                ;;
        esac
    done
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
        EMPTY) echo "  FAIL  $name — ended well without a PASS line: it checked nothing"; failed=1 ;;
        FLAKY)
            echo "  FLAKY $name — failed (load ${failed_load[$name]:-?}), then passed alone; the first run's log: ${flaky_first_log[$name]}"
            failed=1
            ;;
        FAIL)
            if [ -n "${EXPECTED_TO_FAIL[$name]:-}" ]; then
                echo "  FAIL  $name — marked as expected to fail, but not (only) in the expected checks"
            elif [ -n "${flaky_first_log[$name]:-}" ]; then
                echo "  FAIL  $name — and again, alone"
            else
                echo "  FAIL  $name"
            fi
            failed=1
            ;;
        *) echo "  PASS  $name" ;;
    esac
done
if [ -n "$lint_findings" ]; then
    echo "  FAIL  lint: fixed sleeps without their reason (lint.sh; listed at the start of the run)"
    failed=1
fi
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
