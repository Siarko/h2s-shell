#!/usr/bin/env bash
# The mockups' root entry (mockup.qml) and its window (mockups/kit/MockupWindow.qml), headless
# on the fixture mockups in tests/fixtures/mockups/ (H2S_MOCKUP_BASE):
#
#   - a good mockup loads with its qs.* imports, prints one MOCKUP-SHOT line per scene with
#     the subject's bounds, steps on `ipc call mockup next`, answers `ipc call mockup name`,
#     and ends with MOCKUP-DONE and exit 0;
#   - a bad name, a base it does not take, a missing file, a load error, a repeated and an
#     empty scene name each end with MOCKUP-ERROR and exit 2, without a shot.
#
#   tests/mockup-entry-selftest.sh
#
# In the unit runners' isolation (tests/headless.sh): one private headless compositor for
# all cases, a private HOME and runtime dir, the memory cap. Nothing is left running.
#
# Exit status: 0 when every check passed, 1 when one failed, 2 when it could not be set up.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd -P)
# shellcheck disable=SC2034  # read by headless.sh
HEADLESS_NAME=mockup-entry-selftest.sh
# shellcheck source=headless.sh
source "$REPO/tests/headless.sh"
headless_setup

failures=0
check() {
    local verdict=$1 text=$2
    if [ "$verdict" = 0 ]; then echo "  PASS: $text"; else echo "  FAIL: $text"; failures=$((failures + 1)); fi
}

# Runs the entry on one mockup, answering each new MOCKUP-SHOT line with `ipc call mockup
# next` (and asking `name` at the first); sets log, status, name_answer
run_entry() {
    local case=$1 shots_answered=0 shots deadline=$((SECONDS + 30))
    shift
    log=$work/$case.log
    name_answer=""
    memory_cap_wrap quickshell
    headless_cap_unit=$MEMORY_CAP_UNIT
    "${MEMORY_CAP_PREFIX[@]}" "${isolated[@]}" "$@" WAYLAND_DISPLAY=wayland-0 QT_QPA_PLATFORM=wayland \
        "$SETPRIV" --no-new-privs timeout 30 "$LOCKTEST_QS" -p "$REPO/mockup.qml" > "$log" 2>&1 < /dev/null &
    quickshell_pid=$!
    while kill -0 "$quickshell_pid" 2> /dev/null && [ $SECONDS -lt $deadline ]; do
        shots=$(grep -c 'MOCKUP-SHOT ' "$log")
        if [ "$shots" -gt "$shots_answered" ]; then
            [ "$shots_answered" = 0 ] && name_answer=$("${isolated[@]}" WAYLAND_DISPLAY=wayland-0 "$LOCKTEST_QS" -p "$REPO/mockup.qml" ipc call mockup name 2> /dev/null)
            shots_answered=$shots
            "${isolated[@]}" WAYLAND_DISPLAY=wayland-0 "$LOCKTEST_QS" -p "$REPO/mockup.qml" ipc call mockup next > /dev/null 2>&1
        fi
        # A condition polled, not a fixed wait: the deadline above only guards a hang
        sleep 0.05
    done
    wait "$quickshell_pid"
    status=$?
    quickshell_pid=""
    memory_cap_hit "$headless_cap_unit" "$status" "$log" > /dev/null 2>&1
    headless_cap_unit=""
}

fixtures=(H2S_MOCKUP_BASE=tests/fixtures/mockups H2S_MOCKUP_SHOT=1)

echo "good: components/good"
run_entry good "${fixtures[@]}" H2S_MOCKUP=components/good
check "$([ "$status" = 0 ]; echo $?)" "exits 0 (was $status)"
shot_lines=$(grep -o 'MOCKUP-SHOT .*' "$log")
# The button at 20,20 in a 200x80 window: its size is the theme's, its place the mockup's
check "$(grep -q -E '^MOCKUP-SHOT 0 normal 20,20 [1-9][0-9]*x[1-9][0-9]*$' <<< "$shot_lines"; echo $?)" "scene 0 'normal' shot at the subject's bounds"
check "$(grep -q -E '^MOCKUP-SHOT 1 checked 20,20 [1-9][0-9]*x[1-9][0-9]*$' <<< "$shot_lines"; echo $?)" "scene 1 'checked' shot after next"
check "$([ "$(grep -c . <<< "$shot_lines")" = 2 ]; echo $?)" "two shot lines, one per scene"
check "$(grep -q 'MOCKUP-DONE' "$log"; echo $?)" "MOCKUP-DONE after the last scene"
check "$([ "$name_answer" = components/good ]; echo $?)" "ipc name answers components/good (was '$name_answer')"
check "$(! grep -q -E 'MOCKUP-ERROR|TypeError|ReferenceError|is not a type|module .* is not installed' "$log"; echo $?)" "no error: the qs.* imports resolve"
grep -q -E 'MOCKUP-ERROR|TypeError|ReferenceError' "$log" && sed 's/^/    /' "$log" | head -n 20

# Each: case | expected text in the MOCKUP-ERROR line | the variables
errors=(
    "bad name|H2S_MOCKUP is 'components/Bad_Name'|H2S_MOCKUP_SHOT=1 H2S_MOCKUP=components/Bad_Name"
    "no name|H2S_MOCKUP is ''|H2S_MOCKUP_SHOT=1"
    "unknown kind|H2S_MOCKUP is 'widgets/good'|H2S_MOCKUP_SHOT=1 H2S_MOCKUP=widgets/good"
    "path in the name|H2S_MOCKUP is 'components/../good'|H2S_MOCKUP_SHOT=1 H2S_MOCKUP=components/../good"
    "base not taken|H2S_MOCKUP_BASE is 'tests'|H2S_MOCKUP_SHOT=1 H2S_MOCKUP_BASE=tests H2S_MOCKUP=components/good"
    "missing file|components/no-such-mockup:|H2S_MOCKUP_SHOT=1 H2S_MOCKUP=components/no-such-mockup"
    "load error|NoSuchFixtureType|${fixtures[*]} H2S_MOCKUP=components/load-error"
    "repeated scene|scene name 'first' is repeated|${fixtures[*]} H2S_MOCKUP=components/repeated-scene"
    "empty scene|scene 1 has an empty name|${fixtures[*]} H2S_MOCKUP=components/empty-scene"
    "unknown first scene on screen|no scene 'nope'|H2S_MOCKUP_BASE=tests/fixtures/mockups H2S_MOCKUP=components/good H2S_MOCKUP_SCENE=nope"
)
for entry in "${errors[@]}"; do
    IFS='|' read -r case expected variables <<< "$entry"
    echo "$case"
    # shellcheck disable=SC2086  # the variables are words
    run_entry "${case// /-}" $variables
    check "$([ "$status" = 2 ]; echo $?)" "exits 2 (was $status)"
    check "$(grep 'MOCKUP-ERROR ' "$log" | grep -q -F -- "$expected"; echo $?)" "MOCKUP-ERROR names it: $expected"
    check "$(! grep -q -E 'MOCKUP-SHOT|MOCKUP-DONE' "$log"; echo $?)" "no shot, no MOCKUP-DONE"
    grep -q 'MOCKUP-ERROR ' "$log" || sed 's/^/    /' "$log" | head -n 10
done

echo
if [ "$failures" = 0 ]; then
    echo "mockup-entry-selftest.sh: every check passed"
    exit 0
fi
echo "mockup-entry-selftest.sh: $failures check(s) FAILED"
exit 1
