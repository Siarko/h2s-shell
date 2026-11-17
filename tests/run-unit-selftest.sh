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
#
# tests/run-modules.sh with --suite, on the fixture module tests/fixtures/modules/good — the
# first two with the real Quickshell, so tests-modules.qml's part is checked too:
#
#   module-selected   one of its two suites named: that one reports, alone    → must pass
#   module-unknown    a name the module does not list: status 2, nothing run
#   module-extra      (stand-in) more suites report than were selected        → must fail
#
# the suite count against a small root file whose suites are written with and without
# arguments (`arguments`: each one must count), the suites a suite is given, read from the
# same file (`given`, `qualified`), a root file whose suites cannot be read reliably
# (`unbalanced`: said, not counted short), and every suite's suiteName against its file name
# (`names`: a named suite is found by its suiteName followed by "Test").
#
#   flock /tmp/h2s-locktest.flock tests/run-unit-selftest.sh
#
# Each case starts the runner's private headless compositor (nothing shows); no shell runs
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

# interrupted: the runner is told to end while Quickshell runs (a stand-in that never
# ends). It ends at once with status 130 and leaves nothing: not Quickshell, not the
# compositor, not its temp dir. TERM stands for an interrupt here: a command a script starts
# in the background ignores INT.
{
    echo "#!$(command -v bash)"
    # Asked for its version (the runner's first lines), it only ends
    echo '[ "${1:-}" = --version ] && exit 0'
    echo "echo \"\$XDG_RUNTIME_DIR\" > '$work/sleeper.started'"
    echo "exec sleep 200"
} > "$work/sleeper"
chmod +x "$work/sleeper"
LOCKTEST_QS=$work/sleeper "$REPO/tests/run-unit.sh" > "$work/interrupted.log" 2>&1 &
runner_pid=$!
for _ in $(seq 1 1200); do
    [ -s "$work/sleeper.started" ] && break
    kill -0 "$runner_pid" 2> /dev/null || break
    sleep 0.1
done
# The runner's own processes, and theirs (timeout, and the compositor or Quickshell under it)
runner_processes=()
for child in $(pgrep -P "$runner_pid"); do
    runner_processes+=("$child")
    for grandchild in $(pgrep -P "$child"); do runner_processes+=("$grandchild"); done
done
runner_dir=$(dirname "$(cat "$work/sleeper.started" 2> /dev/null)")
check interrupted "Quickshell was running, in the runner's temp dir" test -d "$runner_dir" -a "$runner_dir" != .
check interrupted "the compositor and Quickshell are the runner's processes" test "${#runner_processes[@]}" -ge 4
kill -TERM "$runner_pid" 2> /dev/null
interrupted_at=$SECONDS
for _ in $(seq 1 100); do kill -0 "$runner_pid" 2> /dev/null || break; sleep 0.1; done
if kill -0 "$runner_pid" 2> /dev/null; then
    echo "FAIL interrupted: run-unit.sh still runs $((SECONDS - interrupted_at)) s after the interrupt"
    failures=$((failures + 1))
    kill -KILL "$runner_pid" "${runner_processes[@]}" 2> /dev/null
    wait "$runner_pid" 2> /dev/null
    [ "$runner_dir" != . ] && rm -rf "$runner_dir"
else
    wait "$runner_pid"
    check interrupted "run-unit.sh exited 130" test $? = 130
    none_left() {
        local process
        for process in "${runner_processes[@]}"; do kill -0 "$process" 2> /dev/null && return 1; done
        return 0
    }
    check interrupted "none of its processes is left" none_left
    check interrupted "its temp dir is gone" test ! -e "$runner_dir"
fi
[ "$failures" = 0 ]
