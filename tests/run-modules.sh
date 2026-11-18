#!/usr/bin/env bash
# Runs modules' own test suites, in the same private, headless compositor as the shell's
# (tests/headless.sh, shared with tests/run-unit.sh), with the same tools from the same
# place (see tests/run-unit.sh).
#
#   tests/run-modules.sh <module dir>…                 the suites each module's manifest lists
#   tests/run-modules.sh --suite <name> … <dir>…       only the named ones (--suite once per
#                                                      suite: its file without ".qml")
#   tests/run-modules.sh --log <file> … <dir>…         the output also saved to <file>
#
# A module directory may be anywhere — another repository's checkout, a store path: it is
# given here, made canonical, and loaded the way the shell's module host loads it
# (singletons/ModuleHost.qml: manifest, API check, import check, required programs, its
# `main` created by URL), with this shell's tree as Quickshell's config root. So a module's
# suites can extend the shell's TestCase (`import qs.tests`), import what modules may
# import, and reach the module's own singletons (`import ".."` from a tests/ directory: the
# same instances its main uses). The runner is tests-modules.qml.
#
# A module that does not load (any state but "loaded": a broken file, a wrong API, a
# missing program, …) fails the run with its status and errors, and so does one that lists
# no suites, or a suite that does not compile. With --suite the modules are loaded the same
# way and only the named suites are created (the names reach tests-modules.qml as
# H2S_TEST_MODULE_SUITES); a name is looked for in every module given.
#
# The suites run in module test mode (tests-modules.qml): a module's testPrograms are its
# programs, links and notifications are recorded, not opened or sent. A pkexec is put first
# on PATH (tests/fixtures/pkexec-on-path) that marks the run failed if anything starts it:
# a suite must never meet the real one.
#
# Exit status as tests/run-unit.sh: 0 when every suite passed, 1 when a check FAILed, a
# module did not load, a suite timed out or did not report, a TypeError / ReferenceError was
# printed or Quickshell exited non-zero, 2 when the runner could not be set up (no module
# directory given, one that does not exist or has no module.json, a missing tool) or a --suite name
# is no suite of the modules given, all of them loaded (nothing runs then).
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
# shellcheck disable=SC2034  # read by tests/headless.sh
HEADLESS_NAME=run-modules.sh
output_copy=""
suites=()
while [ $# -gt 0 ]; do
    case "$1" in
        --log)
            output_copy=${2:-}
            [ -n "$output_copy" ] || { echo "run-modules.sh: --log needs a file" >&2; exit 2; }
            shift 2
            ;;
        --suite)
            # Joined with ":" for the runner, and compared there with file names
            [[ "${2:-}" =~ ^[A-Za-z0-9_]+$ ]] || { echo "run-modules.sh: --suite needs a suite's name (its file without .qml)" >&2; exit 2; }
            suites+=("$2")
            shift 2
            ;;
        *) break ;;
    esac
done
[ $# -gt 0 ] || { echo "usage: tests/run-modules.sh [--log <file>] [--suite <name>]… <module dir>…" >&2; exit 2; }

# Canonical, as the launcher makes them (realpath): one directory, one spelling
directories=()
for argument in "$@"; do
    directory=$(cd -- "$argument" 2> /dev/null && pwd -P) \
        || { echo "run-modules.sh: $argument is not a directory" >&2; exit 2; }
    [ -f "$directory/module.json" ] || { echo "run-modules.sh: $argument has no module.json" >&2; exit 2; }
    case "$directory" in *:*) echo "run-modules.sh: $directory: a module path cannot hold ':'" >&2; exit 2 ;; esac
    directories+=("$directory")
done
module_list=$(IFS=:; echo "${directories[*]}")

# shellcheck source=headless.sh
source "$REPO/tests/headless.sh"
headless_setup
headless_run "$REPO/tests-modules.qml" "$output_copy" H2S_TEST_MODULES="$module_list" \
    H2S_TEST_MODULE_SUITES="$(IFS=:; echo "${suites[*]}")" \
    PATH="$REPO/tests/fixtures/pkexec-on-path:${LOCKTEST_TOOLS:+$LOCKTEST_TOOLS/bin:}$PATH"
# A name no loaded module lists: the runner says so and creates no suite
unknown=$(sed -n 's/^.*MODULE-SUITES-UNKNOWN: \([A-Za-z0-9_ ]*\).*$/\1/p' "$HEADLESS_LOG" | tail -n 1)
if [ -n "$unknown" ]; then
    echo "run-modules.sh: no suite named $unknown in the modules given; nothing was run" >&2
    exit 2
fi
# The runner says how many suites it is about to create (the ones the loaded modules list,
# or the named ones), before it runs any: a crash after that is caught by the count
expected=$(sed -n 's/^.*MODULE-SUITES-EXPECTED: \([0-9][0-9]*\).*$/\1/p' "$HEADLESS_LOG" | tail -n 1)
if [ ${#suites[@]} -gt 0 ]; then
    headless_verdict "Module suites" "${expected:-1}" "selected" exactly
else
    headless_verdict "Module suites" "${expected:-1}" "the modules list"
fi
verdict=$?
if [ -e "$work/run/h2s-pkexec-on-path-ran" ]; then
    echo "  a pkexec found on PATH was started (module test mode allows only a module's <testPrograms>/pkexec)"
    verdict=1
fi
exit $verdict
