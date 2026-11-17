#!/usr/bin/env bash
# Checks tests/run-unit.sh's verdict against stand-in Quickshells (LOCKTEST_QS) that print
# a summary and end in a given way — the cases where a crash used to pass:
#
#   crash      one suite's summary, no FAIL line, then SIGSEGV (status 139)  → must fail
#   partial    fewer suites than tests.qml registers, exit 0                  → must fail
#   complete   every suite tests.qml registers, all passed, exit 0            → must pass
#
# and the suite count against a small root file whose suites are written with and without
# arguments (`arguments`: each one must count).
#
#   flock /tmp/h2s-locktest.flock tests/run-unit-selftest.sh
#
# Each case starts the runner's private headless compositor (nothing shows); no shell runs.
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

verdict() {
    LOCKTEST_QS=$work/$1 "$REPO/tests/run-unit.sh" > "$work/$1.log" 2>&1
    local status=$?
    if [ "$status" = "$2" ]; then
        echo "PASS $1: run-unit.sh exited $status"
    else
        echo "FAIL $1: run-unit.sh exited $status, expected $2"
        tail -n 6 "$work/$1.log" | sed 's/^/    /'
        failures=$((failures + 1))
    fi
}
verdict crash 1
verdict partial 1
verdict complete 0
[ "$failures" = 0 ]
