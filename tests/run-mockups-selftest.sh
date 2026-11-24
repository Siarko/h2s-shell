#!/usr/bin/env bash
# The mockups' headless runner (tests/run-mockups.sh), their root entry (mockup.qml) and its
# window (mockups/kit/MockupWindow.qml), on the fixture mockups in tests/fixtures/mockups/
# (H2S_MOCKUP_BASE).
#
# The entry, driven here as the runner drives it:
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
# The runner:
#   - --load-only passes good mockups and writes no shot; --shoot writes one PNG per scene,
#     of the subject's size, into H2S_MOCKUP_SHOTS; the effects fixture's effects are drawn
#     (the renderer draws MultiEffect and layer.effect), and each scene drawn twice in one
#     process is the same file;
#   - a load error, a repeated scene and a QML warning from the mockup's own file FAIL, the
#     others in the same run still PASS;
#   - with no name it runs every component and view fixture, never the planning one, which
#     runs when named; a name that is not <kind>/<name> or not a mockup runs nothing;
#   - a missing tool (grim) is a set-up error naming it, status 2, nothing run;
#   - two fresh runs of the effects fixture write the same files;
#   - a Quickshell whose OpenGL renderer is not llvmpipe is NOT RUN, and leaves no shot;
#   - a mockup with a Timer, a read of the clock and a literal duration FAILs;
#   - old shots go: of a mockup's runs the newest 20 and those younger than a day stay, and
#     over the size limit the oldest run goes, never this run's or one still going;
#   - --compare without a baseline is NOT RUN and keeps its shots; --approve with no run to
#     take does nothing (status 2); --approve writes the baseline (the PNGs, a manifest with
#     the environment and a checksummed line per scene); a fresh run then compares the same
#     (0 differing pixels: the drawing is deterministic across processes);
#   - a baseline one pixel off FAILs, naming the scene, "1 pixel differs" and its review
#     image (old | new | diff; diff.png red at that pixel), the other scene not named;
#   - a baseline PNG that is not the manifest's file, one over 300 KB, a manifest of more
#     than 30 scenes and the baselines together over 15 MB FAIL;
#   - a changed environment line is NOT RUN, "environment changed since the baseline",
#     naming the old and new value, and compares nothing;
#   - --approve refuses a run drawn with the software backend, and leaves the baseline;
#   - the theme's font not installed (a stand-in fc-match, with the system's tools) is NOT
#     RUN, naming the font.
#
#   tests/run-mockups-selftest.sh
#
# The entry's cases in the unit runners' isolation (tests/headless.sh): one private headless
# compositor for all of them, a private HOME and runtime dir, the memory cap; the runner's
# cases each start the runner, which makes its own. Nothing is left running.
#
# Exit status: 0 when every check passed, 1 when one failed, 2 when it could not be set up.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd -P)
# shellcheck disable=SC2034  # read by headless.sh
HEADLESS_NAME=run-mockups-selftest.sh
# The runner's tools, magick among them (the shots are read with it, the pinned one where
# there is nix)
# shellcheck disable=SC2034  # read by headless.sh
HEADLESS_NEED=mockups
# shellcheck source=headless.sh
source "$REPO/tests/headless.sh"

# The entries this script started, by case: ended with headless.sh's own clean-up
declare -A pids=() units=() logs=() statuses=()
# What a case writes into the tree itself (in-tree baselines, a stray file): removed at the end
tree_writes=()
selftest_cleanup() {
    trap '' INT TERM HUP
    local written
    for written in "${tree_writes[@]}"; do rm -rf -- "$written"; done
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

# ---- The runner ---------------------------------------------------------------------
# runner <case> [VAR=value…] -- <arguments…>: tests/run-mockups.sh on the fixtures, its
# shots in the case's own folder; output in out[case], status in runner_status[case]
declare -A out=() runner_status=()
runner() {
    local case=$1
    shift
    local variables=()
    while [ "$1" != -- ]; do variables+=("$1"); shift; done
    shift
    out[$case]=$work/runner-$case.out
    env H2S_MOCKUP_BASE=tests/fixtures/mockups H2S_MOCKUP_SHOTS="$work/shots-$case" LOCKTEST_QS="$LOCKTEST_QS" \
        "${variables[@]}" "$REPO/tests/run-mockups.sh" "$@" > "${out[$case]}" 2>&1 < /dev/null
    runner_status[$case]=$?
}
# verdict_of <case> <name>: the mockup's verdict word in the run's summary
verdict_of() {
    awk -v name="$2" '/^  (PASS|FAIL|NOT RUN) / {
        verdict = $1; mockup = $2
        if ($1 == "NOT") { verdict = "NOT RUN"; mockup = $3 }
        if (mockup == name) { print verdict; exit }
    }' "${out[$1]}"
}
show_on_failure() { [ "$failures" = "$1" ] || sed 's/^/    | /' "${out[$2]}" | tail -n 40; }
# run_of <case> <name>: the one run folder of the mockup's shots
run_of() { find "$work/shots-$1/fixtures/$2" -mindepth 1 -maxdepth 1 -type d 2> /dev/null | head -n 1; }

echo "runner: --load-only on good mockups"
before=$failures
runner load-only -- --load-only components/good components/effects
check "$([ "${runner_status[load-only]}" = 0 ]; echo $?)" "exits 0 (was ${runner_status[load-only]})"
check "$([ "$(verdict_of load-only components/good)" = PASS ]; echo $?)" "components/good PASS"
check "$([ "$(verdict_of load-only components/effects)" = PASS ]; echo $?)" "components/effects PASS"
check "$([ ! -e "$work/shots-load-only" ]; echo $?)" "no shot written"
check "$(grep -q '^renderer: llvmpipe$' "${out[load-only]}"; echo $?)" "says the renderer, llvmpipe"
show_on_failure "$before" load-only

echo "runner: --shoot"
before=$failures
runner shoot -- --shoot components/good components/effects
check "$([ "${runner_status[shoot]}" = 0 ]; echo $?)" "exits 0 (was ${runner_status[shoot]})"
good_run=$(run_of shoot components/good)
effects_run=$(run_of shoot components/effects)
check "$([ "$(cd "$good_run" 2> /dev/null && ls)" = "$(printf '00-normal.png\n01-checked.png\norigin.txt\nrun.txt')" ]; echo $?)" "components/good: 00-normal.png, 01-checked.png, origin.txt and run.txt"
check "$(grep -q -F "shots: $good_run" "${out[shoot]}"; echo $?)" "the verdict names the shots' folder"
# The button's size is the theme's: the shot is the subject's, not the window's 200x80
size=$("$LOCKTEST_MAGICK" identify -format '%wx%h' "$good_run/00-normal.png" 2> /dev/null)
check "$([[ "$size" =~ ^[1-9][0-9]*x[1-9][0-9]*$ ]] && [ "$size" != 200x80 ]; echo $?)" "the shot is cropped to the subject ($size)"
check "$(cmp -s "$good_run/00-normal.png" "$good_run/01-checked.png"; [ $? = 1 ]; echo $?)" "the two scenes differ"
check "$([ "$(find "$effects_run" -name '*.png' | wc -l)" = 8 ]; echo $?)" "components/effects: eight shots"
for scene in rounded-image shadow-blur layer-effect; do
    # Drawn: the effect's item is there, more than the background's one colour
    colours=$("$LOCKTEST_MAGICK" identify -format '%k' "$effects_run"/*-"$scene".png 2> /dev/null)
    check "$([ "${colours:-0}" -gt 1 ]; echo $?)" "the $scene effect is drawn ($colours colours)"
done
for scene in text rounded-image shadow-blur layer-effect; do
    check "$(cmp -s "$effects_run"/0[0-3]-"$scene".png "$effects_run"/0[4-7]-"$scene"-again.png; echo $?)" "$scene drawn twice in one process: the same file"
done
show_on_failure "$before" shoot

echo "runner: the same shots from another process"
before=$failures
runner shoot-again -- --shoot components/effects
again_run=$(run_of shoot-again components/effects)
same=0 compared=0
for file in "$effects_run"/*.png; do
    compared=$((compared + 1))
    cmp -s "$file" "$again_run/${file##*/}" && same=$((same + 1))
done
check "$([ "${runner_status[shoot-again]}" = 0 ] && [ "$compared" = 8 ] && [ "$same" = 8 ]; echo $?)" "two fresh runs of components/effects: the same eight files ($same of $compared)"
show_on_failure "$before" shoot-again

echo "runner: a renderer that is not llvmpipe"
before=$failures
# A Quickshell that takes another Gallium driver whatever it is given: the GL renderer it
# reports is not llvmpipe
mkdir -p "$work/other-gl"
printf '#!%s\nexport GALLIUM_DRIVER=softpipe\nexec %q "$@"\n' "$(type -P bash)" "$LOCKTEST_QS" > "$work/other-gl/qs"
chmod +x "$work/other-gl/qs"
# With the system's tools, a grim first on PATH that writes down that it was called: the
# renderer is checked before the first shot, so it never is (the pinned set has its own grim)
grim_noted=""
if [ "$LOCKTEST_TOOL_SOURCE" = system ]; then
    printf '#!%s\necho called >> %q\nexec %q "$@"\n' "$(type -P bash)" "$work/grim.calls" "$LOCKTEST_GRIM" > "$work/other-gl/grim"
    chmod +x "$work/other-gl/grim"
    grim_noted=1
fi
runner other-gl LOCKTEST_QS="$work/other-gl/qs" PATH="$work/other-gl:$PATH" H2S_TEST_TOOLS="$LOCKTEST_TOOL_SOURCE" -- --shoot components/good
check "$([ "${runner_status[other-gl]}" = 2 ]; echo $?)" "exits 2 (was ${runner_status[other-gl]})"
check "$([ "$(verdict_of other-gl components/good)" = "NOT RUN" ] && grep -q -F 'the renderer is not llvmpipe' "${out[other-gl]}"; echo $?)" "components/good NOT RUN: the renderer is not llvmpipe"
check "$([ -z "$(find "$work/shots-other-gl" -name '*.png' 2> /dev/null)" ]; echo $?)" "no shot is left of it"
[ -n "$grim_noted" ] && check "$([ ! -e "$work/grim.calls" ]; echo $?)" "no shot was taken: the renderer was checked first"
show_on_failure "$before" other-gl

echo "runner: a mockup that keeps time of its own"
before=$failures
runner clock -- --load-only components/clock
check "$([ "${runner_status[clock]}" = 1 ] && [ "$(verdict_of clock components/clock)" = FAIL ]; echo $?)" "components/clock FAIL"
check "$(grep -q -F "Mockup.qml has a Timer" "${out[clock]}" && grep -q -F "reads the clock" "${out[clock]}" && grep -q -F "a literal duration" "${out[clock]}"; echo $?)" "the Timer, the clock and the literal duration are named"
show_on_failure "$before" clock

echo "runner: what fails, beside what passes"
before=$failures
runner failing -- --load-only components/good components/load-error components/repeated-scene components/warning
check "$([ "${runner_status[failing]}" = 1 ]; echo $?)" "exits 1 (was ${runner_status[failing]})"
check "$([ "$(verdict_of failing components/good)" = PASS ]; echo $?)" "components/good PASS"
for name in load-error repeated-scene warning; do
    check "$([ "$(verdict_of failing components/$name)" = FAIL ]; echo $?)" "components/$name FAIL"
done
check "$(grep -q "MOCKUP-ERROR components/load-error: .*NoSuchFixtureType" "${out[failing]}"; echo $?)" "the load error is named"
check "$(grep -q "MOCKUP-ERROR components/repeated-scene: scene name 'first' is repeated" "${out[failing]}"; echo $?)" "the repeated scene is named"
check "$(grep -q "a line about the mockup's own files: .*warning/Mockup.qml.*Unable to assign" "${out[failing]}"; echo $?)" "the warning from the mockup's file is named"
show_on_failure "$before" failing

echo "runner: no name runs every component and view, never a planning mockup"
before=$failures
runner all -- --load-only
expected=$(cd "$REPO/tests/fixtures/mockups" && find components views -mindepth 2 -maxdepth 2 -name Mockup.qml -printf '%h\n' | LC_ALL=C sort)
ran=$(awk '/^  (PASS|FAIL) / { print $2 } /^  NOT RUN / { print $3 }' "${out[all]}" | LC_ALL=C sort)
check "$([ "$ran" = "$expected" ]; echo $?)" "ran each component and view fixture once ($(echo $ran))"
check "$(! grep -q 'planning/' <<< "$ran"; echo $?)" "no planning mockup"
runner planning -- --load-only planning/idea
check "$([ "${runner_status[planning]}" = 0 ] && [ "$(verdict_of planning planning/idea)" = PASS ]; echo $?)" "planning/idea runs when named (status ${runner_status[planning]})"
show_on_failure "$before" all

echo "runner: names that run nothing"
for entry in "Bad_Name|is not <kind>/<name>" "planning/../idea|is not <kind>/<name>" "components/no-such-mockup|no mockup components/no-such-mockup"; do
    IFS='|' read -r name expected <<< "$entry"
    runner bad-name -- --load-only components/good "$name"
    check "$([ "${runner_status[bad-name]}" = 2 ] && grep -q -F -- "$expected" "${out[bad-name]}" && ! grep -q -E '^  (PASS|FAIL)' "${out[bad-name]}"; echo $?)" "'$name': exit 2, '$expected', nothing run"
done
runner no-mode -- components/good
check "$([ "${runner_status[no-mode]}" = 2 ] && grep -q '^usage:' "${out[no-mode]}"; echo $?)" "no mode: the usage, exit 2"

echo "runner: a missing tool (grim)"
before=$failures
# Every program on PATH but grim, the system's tools taken
mkdir -p "$work/no-grim"
IFS=: read -r -a path_parts <<< "$PATH"
for part in "${path_parts[@]}"; do
    for program in "$part"/*; do
        name=${program##*/}
        [ "$name" != grim ] && [ -x "$program" ] && [ ! -e "$work/no-grim/$name" ] && ln -s "$program" "$work/no-grim/$name"
    done
done
runner no-grim PATH="$work/no-grim" H2S_TEST_TOOLS=system -- --shoot components/good
check "$([ "${runner_status[no-grim]}" = 2 ]; echo $?)" "exits 2 (was ${runner_status[no-grim]})"
check "$(grep -q -F "grim not found on PATH (the mockups' shots)" "${out[no-grim]}"; echo $?)" "names grim and its use"
check "$(! grep -q -E '^  (PASS|FAIL)' "${out[no-grim]}" && [ ! -e "$work/shots-no-grim" ]; echo $?)" "nothing run, no shot"
show_on_failure "$before" no-grim

echo "runner: old shots go"
before=$failures
shots=$work/shots-prune/fixtures
# 22 runs of components/good two days old, two younger than a day with older names, and a
# 2 MB run of components/effects older than all of them
for i in $(seq -w 1 22); do mkdir -p "$shots/components/good/20200101-0000$i-1"; touch "$shots/components/good/20200101-0000$i-1/00-normal.png"; done
touch -d '2 days ago' "$shots"/components/good/2020*
mkdir -p "$shots/components/good/20190101-000001-1" "$shots/components/good/20190101-000002-1" "$shots/components/effects/20180101-000000-1"
head -c 2097152 /dev/zero > "$shots/components/effects/20180101-000000-1/00-text.png"
# … and an older one still, of a run that is still going (its pid, in its name, is a live
# run-mockups.sh): it stays
bash -c 'exec -a run-mockups.sh sleep 60' &
live=$!
mkdir -p "$shots/components/effects/20170101-000000-$live"
touch "$shots/components/effects/20170101-000000-$live/00-text.png"
runner prune H2S_MOCKUP_SHOTS_LIMIT_MB=1 -- --shoot components/good
kill "$live" 2> /dev/null
wait "$live" 2> /dev/null
check "$([ "${runner_status[prune]}" = 0 ]; echo $?)" "exits 0 (was ${runner_status[prune]})"
kept=$(find "$shots/components/good" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort)
check "$([ "$(grep -c . <<< "$kept")" = 22 ]; echo $?)" "22 runs of components/good stay ($(grep -c . <<< "$kept"))"
check "$(grep -q -x '20200101-000004-1' <<< "$kept" && ! grep -q -x '20200101-000003-1' <<< "$kept"; echo $?)" "the three oldest of the two-day-old runs went, the 19 newer stayed"
check "$(grep -q -x '20190101-000001-1' <<< "$kept" && grep -q -x '20190101-000002-1' <<< "$kept"; echo $?)" "the runs younger than a day stayed"
this_run=$(sed -n 's|^  PASS *components/good .*; shots: \(.*\)$|\1|p' "${out[prune]}")
check "$([ -n "$this_run" ] && [ -s "$this_run/00-normal.png" ]; echo $?)" "this run's shots stayed ($this_run)"
check "$([ ! -e "$shots/components/effects/20180101-000000-1" ]; echo $?)" "over the size limit, the oldest run went"
check "$([ -e "$shots/components/effects/20170101-000000-$live" ]; echo $?)" "a run still going stayed, older though it is"
show_on_failure "$before" prune

echo "runner: --compare and --approve"
before=$failures
compare_vars=(H2S_MOCKUP_SHOTS="$work/shots-compare" H2S_MOCKUP_BASELINES="$work/baselines")
baseline=$work/baselines/components/good/baseline
# shots_named <case>: the run folder the verdict names
shots_named() { sed -n 's|^.*shots: \([^);]*\).*$|\1|p' "${out[$1]}" | head -n 1; }
# set_baseline_png <file> <scene line's number and name>: the file becomes that scene's
# baseline PNG, with its checksum in the manifest (a baseline approved so)
set_baseline_png() {
    local sum
    cp -- "$1" "$baseline/$2.png"
    sum=$(sha256sum < "$baseline/$2.png")
    sed -i "s/^\(scene ${2%%-*} ${2#*-} [0-9x]* \).*\$/\1${sum%% *}/" "$baseline/manifest.txt"
}

runner approve-none "${compare_vars[@]}" -- --approve components/good
check "$([ "${runner_status[approve-none]}" = 2 ] && grep -q '^NOT DONE components/good — no run of it from this tree' "${out[approve-none]}" && [ ! -e "$baseline" ]; echo $?)" "--approve with no run: status 2, nothing written (was ${runner_status[approve-none]})"

runner compare-none "${compare_vars[@]}" -- --compare components/good
check "$([ "${runner_status[compare-none]}" = 2 ] && [ "$(verdict_of compare-none components/good)" = "NOT RUN" ] && grep -q -F "no baseline ($baseline/manifest.txt)" "${out[compare-none]}"; echo $?)" "--compare without a baseline: NOT RUN, 'no baseline' (status ${runner_status[compare-none]})"
first_run=$(shots_named compare-none)
check "$([ -s "$first_run/00-normal.png" ] && [ -s "$first_run/run.txt" ]; echo $?)" "its shots and run.txt are kept ($first_run)"

check "$(grep -q -x "tree $REPO" "$first_run/origin.txt" && grep -q -E '^commit [0-9a-f]{40}$' "$first_run/origin.txt" \
    && grep -q -E '^changes [0-9a-f]{64}$' "$first_run/origin.txt" && grep -q -E '^mockup [0-9a-f]{64}$' "$first_run/origin.txt"; echo $?)" "origin.txt names the tree, its commit, its uncommitted changes and the mockup's file"

# approve_refuses <case> <text>: --approve refuses, saying the text, and writes no baseline
approve_refuses() {
    runner "$1" "${compare_vars[@]}" -- --approve components/good
    check "$([ "${runner_status[$1]}" = 1 ] && grep -q -F -- "$2" "${out[$1]}" && [ ! -e "$baseline" ]; echo $?)" "--approve refuses: $2 (status ${runner_status[$1]})"
}
cp "$first_run/origin.txt" "$work/origin-saved.txt"
sed -i "s|^tree .*|tree /elsewhere/h2s-shell|" "$first_run/origin.txt"
approve_refuses approve-other-tree "it was made from another tree (/elsewhere/h2s-shell)"
cp "$work/origin-saved.txt" "$first_run/origin.txt"
sed -i "s|^commit .*|commit 0000000000000000000000000000000000000000|" "$first_run/origin.txt"
approve_refuses approve-other-commit "it was made at commit 0000000000000000000000000000000000000000"
cp "$work/origin-saved.txt" "$first_run/origin.txt"
sed -i "s|^changes .*|changes 0000000000000000000000000000000000000000000000000000000000000000|" "$first_run/origin.txt"
approve_refuses approve-other-changes "this tree's uncommitted changes are not the ones it was made with"
cp "$work/origin-saved.txt" "$first_run/origin.txt"
sed -i "s|^mockup .*|mockup 0000000000000000000000000000000000000000000000000000000000000000|" "$first_run/origin.txt"
approve_refuses approve-other-mockup "its Mockup.qml is not the current one"
cp "$work/origin-saved.txt" "$first_run/origin.txt"
mv "$first_run/run.txt" "$work/run-saved.txt"
approve_refuses approve-no-record "did not pass (no run.txt)"
mv "$work/run-saved.txt" "$first_run/run.txt"
# A newer run that was NOT RUN (its renderer) and left no shots: never an older run instead
runner other-gl-newer "${compare_vars[@]}" LOCKTEST_QS="$work/other-gl/qs" H2S_TEST_TOOLS="$LOCKTEST_TOOL_SOURCE" -- --shoot components/good
approve_refuses approve-newer-not-run "left no shots"
runner shoot-again-good "${compare_vars[@]}" -- --shoot components/good
first_run=$(shots_named shoot-again-good)

# An old baseline's PNG the new one does not have goes
mkdir -p "$baseline"
touch "$baseline/05-gone.png"
runner approve "${compare_vars[@]}" -- --approve components/good
manifest=$baseline/manifest.txt
check "$([ "${runner_status[approve]}" = 0 ] && grep -q -F "APPROVED components/good — 2 scenes from $first_run" "${out[approve]}"; echo $?)" "--approve takes the newest run (status ${runner_status[approve]})"
check "$([ "$(cd "$baseline" 2> /dev/null && ls | paste -s -d ' ')" = "00-normal.png 01-checked.png manifest.txt" ]; echo $?)" "the baseline: two PNGs and manifest.txt"
check "$(cmp -s "$first_run/01-checked.png" "$baseline/01-checked.png"; echo $?)" "the PNGs are the run's"
check "$(grep -q -E '^environment renderer OpenGL VENDOR: .*RENDERER: llvmpipe \(LLVM [^,]+, [0-9]+ bits\)' "$manifest" \
    && grep -q -x 'environment backend llvmpipe' "$manifest" && grep -q -E '^environment quickshell .*[0-9]+\.[0-9]+' "$manifest" \
    && grep -q -E '^environment qt-core [0-9a-f]{64} /.*/libQt6Core\.so' "$manifest" && grep -q -E '^environment qt-gui [0-9a-f]{64} /.*/libQt6Gui\.so' "$manifest" \
    && grep -q -E '^environment qt-quick [0-9a-f]{64} /.*/libQt6Quick\.so' "$manifest" && grep -q -E '^environment qt-svg ' "$manifest" \
    && grep -q -E '^environment freetype [0-9a-f]{64} /.*/libfreetype\.so' "$manifest" \
    && grep -q -E '^environment fontconfig [0-9a-f]{64} /.*/libfontconfig\.so' "$manifest" && grep -q -E '^environment harfbuzz ' "$manifest" \
    && grep -q -E '^environment font:JetBrainsMono-Nerd-Font [0-9a-f]{64} /' "$manifest" && grep -q -E '^environment font:JetBrainsMono-Nerd-Font:bold [0-9a-f]{64} /' "$manifest" \
    && grep -q -E '^environment font:sans-serif [0-9a-f]{64} /' "$manifest" && grep -q -E '^environment font:monospace [0-9a-f]{64} /' "$manifest" \
    && grep -q -E '^environment font:emoji [0-9a-f]{64} /' "$manifest" \
    && grep -q -E '^environment font-rendering hinting=[^ ]+ hintstyle=[^ ]* antialias=[^ ]+ rgba=[^ ]* lcdfilter=[^ ]*' "$manifest"; echo $?)" "the manifest's environment: renderer line with the vector width, backend, quickshell, Qt Core/Gui/Quick/Svg, freetype, fontconfig, harfbuzz (by checksum), the fonts' checksums, fontconfig's rendering settings"
normal_sum=$(sha256sum < "$baseline/00-normal.png")
check "$(grep -q -x -E "scene 00 normal [0-9]+x[0-9]+ ${normal_sum%% *}" "$manifest" && grep -q -E '^scene 01 checked [0-9]+x[0-9]+ [0-9a-f]{64}$' "$manifest"; echo $?)" "a scene line per scene, with its size and checksum"
show_on_failure "$before" approve
cp -a "$baseline" "$work/baseline-approved"

before=$failures
runner compare-same "${compare_vars[@]}" -- --compare components/good
check "$([ "${runner_status[compare-same]}" = 0 ] && grep -q '^  PASS     components/good (2 scenes, the same as the baseline' "${out[compare-same]}"; echo $?)" "a fresh run compares the same: PASS, 0 differing pixels (status ${runner_status[compare-same]})"
show_on_failure "$before" compare-same

before=$failures
"$LOCKTEST_MAGICK" "$baseline/01-checked.png" -fill red -draw 'point 5,5' "$work/checked-one-pixel.png"
set_baseline_png "$work/checked-one-pixel.png" 01-checked
runner compare-pixel "${compare_vars[@]}" -- --compare components/good
pixel_run=$(shots_named compare-pixel)
check "$([ "${runner_status[compare-pixel]}" = 1 ] && [ "$(verdict_of compare-pixel components/good)" = FAIL ]; echo $?)" "a baseline one pixel off: FAIL (status ${runner_status[compare-pixel]})"
check "$(grep -q -F "scene 'checked': 1 pixel differs; review: $pixel_run/01-checked-review.png" "${out[compare-pixel]}"; echo $?)" "names the scene, '1 pixel differs' and the review image"
check "$(! grep -q "scene 'normal'" "${out[compare-pixel]}"; echo $?)" "the unchanged scene is not named"
check "$([ -s "$pixel_run/01-checked-review.png" ] && cmp -s "$pixel_run/01-checked/old.png" "$baseline/01-checked.png" \
    && cmp -s "$pixel_run/01-checked/new.png" "$pixel_run/01-checked.png" && [ -s "$pixel_run/01-checked/diff.png" ] && [ ! -e "$pixel_run/00-normal" ]; echo $?)" "old.png, new.png, diff.png and the review image written, for that scene only"
check "$([ "$("$LOCKTEST_MAGICK" "$pixel_run/01-checked/diff.png" -format '%[pixel:p{5,5}]' info: 2> /dev/null)" = "srgb(255,0,0)" ] \
    && [ "$("$LOCKTEST_MAGICK" "$pixel_run/01-checked/diff.png" -format '%[pixel:p{6,5}]' info: 2> /dev/null)" != "srgb(255,0,0)" ]; echo $?)" "diff.png is red at the pixel, and only there"
shot_width=$("$LOCKTEST_MAGICK" identify -format '%w' "$pixel_run/01-checked.png" 2> /dev/null)
review_width=$("$LOCKTEST_MAGICK" identify -format '%w' "$pixel_run/01-checked-review.png" 2> /dev/null)
check "$([ "${review_width:-0}" -ge $((3 * ${shot_width:-1})) ]; echo $?)" "the review image is old | new | diff side by side ($review_width px for a $shot_width px shot)"
show_on_failure "$before" compare-pixel

before=$failures
rm -rf "$baseline" && cp -a "$work/baseline-approved" "$baseline"
"$LOCKTEST_MAGICK" "$baseline/00-normal.png" -fill red -draw 'point 1,1' "$baseline/00-normal.png"
runner compare-tampered "${compare_vars[@]}" -- --compare components/good
check "$([ "${runner_status[compare-tampered]}" = 1 ] && grep -q -F "baseline/00-normal.png is not the approved file" "${out[compare-tampered]}"; echo $?)" "a baseline PNG that is not the manifest's file: FAIL (status ${runner_status[compare-tampered]})"
show_on_failure "$before" compare-tampered

before=$failures
rm -rf "$baseline" && cp -a "$work/baseline-approved" "$baseline"
"$LOCKTEST_MAGICK" -size 400x400 xc: +noise Random "$work/noise.png"
set_baseline_png "$work/noise.png" 00-normal
runner compare-oversize "${compare_vars[@]}" -- --compare components/good
check "$([ "${runner_status[compare-oversize]}" = 1 ] && grep -q -E "baseline/00-normal.png is [0-9]+ KB, over the limit of 300 KB" "${out[compare-oversize]}"; echo $?)" "a baseline PNG over 300 KB: FAIL (status ${runner_status[compare-oversize]})"
show_on_failure "$before" compare-oversize

before=$failures
rm -rf "$baseline" && cp -a "$work/baseline-approved" "$baseline"
for i in $(seq 2 30); do echo "scene $i extra-$i 1x1 0000000000000000000000000000000000000000000000000000000000000000" >> "$baseline/manifest.txt"; done
runner compare-scenes "${compare_vars[@]}" -- --compare components/good
check "$([ "${runner_status[compare-scenes]}" = 1 ] && grep -q -F "the baseline has 31 scenes, over the limit of 30" "${out[compare-scenes]}"; echo $?)" "a baseline of 31 scenes: FAIL (status ${runner_status[compare-scenes]})"
show_on_failure "$before" compare-scenes

before=$failures
rm -rf "$baseline" && cp -a "$work/baseline-approved" "$baseline"
mkdir -p "$work/baselines/components/large/baseline"
truncate -s 16M "$work/baselines/components/large/baseline/00-large.png"
runner compare-total "${compare_vars[@]}" -- --compare components/good
rm -rf "$work/baselines/components/large"
check "$([ "${runner_status[compare-total]}" = 1 ] && [ "$(verdict_of compare-total components/good)" = PASS ] \
    && grep -q -F "the baselines in $work/baselines: 16 MB together, over the limit of 15 MB" "${out[compare-total]}"; echo $?)" "the baselines together over 15 MB: the run FAILs (status ${runner_status[compare-total]})"
show_on_failure "$before" compare-total

before=$failures
qt_line=$(grep '^environment qt-core ' "$baseline/manifest.txt")
sed -i 's|^environment qt-core .*$|environment qt-core /usr/lib/libQt6Core.so.6.0.0|' "$baseline/manifest.txt"
runner compare-environment "${compare_vars[@]}" -- --compare components/good
check "$([ "${runner_status[compare-environment]}" = 2 ] && [ "$(verdict_of compare-environment components/good)" = "NOT RUN" ]; echo $?)" "a changed environment: NOT RUN, not FAIL (status ${runner_status[compare-environment]})"
check "$(grep -q -F "environment changed since the baseline: qt-core: /usr/lib/libQt6Core.so.6.0.0 → ${qt_line#environment qt-core }" "${out[compare-environment]}"; echo $?)" "names what changed, from and to"
environment_run=$(shots_named compare-environment)
check "$(! grep -q 'differ' "${out[compare-environment]}" && [ -s "$environment_run/00-normal.png" ] && [ ! -e "$environment_run/00-normal" ]; echo $?)" "compares nothing, keeps the shots"
show_on_failure "$before" compare-environment

before=$failures
"$LOCKTEST_MAGICK" "$baseline/00-normal.png" -fill red -draw 'point 1,1' "$baseline/00-normal.png"
runner compare-environment-tampered "${compare_vars[@]}" -- --compare components/good
check "$([ "${runner_status[compare-environment-tampered]}" = 1 ] && grep -q -F "baseline/00-normal.png is not the approved file" "${out[compare-environment-tampered]}"; echo $?)" "a tampered baseline FAILs even when the environment changed too (status ${runner_status[compare-environment-tampered]})"
show_on_failure "$before" compare-environment-tampered

# A scene whose size changed, with no pixel of the shot different: the baseline one transparent
# column wider
before=$failures
rm -rf "$baseline" && cp -a "$work/baseline-approved" "$baseline"
normal_size=$("$LOCKTEST_MAGICK" identify -format '%wx%h' "$baseline/00-normal.png")
wider=$(( ${normal_size%x*} + 1 ))x${normal_size#*x}
"$LOCKTEST_MAGICK" "$baseline/00-normal.png" -alpha set -background none -gravity West -extent "$wider" "$work/wider.png"
set_baseline_png "$work/wider.png" 00-normal
sed -i "s/^scene 00 normal $normal_size /scene 00 normal $wider /" "$baseline/manifest.txt"
runner compare-size "${compare_vars[@]}" -- --compare components/good
check "$([ "${runner_status[compare-size]}" = 1 ] && grep -q -F "scene 'normal': 0 pixels differ (the size was $wider, is $normal_size)" "${out[compare-size]}"; echo $?)" "a scene whose size changed FAILs with no pixel different (status ${runner_status[compare-size]})"
show_on_failure "$before" compare-size

# Scenes renamed, added and removed
# scenes_case <case> <expected baseline names>: the scene lists named
scenes_case() {
    runner "$1" "${compare_vars[@]}" -- --compare components/good
    check "$([ "${runner_status[$1]}" = 1 ] && grep -q -F "the scenes are not the baseline's: baseline '$2', now 'normal checked'" "${out[$1]}"; echo $?)" "$1: FAIL, the scene lists named (status ${runner_status[$1]})"
    show_on_failure "$before" "$1"
}
before=$failures
rm -rf "$baseline" && cp -a "$work/baseline-approved" "$baseline"
mv "$baseline/01-checked.png" "$baseline/01-pressed.png"
sed -i 's/^scene 01 checked /scene 01 pressed /' "$baseline/manifest.txt"
scenes_case scene-renamed "normal pressed"
rm -rf "$baseline" && cp -a "$work/baseline-approved" "$baseline"
cp "$baseline/01-checked.png" "$baseline/02-extra.png"
echo "$(grep '^scene 01 ' "$baseline/manifest.txt" | sed 's/^scene 01 checked /scene 02 extra /')" >> "$baseline/manifest.txt"
scenes_case scene-removed-since "normal checked extra"
rm -rf "$baseline" && cp -a "$work/baseline-approved" "$baseline"
rm "$baseline/01-checked.png"
sed -i '/^scene 01 /d' "$baseline/manifest.txt"
scenes_case scene-added-since "normal"

before=$failures
rm -rf "$baseline" && cp -a "$work/baseline-approved" "$baseline"
runner software-shoot "${compare_vars[@]}" H2S_MOCKUP_RENDERER=software -- --shoot components/good
runner approve-software "${compare_vars[@]}" -- --approve components/good
check "$([ "${runner_status[software-shoot]}" = 0 ] && [ "${runner_status[approve-software]}" = 1 ] && grep -q -F "it was not drawn with llvmpipe (software)" "${out[approve-software]}"; echo $?)" "--approve refuses a run drawn with the software backend (status ${runner_status[approve-software]})"
check "$(cmp -s "$baseline/manifest.txt" "$work/baseline-approved/manifest.txt"; echo $?)" "and leaves the baseline as it was"
show_on_failure "$before" approve-software

# Two mockups approved in one call, into the tree's own baselines: the first one's new
# baseline is not an uncommitted change that refuses the second
before=$failures
in_tree_good=$REPO/tests/fixtures/mockups/components/good/baseline
in_tree_effects=$REPO/tests/fixtures/mockups/components/effects/baseline
if [ -e "$in_tree_good" ] || [ -e "$in_tree_effects" ]; then
    check 1 "the fixtures good and effects have no baseline in the tree, for this case to write and remove"
else
    tree_writes+=("$in_tree_good" "$in_tree_effects")
    runner in-tree-shoot H2S_MOCKUP_SHOTS="$work/shots-in-tree" -- --shoot components/good components/effects
    runner in-tree-approve H2S_MOCKUP_SHOTS="$work/shots-in-tree" -- --approve components/good components/effects
    check "$([ "${runner_status[in-tree-shoot]}" = 0 ] && [ "${runner_status[in-tree-approve]}" = 0 ] \
        && grep -q '^APPROVED components/good ' "${out[in-tree-approve]}" && grep -q '^APPROVED components/effects ' "${out[in-tree-approve]}" \
        && [ -s "$in_tree_good/manifest.txt" ] && [ -s "$in_tree_effects/manifest.txt" ]; echo $?)" "--approve of two mockups into the tree's baselines approves both (status ${runner_status[in-tree-approve]})"
    show_on_failure "$before" in-tree-approve
    rm -rf -- "$in_tree_good" "$in_tree_effects"
fi

# The tree changed while a mockup ran (a Quickshell that writes a file into the tree as it
# starts the mockup): its shots are not labelled with the tree as it was before
before=$failures
stray=$REPO/tests/fixtures/mockups/components/good/stray-$$.txt
tree_writes+=("$stray")
mkdir -p "$work/tree-writer"
printf '#!%s\n[ "${1:-}" = -p ] && echo "$$" >> %q\nexec %q "$@"\n' "$(type -P bash)" "$stray" "$LOCKTEST_QS" > "$work/tree-writer/qs"
chmod +x "$work/tree-writer/qs"
runner tree-changed "${compare_vars[@]}" H2S_MOCKUP_SHOTS="$work/shots-tree-changed" LOCKTEST_QS="$work/tree-writer/qs" H2S_TEST_TOOLS="$LOCKTEST_TOOL_SOURCE" -- --shoot components/good
check "$([ "${runner_status[tree-changed]}" = 2 ] && [ "$(verdict_of tree-changed components/good)" = "NOT RUN" ] \
    && grep -q -F "the tree changed while it ran" "${out[tree-changed]}"; echo $?)" "the tree changed while the mockup ran: NOT RUN (status ${runner_status[tree-changed]})"
rm -f -- "$stray"
runner tree-changed-approve "${compare_vars[@]}" H2S_MOCKUP_SHOTS="$work/shots-tree-changed" -- --approve components/good
check "$([ "${runner_status[tree-changed-approve]}" = 1 ]; echo $?)" "and that run cannot be approved (status ${runner_status[tree-changed-approve]})"
show_on_failure "$before" tree-changed

# A Quickshell that names no version: what drew the scenes cannot be told
before=$failures
mkdir -p "$work/mute-qs"
printf '#!%s\n[ "${1:-}" = --version ] && exit 0\nexec %q "$@"\n' "$(type -P bash)" "$LOCKTEST_QS" > "$work/mute-qs/qs"
chmod +x "$work/mute-qs/qs"
runner mute-qs "${compare_vars[@]}" LOCKTEST_QS="$work/mute-qs/qs" H2S_TEST_TOOLS="$LOCKTEST_TOOL_SOURCE" -- --compare components/good
check "$([ "${runner_status[mute-qs]}" = 2 ] && [ "$(verdict_of mute-qs components/good)" = "NOT RUN" ] && grep -q -F "Quickshell names no version" "${out[mute-qs]}"; echo $?)" "a Quickshell that names no version: NOT RUN (status ${runner_status[mute-qs]})"
show_on_failure "$before" mute-qs

# With the system's tools: an fc-match first on PATH that gives another font for every family
if [ "$LOCKTEST_TOOL_SOURCE" = system ]; then
    before=$failures
    mkdir -p "$work/no-theme-font"
    touch "$work/other-font.ttf"
    printf '#!%s\necho "Other Sans|%s"\n' "$(type -P bash)" "$work/other-font.ttf" > "$work/no-theme-font/fc-match"
    chmod +x "$work/no-theme-font/fc-match"
    runner no-theme-font "${compare_vars[@]}" PATH="$work/no-theme-font:$PATH" H2S_TEST_TOOLS=system -- --compare components/good
    check "$([ "${runner_status[no-theme-font]}" = 2 ] && [ "$(verdict_of no-theme-font components/good)" = "NOT RUN" ] \
        && grep -q -F "the theme's font 'JetBrainsMono Nerd Font' is not installed (fontconfig gives 'Other Sans'" "${out[no-theme-font]}"; echo $?)" "the theme's font missing: NOT RUN, the font named (status ${runner_status[no-theme-font]})"
    show_on_failure "$before" no-theme-font
fi

echo
if [ "$failures" = 0 ]; then
    echo "run-mockups-selftest.sh: every check passed"
    exit 0
fi
echo "run-mockups-selftest.sh: $failures check(s) FAILED"
exit 1
