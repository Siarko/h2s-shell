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
#   silent     one of two named suites does not report                        → must fail
#   extra      a suite that was not named reports as well                     → must fail
#
# tests/run-modules.sh with --suite, on the fixture module tests/fixtures/modules/good — the
# first two with the real Quickshell, so tests-modules.qml's part is checked too:
#
#   module-selected   one of its two suites named: that one reports, alone    → must pass
#   module-unknown    a name the module does not list: status 2, nothing run
#   module-extra      (stand-in) more suites report than were selected        → must fail
#
# the suite count against a small root file whose suites are written with and without
# arguments (`arguments`: each one must count), and the suites a suite is given, read from
# the same file (`given`).
#
#   flock /tmp/h2s-locktest.flock tests/run-unit-selftest.sh
#
# Each case starts the runner's private headless compositor (nothing shows); no shell runs
# (the module cases run tests-modules.qml).
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ut-self.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
# shellcheck source=count-suites.sh
source "$REPO/tests/count-suites.sh"

expected=$(count_suites "$REPO/tests.qml")
[ "$expected" -gt 1 ] || { echo "cannot count the suites in tests.qml"; exit 2; }

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
    property var notASuite: Helper {}
    // property var _commented: CommentedTest {}
}
QML
counted=$(count_suites "$work/arguments.qml")
if [ "$counted" = 4 ]; then
    echo "PASS arguments: 4 suites counted"
else
    echo "FAIL arguments: $counted suites counted, expected 4"
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
# (the type without "Test"); `silent` leaves the last one out, `extra` adds one
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
check selected "the two suites reported" reports selected.log LockRules
verdict needed obedient 0 ModuleRegistriesTest
check needed "ModulesTest was run with it" reports needed.log Modules
check needed "VpnProvidersTest was run with it" reports needed.log VpnProviders
verdict logged obedient 0 --log "$work/copy.log" FormatTest
check logged "the output is in the file" reports copy.log Format
verdict unknown obedient 2 FormatTest NoSuchTest
check unknown "no suite ran" reports_nothing unknown.log
verdict silent silent 1 FormatTest LockRulesTest
verdict extra extra 1 FormatTest

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
[ "$failures" = 0 ]
