#!/usr/bin/env bash
# The suites whose subject is input as it arrives through a compositor (tests-input.qml,
# tests/input/): a real click, wheel and key, sent by the lock bed's virtual pointer and
# keyboard (tests/lock/input/ltinput.py) on the run's private headless compositor, in the
# unit runners' isolation (tests/headless.sh). A suite sends its input through
# tests/input/InputDriver.qml, which writes to the client's command pipe (H2S_INPUT_FIFO).
#
#   tests/run-input.sh                  every suite tests-input.qml registers
#   tests/run-input.sh <Suite>…         only those (FloatingListInputTest)
#
# The suites run one after another in one Quickshell: one pointer, one keyboard. Nothing is
# left running.
#
# Exit status: 0 when every check passed, 1 when one failed, 2 when it could not be set up.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd -P)
# shellcheck disable=SC2034  # read by headless.sh
HEADLESS_NAME=run-input.sh
# The virtual devices come with the mockups' need (tests/lock/resolve.sh)
# shellcheck disable=SC2034  # read by headless.sh
HEADLESS_NEED=mockups
# shellcheck disable=SC2034  # read by resolve.sh
LOCKTEST_INPUT=1
# shellcheck source=headless.sh
source "$REPO/tests/headless.sh"

registered=$(sed -n 's/^ *property var _[A-Za-z0-9]*: \([A-Za-z0-9]*Test\) {.*}.*$/\1/p' "$REPO/tests-input.qml")
selected=()
for name in "$@"; do
    grep -q -x -F -- "$name" <<< "$registered" || setup_error "no suite '$name' in tests-input.qml (the suites: $(paste -s -d ' ' <<< "$registered"))"
    selected+=("$name")
done
if [ ${#selected[@]} -gt 0 ]; then
    expected=${#selected[@]}
else
    expected=$(grep -c . <<< "$registered")
fi

input_pid=""
input_cleanup() {
    trap '' INT TERM HUP
    [ -n "$input_pid" ] && { kill -TERM "$input_pid" 2> /dev/null; wait "$input_pid" 2> /dev/null; }
    headless_cleanup
}
trap input_cleanup EXIT

headless_setup

if [ "$LOCKTEST_TOOL_SOURCE" = system ]; then
    make_system_tools "$work/input-tools"
    input_share=$work/input-tools/share
else
    input_share=$LOCKTEST_TOOLS/share
fi
input_fifo=$work/input.fifo
mkfifo "$input_fifo" || setup_error "cannot make the input pipe"
# Started before Quickshell binds its seat (ltinput.py says why)
"${isolated[@]}" WAYLAND_DISPLAY=wayland-0 "$SETPRIV" --no-new-privs timeout 300 "$LOCKTEST_PYTHON" -I -B \
    "$REPO/tests/lock/input/ltinput.py" "$input_share" "$input_share/us.xkb" "$input_fifo" > "$work/input.log" 2>&1 < /dev/null &
input_pid=$!
deadline=$((SECONDS + 10))
# The client ready, a condition polled; ten seconds guard a client that does not start
while [ $SECONDS -lt $deadline ] && ! grep -q 'ltinput ready' "$work/input.log"; do sleep 0.05; done
grep -q 'ltinput ready' "$work/input.log" || { cat "$work/input.log" >&2; setup_error "the virtual pointer and keyboard did not start"; }

suites=$(IFS=:; echo "${selected[*]:-}")
headless_run "$REPO/tests-input.qml" "" H2S_INPUT_FIFO="$input_fifo" ${suites:+H2S_TEST_SUITES="$suites"}
if [ ${#selected[@]} -gt 0 ]; then
    names=()
    for name in "${selected[@]}"; do names+=("${name%Test}"); done
    headless_verdict "Real input suites" "$expected" "selected" exactly "${names[@]}"
else
    headless_verdict "Real input suites" "$expected" "in tests-input.qml"
fi
