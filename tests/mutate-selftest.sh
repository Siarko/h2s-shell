#!/usr/bin/env bash
# Checks tests/mutate.sh on a scratch copy of the tree with a small Rules file and its suite
# (tests/fixtures/mutate): FixtureRules.qml has seven mutants, of each outcome against
# FixtureTest.qml —
#
#   list       --list prints the seven, file:line:column, and runs nothing
#   picked     --list --max 2 --seed 7 picks two, the same two each time
#   run        against the fixture suite (-j 2): the negated returns and the dropped '!'
#              killed; '>=' -> '>' and
#              18 -> 19 survived, named with their lines; '<' -> '<=' and '>' -> '>=' in
#              `list<int>` not compiled; the summary says so; exit 0
#   untouched  after the run the subject in the tree it ran from is as it was (mutants are
#              made in mutate.sh's own copies), and no temp dir is left
#   judged     --judge on canned runs: a load error naming the subject is "not compiled",
#              after a time-out (124) or a kill (137) too; a TypeError or ReferenceError
#              naming it is "killed"; a failed check "killed"; a Quickshell stopped at the
#              memory cap "capped" (counted as killed); 0 "survived"; 2 "not run"
#   unjudged   a suite that fails unmutated: status 2, no mutant run
#   refused    a file outside the tree, a test file, a wrong option: status 2
#
# Runs the real Quickshell in tests/run-unit.sh's headless compositor (nothing shows), with
# its tools taken as that runner takes them. Never in the checkout: the copy is this run's,
# under its temp dir, removed by its path.
#
# Exit status: 0 when every check passed, 1 otherwise, 2 when the copy could not be made.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd -P)
work=$(mktemp -d "${TMPDIR:-/tmp}/mutate-selftest.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$work"' EXIT
failed=0
check() {
    local description=$1
    shift
    if "$@"; then echo "  PASS $description"; else echo "  FAIL $description"; failed=1; fi
}

# The copy: the tree, the fixture as a singleton, its suites registered in tests.qml
tree=$work/tree
mkdir -p "$tree" "$work/tmp"
for entry in "$REPO"/* "$REPO"/.[!.]*; do
    [ -e "$entry" ] || continue
    case "${entry##*/}" in .git | result | result-*) continue ;; esac
    cp -a "$entry" "$tree/" || { echo "cannot copy $entry" >&2; exit 2; }
done
fixtures=$REPO/tests/fixtures/mutate
cp "$fixtures/FixtureRules.qml" "$tree/singletons/MutateFixtureRules.qml"
cp "$fixtures/FixtureTest.qml" "$tree/tests/MutateFixtureRulesTest.qml"
cp "$fixtures/FailingTest.qml" "$tree/tests/MutateFailingTest.qml"
sed -e 's/^\(    property var _promises: PromisesTest {}\)$/    property var _mutateFixtureRules: MutateFixtureRulesTest {}\n    property var _mutateFailing: MutateFailingTest {}\n\1/' \
    "$REPO/tests.qml" > "$tree/tests.qml"
grep -q MutateFailingTest "$tree/tests.qml" || { echo "cannot register the fixture suites in tests.qml" >&2; exit 2; }
subject=singletons/MutateFixtureRules.qml
mutate() { TMPDIR=$work/tmp "$tree/tests/mutate.sh" "$@"; }

echo "list:"
listed=$(mutate --list "$subject" 2>&1)
check "seven mutants" grep -q "^mutate.sh: $subject, 7 of 7 mutants$" <<< "$listed"
for expected in ":8:18  '<' -> '<='" ":8:22  '>' -> '>='" ":11:9  'return age >= 18' -> 'return !(age >= 18)'" \
    ":11:20  '>=' -> '>'" ":11:23  '18' -> '19'" \
    ":15:9  'return !adult(age)' -> 'return !(!adult(age))'" ":15:16  '!' -> ''"; do
    check "lists $expected" grep -q -F "$subject$expected" <<< "$listed"
done
check "ran nothing" test -z "$(ls -A "$work/tmp")"

echo "picked:"
first=$(mutate --list --max 2 --seed 7 "$subject" 2>&1)
again=$(mutate --list --max 2 --seed 7 "$subject" 2>&1)
check "two picked, said with the seed" grep -q "2 of 7 mutants (--max 2 --seed 7)" <<< "$first"
check "two listed" test "$(grep -c "^  $subject:" <<< "$first")" = 2
check "the same two again" test "$first" = "$again"

echo "run:"
mutate -j 2 "$subject" MutateFixtureRulesTest > "$work/run.log" 2>&1
status=$?
check "exit 0 (it exited $status)" test "$status" = 0
check "the summary: killed 3 / survived 2 / not compiled 2" \
    grep -q "^mutate.sh: $subject, [0-9]* s: killed 3 / survived 2 / not compiled 2$" "$work/run.log"
survivors=$(sed -n '/^Surviving mutants/,/^$/p' "$work/run.log")
check "'>=' -> '>' survived" grep -q -F "$subject:11:20  '>=' -> '>'" <<< "$survivors"
check "18 -> 19 survived" grep -q -F "$subject:11:23  '18' -> '19'" <<< "$survivors"
uncompiled=$(sed -n '/^Not compiled/,/^$/p' "$work/run.log")
check "list<int> not compiled, twice" test "$(grep -c -F "$subject:8:" <<< "$uncompiled")" = 2
check "the negated returns killed" grep -q -F "killed  $subject:11:9 " "$work/run.log"
check "… both" grep -q -F "killed  $subject:15:9 " "$work/run.log"
check "the dropped '!' killed" grep -q -F "killed  $subject:15:16 " "$work/run.log"

echo "untouched:"
check "the subject in the tree not changed" cmp -s "$fixtures/FixtureRules.qml" "$tree/$subject"
check "no temp dir left" test -z "$(ls -A "$work/tmp")"

echo "unjudged:"
mutate "$subject" MutateFailingTest > "$work/unjudged.log" 2>&1
status=$?
check "status 2 (it was $status)" test "$status" = 2
check "said the suite failed unmutated" grep -q "MutateFailingTest failed on the unmutated tree" "$work/unjudged.log"
check "no mutant run" bash -c '! grep -q "^  \[" "$1"' _ "$work/unjudged.log"
check "no temp dir left" test -z "$(ls -A "$work/tmp")"

echo "judged:"
error=$'\e[31m ERROR\e[0m:'
printf '%s   caused by @components/Logger.qml[-1:-1]: Type MutateFixtureRules unavailable\n%s   caused by @%s[8:18]: Expected token `identifier'"'"'\n' \
    "$error" "$error" "$subject" > "$work/load.log"
printf 'WARN qml: @%s[11:9]: TypeError: Cannot read property '"'"'x'"'"' of null\n  FAIL: 30 is adult\n' "$subject" > "$work/type.log"
printf 'WARN qml: @%s[11:9]: ReferenceError: age2 is not defined\n' "$subject" > "$work/reference.log"
printf '  FAIL: 30 is adult\n  --- MutateFixtureRules: 2/3 passed, 1 FAILED ---\n' > "$work/failed.log"
printf '  shard 1 (MutateFixtureRulesTest) failed (status 1):\n    MutateFixtureRules: killed at the memory cap (1536M)\n' > "$work/capped.log"
judged() { [ "$("$tree/tests/mutate.sh" --judge "$1" "$2" "$subject")" = "$3" ]; }
check "a load error naming the subject: not compiled" judged "$work/load.log" 1 not-compiled
check "… after a time-out too" judged "$work/load.log" 124 not-compiled
check "… after a kill too" judged "$work/load.log" 137 not-compiled
check "a TypeError naming it: killed" judged "$work/type.log" 1 killed
check "a ReferenceError naming it: killed" judged "$work/reference.log" 1 killed
check "a failed check: killed" judged "$work/failed.log" 1 killed
check "a time-out without a load error: killed" judged "$work/failed.log" 124 killed
check "stopped at the memory cap: capped (counted as killed)" judged "$work/capped.log" 1 capped
check "status 0: survived" judged "$work/failed.log" 0 survived
check "status 2: not run" judged "$work/load.log" 2 not-run

echo "refused:"
mutate --list /etc/hostname > /dev/null 2>&1
check "a file outside the tree: status 2" test $? = 2
mutate --list tests/MutateFixtureRulesTest.qml > /dev/null 2>&1
check "a test file: status 2" test $? = 2
mutate --bogus "$subject" > /dev/null 2>&1
check "a wrong option: status 2" test $? = 2

[ "$failed" = 0 ] && echo "mutate.sh self-test: every check passed" || echo "mutate.sh self-test: FAILED"
exit "$failed"
