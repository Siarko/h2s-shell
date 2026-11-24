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
#   accepted   --accepted with '>=' -> '>' listed: shown apart as accepted, its key not
#              printed again, 18 -> 19's printed as a survivor-key line; an entry for an edited
#              line is stale; the summary says survived 2 (accepted 1) / stale 1
#   listed     an entry without a reason line above it, or not in four fields: status 2
#   untouched  after the run the subject in the tree it ran from is as it was (mutants are
#              made in mutate.sh's own copies), and no temp dir is left
#   judged     --judge on canned runs: a load error naming the subject is "not compiled",
#              after a time-out (124) or a kill (137) too; a TypeError or ReferenceError
#              naming it is "killed"; a failed check "killed"; a time-out (124, or 137 from
#              its -k) without a load error "timed-out"; a Quickshell stopped at the
#              memory cap or the run's budget "capped" (counted as killed); 0 "survived";
#              2 "not run"
#   limits     with a stand-in for the unit runner and a time limit of a second: a mutant
#              slow only the first time (18 -> 19) is run once more, alone, and survives —
#              its accepted entry holds; one that hangs every time (the dropped '!') is
#              killed at the time limit, counted as killed and listed apart, and its accepted
#              entry is stale with a `stale-killed` line; an accepted survivor a check
#              killed the first time only (the first negated return) is run once more and
#              holds; nothing else is run again, the
#              limits are measured again first; --only runs just the mutants it names, and
#              one naming none is status 2
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
check "the summary: killed 3 / survived 2 (accepted 0) / stale 0 / not compiled 2" \
    grep -q "^mutate.sh: $subject, [0-9]* s: killed 3 / survived 2 (accepted 0) / stale 0 / not compiled 2$" "$work/run.log"
check "each survivor's key printed" \
    test "$(grep -c -F "survivor-key	$subject	" "$work/run.log")" = 2
survivors=$(sed -n '/^Surviving mutants/,/^$/p' "$work/run.log")
check "'>=' -> '>' survived" grep -q -F "$subject:11:20  '>=' -> '>'" <<< "$survivors"
check "18 -> 19 survived" grep -q -F "$subject:11:23  '18' -> '19'" <<< "$survivors"
uncompiled=$(sed -n '/^Not compiled/,/^$/p' "$work/run.log")
check "list<int> not compiled, twice" test "$(grep -c -F "$subject:8:" <<< "$uncompiled")" = 2
check "the negated returns killed" grep -q -F "killed  $subject:11:9 " "$work/run.log"
check "… both" grep -q -F "killed  $subject:15:9 " "$work/run.log"
check "the dropped '!' killed" grep -q -F "killed  $subject:15:16 " "$work/run.log"

echo "accepted:"
{
    echo "# reason: the fixture's own equivalent"
    printf '%s\t%s\t%s\t%s\n' "$subject" ">= -> >" "#1" "return age >= 18;"
    echo
    echo "# reason: a line since edited"
    printf '%s\t%s\t%s\t%s\n' "$subject" "18 -> 19" "#1" "return age >= 21;"
    echo "# reason: another file's, not counted here"
    printf '%s\t%s\t%s\t%s\n' "singletons/OtherRules.qml" "< -> <=" "#1" "return a < b;"
} > "$work/accepted.txt"
mutate -j 2 --accepted "$work/accepted.txt" "$subject" MutateFixtureRulesTest > "$work/accepted.log" 2>&1
check "the summary: survived 2 (accepted 1) / stale 1" \
    grep -q "^mutate.sh: $subject, [0-9]* s: killed 3 / survived 2 (accepted 1) / stale 1 / not compiled 2$" "$work/accepted.log"
check "the accepted one is shown apart" \
    bash -c 'sed -n "/^Accepted survivors/,/^\$/p" "$1" | grep -q -F "$2:11:20  '"'"'>='"'"' -> '"'"'>'"'"'"' _ "$work/accepted.log" "$subject"
check "the other survivor's key only" \
    bash -c '[ "$(grep -c "^survivor-key" "$1")" = 1 ] && grep -q -F "survivor-key	$2	18 -> 19	#1	return age >= 18;" "$1"' _ "$work/accepted.log" "$subject"
check "the edited line's entry named stale" \
    bash -c 'sed -n "/^Stale accepted entries/,/^\$/p" "$1" | grep -q -F "return age >= 21;"' _ "$work/accepted.log"

echo "listed:"
printf '%s\t%s\t%s\t%s\n' "$subject" ">= -> >" "#1" "return age >= 18;" > "$work/no-reason.txt"
mutate --list --accepted "$work/no-reason.txt" "$subject" > "$work/listed.log" 2>&1
check "an entry without a reason: status 2" test $? = 2
check "… said, with its line" grep -q "no-reason.txt:1: an entry without a '# reason: …' line" "$work/listed.log"
printf '# reason: x\n%s >= -> > #1\n' "$subject" > "$work/no-tabs.txt"
mutate --list --accepted "$work/no-tabs.txt" "$subject" > /dev/null 2>&1
check "an entry not in four fields: status 2" test $? = 2

echo "untouched:"
check "the subject in the tree not changed" cmp -s "$fixtures/FixtureRules.qml" "$tree/$subject"
check "no temp dir left" test -z "$(ls -A "$work/tmp")"

echo "limits:"
# A tree of its own whose unit runner is a stand-in: it passes on the subject as it is,
# sleeps past the limit on 18 -> 19 the first time only and on the dropped '!' every time,
# fails on the first negated return the first time only, passes on '>=' -> '>' and fails on
# anything else. Each run of it is noted in runs
limits=$work/limits
mkdir -p "$limits/tree/tests" "$limits/tree/singletons" "$limits/state"
cp "$REPO/tests/mutate.sh" "$REPO/tests/memory-cap.sh" "$limits/tree/tests/"
cp "$fixtures/FixtureRules.qml" "$limits/tree/$subject"
cp "$fixtures/FixtureRules.qml" "$limits/state/original.qml"
cat > "$limits/tree/tests/run-unit.sh" << STANDIN
#!$(type -P bash)
state=$limits/state
subject=\$(dirname "\$0")/../$subject
if cmp -s "\$subject" "\$state/original.qml"; then echo unmutated >> "\$state/runs"; exit 0; fi
if grep -q "age >= 19" "\$subject"; then
    echo slow >> "\$state/runs"
    [ -e "\$state/slow-once" ] && exit 0
    touch "\$state/slow-once"
    exec sleep 20
fi
if grep -q "return adult(age);" "\$subject"; then echo hang >> "\$state/runs"; exec sleep 20; fi
if grep -q "age > 18" "\$subject"; then echo survivor >> "\$state/runs"; exit 0; fi
if grep -q "return !(age >= 18)" "\$subject"; then
    echo flaky >> "\$state/runs"
    [ -e "\$state/flaky-once" ] && exit 0
    touch "\$state/flaky-once"
    echo "  FAIL: a check that fails on its own"
    exit 1
fi
echo other >> "\$state/runs"
echo "  FAIL: a check"
exit 1
STANDIN
chmod +x "$limits/tree/tests/run-unit.sh"
{
    echo "# reason: slow only under load"
    printf '%s\t%s\t%s\t%s\n' "$subject" "18 -> 19" "#1" "return age >= 18;"
    echo "# reason: an entry a hang kills"
    printf '%s\t%s\t%s\t%s\n' "$subject" "! -> " "#1" "return !adult(age);"
    echo "# reason: killed once by a suite failing on its own"
    printf '%s\t%s\t%s\t%s\n' "$subject" "return age >= 18 -> return !(age >= 18)" "#1" "return age >= 18;"
} > "$limits/accepted.txt"
limited() { H2S_MUTATE_MIN_LIMIT=1 H2S_TEST_MEMORY_MAX=0 H2S_TEST_MEMORY_BUDGET=0 TMPDIR=$work/tmp "$limits/tree/tests/mutate.sh" "$@"; }
limited -j 2 --accepted "$limits/accepted.txt" "$subject" MutateFixtureRulesTest > "$limits/run.log" 2>&1
status=$?
check "exit 0 (it exited $status)" test "$status" = 0
check "the summary: killed 4 (1 at the time limit) / survived 3 (accepted 2) / stale 1" \
    grep -q "^mutate.sh: $subject, [0-9]* s: killed 4 (1 at the time limit) / survived 3 (accepted 2) / stale 1 / not compiled 0$" "$limits/run.log"
check "an accepted survivor killed once by a check: run once more, alone: survived" \
    grep -q -F "[again 1/3] survived  $subject:11:9 " "$limits/run.log"
check "the slow one first stopped at the time limit" grep -q -F "] killed (time limit)  $subject:11:23 " "$limits/run.log"
check "… run once more, alone: survived" grep -q -F "[again 2/3] survived  $subject:11:23 " "$limits/run.log"
check "… shown as accepted" bash -c 'sed -n "/^Accepted survivors/,/^\$/p" "$1" | grep -q -F "$2:11:23 "' _ "$limits/run.log" "$subject"
check "the hang run once more and stopped again" grep -q -F "[again 3/3] killed (time limit)  $subject:15:16 " "$limits/run.log"
check "… listed apart" bash -c 'sed -n "/^Killed at the time limit/,/^\$/p" "$1" | grep -q -F "$2:15:16 "' _ "$limits/run.log" "$subject"
check "… its entry stale, with a stale-killed line" \
    grep -q -F "stale-killed	$subject	! -> 	#1	return !adult(age);" "$limits/run.log"
check "… the only stale-killed line" test "$(grep -c "^stale-killed" "$limits/run.log")" = 1
check "nothing else run again (the hang, the slow and the flaky one twice, four others once)" \
    bash -c '[ "$(grep -c hang "$1")" = 2 ] && [ "$(grep -c slow "$1")" = 2 ] && [ "$(grep -c flaky "$1")" = 2 ] && [ "$(grep -c -e other -e survivor "$1")" = 4 ]' _ "$limits/state/runs"
check "the limits measured again before the second runs" test "$(grep -c unmutated "$limits/state/runs")" = 2
grep -F "18 -> 19" "$limits/accepted.txt" > "$limits/only.txt"
: > "$limits/state/runs"
limited --only "$limits/only.txt" "$subject" MutateFixtureRulesTest > "$limits/only.log" 2>&1
check "--only: one mutant of seven" grep -q -F "mutate.sh: $subject, 1 of 7 mutants (--only $limits/only.txt)" "$limits/only.log"
check "… only it run" test "$(grep -v -c unmutated "$limits/state/runs")" = 1
printf '%s\t%s\t%s\t%s\n' "$subject" "18 -> 19" "#1" "return age >= 21;" > "$limits/none.txt"
limited --only "$limits/none.txt" "$subject" MutateFixtureRulesTest > /dev/null 2>&1
check "--only naming no mutant: status 2" test $? = 2
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
printf '  shard 1 (MutateFixtureRulesTest) failed (status 1):\n    MutateFixtureRules: killed at the run'"'"'s memory budget (20G, all its processes together)\n' > "$work/budget.log"
judged() { [ "$("$tree/tests/mutate.sh" --judge "$1" "$2" "$subject")" = "$3" ]; }
check "a load error naming the subject: not compiled" judged "$work/load.log" 1 not-compiled
check "… after a time-out too" judged "$work/load.log" 124 not-compiled
check "… after a kill too" judged "$work/load.log" 137 not-compiled
check "a TypeError naming it: killed" judged "$work/type.log" 1 killed
check "a ReferenceError naming it: killed" judged "$work/reference.log" 1 killed
check "a failed check: killed" judged "$work/failed.log" 1 killed
check "a time-out without a load error: timed out" judged "$work/failed.log" 124 timed-out
check "… killed after the time-out too" judged "$work/failed.log" 137 timed-out
check "stopped at the memory cap: capped (counted as killed)" judged "$work/capped.log" 1 capped
check "stopped at the run's memory budget: capped too" judged "$work/budget.log" 1 capped
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
