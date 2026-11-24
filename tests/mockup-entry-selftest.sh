#!/usr/bin/env bash
# The mockups' root entry (mockup.qml) and its window (mockups/kit/MockupWindow.qml), headless
# on the fixture mockups in tests/fixtures/mockups/ (H2S_MOCKUP_BASE):
#
#   - a good mockup loads with its qs.* imports, prints one MOCKUP-SHOT line per scene with
#     the subject's bounds, steps on `ipc call mockup next`, answers `ipc call mockup name`,
#     and ends with MOCKUP-DONE and exit 0; also with the tree reached through a symbolic
#     link, and two at once on one display, each stepped by its instance id;
#   - on screen (no H2S_MOCKUP_SHOT), H2S_MOCKUP_SCENE opens that scene;
#   - a view that reaches the module host, the notification server, Notifier and the helper,
#     started with H2S_SHELL_MODULES and H2S_SHELL_HELPER set, loads no module, registers no
#     server, sends nothing and has no helper;
#   - a bad name, a base it does not take, a missing file, a load error, a root that is not
#     a MockupWindow, a repeated and an empty scene name, an unknown first scene, and shots
#     that take longer than their limit each end with MOCKUP-ERROR and exit 2.
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

# The entries this script started, by case: ended with headless.sh's own clean-up
declare -A pids=() units=() logs=() statuses=()
selftest_cleanup() {
    trap '' INT TERM HUP
    local case
    for case in "${!pids[@]}"; do
        kill -TERM "${pids[$case]}" 2> /dev/null
    done
    for case in "${!pids[@]}"; do
        wait "${pids[$case]}" 2> /dev/null
        memory_cap_hit "${units[$case]}" 1 > /dev/null 2>&1
    done
    headless_cleanup
}
trap selftest_cleanup EXIT

headless_setup

failures=0
check() {
    local verdict=$1 text=$2
    if [ "$verdict" = 0 ]; then echo "  PASS: $text"; else echo "  FAIL: $text"; failures=$((failures + 1)); fi
}

# start_entry <case> <root file> [VAR=value…]: the entry started in the background
start_entry() {
    local case=$1 root=$2
    shift 2
    logs[$case]=$work/$case.log
    : > "${logs[$case]}"
    memory_cap_wrap quickshell
    units[$case]=$MEMORY_CAP_UNIT
    "${MEMORY_CAP_PREFIX[@]}" "${isolated[@]}" "$@" WAYLAND_DISPLAY=wayland-0 QT_QPA_PLATFORM=wayland \
        "$SETPRIV" --no-new-privs timeout 30 "$LOCKTEST_QS" -p "$root" > "${logs[$case]}" 2>&1 < /dev/null &
    pids[$case]=$!
}

# The instance id of a case's Quickshell, from its log ("" until it says it)
instance_of() {
    sed -n 's|.*/by-id/\([a-z0-9]*\)/log\.qslog.*|\1|p' "${logs[$1]}" | head -n 1
}

ipc() {
    local id=$1
    shift
    "${isolated[@]}" WAYLAND_DISPLAY=wayland-0 "$LOCKTEST_QS" ipc --id "$id" "$@" 2> /dev/null
}

# finish_entry <case>: waited for; statuses[case] set
finish_entry() {
    local case=$1
    wait "${pids[$case]}"
    statuses[$case]=$?
    memory_cap_hit "${units[$case]}" "${statuses[$case]}" "${logs[$case]}" > /dev/null 2>&1
    unset "pids[$case]"
}

# drive <answer: yes|no> <case>…: each new MOCKUP-SHOT line of each case answered with
# `ipc call mockup next` addressed to its instance (with `yes`), its name asked at its first
# shot (names[case]); until all have ended (a 30 s deadline guards a hang)
declare -A names=()
drive() {
    local answer=$1 case shots id deadline=$((SECONDS + 30)) alive
    shift
    declare -A answered=()
    for case in "$@"; do answered[$case]=0; names[$case]=""; done
    while [ $SECONDS -lt $deadline ]; do
        alive=0
        for case in "$@"; do
            kill -0 "${pids[$case]}" 2> /dev/null || continue
            alive=1
            shots=$(grep -c 'MOCKUP-SHOT ' "${logs[$case]}")
            [ "$shots" -gt "${answered[$case]}" ] || continue
            id=$(instance_of "$case")
            [ -n "$id" ] || continue
            [ "${answered[$case]}" = 0 ] && names[$case]=$(ipc "$id" call mockup name)
            answered[$case]=$shots
            [ "$answer" = yes ] && ipc "$id" call mockup next > /dev/null
        done
        [ "$alive" = 1 ] || break
        # A condition polled, not a fixed wait: the deadline above only guards a hang
        sleep 0.05
    done
    for case in "$@"; do finish_entry "$case"; done
}

fixtures=(H2S_MOCKUP_BASE=tests/fixtures/mockups H2S_MOCKUP_SHOT=1)

# check_good <case> <expected name>: the good fixture's two shots, done, its name
check_good() {
    local case=$1 log=${logs[$1]} shot_lines
    check "$([ "${statuses[$case]}" = 0 ]; echo $?)" "exits 0 (was ${statuses[$case]})"
    shot_lines=$(grep -o 'MOCKUP-SHOT .*' "$log")
    # The button at 20,20 in a 200x80 window: its size is the theme's, its place the mockup's
    check "$(grep -q -E '^MOCKUP-SHOT 0 normal 20,20 [1-9][0-9]*x[1-9][0-9]*$' <<< "$shot_lines"; echo $?)" "scene 0 'normal' shot at the subject's bounds"
    check "$(grep -q -E '^MOCKUP-SHOT 1 checked 20,20 [1-9][0-9]*x[1-9][0-9]*$' <<< "$shot_lines"; echo $?)" "scene 1 'checked' shot after next"
    check "$([ "$(grep -c . <<< "$shot_lines")" = 2 ]; echo $?)" "two shot lines, one per scene"
    check "$(grep -q 'MOCKUP-DONE' "$log"; echo $?)" "MOCKUP-DONE after the last scene"
    check "$([ "${names[$case]}" = components/good ]; echo $?)" "ipc name answers components/good (was '${names[$case]}')"
    check "$(! grep -q -E 'MOCKUP-ERROR|TypeError|ReferenceError|is not a type|module .* is not installed' "$log"; echo $?)" "no error: the qs.* imports resolve"
    grep -q -E 'MOCKUP-ERROR|TypeError|ReferenceError' "$log" && sed 's/^/    /' "$log" | head -n 20
}

echo "good: components/good"
start_entry good "$REPO/mockup.qml" "${fixtures[@]}" H2S_MOCKUP=components/good
drive yes good
check_good good

echo "the tree through a symbolic link"
ln -s "$REPO" "$work/tree-link"
start_entry link "$work/tree-link/mockup.qml" "${fixtures[@]}" H2S_MOCKUP=components/good
drive yes link
check_good link

echo "two at once on one display, each stepped by its instance id"
start_entry first "$REPO/mockup.qml" "${fixtures[@]}" H2S_MOCKUP=components/good
start_entry second "$REPO/mockup.qml" "${fixtures[@]}" H2S_MOCKUP=components/good
drive yes first second
check_good first
check_good second

echo "on screen: H2S_MOCKUP_SCENE opens that scene"
start_entry scene "$REPO/mockup.qml" H2S_MOCKUP_BASE=tests/fixtures/mockups H2S_MOCKUP=components/good H2S_MOCKUP_SCENE=checked
scene_answer=""
deadline=$((SECONDS + 30))
while [ $SECONDS -lt $deadline ] && kill -0 "${pids[scene]}" 2> /dev/null; do
    id=$(instance_of scene)
    [ -n "$id" ] && scene_answer=$(ipc "$id" call mockup scene)
    [ -n "$scene_answer" ] && break
    # A condition polled (the instance answering), not a fixed wait
    sleep 0.05
done
kill -TERM "${pids[scene]}" 2> /dev/null
finish_entry scene
check "$([ "$scene_answer" = checked ]; echo $?)" "ipc scene answers checked (was '$scene_answer')"
check "$(! grep -q -E 'MOCKUP-SHOT|MOCKUP-ERROR|TypeError|ReferenceError' "${logs[scene]}"; echo $?)" "no shot, no error"

echo "isolation: a view that reaches modules, notifications and the helper"
start_entry isolation "$REPO/mockup.qml" "${fixtures[@]}" H2S_MOCKUP=views/isolation \
    H2S_SHELL_MODULES="$REPO/tests/fixtures/modules/good" H2S_SHELL_HELPER=/nonexistent/h2s-helper
drive yes isolation
facts=$(grep -o 'MOCKUP-FACTS .*' "${logs[isolation]}")
check "$([ "${statuses[isolation]}" = 0 ]; echo $?)" "exits 0 (was ${statuses[isolation]})"
check "$(grep -q -F 'modules=0 ' <<< "$facts"; echo $?)" "no module directory taken from H2S_SHELL_MODULES ($facts)"
check "$(grep -q -F 'testMode=true ' <<< "$facts"; echo $?)" "the module host in module test mode"
# Quickshell's own word when a NotificationServer tries the session bus (there is none here)
check "$(! grep -q 'quickshell.service.notifications' "${logs[isolation]}"; echo $?)" "no notification server tried the session bus"
check "$(grep -q -F 'recorded=1 ' <<< "$facts"; echo $?)" "Notifier recorded the notification instead of sending it"
check "$(grep -q -F "helper=''" <<< "$facts"; echo $?)" "no helper taken from H2S_SHELL_HELPER"
check "$(! grep -q -E 'MOCKUP-ERROR|TypeError|ReferenceError' "${logs[isolation]}"; echo $?)" "no error"
grep -q -E 'MOCKUP-ERROR|TypeError|ReferenceError' "${logs[isolation]}" && sed 's/^/    /' "${logs[isolation]}" | head -n 20

echo "shots longer than their limit"
start_entry limit "$REPO/mockup.qml" "${fixtures[@]}" H2S_MOCKUP=components/good H2S_MOCKUP_SHOT_LIMIT_MS=1500
drive no limit
check "$([ "${statuses[limit]}" = 2 ]; echo $?)" "exits 2 (was ${statuses[limit]})"
check "$(grep 'MOCKUP-ERROR ' "${logs[limit]}" | grep -q -F "longer than 1500 ms (at scene 0 'normal', waiting for next)"; echo $?)" "MOCKUP-ERROR names the limit, the scene and what it waited for"
check "$(! grep -q 'MOCKUP-DONE' "${logs[limit]}"; echo $?)" "no MOCKUP-DONE"

# Each: case | expected text in the MOCKUP-ERROR line | the variables
errors=(
    "bad name|H2S_MOCKUP is 'components/Bad_Name'|H2S_MOCKUP_SHOT=1 H2S_MOCKUP=components/Bad_Name"
    "no name|H2S_MOCKUP is ''|H2S_MOCKUP_SHOT=1"
    "unknown kind|H2S_MOCKUP is 'widgets/good'|H2S_MOCKUP_SHOT=1 H2S_MOCKUP=widgets/good"
    "path in the name|H2S_MOCKUP is 'components/../good'|H2S_MOCKUP_SHOT=1 H2S_MOCKUP=components/../good"
    "base not taken|H2S_MOCKUP_BASE is 'tests'|H2S_MOCKUP_SHOT=1 H2S_MOCKUP_BASE=tests H2S_MOCKUP=components/good"
    "missing file|components/no-such-mockup:|H2S_MOCKUP_SHOT=1 H2S_MOCKUP=components/no-such-mockup"
    "load error|NoSuchFixtureType|${fixtures[*]} H2S_MOCKUP=components/load-error"
    "not a MockupWindow|is not a MockupWindow|${fixtures[*]} H2S_MOCKUP=components/not-a-window"
    "repeated scene|scene name 'first' is repeated|${fixtures[*]} H2S_MOCKUP=components/repeated-scene"
    "empty scene|scene 1 has an empty name|${fixtures[*]} H2S_MOCKUP=components/empty-scene"
    "unknown first scene on screen|no scene 'nope'|H2S_MOCKUP_BASE=tests/fixtures/mockups H2S_MOCKUP=components/good H2S_MOCKUP_SCENE=nope"
    "bad shot limit|H2S_MOCKUP_SHOT_LIMIT_MS is 'soon'|${fixtures[*]} H2S_MOCKUP=components/good H2S_MOCKUP_SHOT_LIMIT_MS=soon"
)
for entry in "${errors[@]}"; do
    IFS='|' read -r name expected variables <<< "$entry"
    case=${name// /-}
    echo "$name"
    # shellcheck disable=SC2086  # the variables are words
    start_entry "$case" "$REPO/mockup.qml" $variables
    drive yes "$case"
    log=${logs[$case]}
    check "$([ "${statuses[$case]}" = 2 ]; echo $?)" "exits 2 (was ${statuses[$case]})"
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
