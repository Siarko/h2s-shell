#!/usr/bin/env bash
# The lock bed's runner checking itself, in seconds, without a stack: lint.sh's cases, and
# run.sh's second run of a failed test — a scenario that fails once and then passes is
# FLAKY (the run still fails, the flaky log gets its line, the first log is kept), one that
# fails twice is a FAIL. The scenarios start nothing: they live in a directory of this
# script's (LOCKTEST_EXTRA_TESTS), and the run takes a lock file of its own, so a real run
# of the bed may go on meanwhile.
#
#   tests/lock/selftest.sh
#
# Exit status: 0 when every check passed, 1 when one failed.
set -uo pipefail

LOCKTEST_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
work=$(mktemp -d /tmp/h2s-lockself.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
failures=0
pass() { echo "PASS $*"; }
failed() { echo "FAIL $*"; failures=$((failures + 1)); }

if "$LOCKTEST_DIR/lint.sh" --selftest > "$work/lint.out" 2>&1; then
    pass "lint.sh: its cases ($(grep -c '^PASS' "$work/lint.out"))"
else
    failed "lint.sh: its cases"
    grep -v '^PASS' "$work/lint.out"
fi
if "$LOCKTEST_DIR/lint.sh" > "$work/lint-tree.out" 2>&1; then
    pass "lint.sh: the bed's scenarios have no fixed sleep without its reason"
else
    failed "lint.sh: fixed sleeps without their reason"
    cat "$work/lint-tree.out"
fi

mkdir -p "$work/tests" "$work/cache" "$work/temp"
# (Its first run edits its copy of the shell, as some tests do: the second must get a fresh one)
cat > "$work/tests/self-flaky.sh" << EOF
if [ ! -e '$work/flaky-ran' ]; then
    : > '$work/flaky-ran'
    : > "\$LOCKTEST_SHELL/edited-by-the-first-run"
    fail "the first time"
elif [ -e "\$LOCKTEST_SHELL/edited-by-the-first-run" ]; then
    fail "the second time, in the first run's copy of the shell"
else
    pass "the second time, in a fresh copy of the shell"
fi
EOF
echo 'fail "every time"' > "$work/tests/self-failing.sh"
echo 'pass "always"' > "$work/tests/self-passing.sh"
env LOCKTEST_KEEP=1 LOCKTEST_LOCK_FILE="$work/bed.flock" LOCKTEST_EXTRA_TESTS="$work/tests" XDG_CACHE_HOME="$work/cache" \
    TMPDIR="$work/temp" timeout 300 "$LOCKTEST_DIR/run.sh" -j 2 self-flaky self-failing self-passing \
    > "$work/run.out" 2>&1 < /dev/null
status=$?
summary=$(sed -n '/^Summary/,$p' "$work/run.out")
[ "$status" = 1 ] && pass "the run fails (status 1)" || failed "the run's status: $status, not 1"
grep -q '^  FLAKY self-flaky — failed (load [0-9.]*), then passed alone; the first run.s log: .*/self-flaky.first/test.log$' <<< "$summary" \
    && pass "failed once, passed alone: FLAKY" || failed "no FLAKY line for self-flaky"
grep -qx '  FAIL  self-failing — and again, alone' <<< "$summary" \
    && pass "failed twice: FAIL" || failed "no 'FAIL … and again, alone' line for self-failing"
grep -qx '  PASS  self-passing' <<< "$summary" && pass "passed: PASS, not run again" || failed "self-passing did not PASS"
[ "$(grep -cx '== self-passing' "$work/run.out")" = 1 ] || failed "self-passing ran more than once"
grep -q '^failed, so run once more, alone: self-flaky self-failing$' "$work/run.out" \
    && pass "only the failed ones ran again" || failed "the second run's list"
flaky_line=$(cat "$work/cache/h2s-shell-tests/flaky.log" 2> /dev/null)
grep -qE '^[0-9-]+T[0-9:]+ self-flaky commit=[0-9a-z]+ load=[0-9.]+ jobs=2 first-log=/.*/self-flaky\.first/test\.log$' <<< "$flaky_line" \
    && [ "$(wc -l <<< "$flaky_line")" = 1 ] \
    && pass "the flaky log has one line: date, test, commit, load, jobs, first log" \
    || failed "the flaky log: '$flaky_line'"
first_log=$(sed -n 's/^  FLAKY self-flaky .*first run.s log: //p' <<< "$summary")
grep -q '^    FAIL the first time$' "$first_log" 2> /dev/null \
    && pass "the first run's log is kept" || failed "the first run's log ($first_log)"
artifacts=${first_log%/self-flaky.first/test.log}
[ -e "$artifacts/shells/self-flaky.first/edited-by-the-first-run" ] && [ ! -e "$artifacts/shells/self-flaky/edited-by-the-first-run" ] \
    && pass "LOCKTEST_KEEP=1: the second run had a fresh copy of the shell, the first's kept aside" \
    || failed "the copies of the shell under $artifacts/shells"
[ "$failures" = 0 ] || { echo "--- run.sh's output:"; cat "$work/run.out"; }

echo
if [ "$failures" = 0 ]; then echo "selftest: all passed"; else echo "selftest: $failures failed"; fi
[ "$failures" = 0 ]
