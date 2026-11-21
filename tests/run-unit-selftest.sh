#!/usr/bin/env bash
# Checks tests/run-unit.sh's verdict against stand-in Quickshells (LOCKTEST_QS) that print
# a summary and end in a given way — the cases where a crash used to pass:
#
#   crash      one suite's summary, no FAIL line, then SIGSEGV (status 139)  → must fail
#   partial    fewer suites than tests.qml registers, exit 0                  → must fail
#   complete   every suite tests.qml registers, all passed, exit 0            → must pass
#
# with suites named to the runner (the `obedient` stand-in reports the suites it is told to
# run in H2S_TEST_SUITES, and no other):
#
#   selected   two named suites, both report                                  → must pass
#   needed     ModuleRegistriesTest: the suites it is given are run with it   → must pass
#   logged     --log <file> with a named suite: the output is in the file     → must pass
#   unknown    a name tests.qml does not register: status 2, nothing started
#   empty      an empty name, alone or beside a suite: status 2, nothing started
#   silent     one of two named suites does not report                        → must fail
#   extra      a suite that was not named reports as well                     → must fail
#   renamed    as many suites report as were named, one of them another suite → must fail
#   real       (the real Quickshell) FormatTest named: Format reports, alone  → must pass
#   limited    (the real Quickshell, a copy of the tree) a suite that never finishes, with
#              its own 2 s limit: fails as timed out at that limit             → must fail
#
# tests/run-modules.sh with --suite, on the fixture module tests/fixtures/modules/good — the
# first two with the real Quickshell, so tests-modules.qml's part is checked too:
#
#   module-selected   one of its two suites named: that one reports, alone    → must pass
#   module-unknown    a name the module does not list: status 2, nothing run
#   module-extra      (stand-in) more suites report than were selected        → must fail
#   module-uncounted  (stand-in) a suite reports, but no line said how many   → must fail
#                     would: with --suite and without
#
# the suite count against a small root file whose suites are written with and without
# arguments (`arguments`: each one must count), the suites a suite is given, read from the
# same file (`given`, `qualified`), a root file whose suites cannot be read reliably
# (`unbalanced`: said, not counted short), and every suite's suiteName against its file name
# (`names`: a named suite is found by its suiteName followed by "Test").
#
# and how the runner ends:
#
#   unreadable          a tests.qml like `unbalanced`: status 2, nothing started
#   interrupted         told to end while Quickshell runs: status 130 at once, no
#                       process and no temp dir left
#   interrupted-twice   a Quickshell that ignores the request, and a second interrupt
#                       during the cleanup: the same
#
#   tests/run-unit-selftest.sh
#
# It takes no lock, as the runner takes none: another run beside it shares only the
# processor. Each case starts the runner's private headless compositor (nothing shows); no shell runs
# (`real` runs tests.qml, the module cases tests-modules.qml). The tools are found as the
# runner finds them (tests/run-unit.sh), so the verdict is guarded with the pinned tools and
# with the system's.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ut-self.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
# shellcheck source=count-suites.sh
source "$REPO/tests/count-suites.sh"

expected=$(count_suites "$REPO/tests.qml")
[ "$expected" -gt 1 ] || { echo "cannot count the suites in tests.qml"; exit 2; }
suites_agree "$REPO/tests.qml" || { echo "cannot read the suites of tests.qml: its registration lines and the suites read from them differ in number"; exit 2; }

failures=0

# A suite that takes arguments counts like one that takes none
cat > "$work/arguments.qml" << 'QML'
Item {
    property var _plain: PlainTest {}
    property var _spaced: SpacedTest { }
    property var _ordered: OrderedTest { after: _plain; other: _spaced }
    property var _open: OpenTest {
        after: _ordered
    }
    property var _qualified: QualifiedTest { after: root._spaced }
    property var notASuite: Helper {}
    // property var _commented: CommentedTest {}
}
QML
counted=$(count_suites "$work/arguments.qml")
if [ "$counted" = 5 ] && suites_agree "$work/arguments.qml"; then
    echo "PASS arguments: 5 suites counted, and as many read"
else
    echo "FAIL arguments: $counted suites counted, $(registered_suites "$work/arguments.qml" | grep -c .) read, expected 5"
    failures=$((failures + 1))
fi

# What a suite is given brings it along, on its line or on the next ones, each suite once
needed=$(suites_with_needed "$work/arguments.qml" OpenTest PlainTest | tr '\n' ' ')
if [ "$needed" = "OpenTest PlainTest OrderedTest SpacedTest " ]; then
    echo "PASS given: OpenTest brings OrderedTest, PlainTest and SpacedTest"
else
    echo "FAIL given: OpenTest and PlainTest gave '$needed'"
    failures=$((failures + 1))
fi

# A suite named through the root object is given all the same
needed=$(suites_with_needed "$work/arguments.qml" QualifiedTest | tr '\n' ' ')
if [ "$needed" = "QualifiedTest SpacedTest " ]; then
    echo "PASS qualified: QualifiedTest brings SpacedTest"
else
    echo "FAIL qualified: QualifiedTest gave '$needed'"
    failures=$((failures + 1))
fi

# A brace in a string hides the suites after it from the reading that follows braces: the
# two counts differ, and that is what the runner refuses to start on
cat > "$work/unbalanced.qml" << 'QML'
Item {
    property var _first: FirstTest {
        label: "{"
    }
    property var _second: SecondTest {}
    property var _third: ThirdTest { after: _first }
}
QML
if [ "$(count_suites "$work/unbalanced.qml")" = 3 ] && ! suites_agree "$work/unbalanced.qml"; then
    echo "PASS unbalanced: 3 suites counted, the reading that differs is noticed"
else
    echo "FAIL unbalanced: $(count_suites "$work/unbalanced.qml") suites counted, $(registered_suites "$work/unbalanced.qml" | grep -c .) read, and no difference noticed"
    failures=$((failures + 1))
fi

# TestCase finds a named suite by its suiteName followed by "Test", the runner by its file
misnamed=""
for file in "$REPO"/tests/*Test.qml; do
    type=$(basename "$file" .qml)
    grep -q -E "^[[:space:]]*suiteName: \"${type%Test}\"[[:space:]]*$" "$file" || misnamed="$misnamed $type"
done
if [ -z "$misnamed" ]; then
    echo "PASS names: every suite's suiteName is its file name without Test"
else
    echo "FAIL names: suiteName is not the file name without Test in:$misnamed"
    failures=$((failures + 1))
fi

# stand_in <name> <summaries> <how it ends>
stand_in() {
    {
        echo "#!$(command -v bash)"
        for ((i = 1; i <= $2; i++)); do echo "echo '  INFO: --- Suite$i: 3/3 passed'"; done
        echo "$3"
    } > "$work/$1"
    chmod +x "$work/$1"
}
stand_in crash 1 'kill -SEGV $$'
stand_in partial $((expected - 1)) 'exit 0'
stand_in complete "$expected" 'exit 0'

# Reports the suites the runner selected (H2S_TEST_SUITES), under the names TestCase prints
# (the type without "Test"); `silent` leaves the last one out, `extra` adds one, `renamed`
# reports another suite in place of the last
selecting_stand_in() {
    {
        echo "#!$(command -v bash)"
        echo 'IFS=: read -r -a names <<< "${H2S_TEST_SUITES:-}"'
        echo "$2"
        echo 'for name in "${names[@]}"; do echo "  INFO: --- ${name%Test}: 3/3 passed"; done'
        echo 'exit 0'
    } > "$work/$1"
    chmod +x "$work/$1"
}
selecting_stand_in obedient ''
selecting_stand_in silent 'unset "names[-1]"'
selecting_stand_in extra 'names+=(UnnamedTest)'
selecting_stand_in renamed 'names[-1]=UnnamedTest'

# verdict <case> <stand-in, or "real" for the Quickshell the runners find> <expected status>
#         [<argument of the runner>…]: the runner is $runner
runner=run-unit.sh
verdict() {
    local name=$1 quickshell=$2 expected_status=$3 status
    shift 3
    if [ "$quickshell" = real ]; then
        "$REPO/tests/$runner" "$@" > "$work/$name.log" 2>&1
    else
        LOCKTEST_QS=$work/$quickshell "$REPO/tests/$runner" "$@" > "$work/$name.log" 2>&1
    fi
    status=$?
    if [ "$status" = "$expected_status" ]; then
        echo "PASS $name: $runner exited $status"
    else
        echo "FAIL $name: $runner exited $status, expected $expected_status"
        tail -n 6 "$work/$name.log" | sed 's/^/    /'
        failures=$((failures + 1))
    fi
}
# check <case> <what> <command…>: something else a case must show
check() {
    local name=$1 what=$2
    shift 2
    if "$@"; then
        echo "PASS $name: $what"
    else
        echo "FAIL $name: not so: $what"
        failures=$((failures + 1))
    fi
}
reports() { grep -q -- "--- $2: 3/3 passed" "$work/$1"; }
# The runner's verdict lists each suite that reported, indented
reports_only() {
    [ "$(grep -c -E -- '^  --- .* passed' "$work/$1")" = 1 ] && grep -q -E -- "^  --- $2: [0-9]+/[0-9]+ passed" "$work/$1"
}
reports_nothing() { ! grep -q -- "passed" "$work/$1"; }

verdict crash crash 1
verdict partial partial 1
verdict complete complete 0

verdict selected obedient 0 FormatTest LockRulesTest
check selected "FormatTest reported" reports selected.log Format
check selected "LockRulesTest reported" reports selected.log LockRules
verdict needed obedient 0 ModuleRegistriesTest
check needed "ModulesTest was run with it" reports needed.log Modules
check needed "VpnProvidersTest was run with it" reports needed.log VpnProviders
verdict logged obedient 0 --log "$work/copy.log" FormatTest
check logged "the output is in the file" reports copy.log Format
verdict unknown obedient 2 FormatTest NoSuchTest
check unknown "no suite ran" reports_nothing unknown.log
verdict empty obedient 2 ""
check empty "no suite ran" reports_nothing empty.log
verdict empty-beside obedient 2 "" FormatTest
check empty-beside "no suite ran" reports_nothing empty-beside.log
verdict silent silent 1 FormatTest LockRulesTest
verdict extra extra 1 FormatTest
verdict renamed renamed 1 FormatTest LockRulesTest
verdict real real 0 FormatTest
check real "Format reported, alone" reports_only real.log "Format"

# limited: an asynchronous suite that never finishes and sets its own limit (2 s) fails as
# timed out at that limit, not at the runner's default. The runner takes its tree from where
# it is, so a copy of it beside a tests.qml with that suite added runs that file; the rest of
# the tree is linked.
mkdir -p "$work/limited/tests"
for entry in "$REPO"/* "$REPO"/.[!.]*; do
    case "${entry##*/}" in tests.qml|tests|.git) continue ;; esac
    ln -s "$entry" "$work/limited/${entry##*/}"
done
for entry in "$REPO"/tests/*; do ln -s "$entry" "$work/limited/tests/${entry##*/}"; done
rm "$work/limited/tests/run-unit.sh"
cp "$REPO/tests/run-unit.sh" "$work/limited/tests/"
cat > "$work/limited/tests/HungTest.qml" << 'QML'
TestCase {
    suiteName: "Hung"
    asynchronous: true
    timeLimitMs: 2000
}
QML
sed -e 's/^\(    property var _promises: PromisesTest {}\)$/    property var _hung: HungTest {}\n\1/' \
    -e 's/^\(    readonly property var _asyncSuites: \[\)/\1_hung, /' "$REPO/tests.qml" > "$work/limited/tests.qml"
limited_started=$SECONDS
"$work/limited/tests/run-unit.sh" HungTest > "$work/limited.log" 2>&1
limited_status=$?
limited_took=$((SECONDS - limited_started))
check limited "run-unit.sh exited 1 (it exited $limited_status)" test "$limited_status" = 1
check limited "the suite failed as timed out at its own limit" grep -q "FAIL: timed out (2 s)" "$work/limited.log"
check limited "… well before the runner's default (it took ${limited_took} s)" test "$limited_took" -lt 60

runner=run-modules.sh
good=$REPO/tests/fixtures/modules/good
verdict module-selected real 0 --suite GoodStateTest "$good"
check module-selected "GoodStateTest reported, alone" reports_only module-selected.log "good: GoodState"
verdict module-unknown real 2 --suite GoodStateTest --suite NoSuchTest "$good"
check module-unknown "no suite ran" reports_nothing module-unknown.log
{
    echo "#!$(command -v bash)"
    echo "echo 'MODULE-SUITES-EXPECTED: 1'"
    echo "echo '  INFO: --- one: 3/3 passed ---'"
    echo "echo '  INFO: --- another: 3/3 passed ---'"
} > "$work/module-extra"
chmod +x "$work/module-extra"
verdict module-extra module-extra 1 --suite GoodStateTest "$good"
{
    echo "#!$(command -v bash)"
    echo "echo '  INFO: --- good: GoodState: 5/5 passed ---'"
} > "$work/module-uncounted"
chmod +x "$work/module-uncounted"
verdict module-uncounted module-uncounted 1 --suite GoodStateTest "$good"
check module-uncounted "said so" grep -q "no MODULE-SUITES-EXPECTED line" "$work/module-uncounted.log"
verdict module-uncounted-all module-uncounted 1 "$good"

# unreadable: a tests.qml whose suites cannot be read reliably (the `unbalanced` file) ends
# the runner with status 2 before anything is started, with and without a name. The runner
# takes its tree from where it is, so a copy of it beside that file reads that file (and
# has no headless.sh to start anything with).
mkdir -p "$work/tree/tests"
cp "$REPO/tests/run-unit.sh" "$REPO/tests/count-suites.sh" "$work/tree/tests/"
cp "$work/unbalanced.qml" "$work/tree/tests.qml"
refuses_unreadable() {
    "$work/tree/tests/run-unit.sh" "$@" > "$work/unreadable.log" 2>&1
    [ $? = 2 ] && grep -q "^run-unit.sh: cannot read the suites of tests.qml: .*nothing was run" "$work/unreadable.log" \
        && [ "$(grep -c . "$work/unreadable.log")" = 1 ]
}
check unreadable "run-unit.sh exited 2 and said why, nothing else" refuses_unreadable
check unreadable "… with a suite named too" refuses_unreadable FirstTest

# interrupted: the runner is told to end while Quickshell runs (a stand-in that never
# ends). It ends at once with status 130 and leaves nothing: not Quickshell, not the
# compositor, not its temp dir. TERM stands for an interrupt here: a command a script starts
# in the background ignores INT.
# interrupted-twice: a Quickshell that does not end when told to (TERM ignored), and a
# second interrupt while the runner is stopping it: the runner still leaves nothing.
{
    echo "#!$(command -v bash)"
    # Asked for its version (the runner's first lines), it only ends
    echo '[ "${1:-}" = --version ] && exit 0'
    echo "echo \"\$XDG_RUNTIME_DIR\" > '$work/sleeper.started'"
    echo "exec sleep 200"
} > "$work/sleeper"
{
    echo "#!$(command -v bash)"
    echo '[ "${1:-}" = --version ] && exit 0'
    # Says when it was told to end, which is when the runner has begun to clean up
    echo "trap \"echo told > '$work/stubborn.told'\" TERM"
    echo "(trap '' TERM; exec sleep 200) &"
    echo "echo \"\$XDG_RUNTIME_DIR\" > '$work/stubborn.started'"
    echo 'while kill -0 $! 2> /dev/null; do wait; done'
} > "$work/stubborn"
chmod +x "$work/sleeper" "$work/stubborn"

runner_pid=""
runner_processes=()
runner_dir=""
# descendants <pid>: its children and theirs, to any depth
descendants() {
    local child
    for child in $(pgrep -P "$1"); do
        echo "$child"
        descendants "$child"
    done
}
none_left() {
    local process
    for process in "${runner_processes[@]}"; do kill -0 "$process" 2> /dev/null && return 1; done
    return 0
}
# Whatever of a case's runner is still there, and its temp dir: after the case, and when
# this script is ended in the middle of one. The runner is asked first — it stops what it
# started, also what was not written down here yet — then the pids written down are killed.
stop_runner() {
    local process
    if [ -n "$runner_pid" ] && kill -TERM "$runner_pid" 2> /dev/null; then
        for _ in $(seq 1 50); do kill -0 "$runner_pid" 2> /dev/null || break; sleep 0.1; done
    fi
    for process in $runner_pid "${runner_processes[@]}"; do
        kill -0 "$process" 2> /dev/null && kill -KILL "$process" 2> /dev/null
    done
    [ -n "$runner_pid" ] && wait "$runner_pid" 2> /dev/null
    case "$runner_dir" in /tmp/ut.*) rm -rf "$runner_dir" ;; esac
    runner_pid=""
    runner_processes=()
    runner_dir=""
}
trap 'trap "" INT TERM HUP; stop_runner; rm -rf "$work"' EXIT

# interrupt <case> <stand-in> <processes it makes the runner have> [twice]
interrupt() {
    local name=$1 quickshell=$2 expected_processes=$3 twice=${4:-} status
    LOCKTEST_QS=$work/$quickshell "$REPO/tests/run-unit.sh" > "$work/$name.log" 2>&1 &
    runner_pid=$!
    for _ in $(seq 1 1200); do
        [ -s "$work/$quickshell.started" ] && break
        kill -0 "$runner_pid" 2> /dev/null || break
        sleep 0.1
    done
    # timeout and the compositor, timeout and Quickshell (and what Quickshell started)
    mapfile -t runner_processes < <(descendants "$runner_pid")
    runner_dir=$(dirname "$(cat "$work/$quickshell.started" 2> /dev/null)")
    check "$name" "Quickshell was running, in the runner's temp dir" test -d "$runner_dir" -a "$runner_dir" != .
    check "$name" "the compositor and Quickshell are the runner's processes" test "${#runner_processes[@]}" -ge "$expected_processes"
    kill -TERM "$runner_pid" 2> /dev/null
    if [ -n "$twice" ]; then
        for _ in $(seq 1 100); do [ -s "$work/$quickshell.told" ] && break; sleep 0.1; done
        check "$name" "Quickshell was told to end: the runner is cleaning up" test -s "$work/$quickshell.told"
        kill -TERM "$runner_pid" 2> /dev/null
    fi
    for _ in $(seq 1 100); do kill -0 "$runner_pid" 2> /dev/null || break; sleep 0.1; done
    if kill -0 "$runner_pid" 2> /dev/null; then
        echo "FAIL $name: run-unit.sh still runs 10 s after the interrupt"
        failures=$((failures + 1))
    else
        wait "$runner_pid"
        status=$?
        check "$name" "run-unit.sh exited 130" test "$status" = 130
        check "$name" "none of its processes is left" none_left
        check "$name" "its temp dir is gone" test ! -e "$runner_dir"
    fi
    stop_runner
}
interrupt interrupted sleeper 4
interrupt interrupted-twice stubborn 5 twice
[ "$failures" = 0 ]
