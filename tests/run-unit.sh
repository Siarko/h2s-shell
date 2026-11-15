#!/usr/bin/env bash
# Runs the unit suites (tests.qml) in a private, headless compositor, so that nothing shows
# on the screen: PointerInputTest and LockViewTest open a small window, and in the real
# session it would appear there, under your pointer.
#
#   tests/run-unit.sh            the suites of this checkout
#   tests/run-unit.sh <log>      the output also saved to <log>
#
# The isolation (a headless labwc in a private runtime dir, D-Bus addresses that lead
# nowhere, a private HOME and XDG directories, no new privileges) and the verdict are
# tests/headless.sh's, shared with tests/run-modules.sh.
#
# Exit status: 0 when every suite passed, 1 when a check FAILed, a suite timed out, a
# TypeError / ReferenceError was printed, Quickshell exited non-zero (a crash after a
# partial summary included) or fewer suites reported than tests.qml registers, 2 when the
# runner could not be set up.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
# shellcheck disable=SC2034  # read by tests/headless.sh
HEADLESS_NAME=run-unit.sh
# shellcheck source=headless.sh
source "$REPO/tests/headless.sh"

headless_setup
headless_run "$REPO/tests.qml" "${1:-}"
# Every suite tests.qml registers (`property var _name: SomethingTest {}`) must report
expected=$(grep -c -E '^[[:space:]]*property var _[A-Za-z0-9]+: [A-Za-z0-9]+Test \{\}' "$REPO/tests.qml")
headless_verdict "Unit suites" "$expected" "in tests.qml"
exit $?
