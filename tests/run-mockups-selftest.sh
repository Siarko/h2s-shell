#!/usr/bin/env bash
# The mockups' headless runner (tests/run-mockups.sh), their root entry (mockup.qml) and its
# window (mockups/kit/MockupWindow.qml), on the fixture mockups in tests/fixtures/mockups/
# (H2S_MOCKUP_BASE).
#
# The entry, driven here as the runner drives it:
#   - a good mockup loads with its qs.* imports, prints one MOCKUP-SHOT line per state with
#     the subject's bounds, steps on `ipc call mockup next`, answers `ipc call mockup name`,
#     and ends with MOCKUP-DONE and exit 0; also with the tree reached through a symbolic
#     link, and two at once on one display, each stepped by its instance id; its window is
#     the layer-shell panel (`ipc call mockup window`);
#   - on screen (no H2S_MOCKUP_SHOT), H2S_MOCKUP_STATE opens a component on that state, in a
#     floating window (a normal toplevel, never the panel), with every state's button inside
#     it and that state's checked; H2S_MOCKUP_SCENE a plan on that scene, also for a plan
#     taller than the screen, whose own item reaches above its content; on screen the
#     content never scrolls by a drag (a drag is the mockup's), only by the wheel and a
#     vertical scroll bar shown while it does not fit; a real wheel (the lock bed's virtual
#     pointer, tests/lock/input/ltinput.py) scrolls a component's, a plan's and the gallery's
#     window by 48 px a notch, a plan's sideways by a horizontal wheel and by Shift, and a
#     touchpad's stroke (its virtual two-finger swipe) by its pixels; and the shell's own:
#     the event form's colour row (a fixture plan), sideways only by Shift or a sideways
#     stroke, no plain WheelHandler in the tree but components/WheelScroll.qml;
#   - with state cells (the kit's StateGrid): shot in their grid, each cropped to its cell; on
#     screen with no state named, every state's cell shown, none overlapping, labelled with its
#     name and about.txt's description in order, a pointer state saying how to see it, no
#     state current and no buttons, and at rest using next to no processor time (the
#     fixture, and each component and view mockup);
#     H2S_MOCKUP_STATE one cell alone, labelled, current; a plan has no cells, its scene
#     buttons each with its scene's description as tooltip;
#   - a plan on a scene that holds a list open (plans/open-list), switched to another scene:
#     a click on that scene's button lands (the hidden scene's list leaves no press catcher);
#     and with a real pointer (plans/held-list), in a scene holding a list open, a press on
#     another scene's button switches scenes (the kit's buttons lie above every overlay), the
#     scene's own button brings the list back, a press outside closes it;
#   - `ipc call mockup theme <name>` on screen shows it in that theme and answers the name;
#   - the gallery (H2S_MOCKUP=gallery, on mockups/), in the built-in theme and opened in a
#     fixture theme (tests/fixtures/mockup-themes/, H2S_MOCKUP_THEME): a section per
#     component and view on disk, in order, the last one not built before it is reached, each
#     built once jumped to and at the top of the view then, in all its states
#     labelled from about.txt, no error or warning, at rest using next to no processor time;
#     the filter keeps only matching sections; the theme switched over IPC to default and
#     back, an unknown one refused with the list;
#   - on screen, the window closed through the compositor (as by its close button) ends the
#     process with status 0: a component's, a plan's and the gallery's;
#   - a view that reaches the module host, the notification server, Notifier and the helper,
#     started with H2S_SHELL_MODULES and H2S_SHELL_HELPER set, loads no module, registers no
#     server, sends nothing and has no helper;
#   - a bad name, a base it does not take, a missing file, a load error, a root that is not
#     a MockupWindow, each broken form of about.txt (missing, no description, the other
#     kind's keyword, a bad, a repeated, an empty or an undescribed name, too long), a Mockup.qml still
#     setting names, an unknown first state, the old
#     planning/ folder, H2S_MOCKUP_SCENE for a component and H2S_MOCKUP_STATE for a plan, a
#     mockup still setting the kit's old `scenes`, a theme while shooting (the baselines are
#     the built-in theme's), the gallery while shooting or with a state, and shots that take
#     longer than their limit each end with MOCKUP-ERROR and exit 2.
#
# The runner:
#   - --load-only passes good mockups and writes no shot; --shoot writes one PNG per state,
#     of the subject's size, into H2S_MOCKUP_SHOTS; the effects fixture's effects are drawn
#     (the renderer draws MultiEffect and layer.effect), and each state drawn twice in one
#     process is the same file;
#   - H2S_MOCKUP_CHECK=1 checks a plan and a component without a window: MOCKUP-CHECKED
#     with the count, exit 0; also a plan whose scenes are named constructor, toString and
#     hasOwnProperty (a plain object's own names, never taken as repeated);
#   - a load error, a repeated state, a missing about.txt, names set in Mockup.qml and a QML
#     warning from the mockup's own file FAIL, the others in the same run still PASS;
#   - with no name it runs every component and view fixture, and --load-only checks every
#     plan without a window (a broken plan's about.txt FAILs); a plan steps through its
#     scenes when named, and --compare or --approve of a plan is refused (plans have no
#     baseline); a name that is not <kind>/<name>, under planning/ (with the move to make)
#     or not a mockup runs nothing;
#   - --by-system takes --compare on Arch and --load-only on NixOS and any other system,
#     saying which (made-up systems' os-release), and runs nothing (status 2) on a system
#     that cannot be told; with no component or view mockup in the
#     tree it says nothing to run, status 0, where --load-only is status 2;
#   - a missing tool (grim) is a set-up error naming it, status 2, nothing run;
#   - two fresh runs of the effects fixture write the same files;
#   - a Quickshell whose OpenGL renderer is not llvmpipe is NOT RUN, and leaves no shot;
#   - a mockup with a Timer, a read of the clock and a literal duration FAILs;
#   - old shots go: of a mockup's runs the newest 20 and those younger than a day stay, and
#     over the size limit the oldest run goes, never this run's or one still going;
#   - --compare without a baseline is NOT RUN and keeps its shots; --approve with no run to
#     take does nothing (status 2); --approve writes the baseline (the PNGs, a manifest with
#     the environment and a checksummed state line per state); a fresh run then compares the same
#     (0 differing pixels: the drawing is deterministic across processes);
#   - a baseline one pixel off FAILs, naming the state, "1 pixel differs" and its review
#     image (old | new | diff; diff.png red at that pixel), the other state not named;
#   - a baseline PNG that is not the manifest's file, one over 300 KB, a manifest of more
#     than 30 states, a manifest still saying scene and the baselines together over 15 MB
#     FAIL;
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
# The lock bed's virtual pointer and keyboard too: a real wheel on the window
# shellcheck disable=SC2034  # read by resolve.sh
LOCKTEST_INPUT=1
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
    [ -n "${input_pid:-}" ] && { kill -TERM "$input_pid" 2> /dev/null; wait "$input_pid" 2> /dev/null; }
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
# shot (names[case]), and its window (windows[case]); until all have ended (a 30 s deadline
# guards a hang)
declare -A names=() windows=()
drive() {
    local answer=$1 case shots id deadline=$((SECONDS + 30)) alive
    shift
    declare -A answered=()
    for case in "$@"; do answered[$case]=0; names[$case]=""; windows[$case]=""; done
    while [ $SECONDS -lt $deadline ]; do
        alive=0
        for case in "$@"; do
            kill -0 "${pids[$case]}" 2> /dev/null || continue
            alive=1
            shots=$(grep -c 'MOCKUP-SHOT ' "${logs[$case]}")
            [ "$shots" -gt "${answered[$case]}" ] || continue
            id=$(instance_of "$case")
            [ -n "$id" ] || continue
            if [ "${answered[$case]}" = 0 ]; then
                names[$case]=$(ipc "$id" call mockup name)
                windows[$case]=$(ipc "$id" call mockup window)
            fi
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
    check "$(grep -q -E '^MOCKUP-SHOT 0 normal 20,20 [1-9][0-9]*x[1-9][0-9]*$' <<< "$shot_lines"; echo $?)" "state 0 'normal' shot at the subject's bounds"
    check "$(grep -q -E '^MOCKUP-SHOT 1 checked 20,20 [1-9][0-9]*x[1-9][0-9]*$' <<< "$shot_lines"; echo $?)" "state 1 'checked' shot after next"
    check "$([ "$(grep -c . <<< "$shot_lines")" = 2 ]; echo $?)" "two shot lines, one per state"
    check "$(grep -q 'MOCKUP-DONE' "$log"; echo $?)" "MOCKUP-DONE after the last state"
    check "$([ "${names[$case]}" = components/good ]; echo $?)" "ipc name answers components/good (was '${names[$case]}')"
    check "$([ "${windows[$case]}" = panel ]; echo $?)" "shot in the layer-shell panel (ipc window was '${windows[$case]}')"
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

# on_screen <case> <mockup> <state or scene>: started on screen on it (H2S_MOCKUP_SCENE for a
# plan, H2S_MOCKUP_STATE otherwise); current_answer, window_answer and buttons_answer what it
# answers over IPC once it has started, and scroller_answer
on_screen() {
    local case=$1 id deadline=$((SECONDS + 30)) variable=H2S_MOCKUP_STATE
    [[ "$2" == plans/* ]] && variable=H2S_MOCKUP_SCENE
    start_entry "$case" "$REPO/mockup.qml" H2S_MOCKUP_BASE=tests/fixtures/mockups H2S_MOCKUP="$2" "$variable=$3"
    current_answer="" window_answer="" buttons_answer="" scroller_answer="" theme_answer=""
    while [ $SECONDS -lt $deadline ] && kill -0 "${pids[$case]}" 2> /dev/null; do
        id=$(instance_of "$case")
        [ -n "$id" ] && current_answer=$(ipc "$id" call mockup current)
        if [ -n "$current_answer" ]; then
            window_answer=$(ipc "$id" call mockup window)
            buttons_answer=$(ipc "$id" call mockup buttons)
            scroller_answer=$(ipc "$id" call mockup scroller)
            theme_answer=$(ipc "$id" call mockup theme default)
            break
        fi
        # A condition polled (the instance answering), not a fixed wait
        sleep 0.05
    done
    kill -TERM "${pids[$case]}" 2> /dev/null
    finish_entry "$case"
}

echo "on screen: H2S_MOCKUP_STATE opens a component on that state, in a floating window"
on_screen state components/good checked
check "$([ "$current_answer" = checked ]; echo $?)" "ipc current answers checked (was '$current_answer')"
check "$([ "$window_answer" = floating ]; echo $?)" "a floating window, not the panel (ipc window was '$window_answer')"
check "$([ "$buttons_answer" = "2 of 2 shown, checked checked" ]; echo $?)" "both state buttons inside the window, 'checked' checked (was '$buttons_answer')"
check "$([ "$scroller_answer" = "wheel, vertical bar hidden" ]; echo $?)" "content that fits: no drag-scrolling, no scroll bar (was '$scroller_answer')"
check "$([ "$theme_answer" = default ]; echo $?)" "ipc theme default: shown in it, the name answered (was '$theme_answer')"
check "$(! grep -q -E 'MOCKUP-SHOT|MOCKUP-ERROR|TypeError|ReferenceError' "${logs[state]}"; echo $?)" "no shot, no error"

echo "on screen: H2S_MOCKUP_SCENE opens a plan taller than the screen on that scene, its buttons in the window"
on_screen tall plans/tall second
check "$([ "$current_answer" = second ]; echo $?)" "ipc current answers second (was '$current_answer')"
check "$([ "$window_answer" = floating ]; echo $?)" "a floating window (ipc window was '$window_answer')"
check "$([ "$buttons_answer" = "3 of 3 shown, checked second" ]; echo $?)" "the three scene buttons inside the window, 'second' checked (was '$buttons_answer')"
check "$([ "$scroller_answer" = "wheel, vertical bar shown" ]; echo $?)" "content taller than the window: scrolled by the wheel and a shown scroll bar, never by a drag (was '$scroller_answer')"
check "$(! grep -q -E 'MOCKUP-ERROR|TypeError|ReferenceError' "${logs[tall]}"; echo $?)" "no error"

# The Quickshell process under a case's background job (the memory cap's wrapper, then
# timeout, each with the entry on its command line): the deepest process of the job's tree
# whose command line names mockup.qml (Quickshell's executable is a wrapper on NixOS, so its
# path tells nothing)
quickshell_pid() {
    local pid=$1 child found=""
    for child in $(pgrep -P "$pid"); do
        found=$(quickshell_pid "$child")
        [ -n "$found" ] && break
        if tr '\0' ' ' < "/proc/$child/cmdline" 2> /dev/null | grep -q -F 'mockup.qml'; then found=$child; break; fi
    done
    echo "$found"
}

# cpu_ticks <pid>: the processor time it has used, in clock ticks (user and system)
cpu_ticks() {
    awk '{ sub(/^.*\) /, ""); print $12 + $13 }' "/proc/$1/stat" 2> /dev/null
}

# on_screen_cells <case> <base> <mockup> [<state or scene>]: started on screen (all its
# states when none is named); once its window is made, cells_answer, current_answer,
# buttons_answer and tooltips_answer what it answers over IPC, and idle_ticks the processor
# time it used over the next two seconds, at rest; with grab_state and grab_file set, that
# state's cell saved into the file as drawn
grab_state="" grab_file=""
on_screen_cells() {
    local case=$1 base=$2 mockup=$3 first=${4:-} id deadline=$((SECONDS + 30)) made="" variable=H2S_MOCKUP_STATE
    [[ "$mockup" == plans/* ]] && variable=H2S_MOCKUP_SCENE
    local extra=()
    [ -n "$first" ] && extra=("$variable=$first")
    start_entry "$case" "$REPO/mockup.qml" H2S_MOCKUP_BASE="$base" H2S_MOCKUP="$mockup" "${extra[@]}"
    cells_answer="" current_answer="" buttons_answer="" tooltips_answer="" idle_ticks=""
    local qs_pid before
    while [ $SECONDS -lt $deadline ] && kill -0 "${pids[$case]}" 2> /dev/null; do
        id=$(instance_of "$case")
        [ -n "$id" ] && made=$(ipc "$id" call mockup window)
        if [ -n "$made" ]; then
            cells_answer=$(ipc "$id" call mockup cells)
            current_answer=$(ipc "$id" call mockup current)
            buttons_answer=$(ipc "$id" call mockup buttons)
            tooltips_answer=$(ipc "$id" call mockup tooltips)
            # A window at rest uses next to no processor time; items fighting over the
            # keyboard keep a core busy. Measured over an interval, which is what this
            # check is about: a fixed wait, not a wait for a condition
            qs_pid=$(quickshell_pid "${pids[$case]}")
            if [ -n "$qs_pid" ]; then
                before=$(cpu_ticks "$qs_pid")
                sleep 2
                idle_ticks=$(( $(cpu_ticks "$qs_pid") - before ))
            fi
            if [ -n "$grab_state" ] && [ -z "$(ipc "$id" call mockup grab "$grab_state" "$grab_file")" ]; then
                # The file written once the grab is done, a condition polled
                while [ $SECONDS -lt $deadline ] && [ ! -s "$grab_file" ]; do sleep 0.05; done
            fi
            break
        fi
        # A condition polled (the window made), not a fixed wait
        sleep 0.05
    done
    kill -TERM "${pids[$case]}" 2> /dev/null
    finish_entry "$case"
}

echo "state cells: shot in a grid of two a row, each shot cropped to its cell"
start_entry cells-shot "$REPO/mockup.qml" "${fixtures[@]}" H2S_MOCKUP=components/cells
drive yes cells-shot
check "$([ "$(grep -o 'MOCKUP-SHOT .*' "${logs[cells-shot]}")" = "$(printf 'MOCKUP-SHOT 0 rest 0,0 120x60\nMOCKUP-SHOT 1 checked 120,0 120x60\nMOCKUP-SHOT 2 hover 0,60 120x60')" ]; echo $?)" "rest, checked, hover at their cells, in about.txt's order"
check "$(! grep -q -E 'MOCKUP-ERROR|TypeError|ReferenceError' "${logs[cells-shot]}"; echo $?)" "no error"

echo "on screen: a component with state cells opens in all its states, each labelled from about.txt"
on_screen_cells cells-all tests/fixtures/mockups components/cells
expected_cells=$(printf '%s\n' "3 of 3 shown, none overlapping" "rest — The button at rest" "checked — The button checked" \
    "hover — The pointer over the button (point at it, or open cells/hover)")
check "$([ "$cells_answer" = "$expected_cells" ]; echo $?)" "every state shown, in order, labelled with its name and description, the pointer state saying how to see it (was '$cells_answer')"
check "$([ -z "$current_answer" ]; echo $?)" "no state current: the simulated pointer lights none (was '$current_answer')"
check "$([ "$buttons_answer" = "0 of 3 shown, checked " ]; echo $?)" "no state buttons (was '$buttons_answer')"
check "$(! grep -q -E 'MOCKUP-SHOT|MOCKUP-ERROR|TypeError|ReferenceError' "${logs[cells-all]}"; echo $?)" "no shot, no error"
check "$([ -n "$idle_ticks" ] && [ "$idle_ticks" -lt 50 ]; echo $?)" "at rest: under 50 ticks of processor time in 2 s (was '$idle_ticks')"

echo "on screen: H2S_MOCKUP_STATE opens one state of a component with state cells, labelled"
on_screen_cells cells-one tests/fixtures/mockups components/cells hover
check "$([ "$cells_answer" = "$(printf '%s\n' "1 of 3 shown, none overlapping" "hover — The pointer over the button")" ]; echo $?)" "only hover's cell, labelled, without the all-states note (was '$cells_answer')"
check "$([ "$current_answer" = hover ]; echo $?)" "hover current: its simulated pointer placed (was '$current_answer')"
check "$(! grep -q -E 'MOCKUP-ERROR|TypeError|ReferenceError' "${logs[cells-one]}"; echo $?)" "no error"

echo "on screen: a plan keeps its scene buttons, each with its scene's description as tooltip"
on_screen_cells plan-tips tests/fixtures/mockups plans/tall
check "$([ "$cells_answer" = "no cells: a plan, its scene buttons" ]; echo $?)" "no cells (was '$cells_answer')"
check "$([ "$buttons_answer" = "3 of 3 shown, checked first" ]; echo $?)" "its three buttons, the first scene checked (was '$buttons_answer')"
check "$([ "$tooltips_answer" = "$(printf '%s\n' "first: The first scene" "second: The second scene" "third: The third scene")" ]; echo $?)" "each button's tooltip its scene's description (was '$tooltips_answer')"

echo "on screen: a scene with a list held open, then another scene: its clicks still land"
start_entry open-list "$REPO/mockup.qml" H2S_MOCKUP_BASE=tests/fixtures/mockups H2S_MOCKUP=plans/open-list H2S_MOCKUP_SCENE=open
click_answer="" deadline=$((SECONDS + 30))
while [ $SECONDS -lt $deadline ] && kill -0 "${pids[open-list]}" 2> /dev/null; do
    id=$(instance_of open-list)
    if [ -n "$id" ] && [ "$(ipc "$id" call mockup window)" = floating ] && [ "$(ipc "$id" call probe scene button)" = button ]; then
        # The button shown, a condition polled
        while [ $SECONDS -lt $deadline ]; do
            click_answer=$(ipc "$id" call probe click)
            [ "$click_answer" != hidden ] && break
            sleep 0.05
        done
        break
    fi
    # A condition polled (the window made), not a fixed wait
    sleep 0.05
done
kill -TERM "${pids[open-list]}" 2> /dev/null
finish_entry open-list
check "$([ "$click_answer" = "clicks 1" ]; echo $?)" "the hidden scene's list and its press catcher are gone: the click reaches the button (was '$click_answer')"
check "$(! grep -q -E 'MOCKUP-ERROR|TypeError|ReferenceError' "${logs[open-list]}"; echo $?)" "no error"

echo "on screen: a cell among all the states drawn as when its state opens alone"
grab_state=on grab_file=$work/toggle-all-on.png
on_screen_cells toggle-all mockups components/toggle-switch
grab_file=$work/toggle-one-on.png
on_screen_cells toggle-one mockups components/toggle-switch on
grab_state="" grab_file=""
differing=$("$LOCKTEST_MAGICK" compare -metric AE "$work/toggle-all-on.png" "$work/toggle-one-on.png" null: 2>&1 | cut -d ' ' -f 1)
check "$([ -s "$work/toggle-all-on.png" ] && [ -s "$work/toggle-one-on.png" ] && [ "$differing" = 0 ]; echo $?)" "toggle-switch's 'on' cell: the same pixels in both, never a disabled look ($differing differing)"

echo "on screen: the mockups in all their states"
for entry in components/pill:6 components/small-button:24 components/status-pill:5 components/toggle-switch:4 views/nixos-page:16 views/settings-modal:10; do
    mockup=${entry%%:*} count=${entry#*:}
    on_screen_cells "all-${mockup#*/}" mockups "$mockup"
    labels=$(tail -n +2 <<< "$cells_answer" | sed 's/ — .*//')
    declared=$(source "$REPO/tests/mockup-about.sh" && about_read "$REPO/mockups/$mockup" state > /dev/null && printf '%s\n' "${about_names[@]}")
    check "$([ "$(head -n 1 <<< "$cells_answer")" = "$count of $count shown, none overlapping" ] && [ "$labels" = "$declared" ]; echo $?)" "$mockup: every state labelled, in about.txt's order, none overlapping (was '$(head -n 1 <<< "$cells_answer")')"
    check "$(! grep -q -E 'MOCKUP-ERROR|TypeError|ReferenceError|Binding loop' "${logs[all-${mockup#*/}]}"; echo $?)" "$mockup: no error"
    check "$([ -n "$idle_ticks" ] && [ "$idle_ticks" -lt 50 ]; echo $?)" "$mockup: at rest, nothing fighting over the keyboard: under 50 ticks of processor time in 2 s (was '$idle_ticks')"
done

# gallery_run <case> [VAR=value…]: the gallery started on screen on mockups/; once its
# sections are listed each is jumped to in turn and waited for (built or failed):
# sections_answer then, cells_of[<section>] each one's cells, idle_ticks the processor time
# it used over the next two seconds at rest, and theme_answers what `ipc call mockup theme`
# answered to "", contrast, "", default, "", nope (a line each)
declare -A cells_of=() top_of=()
gallery_run() {
    local case=$1 id="" deadline=$((SECONDS + 60)) sections="" section qs_pid before
    shift
    start_entry "$case" "$REPO/mockup.qml" H2S_MOCKUP=gallery "$@"
    sections_answer="" idle_ticks="" theme_answers="" filter_answer="" far_before=""
    cells_of=() top_of=()
    while [ $SECONDS -lt $deadline ] && kill -0 "${pids[$case]}" 2> /dev/null; do
        id=$(instance_of "$case")
        [ -n "$id" ] && [ "$(ipc "$id" call mockup window)" = floating ] && sections=$(ipc "$id" call mockup sections)
        [ -n "$sections" ] && break
        # A condition polled (the folders listed), not a fixed wait
        sleep 0.05
    done
    if [ -n "$sections" ]; then
        # The first section built where it stands, a condition polled; the last one, far below,
        # not built before it is reached
        local first last
        first=$(head -n 1 <<< "$sections" | awk '{ print $1 }') last=$(tail -n 1 <<< "$sections" | awk '{ print $1 }')
        while [ $SECONDS -lt $deadline ] && ! ipc "$id" call mockup sections | grep -q -x -F "$first built"; do sleep 0.05; done
        far_before=$(ipc "$id" call mockup sections | grep -F "$last ")
        # The last first: the placeholders above it grow as they are built under the view
        for section in "$last" $(awk '{ print $1 }' <<< "$sections" | grep -v -x -F "$last"); do
            ipc "$id" call mockup jump "$section" > /dev/null
            # Built (or failed) once jumped to, a condition polled
            while [ $SECONDS -lt $deadline ] && ipc "$id" call mockup sections | grep -q -x -F "$section waiting"; do sleep 0.05; done
            # At the top of the view once the sections above it have grown, a condition polled
            while [ $SECONDS -lt $deadline ] && [ "$(ipc "$id" call mockup top)" != "$section" ]; do sleep 0.05; done
            top_of[$section]=$(ipc "$id" call mockup top)
            cells_of[$section]=$(ipc "$id" call mockup cells "$section")
        done
        sections_answer=$(ipc "$id" call mockup sections)
        # Measured over an interval, which is what this check is about: a fixed wait
        qs_pid=$(quickshell_pid "${pids[$case]}")
        if [ -n "$qs_pid" ]; then
            before=$(cpu_ticks "$qs_pid")
            sleep 2
            idle_ticks=$(( $(cpu_ticks "$qs_pid") - before ))
        fi
        filter_answer=$(ipc "$id" call mockup filter "pointer over the large")
        ipc "$id" call mockup filter "" > /dev/null
        theme_answers=$(for name in "" contrast "" default "" nope; do ipc "$id" call mockup theme "$name"; done)
    fi
    kill -TERM "${pids[$case]}" 2> /dev/null
    finish_entry "$case"
}

# The elements on disk, as the gallery lists them, and each one's states from about.txt
elements_on_disk=$(cd "$REPO/mockups" && for folder in components/*/ views/*/; do echo "${folder%/}"; done)
theme_config=$work/theme-config
mkdir -p "$theme_config/h2s_shell/themes"
echo '{}' > "$theme_config/h2s_shell/config.json"
cp "$REPO/tests/fixtures/mockup-themes/contrast.json" "$theme_config/h2s_shell/themes/"

for run in built-in contrast; do
    if [ "$run" = built-in ]; then
        echo "the gallery: every component and view in all its states, in the built-in theme"
        gallery_run gallery-$run XDG_CONFIG_HOME="$theme_config"
    else
        echo "the gallery opened in a theme file (H2S_MOCKUP_THEME), switched over IPC"
        gallery_run gallery-$run XDG_CONFIG_HOME="$theme_config" H2S_MOCKUP_THEME=contrast
    fi
    check "$([ "$(awk '{ print $1 }' <<< "$sections_answer")" = "$elements_on_disk" ]; echo $?)" "$run: a section per component and view on disk, components first, each alphabetical (was '$(awk '{ print $1 }' <<< "$sections_answer" | paste -s -d ' ')')"
    check "$([ "$far_before" = "views/settings-modal waiting" ]; echo $?)" "$run: before any jump the last section, far below the view, is not built (was '$far_before')"
    check "$([ -n "$sections_answer" ] && ! grep -q -v ' built$' <<< "$sections_answer"; echo $?)" "$run: every section built once jumped to ($(grep -v ' built$' <<< "$sections_answer" | paste -s -d ';'))"
    tops=$(for element in $elements_on_disk; do [ "${top_of[$element]:-}" = "$element" ] || echo "$element:${top_of[$element]:-}"; done)
    check "$([ -z "$tops" ]; echo $?)" "$run: each section jumped to at the top of the view, the sections above it grown ($tops)"
    for element in $elements_on_disk; do
        declared=$(source "$REPO/tests/mockup-about.sh" && about_read "$REPO/mockups/$element" state > /dev/null && printf '%s\n' "${about_names[@]}")
        count=$(grep -c . <<< "$declared")
        labels=$(tail -n +2 <<< "${cells_of[$element]:-}" | sed 's/ — .*//')
        check "$([ "$(head -n 1 <<< "${cells_of[$element]:-}")" = "$count of $count shown, none overlapping" ] && [ "$labels" = "$declared" ]; echo $?)" "$run: $element in all its states, labelled from about.txt in its order (was '$(head -n 1 <<< "${cells_of[$element]:-}")')"
    done
    check "$(! grep -q -E 'MOCKUP-ERROR|TypeError|ReferenceError|Binding loop|qml.*(Unable|Cannot)|\[Theme\]|file://' "${logs[gallery-$run]}"; echo $?)" "$run: no error or warning"
    grep -E 'MOCKUP-ERROR|TypeError|ReferenceError|Binding loop|\[Theme\]|file://' "${logs[gallery-$run]}" | head -n 5 | sed 's/^/    | /'
    check "$([ -n "$idle_ticks" ] && [ "$idle_ticks" -lt 50 ]; echo $?)" "$run: every section built, at rest: under 50 ticks of processor time in 2 s (was '$idle_ticks')"
done
echo "the gallery on the fixtures: sections built only as they come near, a jump kept at the top while those above grow"
start_entry gallery-lazy "$REPO/mockup.qml" H2S_MOCKUP=gallery H2S_MOCKUP_BASE=tests/fixtures/mockups XDG_CONFIG_HOME="$theme_config"
lazy_id="" lazy_sections="" lazy_before="" lazy_after="" lazy_top="" deadline=$((SECONDS + 60))
while [ $SECONDS -lt $deadline ] && kill -0 "${pids[gallery-lazy]}" 2> /dev/null; do
    lazy_id=$(instance_of gallery-lazy)
    [ -n "$lazy_id" ] && lazy_sections=$(ipc "$lazy_id" call mockup sections)
    # The folders listed and the first section built or failed where it stands, a condition polled
    [ -n "$lazy_sections" ] && ! head -n 1 <<< "$lazy_sections" | grep -q ' waiting$' && break
    sleep 0.05
done
if [ -n "$lazy_sections" ]; then
    lazy_before=$(ipc "$lazy_id" call mockup sections)
    ipc "$lazy_id" call mockup jump views/long-c > /dev/null
    # The section above it built (it grows by some 2000 px), a condition polled
    while [ $SECONDS -lt $deadline ] && ipc "$lazy_id" call mockup sections | grep -q -x -E 'views/long-[bc] waiting'; do sleep 0.05; done
    lazy_after=$(ipc "$lazy_id" call mockup sections)
    # Placed again once the column is laid out: polled, five seconds guarding a hang
    top_deadline=$((SECONDS + 5))
    while [ $SECONDS -lt $top_deadline ] && [ "$(ipc "$lazy_id" call mockup top)" != views/long-c ]; do sleep 0.05; done
    lazy_top=$(ipc "$lazy_id" call mockup top)
fi
kill -TERM "${pids[gallery-lazy]}" 2> /dev/null
finish_entry gallery-lazy
check "$(grep -q -x 'views/long-b waiting' <<< "$lazy_before" && grep -q -x 'views/long-c waiting' <<< "$lazy_before"; echo $?)" "before any jump the tall sections far below are not built ($(grep long- <<< "$lazy_before" | paste -s -d ';'))"
check "$(grep -q -x 'views/long-b built' <<< "$lazy_after" && grep -q -x 'views/long-c built' <<< "$lazy_after"; echo $?)" "jumped to views/long-c: it and the section above it built ($(grep long- <<< "$lazy_after" | paste -s -d ';'))"
check "$([ "$lazy_top" = views/long-c ]; echo $?)" "views/long-c stays at the top of the view while views/long-b above it grows (top was '$lazy_top')"
check "$(grep -q '^components/load-error failed: .*NoSuchFixtureType' <<< "$lazy_before" && grep -q '^components/no-about failed: about.txt is missing' <<< "$lazy_before"; echo $?)" "a mockup that does not load and a missing about.txt: their sections say why"
check "$(! grep -q -E 'MOCKUP-ERROR|TypeError|ReferenceError|Binding loop' "${logs[gallery-lazy]}"; echo $?)" "no error"
check "$([ "$filter_answer" = components/pill ]; echo $?)" "the filter: only the section whose state holds every word (was '$filter_answer')"
expected_themes=$(printf '%s\n' contrast contrast contrast default default "no theme 'nope'; the themes: default, contrast")
check "$([ "$theme_answers" = "$expected_themes" ]; echo $?)" "opened in contrast; theme switches to default and back, asks, refuses an unknown one with the list (was '$(paste -s -d '|' <<< "$theme_answers")')"

# ---- A real wheel ---------------------------------------------------------------------
# The lock bed's virtual pointer and keyboard (tests/lock/input/ltinput.py) on the compositor:
# the wheel arrives as a mouse's does through a compositor, with Qt's own idea of the device,
# which the scroller's properties (ipc scroller) never showed
if [ "$LOCKTEST_TOOL_SOURCE" = system ]; then
    make_system_tools "$work/input-tools"
    input_share=$work/input-tools/share
else
    input_share=$LOCKTEST_TOOLS/share
fi
input_fifo=$work/input.fifo
mkfifo "$input_fifo"
"${isolated[@]}" WAYLAND_DISPLAY=wayland-0 "$SETPRIV" --no-new-privs timeout 300 "$LOCKTEST_PYTHON" -I -B \
    "$REPO/tests/lock/input/ltinput.py" "$input_share" "$input_share/us.xkb" "$input_fifo" > "$work/input.log" 2>&1 < /dev/null &
input_pid=$!
deadline=$((SECONDS + 10))
# The client ready, a condition polled
while [ $SECONDS -lt $deadline ] && ! grep -q 'ltinput ready' "$work/input.log"; do sleep 0.05; done
input_ready=$(grep -c 'ltinput ready' "$work/input.log")
check "$([ "$input_ready" = 1 ]; echo $?)" "the virtual pointer started ($(tail -n 1 "$work/input.log"))"

# send_input <command>: handed to the input client; returns once the compositor has it (the
# client's acknowledgement), five seconds at most
send_input() {
    local before
    before=$(cat "$input_fifo.ack" 2> /dev/null | wc -l)
    timeout 5 bash -c 'printf "%s\n" "$2" > "$1"' _ "$input_fifo" "$1" || return 1
    local deadline=$((SECONDS + 5))
    # The acknowledgement, a condition polled
    while [ $SECONDS -lt $deadline ] && [ "$(cat "$input_fifo.ack" 2> /dev/null | wc -l)" -le "$before" ]; do sleep 0.05; done
}

# wheel_run <case> <command;command…> [VAR=value…]: the entry started on screen; once its
# window is made (the gallery: its first section built or failed) the pointer put at the output's
# centre, inside the window (which opens centred), and each wheel command sent in turn:
# wheel_scroller what `ipc scroller` answered first, wheel_positions `ipc position` before
# the first and after each (once it changed, or after five seconds), a line each
wheel_run() {
    local case=$1 commands=$2 id="" deadline=$((SECONDS + 60)) made="" command position steps=()
    shift 2
    start_entry "$case" "$REPO/mockup.qml" "$@"
    wheel_scroller="" wheel_positions=""
    while [ $SECONDS -lt $deadline ] && kill -0 "${pids[$case]}" 2> /dev/null; do
        id=$(instance_of "$case")
        [ -n "$id" ] && made=$(ipc "$id" call mockup window)
        if [ "$made" = floating ] && { [ "$(ipc "$id" call mockup name)" != gallery ] \
            || ipc "$id" call mockup sections | head -n 1 | grep -q -E ' (built|failed: .*)$'; }; then
            break
        fi
        # A condition polled (the window made), not a fixed wait
        sleep 0.05
    done
    if [ "$made" = floating ]; then
        wheel_scroller=$(ipc "$id" call mockup scroller)
        send_input "abs 1 1 2 2"
        position=$(ipc "$id" call mockup position)
        wheel_positions=$position
        IFS=';' read -r -a steps <<< "$commands"
        for command in "${steps[@]}"; do
            send_input "$command"
            local moved_deadline=$((SECONDS + 5)) now
            # Moved, a condition polled; five seconds for a wheel that does nothing
            while now=$(ipc "$id" call mockup position) && [ "$now" = "$position" ] && [ $SECONDS -lt $moved_deadline ]; do sleep 0.05; done
            position=$now
            wheel_positions+=$'\n'$position
        done
    fi
    kill -TERM "${pids[$case]}" 2> /dev/null
    finish_entry "$case"
}

echo "on screen: a real mouse wheel scrolls a component's window (the pointer over its cells)"
wheel_run wheel-component "scroll vertical 3" H2S_MOCKUP=components/small-button
check "$([ "$wheel_scroller" = "wheel, vertical bar shown" ]; echo $?)" "small-button's states taller than the window (scroller was '$wheel_scroller')"
check "$([ "$wheel_positions" = "$(printf '%s\n' 0,0 0,144)" ]; echo $?)" "three notches down: 48 px each (positions were '$(paste -s -d ' ' <<< "$wheel_positions")')"
check "$(! grep -q -E 'MOCKUP-ERROR|TypeError|ReferenceError' "${logs[wheel-component]}"; echo $?)" "no error"

echo "on screen: a real wheel scrolls a plan both ways: down, sideways by a horizontal wheel and by Shift, up; a touchpad's stroke with the finger"
wheel_run wheel-plan "scroll vertical 3;scroll horizontal 2;scroll vertical 2 shift;scroll vertical -1;swipe vertical 40" \
    H2S_MOCKUP_BASE=tests/fixtures/mockups H2S_MOCKUP=plans/tall H2S_MOCKUP_SCENE=first
check "$([ "$wheel_positions" = "$(printf '%s\n' 0,0 0,144 96,144 192,144 192,96 192,136)" ]; echo $?)" "down 3, right 2, Shift+down 2 to the right, up 1, a touchpad's 40 px stroke down by 40 px (positions were '$(paste -s -d ' ' <<< "$wheel_positions")')"
check "$(! grep -q -E 'MOCKUP-ERROR|TypeError|ReferenceError' "${logs[wheel-plan]}"; echo $?)" "no error"

echo "on screen: a real wheel scrolls the gallery"
wheel_run wheel-gallery "scroll vertical 3" H2S_MOCKUP=gallery H2S_MOCKUP_BASE=tests/fixtures/mockups XDG_CONFIG_HOME="$theme_config"
check "$([ "$wheel_positions" = "$(printf '%s\n' 0,0 0,144)" ]; echo $?)" "three notches down (positions were '$(paste -s -d ' ' <<< "$wheel_positions")')"
check "$(! grep -q -E 'MOCKUP-ERROR|TypeError|ReferenceError|Binding loop' "${logs[wheel-gallery]}"; echo $?)" "no error"
echo "the shell's wheel handlers: the event form's colour row scrolls by a real wheel"
start_entry wheel-row "$REPO/mockup.qml" H2S_MOCKUP_BASE=tests/fixtures/mockups H2S_MOCKUP=plans/wheel
row_answer="" deadline=$((SECONDS + 30))
while [ $SECONDS -lt $deadline ] && kill -0 "${pids[wheel-row]}" 2> /dev/null; do
    id=$(instance_of wheel-row)
    # The window made and given the keyboard (Shift goes to it), a condition polled
    [ -n "$id" ] && grep -q WHEEL-ACTIVE "${logs[wheel-row]}" && break
    sleep 0.05
done
if [ -n "$id" ]; then
    send_input "abs 1 1 2 2"
    # A plain vertical wheel passes it by; Shift with it and a touchpad's sideways stroke move it
    send_input "scroll vertical 3"
    send_input "scroll vertical 3 shift"
    send_input "swipe horizontal -40"
    # The row scrolled, a condition polled; five seconds for a wheel that does nothing
    row_deadline=$((SECONDS + 5))
    while [ $SECONDS -lt $row_deadline ] && ! grep -q -E 'WHEEL-ROW 140$' "${logs[wheel-row]}"; do sleep 0.05; done
    row_answer=$(grep -o -E 'WHEEL-ROW [0-9]+' "${logs[wheel-row]}" | paste -s -d ' ')
fi
kill -TERM "${pids[wheel-row]}" 2> /dev/null
finish_entry wheel-row
# (the stroke's steps may come one by one or together: its last value is the check)
check "$([ "${row_answer%% WHEEL-ROW *}" = "WHEEL-ROW 180" ] && [ "${row_answer##* }" = 140 ]; echo $?)" "three plain notches leave the swatches, three with Shift move them 180 px (60 a notch), a 40 px stroke back by 40 (was '$row_answer')"
check "$(! grep -q -E 'MOCKUP-ERROR|TypeError|ReferenceError' "${logs[wheel-row]}"; echo $?)" "no error"

# point_at <id> <x,y>: the pointer moved to that place in the window, from where the probe
# sees it now (relative moves: the window's place on the output is the compositor's); a few
# corrections at most; 0 once it is there
point_at() {
    local id=$1 target=$2 here attempt
    for attempt in 1 2 3 4; do
        here=$(ipc "$id" call probe pointer)
        [ -z "$here" ] && return 1
        [ "$here" = "$target" ] && return 0
        send_input "move $((${target%,*} - ${here%,*})) $((${target#*,} - ${here#*,}))"
        local deadline=$((SECONDS + 5))
        # Seen moved, a condition polled
        while [ $SECONDS -lt $deadline ] && [ "$(ipc "$id" call probe pointer)" = "$here" ]; do sleep 0.05; done
    done
    [ "$(ipc "$id" call probe pointer)" = "$target" ]
}

# await <id> <expected> <ipc call…>: polls the call until it answers <expected>, five seconds
# at most; prints the last answer
await() {
    local id=$1 expected=$2 answer deadline=$((SECONDS + 5))
    shift 2
    # A condition polled
    while answer=$(ipc "$id" call "$@") && [ "$answer" != "$expected" ] && [ $SECONDS -lt $deadline ]; do sleep 0.05; done
    printf '%s' "$answer"
}

echo "on screen: a real pointer in a scene holding a list open: a scene button takes the press, a press outside closes the list"
start_entry held-list "$REPO/mockup.qml" H2S_MOCKUP_BASE=tests/fixtures/mockups H2S_MOCKUP=plans/held-list H2S_MOCKUP_SCENE=open
held_steps="" deadline=$((SECONDS + 30)) id=""
while [ $SECONDS -lt $deadline ] && kill -0 "${pids[held-list]}" 2> /dev/null; do
    id=$(instance_of held-list)
    [ -n "$id" ] && [ "$(ipc "$id" call mockup window)" = floating ] && [ "$(ipc "$id" call probe list)" = shown ] && break
    id=""
    # A condition polled (the window made, the list shown), not a fixed wait
    sleep 0.05
done
if [ -n "$id" ]; then
    send_input "abs 1 1 2 2"
    send_input "move 1 1"
    pointer_deadline=$((SECONDS + 5))
    # The pointer seen in the window, a condition polled
    while [ $SECONDS -lt $pointer_deadline ] && [ -z "$(ipc "$id" call probe pointer)" ]; do sleep 0.05; done
    point_at "$id" "$(ipc "$id" call mockup place other)" && send_input "click left"
    held_steps="$(await "$id" other mockup current) $(await "$id" hidden probe list)"
    point_at "$id" "$(ipc "$id" call mockup place open)" && send_input "click left"
    held_steps+=" $(await "$id" open mockup current) $(await "$id" shown probe list)"
    point_at "$id" "$(ipc "$id" call probe outside)" && send_input "click left"
    held_steps+=" $(await "$id" hidden probe list) $(ipc "$id" call mockup current)"
fi
kill -TERM "${pids[held-list]}" 2> /dev/null
finish_entry held-list
check "$([ "$held_steps" = "other hidden open shown hidden open" ]; echo $?)" "the other scene's button switches scenes, the open one's brings the list back, a press outside closes it (was '$held_steps')"
check "$(! grep -q -E 'MOCKUP-ERROR|TypeError|ReferenceError' "${logs[held-list]}"; echo $?)" "no error"

# Every wheel handler in the tree is the shell's WheelScroll, which takes a mouse wheel as
# Qt on Wayland hands it over (from its touchpad device); a plain WheelHandler turns it away
plain_handlers=$(cd "$REPO" && grep -r -l -E '(^|[^A-Za-z.])WheelHandler[[:space:]]*\{' --include='*.qml' . | sed 's|^\./||' \
    | grep -v -x -F components/WheelScroll.qml)
check "$([ -z "$plain_handlers" ]; echo $?)" "no plain WheelHandler outside components/WheelScroll.qml ($(paste -s -d ' ' <<< "$plain_handlers"))"

kill -TERM "$input_pid" 2> /dev/null
wait "$input_pid" 2> /dev/null
input_pid=""

# closed_by_user <case> <title> [VAR=value…]: the entry started on screen; once its window
# is made, closed through the compositor as its close button does (the closer fixture);
# closer_answer what the closer said, ended_answer "ended <status>" when the entry ended
# within ten seconds after, else "still running" (then ended here)
closed_by_user() {
    local case=$1 title=$2 id="" deadline=$((SECONDS + 30))
    shift 2
    start_entry "$case" "$REPO/mockup.qml" "$@"
    closer_answer="" ended_answer="still running"
    while [ $SECONDS -lt $deadline ] && kill -0 "${pids[$case]}" 2> /dev/null; do
        id=$(instance_of "$case")
        # The window made, a condition polled
        [ -n "$id" ] && [ "$(ipc "$id" call mockup window)" = floating ] && break
        sleep 0.05
    done
    start_entry "$case-closer" "$REPO/tests/fixtures/mockup-closer/shell.qml" H2S_CLOSE_TITLE="$title"
    finish_entry "$case-closer"
    closer_answer=$(grep -o -E 'CLOSER-(CLOSED [0-9]+|NONE)' "${logs[$case-closer]}" | head -n 1)
    # The entry gone, a condition polled; ten seconds guard a process left without a window
    deadline=$((SECONDS + 10))
    while [ $SECONDS -lt $deadline ] && kill -0 "${pids[$case]}" 2> /dev/null; do sleep 0.05; done
    kill -0 "${pids[$case]}" 2> /dev/null && kill -TERM "${pids[$case]}" 2> /dev/null
    finish_entry "$case"
    [ "${statuses[$case]}" = 143 ] || ended_answer="ended ${statuses[$case]}"
}

echo "on screen: the window closed by the user ends the process"
closed_by_user close-one components/good H2S_MOCKUP_BASE=tests/fixtures/mockups H2S_MOCKUP=components/good
check "$([ "$closer_answer" = "CLOSER-CLOSED 1" ]; echo $?)" "the compositor asked to close the window titled components/good (closer said '$closer_answer')"
check "$([ "$ended_answer" = "ended 0" ]; echo $?)" "the process ends, status 0, with no window left (was '$ended_answer')"
closed_by_user close-plan plans/idea H2S_MOCKUP_BASE=tests/fixtures/mockups H2S_MOCKUP=plans/idea
check "$([ "$closer_answer" = "CLOSER-CLOSED 1" ] && [ "$ended_answer" = "ended 0" ]; echo $?)" "a plan's window closed: the process ends, status 0 (closer '$closer_answer', '$ended_answer')"
closed_by_user close-gallery gallery H2S_MOCKUP_BASE=tests/fixtures/mockups H2S_MOCKUP=gallery XDG_CONFIG_HOME="$theme_config"
check "$([ "$closer_answer" = "CLOSER-CLOSED 1" ] && [ "$ended_answer" = "ended 0" ]; echo $?)" "the gallery's window closed: the process ends, status 0 (closer '$closer_answer', '$ended_answer')"

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
check "$(grep 'MOCKUP-ERROR ' "${logs[limit]}" | grep -q -F "longer than 1500 ms (at state 0 'normal', waiting for next)"; echo $?)" "MOCKUP-ERROR names the limit, the state and what it waited for"
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
    "about.txt: missing|about.txt is missing, empty or unreadable|${fixtures[*]} H2S_MOCKUP=components/no-about"
    "about.txt: no description|about.txt: no 'description:' line|${fixtures[*]} H2S_MOCKUP=components/no-description"
    "about.txt: a plan's keyword in a component|about.txt line 2: 'scene:' is a plan's|${fixtures[*]} H2S_MOCKUP=components/wrong-keyword"
    "about.txt: a component's keyword in a plan|about.txt line 2: 'state:' is a component's or a view's|${fixtures[*]} H2S_MOCKUP=plans/wrong-keyword"
    "about.txt: a bad name|the state name 'Bad_Name' is not letters, digits and '-'|${fixtures[*]} H2S_MOCKUP=components/bad-name"
    "about.txt: a repeated name|about.txt line 4: the state name 'first' is repeated (line 2)|${fixtures[*]} H2S_MOCKUP=components/repeated-name"
    "about.txt: a state without a name|about.txt line 2: a state without a name|${fixtures[*]} H2S_MOCKUP=components/empty-name"
    "about.txt: a state without its description|about.txt line 2: the state 'first' has no description|${fixtures[*]} H2S_MOCKUP=components/no-state-description"
    "about.txt: a description too long|about.txt line 1: the description is 101 characters, over 100|${fixtures[*]} H2S_MOCKUP=components/too-long"
    "names set in Mockup.qml|the states are declared in about.txt, not in Mockup.qml|${fixtures[*]} H2S_MOCKUP=components/sets-names"
    "a check of a broken about.txt|about.txt line 2: 'state:' is a component's or a view's|H2S_MOCKUP_BASE=tests/fixtures/mockups H2S_MOCKUP_CHECK=1 H2S_MOCKUP=plans/wrong-keyword"
    "check and shots at once|H2S_MOCKUP_CHECK and H2S_MOCKUP_SHOT are both set|${fixtures[*]} H2S_MOCKUP_CHECK=1 H2S_MOCKUP=components/good"
    "unknown first state on screen|no state 'nope'|H2S_MOCKUP_BASE=tests/fixtures/mockups H2S_MOCKUP=components/good H2S_MOCKUP_STATE=nope"
    "unknown first scene of a plan on screen|no scene 'nope'|H2S_MOCKUP_BASE=tests/fixtures/mockups H2S_MOCKUP=plans/tall H2S_MOCKUP_SCENE=nope"
    "the old planning folder|mockups/planning/ is now mockups/plans/|${fixtures[*]} H2S_MOCKUP=planning/idea"
    "a scene for a component|H2S_MOCKUP_SCENE is set for components/good|H2S_MOCKUP_BASE=tests/fixtures/mockups H2S_MOCKUP=components/good H2S_MOCKUP_SCENE=checked"
    "a state for a plan|H2S_MOCKUP_STATE is set for the plan plans/tall|H2S_MOCKUP_BASE=tests/fixtures/mockups H2S_MOCKUP=plans/tall H2S_MOCKUP_STATE=second"
    "the kit's old scenes|the kit's scenes and scene are now names and current, and the states are declared in about.txt|${fixtures[*]} H2S_MOCKUP=components/old-scenes"
    "bad shot limit|H2S_MOCKUP_SHOT_LIMIT_MS is 'soon'|${fixtures[*]} H2S_MOCKUP=components/good H2S_MOCKUP_SHOT_LIMIT_MS=soon"
    "a theme while shooting|H2S_MOCKUP_THEME is 'contrast' while shooting: shots and baselines are always drawn in the built-in theme|${fixtures[*]} H2S_MOCKUP=components/good H2S_MOCKUP_THEME=contrast"
    "the gallery while shooting|H2S_MOCKUP_SHOT is set for the gallery|H2S_MOCKUP_SHOT=1 H2S_MOCKUP=gallery"
    "the gallery with a state|H2S_MOCKUP_STATE is set for the gallery|H2S_MOCKUP=gallery H2S_MOCKUP_STATE=idle"
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

echo "H2S_MOCKUP_CHECK: an element checked without a window"
start_entry check-plan "$REPO/mockup.qml" H2S_MOCKUP_BASE=tests/fixtures/mockups H2S_MOCKUP_CHECK=1 H2S_MOCKUP=plans/tall
start_entry check-component "$REPO/mockup.qml" H2S_MOCKUP_BASE=tests/fixtures/mockups H2S_MOCKUP_CHECK=1 H2S_MOCKUP=components/good
# Names that a plain object already has (constructor, toString): names like any other
start_entry check-object-names "$REPO/mockup.qml" H2S_MOCKUP_BASE=tests/fixtures/mockups H2S_MOCKUP_CHECK=1 H2S_MOCKUP=plans/object-names
drive no check-plan check-component check-object-names
for entry in "check-plan|MOCKUP-CHECKED 3 scenes" "check-component|MOCKUP-CHECKED 2 states" "check-object-names|MOCKUP-CHECKED 3 scenes"; do
    IFS='|' read -r case expected <<< "$entry"
    check "$([ "${statuses[$case]}" = 0 ]; echo $?)" "$case: exits 0 (was ${statuses[$case]})"
    check "$(grep -q -F -- "$expected" "${logs[$case]}"; echo $?)" "$case: says $expected"
    check "$(! grep -q -E 'MOCKUP-SHOT|MOCKUP-ERROR|TypeError|ReferenceError|OpenGL VENDOR' "${logs[$case]}"; echo $?)" "$case: no window drawn, no shot, no error"
    grep -q -F -- "$expected" "${logs[$case]}" || sed 's/^/    /' "${logs[$case]}" | head -n 10
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
runner failing -- --load-only components/good components/load-error components/repeated-name components/warning components/no-about \
    components/sets-names
check "$([ "${runner_status[failing]}" = 1 ]; echo $?)" "exits 1 (was ${runner_status[failing]})"
check "$([ "$(verdict_of failing components/good)" = PASS ]; echo $?)" "components/good PASS"
for name in load-error repeated-name warning no-about sets-names; do
    check "$([ "$(verdict_of failing components/$name)" = FAIL ]; echo $?)" "components/$name FAIL"
done
check "$(grep -q "MOCKUP-ERROR components/load-error: .*NoSuchFixtureType" "${out[failing]}"; echo $?)" "the load error is named"
check "$(grep -q -F "about.txt line 4: the state name 'first' is repeated (line 2)" "${out[failing]}"; echo $?)" "the repeated state is named, by its line in about.txt"
check "$(grep -q -F "about.txt is missing: every element declares its description and its states there" "${out[failing]}"; echo $?)" "the missing about.txt is named"
check "$(grep -q -F "the states are declared in about.txt, not in Mockup.qml" "${out[failing]}"; echo $?)" "names set in Mockup.qml: about.txt named"
check "$(grep -q "a line about the mockup's own files: .*warning/Mockup.qml.*Unable to assign" "${out[failing]}"; echo $?)" "the warning from the mockup's file is named"
show_on_failure "$before" failing

echo "runner: no name runs every component and view, and --load-only checks every plan without a window"
before=$failures
runner all -- --load-only
expected=$(cd "$REPO/tests/fixtures/mockups" && find components views plans -mindepth 2 -maxdepth 2 -name Mockup.qml -printf '%h\n' | LC_ALL=C sort)
ran=$(awk '/^  (PASS|FAIL) / { print $2 } /^  NOT RUN / { print $3 }' "${out[all]}" | LC_ALL=C sort)
check "$([ "$ran" = "$expected" ]; echo $?)" "ran each fixture once, plans included ($(echo $ran))"
check "$(grep -q -F 'PASS     plans/tall (checked: 3 scenes declared, no window' "${out[all]}"; echo $?)" "plans/tall: checked, its three scenes, no window"
check "$([ "$(verdict_of all plans/wrong-keyword)" = FAIL ] && grep -q -F "about.txt line 2: 'state:' is a component's or a view's" "${out[all]}"; echo $?)" "plans/wrong-keyword: FAIL, its line named"
runner plan -- --load-only plans/idea
check "$([ "${runner_status[plan]}" = 0 ] && [ "$(verdict_of plan plans/idea)" = PASS ] && grep -q -F 'plans/idea (1 scenes,' "${out[plan]}"; echo $?)" "plans/idea runs when named, its verdict counting scenes (status ${runner_status[plan]})"
show_on_failure "$before" all

echo "runner: names that run nothing"
for entry in "Bad_Name|is not <kind>/<name>" "plans/../idea|is not <kind>/<name>" "planning/idea|mockups/planning/ is now mockups/plans/ (git mv mockups/planning/idea mockups/plans/idea)" "components/no-such-mockup|no mockup components/no-such-mockup"; do
    IFS='|' read -r name expected <<< "$entry"
    runner bad-name -- --load-only components/good "$name"
    check "$([ "${runner_status[bad-name]}" = 2 ] && grep -q -F -- "$expected" "${out[bad-name]}" && ! grep -q -E '^  (PASS|FAIL)' "${out[bad-name]}"; echo $?)" "'$name': exit 2, '$expected', nothing run"
done
# Plans have no baseline: comparing or approving one is refused
for mode in compare approve; do
    runner plan-$mode -- --$mode components/good plans/idea
    check "$([ "${runner_status[plan-$mode]}" = 2 ] && grep -q -F "plans/idea is a plan: plans have no baseline" "${out[plan-$mode]}" \
        && ! grep -q -E '^  (PASS|FAIL|NOT RUN) |^(APPROVED|REFUSED|NOT DONE) ' "${out[plan-$mode]}"; echo $?)" "--$mode of a plan: refused, exit 2, nothing run"
done
runner no-mode -- components/good
check "$([ "${runner_status[no-mode]}" = 2 ] && grep -q '^usage:' "${out[no-mode]}"; echo $?)" "no mode: the usage, exit 2"

echo "runner: --by-system, the mode by the system"
before=$failures
# Made-up systems: a root each with its os-release (read under H2S_DISTRIBUTION_ROOT)
for system in arch nixos fedora; do
    mkdir -p "$work/system-$system/etc"
    cp "$REPO/tests/fixtures/distribution/$system.os-release" "$work/system-$system/etc/os-release"
done
# (Fedora is the generic distribution: no set of its own)
for entry in "arch|arch|compare" "nixos|nixos|load-only" "fedora|generic|load-only"; do
    IFS='|' read -r system detected expected <<< "$entry"
    runner by-system-$system H2S_DISTRIBUTION_ROOT="$work/system-$system" -- --by-system Bad_Name
    check "$([ "${runner_status[by-system-$system]}" = 2 ] && grep -q -x -F -- "run-mockups.sh: the system is $detected: --$expected" "${out[by-system-$system]}"; echo $?)" "$system: says the system is $detected, --$expected"
done
# A system that cannot be told (an os-release that cannot be read) runs nothing: NOT RUN,
# never load-only
mkdir -p "$work/system-unknown/etc/os-release"
runner by-system-unknown H2S_DISTRIBUTION_ROOT="$work/system-unknown" -- --by-system components/good
check "$([ "${runner_status[by-system-unknown]}" = 2 ] && grep -q -F 'cannot be told' "${out[by-system-unknown]}" && ! grep -q -E '^ *PASS ' "${out[by-system-unknown]}"; echo $?)" "unknown system: status 2, nothing run (status ${runner_status[by-system-unknown]})"
runner by-system-run H2S_DISTRIBUTION_ROOT="$work/system-nixos" -- --by-system components/good
check "$([ "${runner_status[by-system-run]}" = 0 ] && [ "$(verdict_of by-system-run components/good)" = PASS ] && [ ! -e "$work/shots-by-system-run" ]; echo $?)" "nixos: components/good PASS, load-only (no shot; status ${runner_status[by-system-run]})"
show_on_failure "$before" by-system-run
# A tree with no component or view mockup: nothing to check is no failure for --by-system,
# a set-up error for the others
empty=$work/empty-tree
mkdir -p "$empty/tests" "$empty/scripts" "$empty/mockups/kit"
cp "$REPO/tests/run-mockups.sh" "$REPO/tests/mockup-about.sh" "$empty/tests/"
cp "$REPO/scripts/distribution.sh" "$empty/scripts/"
cp -r "$REPO/distributions" "$empty/"
empty_out=$(H2S_DISTRIBUTION_ROOT="$work/system-arch" "$empty/tests/run-mockups.sh" --by-system 2>&1)
empty_status=$?
check "$([ "$empty_status" = 0 ] && grep -q -F 'no component or view mockup in mockups/: nothing to run' <<< "$empty_out"; echo $?)" "no mockup in the tree: --by-system says nothing to run, status 0 (was $empty_status)"
empty_out=$("$empty/tests/run-mockups.sh" --load-only 2>&1)
empty_status=$?
check "$([ "$empty_status" = 2 ]; echo $?)" "… --load-only: status 2 (was $empty_status)"

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
# run-mockups.sh): it stays. The stand-in is a bash named run-mockups.sh that waits on a
# FIFO no one writes, with no child to outlive it; never `exec -a … sleep`: a multi-call
# coreutils (NixOS) picks its program by that name and exits at once
mkfifo "$work/prune-live.fifo"
(exec -a run-mockups.sh bash -c 'read -r -t 60 <> "$0"' "$work/prune-live.fifo") &
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
# set_baseline_png <file> <state line's number and name>: the file becomes that state's
# baseline PNG, with its checksum in the manifest (a baseline approved so)
set_baseline_png() {
    local sum
    cp -- "$1" "$baseline/$2.png"
    sum=$(sha256sum < "$baseline/$2.png")
    sed -i "s/^\(state ${2%%-*} ${2#*-} [0-9x]* \).*\$/\1${sum%% *}/" "$baseline/manifest.txt"
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
check "$([ "${runner_status[approve]}" = 0 ] && grep -q -F "APPROVED components/good — 2 states from $first_run" "${out[approve]}"; echo $?)" "--approve takes the newest run (status ${runner_status[approve]})"
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
check "$(grep -q -x -E "state 00 normal [0-9]+x[0-9]+ ${normal_sum%% *}" "$manifest" && grep -q -E '^state 01 checked [0-9]+x[0-9]+ [0-9a-f]{64}$' "$manifest"; echo $?)" "a state line per state, with its size and checksum"
show_on_failure "$before" approve
cp -a "$baseline" "$work/baseline-approved"

before=$failures
runner compare-same "${compare_vars[@]}" -- --compare components/good
check "$([ "${runner_status[compare-same]}" = 0 ] && grep -q '^  PASS     components/good (2 states, the same as the baseline' "${out[compare-same]}"; echo $?)" "a fresh run compares the same: PASS, 0 differing pixels (status ${runner_status[compare-same]})"
show_on_failure "$before" compare-same

before=$failures
"$LOCKTEST_MAGICK" "$baseline/01-checked.png" -fill red -draw 'point 5,5' "$work/checked-one-pixel.png"
set_baseline_png "$work/checked-one-pixel.png" 01-checked
runner compare-pixel "${compare_vars[@]}" -- --compare components/good
pixel_run=$(shots_named compare-pixel)
check "$([ "${runner_status[compare-pixel]}" = 1 ] && [ "$(verdict_of compare-pixel components/good)" = FAIL ]; echo $?)" "a baseline one pixel off: FAIL (status ${runner_status[compare-pixel]})"
check "$(grep -q -F "state 'checked': 1 pixel differs; review: $pixel_run/01-checked-review.png" "${out[compare-pixel]}"; echo $?)" "names the state, '1 pixel differs' and the review image"
check "$(! grep -q "state 'normal'" "${out[compare-pixel]}"; echo $?)" "the unchanged state is not named"
check "$([ -s "$pixel_run/01-checked-review.png" ] && cmp -s "$pixel_run/01-checked/old.png" "$baseline/01-checked.png" \
    && cmp -s "$pixel_run/01-checked/new.png" "$pixel_run/01-checked.png" && [ -s "$pixel_run/01-checked/diff.png" ] && [ ! -e "$pixel_run/00-normal" ]; echo $?)" "old.png, new.png, diff.png and the review image written, for that state only"
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
for i in $(seq 2 30); do echo "state $i extra-$i 1x1 0000000000000000000000000000000000000000000000000000000000000000" >> "$baseline/manifest.txt"; done
runner compare-states "${compare_vars[@]}" -- --compare components/good
check "$([ "${runner_status[compare-states]}" = 1 ] && grep -q -F "the baseline has 31 states, over the limit of 30" "${out[compare-states]}"; echo $?)" "a baseline of 31 states: FAIL (status ${runner_status[compare-states]})"
show_on_failure "$before" compare-states

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

# A state whose size changed, with no pixel of the shot different: the baseline one transparent
# column wider
before=$failures
rm -rf "$baseline" && cp -a "$work/baseline-approved" "$baseline"
normal_size=$("$LOCKTEST_MAGICK" identify -format '%wx%h' "$baseline/00-normal.png")
wider=$(( ${normal_size%x*} + 1 ))x${normal_size#*x}
"$LOCKTEST_MAGICK" "$baseline/00-normal.png" -alpha set -background none -gravity West -extent "$wider" "$work/wider.png"
set_baseline_png "$work/wider.png" 00-normal
sed -i "s/^state 00 normal $normal_size /state 00 normal $wider /" "$baseline/manifest.txt"
runner compare-size "${compare_vars[@]}" -- --compare components/good
check "$([ "${runner_status[compare-size]}" = 1 ] && grep -q -F "state 'normal': 0 pixels differ (the size was $wider, is $normal_size)" "${out[compare-size]}"; echo $?)" "a state whose size changed FAILs with no pixel different (status ${runner_status[compare-size]})"
show_on_failure "$before" compare-size

# Scenes renamed, added and removed
# states_case <case> <expected baseline names>: the state lists named
states_case() {
    runner "$1" "${compare_vars[@]}" -- --compare components/good
    check "$([ "${runner_status[$1]}" = 1 ] && grep -q -F "the states are not the baseline's: baseline '$2', now 'normal checked'" "${out[$1]}"; echo $?)" "$1: FAIL, the state lists named (status ${runner_status[$1]})"
    show_on_failure "$before" "$1"
}
before=$failures
rm -rf "$baseline" && cp -a "$work/baseline-approved" "$baseline"
mv "$baseline/01-checked.png" "$baseline/01-pressed.png"
sed -i 's/^state 01 checked /state 01 pressed /' "$baseline/manifest.txt"
states_case state-renamed "normal pressed"
rm -rf "$baseline" && cp -a "$work/baseline-approved" "$baseline"
cp "$baseline/01-checked.png" "$baseline/02-extra.png"
echo "$(grep '^state 01 ' "$baseline/manifest.txt" | sed 's/^state 01 checked /state 02 extra /')" >> "$baseline/manifest.txt"
states_case state-removed-since "normal checked extra"
rm -rf "$baseline" && cp -a "$work/baseline-approved" "$baseline"
rm "$baseline/01-checked.png"
sed -i '/^state 01 /d' "$baseline/manifest.txt"
states_case state-added-since "normal"

# A manifest still saying scene, the keyword's old name: FAIL, the fix named
before=$failures
rm -rf "$baseline" && cp -a "$work/baseline-approved" "$baseline"
sed -i 's/^state /scene /' "$baseline/manifest.txt"
runner compare-old-keyword "${compare_vars[@]}" -- --compare components/good
check "$([ "${runner_status[compare-old-keyword]}" = 1 ] && grep -q -F "baseline/manifest.txt says scene, the keyword's old name: state" "${out[compare-old-keyword]}"; echo $?)" "a manifest still saying scene: FAIL, the keyword named (status ${runner_status[compare-old-keyword]})"
show_on_failure "$before" compare-old-keyword

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

# A Quickshell that names no version: what drew the states cannot be told
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
