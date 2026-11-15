#!/usr/bin/env bash
# Runs modules' own test suites, in the same private, headless compositor as the shell's
# (tests/headless.sh, shared with tests/run-unit.sh).
#
#   tests/run-modules.sh <module dir>…           the suites each module's manifest lists
#   tests/run-modules.sh --log <file> <dir>…     the output also saved to <file>
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
# no suites, or a suite that does not compile.
#
# Exit status as tests/run-unit.sh: 0 when every suite passed, 1 when a check FAILed, a
# module did not load, a suite timed out or did not report, a TypeError / ReferenceError was
# printed or Quickshell exited non-zero, 2 when the runner could not be set up (no module
# directory given, one that does not exist or has no module.json, tools).
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
# shellcheck disable=SC2034  # read by tests/headless.sh
HEADLESS_NAME=run-modules.sh
output_copy=""
if [ "${1:-}" = --log ]; then
    output_copy=${2:-}
    shift 2 || { echo "run-modules.sh: --log needs a file" >&2; exit 2; }
fi
[ $# -gt 0 ] || { echo "usage: tests/run-modules.sh [--log <file>] <module dir>…" >&2; exit 2; }

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
headless_run "$REPO/tests-modules.qml" "$output_copy" H2S_TEST_MODULES="$module_list"
# The runner says how many suites the loaded modules list, before it runs any: a crash
# after that is caught by the count
expected=$(sed -n 's/^.*MODULE-SUITES-EXPECTED: \([0-9][0-9]*\).*$/\1/p' "$HEADLESS_LOG" | tail -n 1)
headless_verdict "Module suites" "${expected:-1}" "the modules list"
exit $?
