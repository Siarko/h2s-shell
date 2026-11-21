#!/usr/bin/env bash
# Runs the unit suites (tests.qml) in a private, headless compositor, so that nothing shows
# on the screen: PointerInputTest, ToastDragTest, ButtonKindsTest, LockViewTest, ApiElementsTest,
# ModuleIconTest, AuthPromptViewTest, SettingsModalTest and ModulesPageTest open a small window, FileChooserTest a file dialog, and in the real
# session they would appear there, under your pointer.
#
#   tests/run-unit.sh                            every suite tests.qml registers
#   tests/run-unit.sh FormatTest LockRulesTest   only the named ones (a suite is named by its
#                                                type, the file in tests/ without ".qml")
#   tests/run-unit.sh --log <file> [<suite>…]    the output also saved to <file>
#
# A named suite brings the suites tests.qml gives it (ModuleRegistriesTest is given
# ModulesTest and VpnProvidersTest and waits for them): they run and are counted too. The
# names reach tests/TestCase.qml as H2S_TEST_SUITES; every suite is still built, the others
# do not run. A suite is found there by its suiteName followed by "Test", so that is what its
# file is called.
#
# The isolation (a headless labwc in a private runtime dir, D-Bus addresses that lead
# nowhere, a private HOME and XDG directories, no new privileges) and the verdict are
# tests/headless.sh's, shared with tests/run-modules.sh. On PATH first: stand-ins for nmcli
# and notify-send (tests/fixtures/unit-path), for the suites that build the real settings
# window.
#
# Needs Quickshell, labwc, setpriv, setsid and timeout. labwc and setpriv are the pinned
# ones of tests/lock/tools.nix where there is a `nix` command, else those on PATH
# (H2S_TEST_TOOLS=nix or =system says which); Quickshell is LOCKTEST_QS, else the one the
# h2s-shell launcher runs, else qs or quickshell on PATH (tests/lock/resolve.sh). The first
# lines printed say what was taken.
#
# Exit status: 0 when every suite passed, 1 when a check FAILed, a suite timed out, checked
# nothing (0/0) or checked after it had reported, a
# TypeError / ReferenceError was printed, Quickshell exited non-zero (a crash after a
# partial summary included) or fewer suites reported than tests.qml registers — with names:
# a named or needed suite did not report, or another one did —, 2 when the runner could not
# be set up (a missing tool is named, with its use), a name is empty or not a suite of
# tests.qml, or the suites of tests.qml cannot be read reliably (nothing runs then).
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
# shellcheck disable=SC2034  # read by tests/headless.sh
HEADLESS_NAME=run-unit.sh
# shellcheck source=count-suites.sh
source "$REPO/tests/count-suites.sh"

output_copy=""
if [ "${1:-}" = --log ]; then
    output_copy=${2:-}
    [ -n "$output_copy" ] || { echo "run-unit.sh: --log needs a file" >&2; exit 2; }
    shift 2
fi
case "${1:-}" in -*) echo "usage: tests/run-unit.sh [--log <file>] [<suite>…]" >&2; exit 2 ;; esac

# The expected count and the selection both come from tests.qml's registration lines: when
# the two ways of reading them disagree, neither can be trusted
suites_agree "$REPO/tests.qml" \
    || { echo "run-unit.sh: cannot read the suites of tests.qml: $(count_suites "$REPO/tests.qml") registration lines, $(registered_suites "$REPO/tests.qml" | grep -c .) suites read from them (a brace in a string or comment of a suite's arguments?); nothing was run" >&2; exit 2; }

# Before anything is started: a name tests.qml does not register must not end as a pass
selected=()
for name in "$@"; do
    [ -n "$name" ] || { echo "run-unit.sh: an empty suite name; nothing was run" >&2; exit 2; }
done
if [ $# -gt 0 ]; then
    unknown=$(suites_with_needed "$REPO/tests.qml" "$@" 2>&1 > /dev/null) || {
        echo "run-unit.sh: no suite named '$unknown' in tests.qml (a suite is named by its type: FormatTest); nothing was run" >&2
        exit 2
    }
    mapfile -t selected < <(suites_with_needed "$REPO/tests.qml" "$@")
    echo "run-unit.sh: running ${selected[*]}"
fi

# shellcheck source=headless.sh
source "$REPO/tests/headless.sh"
headless_setup
# Stand-ins for nmcli and notify-send first on PATH: suites that build the real settings
# window start the shell's network readers and may notify, and must reach no real daemon
unit_path=PATH="$REPO/tests/fixtures/unit-path:${LOCKTEST_TOOLS:+$LOCKTEST_TOOLS/bin:}$PATH"
if [ ${#selected[@]} -gt 0 ]; then
    headless_run "$REPO/tests.qml" "$output_copy" "$unit_path" H2S_TEST_SUITES="$(IFS=:; echo "${selected[*]}")"
    # Exactly the selected suites must report, under the names TestCase gives them
    headless_verdict "Unit suites" ${#selected[@]} "selected" exactly "${selected[@]%Test}"
else
    headless_run "$REPO/tests.qml" "$output_copy" "$unit_path"
    # Every suite tests.qml registers (`property var _name: SomethingTest {…}`) must report
    headless_verdict "Unit suites" "$(count_suites "$REPO/tests.qml")" "in tests.qml"
fi
exit $?
