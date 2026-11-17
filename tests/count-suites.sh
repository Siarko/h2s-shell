# shellcheck shell=bash
# The number of suites a root file registers, shared by tests/run-unit.sh and
# tests/run-unit-selftest.sh. Sourced.
#
#   count_suites <root.qml>    prints how many `property var _name: SomethingTest {…}` lines
#                              it has; a suite written with arguments
#                              (`SomethingTest { after: _other }`) counts as well

count_suites() {
    grep -c -E '^[[:space:]]*property var _[A-Za-z0-9]+: [A-Za-z0-9]+Test[[:space:]]*\{' "$1"
}
