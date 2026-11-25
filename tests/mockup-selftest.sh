#!/usr/bin/env bash
# The mockups' screen tool (tests/mockup.sh), on the fixture mockups (H2S_MOCKUP_BASE=
# tests/fixtures/mockups) and stand-ins only: a stand-in `qs` (its `list --all`, `ipc … call
# mockup name`, `kill` and `-p`), `hyprctl` and `kitten`, on a PATH of the few system tools the
# tool needs, so that neither a real Quickshell, the compositor nor a terminal's images are
# reached. Nothing is opened on a screen.
#
#   - list: every fixture element under its kind's heading with about.txt's description and
#     its states or scenes, "*" on the open ones, a broken about.txt said; on fixture trees
#     (--main, --also) the exact output at COLUMNS=60: each element once, the main tree's
#     version, a working tree's own elements [not merged: <label>] (an old-layout one too), a
#     tree that only duplicates the main one adding nothing, no colour off a terminal;
#     list <element> with each state's description; search in names and descriptions of
#     elements, states and scenes, any case, every word, no match status 1;
#   - tests/mockup-about.sh: the fixtures' about.txt read, each broken form (missing, no
#     description, the wrong keyword, a bad, a repeated, an empty or an undescribed name, too long, a
#     second description, an unknown keyword, over 30 states) refused, naming the line; every
#     element of mockups/ as the format says;
#   - a name or a unique part of one; a part that matches several is refused;
#   - close picks only instances whose config is this tree's mockup.qml, by the name each
#     answers over IPC: never another tree's mockup, never the shell, never an instance that
#     answers no name (with -n the commands printed, without it `qs kill --pid` run);
#   - open, -n: through Hyprland's exec when Hyprland is there, else setsid; a state name
#     a shell would read (; & | $( ) `) refused before any command is built; an instance
#     already running is said, --restart closes it first; --scene on a component and
#     --state on a plan refused; a name under planning/ (the plans' old folder) refused;
#   - open, run: the entry starts with every inherited H2S_* variable dropped (the shell's
#     H2S_SHELL_MODULES, a stray H2S_MOCKUP_SHOT), H2S_MOCKUP and H2S_MOCKUP_STATE (a plan:
#     H2S_MOCKUP_SCENE) set, the rest of the environment kept;
#   - review: under a kitty terminal (KITTY_WINDOW_ID, TERM=xterm-kitty) each differing
#     state's old, new and diff go to `kitten icat`, labelled; elsewhere, and in kitty without
#     kitten, their paths are printed; a mockup with no baseline shows its new shots; no run
#     is said; review and approve of a plan are refused (plans have no baseline).
#
#   tests/mockup-selftest.sh
#
# Exit status: 0 when every check passed, 1 when one failed, 2 when it could not be set up.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd -P)
TOOL=$REPO/tests/mockup.sh
ENTRY=$REPO/mockup.qml
work=$(mktemp -d "${TMPDIR:-/tmp}/mockup-selftest.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$work"' EXIT
failures=0
check() {
    local verdict=$1 text=$2
    if [ "$verdict" = 0 ]; then echo "  PASS: $text"; else echo "  FAIL: $text"; failures=$((failures + 1)); fi
}

# PATH: the stand-ins, then links to the system tools the screen tool uses (no qs, hyprctl,
# kitten or kitty among them)
mkdir -p "$work/fake" "$work/tools"
for tool in bash env sed grep awk readlink dirname cut tr sort seq sleep sha256sum setsid stty cat; do
    found=$(command -v "$tool") || { echo "mockup-selftest.sh: needs $tool" >&2; exit 2; }
    ln -s "$found" "$work/tools/$tool"
done
cat > "$work/fake/qs" << 'EOF'
#!/usr/bin/env bash
# A stand-in Quickshell: list --all from $FAKE/list.txt, a name per pid from $FAKE/name-<pid>,
# each call logged; -p records its environment and joins the list as a running mockup
echo "qs $*" >> "$FAKE/qs.log"
case "$1" in
    list) cat "$FAKE/list.txt" 2> /dev/null ;;
    ipc) [ "$2" = --pid ] && cat "$FAKE/name-$3" 2> /dev/null ;;
    kill) ;;
    -p)
        env > "$FAKE/env.txt"
        printf 'Instance started1:\n  Process ID: 4194398\n  Config path: %s\n' "$2" >> "$FAKE/list.txt"
        echo "$H2S_MOCKUP" > "$FAKE/name-4194398"
        ;;
esac
exit 0
EOF
for stand_in in hyprctl kitten; do
    printf '#!/usr/bin/env bash\necho "%s $*" >> "$FAKE/%s.log"\n' "$stand_in" "$stand_in" > "$work/fake/$stand_in"
done
chmod +x "$work/fake"/*
# Pids above any kernel's pid_max: the tool's wait for a closed one never meets a real process
cat > "$work/list.txt" << EOF
Instance aaaa:
  Process ID: 4194301
  Config path: $ENTRY
Instance bbbb:
  Process ID: 4194302
  Config path: $ENTRY
Instance cccc:
  Process ID: 4194303
  Config path: /another/tree/mockup.qml
Instance dddd:
  Process ID: 4194304
  Config path: $REPO/shell.qml
Instance eeee:
  Process ID: 4194305
  Config path: $ENTRY
EOF
echo components/good > "$work/name-4194301"
echo views/isolation > "$work/name-4194302"
echo components/good > "$work/name-4194303"
echo components/good > "$work/name-4194304"
# (4194305 answers no name: not a mockup)

# tool <case> [VAR=value…] -- <arguments…>: the tool on the stand-ins, its output in
# $work/<case>.out, its status in status[<case>]; FAKE is a fresh copy of the canned state
declare -A status
tool() {
    local case=$1
    shift
    local variables=()
    while [ "$1" != -- ]; do variables+=("$1"); shift; done
    shift
    rm -rf "$work/state-$case"
    mkdir -p "$work/state-$case"
    cp "$work/list.txt" "$work"/name-* "$work/state-$case/"
    env -i HOME="$work/home" PATH="$work/fake:$work/tools" FAKE="$work/state-$case" TERM=dumb \
        H2S_MOCKUP_BASE=tests/fixtures/mockups H2S_MOCKUP_SHOTS="$work/shots" \
        "${variables[@]}" bash "$TOOL" "$@" > "$work/$case.out" 2>&1 < /dev/null
    status[$case]=$?
}
out() { cat "$work/$1.out"; }
log_of() { cat "$work/state-$1/$2.log" 2> /dev/null; }
has() { grep -q -F -- "$2" "$work/$1.out"; }

echo "list"
tool list -- list
check "$(out list | grep -q -E '^Components$' && out list | grep -q -E '^Views$' && out list | grep -q -E '^Plans$'; echo $?)" "kind headings: Components, Views, Plans"
check "$(out list | grep -q -E "^  good +\* The runners' fixture mockup that loads$" && out list | grep -q -E '^ +states: normal, checked$'; echo $?)" "components/good: open, its description and states"
check "$(out list | grep -q -E '^  isolation +\* '; echo $?)" "views/isolation: open (another instance of the entry)"
check "$(out list | grep -q -E '^  clock +A fixture' && out list | grep -q -E '^ +scenes: first, second, third$'; echo $?)" "components/clock: not open; plans/tall: its scenes"
check "$(! has list planning; echo $?)" "no old planning folder in the fixtures: nothing said of it"
check "$(log_of list qs | grep -q -E 'ipc --pid (4194303|4194304) '; [ $? = 1 ]; echo $?)" "another tree's instance and the shell are never asked their name"
check "$(out list | grep -q -E '^  no-about +\(broken: about.txt is missing'; echo $?)" "components/no-about: listed, its missing about.txt said"
check "$(out list | grep -q -E "^  wrong-keyword +\(broken: about.txt line 2: 'state:' is a component's"; echo $?)" "plans/wrong-keyword: listed, its broken line said"

echo "list and search over trees (--main, --also)"
# Fixture trees: a main one, a working tree with a plan of its own and a copy of a main
# element, one in the old layout (planning/, no about.txt) sharing that plan, and a copy of
# the main tree (a pinned tree that only duplicates it)
trees=$work/trees
fix=tests/fixtures/mockups
# element <tree> <kind>/<name> [<about.txt line>...]: its Mockup.qml and, with lines, about.txt
element() {
    local folder=$trees/$1/$fix/$2
    shift 2
    mkdir -p "$folder"
    : > "$folder/Mockup.qml"
    [ $# -eq 0 ] || printf '%s\n' "$@" > "$folder/about.txt"
}
element main components/alpha "description: The first component" "state: rest The alpha at rest" "state: hover The pointer over alpha"
element main components/beta-long "description: A component whose description is long enough to wrap at sixty columns" \
    "state: one Its first" "state: two Its second" "state: three Its third" "state: four Its fourth" "state: five Its fifth" "state: six-and-more The last, HOVERED by nothing"
element main components/broken "description: Broken" "scene: x A plan's line"
element main views/panel "description: A panel view" "state: only The panel"
element main plans/idea "description: An idea" "scene: first The first scene" "scene: hover-test Where the pointer rests"
mkdir -p "$trees/main/mockups/kit"
: > "$trees/main/mockups/kit/Gallery.qml"
element side components/alpha "description: The first component, changed in a working tree" "state: rest At rest"
element side plans/fresh "description: A plan only in a working tree" "scene: start The start"
element side plans/both "description: A plan in two working trees" "scene: one The one scene"
element old components/alpha
element old planning/both
element old planning/legacy
echo "# Mockup: An old plan's notes" > "$trees/old/$fix/planning/legacy/MOCKUP.md"
cp -r "$trees/main" "$trees/pin"
for t in main side old pin; do : > "$trees/$t/mockup.qml"; done
printf 'Instance ffff:\n  Process ID: 4194306\n  Config path: %s\n' "$trees/main/mockup.qml" >> "$work/list.txt"
echo components/alpha > "$work/name-4194306"
over=(--main "$trees/main" --also "$trees/side=side" --also "$trees/old=old" --also "$trees/pin=pin")
tool trees COLUMNS=60 -- list "${over[@]}"
cat > "$work/trees.expected" << EXPECTED
Components
  alpha     * The first component
              states: rest, hover
  beta-long   A component whose description is long enough
              to wrap at sixty columns
              states: one, two, three, four, five,
                      six-and-more
  broken      (broken: about.txt line 2: 'scene:' is a
              plan's; a component or a view declares
              'state:' lines)
              about.txt: no 'state:' line
Views
  panel       A panel view
              states: only
Plans
  both        A plan in two working trees
              [not merged: side, old]
              scenes: one
  fresh       A plan only in a working tree
              [not merged: side]
              scenes: start
  idea        An idea
              scenes: first, hover-test
  legacy      An old plan's notes
              [not merged: old]
              old layout: no about.txt, its scenes not
              declared

Gallery: tests/mockup.sh open gallery    * open now
EXPECTED
check "$(diff "$work/trees.expected" "$work/trees.out" > "$work/trees.diff"; echo $?)" "list: grouped by kind, each element once, the main tree's version, working trees' own elements not merged, wrapped at COLUMNS=60 $(cat "$work/trees.diff")"
check "$([ "$(grep -c -E '^  alpha ' "$work/trees.out")" = 1 ] && ! has trees changed && ! has trees '[not merged: pin' && ! has trees '== '; echo $?)" "no duplicates: a copy in a working tree and a tree that only duplicates the main one add nothing, no tree headings"
check "$(! grep -q $'\e' "$work/trees.out"; echo $?)" "not a terminal: no colour"
tool one COLUMNS=60 H2S_MOCKUP_COMMAND=tools/mockup.sh -- list alpha "${over[@]}"
cat > "$work/one.expected" << EXPECTED
Component alpha (open) — The first component
  rest   The alpha at rest
  hover  The pointer over alpha
Open: tools/mockup.sh open components/alpha   one state: tools/mockup.sh open components/alpha --state rest
EXPECTED
check "$(diff "$work/one.expected" "$work/one.out" > "$work/one.diff"; echo $?)" "list <element>: each state with its description, the command named by H2S_MOCKUP_COMMAND $(cat "$work/one.diff")"
tool one-fresh COLUMNS=60 -- list fresh "${over[@]}"
check "$(has one-fresh 'Plan fresh — A plan only in a working tree' && has one-fresh '[not merged: side]' && has one-fresh '  start  The start' && has one-fresh '--scene start'; echo $?)" "list <plan> not merged: its note and scenes, --scene"
tool one-several -- list a "${over[@]}"
check "$([ "${status[one-several]}" = 2 ] && has one-several 'matches several elements'; echo $?)" "list <part> matching several: refused (status ${status[one-several]})"
tool search COLUMNS=60 -- search HOVER "${over[@]}"
cat > "$work/search.expected" << EXPECTED
Components
  alpha     * The first component
              hover  The pointer over alpha
  beta-long   A component whose description is long enough
              to wrap at sixty columns
              six-and-more  The last, HOVERED by nothing
Plans
  idea        An idea
              hover-test  Where the pointer rests
EXPECTED
check "$(diff "$work/search.expected" "$work/search.out" > "$work/search.diff"; echo $?)" "search: names and descriptions of states, any case, shown like list with the matching states $(cat "$work/search.diff")"
tool search-element COLUMNS=60 -- search working tree "${over[@]}"
check "$(has search-element '  both ' && has search-element '  fresh ' && has search-element 'scenes: start' && ! has search-element '  alpha' && ! has search-element '  idea'; echo $?)" "search of several words in an element's description: the element whole, every word needed"
tool search-mixed COLUMNS=60 -- search panel only "${over[@]}"
check "$(has search-mixed '  panel ' && has search-mixed '  only  The panel' && ! has search-mixed 'states:'; echo $?)" "search: a word in the name, another in a state: that state shown"
tool search-none -- search nothing-like-this "${over[@]}"
check "$([ "${status[search-none]}" = 1 ] && [ "$(out search-none)" = 'Nothing matches "nothing-like-this" (tests/mockup.sh list shows everything)' ]; echo $?)" "search with no match: said, status 1 (status ${status[search-none]})"
tool also-open -- -n open alpha --also "$trees/side=side"
check "$([ "${status[also-open]}" = 2 ] && has also-open '--main and --also are for list and search'; echo $?)" "--also with open: refused"
tool also-bad -- list --also "$trees/side"
check "$([ "${status[also-bad]}" = 2 ] && has also-bad 'needs <tree folder>=<label>'; echo $?)" "--also without a label: refused"

echo "about.txt (tests/mockup-about.sh)"
# shellcheck source=mockup-about.sh
source "$REPO/tests/mockup-about.sh"
fixtures=$REPO/tests/fixtures/mockups
about_read "$fixtures/components/good" state
check "$([ $? = 0 ] && [ "$about_description" = "The runners' fixture mockup that loads" ] && [ "${about_names[*]}" = "normal checked" ] \
    && [ "${about_descriptions[1]}" = "The button checked" ]; echo $?)" "components/good: its description, names and descriptions"
about_read "$fixtures/plans/tall" scene
check "$([ $? = 0 ] && [ "${about_names[*]}" = "first second third" ]; echo $?)" "plans/tall: its three scenes"
# Each broken form: kind/name | word | the error expected
for entry in \
    "components/no-about|state|about.txt is missing" \
    "components/no-description|state|about.txt: no 'description:' line" \
    "components/wrong-keyword|state|about.txt line 2: 'scene:' is a plan's" \
    "plans/wrong-keyword|scene|about.txt line 2: 'state:' is a component's or a view's" \
    "components/bad-name|state|the state name 'Bad_Name' is not letters, digits and '-'" \
    "components/repeated-name|state|about.txt line 4: the state name 'first' is repeated (line 2)" \
    "components/empty-name|state|about.txt line 2: a state without a name" \
    "components/no-state-description|state|about.txt line 2: the state 'first' has no description" \
    "components/too-long|state|about.txt line 1: the description is 101 characters, over 100"; do
    IFS='|' read -r element word expected <<< "$entry"
    about_read "$fixtures/$element" "$word"
    verdict=$?
    check "$([ "$verdict" = 1 ] && printf '%s\n' "${about_errors[@]}" | grep -q -F -- "$expected"; echo $?)" "$element: refused, '$expected'"
done
# A description of exactly 100 characters, a state's too; then one over, a second
# description, 31 states and an unknown keyword
about_dir=$work/about
mkdir -p "$about_dir"
long=$(printf 'x%.0s' $(seq 100))
printf 'description: %s\nstate: a %s\n' "$long" "$long" > "$about_dir/about.txt"
about_read "$about_dir" state
check "$?" "100 characters, the description's and a state's: taken"
printf 'description: d\ndescription: e\nstate: a %sx\nlabel: x\n' "$long" > "$about_dir/about.txt"
about_read "$about_dir" state
check "$([ $? = 1 ] && [ "${about_errors[*]}" = "about.txt line 2: a second description about.txt line 3: the state 'a' has a description of 101 characters, over 100 about.txt line 4: 'label:' is not 'description:' or 'state:'" ]; echo $?)" "a second description, a state's 101 characters and an unknown keyword, each named (${about_errors[*]})"
{ echo "description: d"; for i in $(seq 31); do echo "state: s$i The state $i"; done; } > "$about_dir/about.txt"
about_read "$about_dir" state
check "$([ $? = 1 ] && [ "${about_errors[*]}" = "about.txt: 31 states, over 30" ]; echo $?)" "31 states: over the limit"
# Every real element's about.txt is as the format says, plans included
for folder in "$REPO"/mockups/{components,views,plans}/*/; do
    folder=${folder%/}
    word=state
    [[ "$folder" == */plans/* ]] && word=scene
    about_read "$folder" "$word"
    check "$?" "mockups/${folder#"$REPO/mockups/"}: about.txt as the format says ${about_errors[*]}"
done

echo "names"
tool part -- -n close isol
check "$(has part "Would close views/isolation"; echo $?)" "a unique part names its mockup"
tool several -- -n close o
check "$([ "${status[several]}" = 2 ] && has several 'matches several mockups'; echo $?)" "a part matching several is refused (status ${status[several]})"

echo "close"
tool close-one -- -n close components/good
check "$([ "$(grep -c '^qs kill' "$work/close-one.out")" = 1 ] && has close-one 'qs kill --pid 4194301'; echo $?)" "close <name> -n: only this tree's instance of it (not another tree's, not the shell)"
tool close-all -- -n close
check "$([ "$(grep '^qs kill' "$work/close-all.out" | sed 's/ *$//' | sort | paste -s -d ,)" = "qs kill --pid 4194301,qs kill --pid 4194302" ]; echo $?)" "close -n: this tree's two mockups, never the shell, another tree or a nameless instance"
tool close-run -- close components/good
check "$([ "$(log_of close-run qs | grep '^qs kill')" = "qs kill --pid 4194301" ] && has close-run 'Closed components/good'; echo $?)" "close <name>: qs kill --pid on that instance only"
tool close-none -- close components/clock
check "$(has close-none 'components/clock is not running' && ! log_of close-none qs | grep -q '^qs kill'; echo $?)" "close of a mockup not running kills nothing"

echo "open"
tool open-hypr HYPRLAND_INSTANCE_SIGNATURE=test -- -n open clock --state ticking
dispatch=$(printf '%q' "hl.dsp.exec_cmd(\"'$TOOL' '__exec' 'tests/fixtures/mockups' 'components/clock' 'ticking'\")")
check "$(has open-hypr "hyprctl dispatch $dispatch" && [ ! -s "$work/state-open-hypr/hyprctl.log" ]; echo $?)" "-n under Hyprland: the exec dispatch printed, of this tool's __exec with the state, nothing run"
tool open-setsid -- -n open components/clock
check "$(has open-setsid "setsid -f $TOOL __exec tests/fixtures/mockups components/clock"; echo $?)" "-n without Hyprland: setsid printed"
tool open-running HYPRLAND_INSTANCE_SIGNATURE=test -- -n open good
check "$(has open-running 'components/good is already running (pid 4194301)' && ! has open-running hyprctl; echo $?)" "a running mockup: said, not started again"
tool open-restart HYPRLAND_INSTANCE_SIGNATURE=test -- -n open good --restart
check "$(has open-restart 'qs kill --pid 4194301' && has open-restart 'hyprctl dispatch'; echo $?)" "--restart: closed, then started"
tool open-badstate -- -n open clock --state 'a b'
check "$([ "${status[open-badstate]}" = 2 ]; echo $?)" "a state with whitespace is refused (status ${status[open-badstate]})"
tool open-scene-of-component HYPRLAND_INSTANCE_SIGNATURE=test -- -n open clock --scene ticking
check "$([ "${status[open-scene-of-component]}" = 2 ] && has open-scene-of-component 'it has states (--state), not scenes' && ! has open-scene-of-component hyprctl; echo $?)" "--scene on a component is refused (status ${status[open-scene-of-component]})"
tool open-state-of-plan HYPRLAND_INSTANCE_SIGNATURE=test -- -n open plans/tall --state second
check "$([ "${status[open-state-of-plan]}" = 2 ] && has open-state-of-plan 'is a plan: it has scenes (--scene)' && ! has open-state-of-plan hyprctl; echo $?)" "--state on a plan is refused (status ${status[open-state-of-plan]})"
tool open-both -- -n open clock --state ticking --scene ticking
check "$([ "${status[open-both]}" = 2 ] && has open-both 'one of --state and --scene'; echo $?)" "--state and --scene together are refused (status ${status[open-both]})"
tool open-planning -- -n open planning/idea
check "$([ "${status[open-planning]}" = 2 ] && has open-planning 'mockups/planning/ is now mockups/plans/' && has open-planning 'plans/idea'; echo $?)" "a name under planning/ is refused with the move to make (status ${status[open-planning]})"
for hostile in 'x;id' 'x&&id' 'x|id' '$(id)' 'x`id`'; do
    tool open-hostile HYPRLAND_INSTANCE_SIGNATURE=test -- -n open clock --state "$hostile"
    check "$([ "${status[open-hostile]}" = 2 ] && ! has open-hostile hyprctl && ! has open-hostile setsid; echo $?)" "a state a shell would read ($hostile) is refused before any command is built (status ${status[open-hostile]})"
done
tool open-run H2S_SHELL_MODULES=/modules H2S_SHELL_HELPER=/helper H2S_MOCKUP_SHOT=1 KEPT=yes -- open components/clock --state ticking
envs=$work/state-open-run/env.txt
check "$([ -f "$envs" ] && grep -q -x 'H2S_MOCKUP=components/clock' "$envs" && grep -q -x 'H2S_MOCKUP_STATE=ticking' "$envs" \
    && ! grep -q '^H2S_MOCKUP_SCENE=' "$envs" \
    && grep -q -x 'H2S_MOCKUP_BASE=tests/fixtures/mockups' "$envs" && grep -q -x 'KEPT=yes' "$envs"; echo $?)" "open: the entry gets H2S_MOCKUP, the state (H2S_MOCKUP_STATE) and the base, the rest of the environment kept"
tool open-plan -- open plans/tall --scene second
envs=$work/state-open-plan/env.txt
check "$([ -f "$envs" ] && grep -q -x 'H2S_MOCKUP=plans/tall' "$envs" && grep -q -x 'H2S_MOCKUP_SCENE=second' "$envs" \
    && ! grep -q '^H2S_MOCKUP_STATE=' "$envs"; echo $?)" "open of a plan: the scene goes as H2S_MOCKUP_SCENE"
check "$([ -f "$envs" ] && ! grep -q -E '^(H2S_SHELL_MODULES|H2S_SHELL_HELPER|H2S_MOCKUP_SHOT|H2S_MOCKUP_SHOTS)=' "$envs"; echo $?)" "open: the inherited H2S_* variables are dropped (H2S_SHELL_MODULES, H2S_SHELL_HELPER, H2S_MOCKUP_SHOT)"
check "$(log_of open-run qs | grep -q -x -F "qs -p $ENTRY" && has open-run 'Opened components/clock (pid 4194398)'; echo $?)" "open: qs -p <tree>/mockup.qml, then found running"

echo "review"
key=$(printf '%s' "$REPO" | sha256sum | cut -c 1-16)
run=$work/shots/fixtures/components/good/20261124-120000-1
mkdir -p "$run/01-checked"
for file in 00-normal.png 01-checked.png 01-checked-review.png 01-checked/old.png 01-checked/new.png 01-checked/diff.png; do : > "$run/$file"; done
echo 20261124-120000-1 > "$work/shots/fixtures/components/good/last-run-$key"
mkdir -p "$work/baselines/components/good/baseline"
: > "$work/baselines/components/good/baseline/manifest.txt"
fresh=$work/shots/fixtures/components/clock/20261124-120000-2
mkdir -p "$fresh"
: > "$fresh/00-ticking.png"
echo 20261124-120000-2 > "$work/shots/fixtures/components/clock/last-run-$key"
review_env=(H2S_MOCKUP_BASELINES="$work/baselines")
tool review-kitty "${review_env[@]}" KITTY_WINDOW_ID=3 -- -n review good
check "$(has review-kitty "$REPO/tests/run-mockups.sh --compare components/good"; echo $?)" "-n: the comparison's command printed"
check "$(for kind in old new diff; do has review-kitty "components/good, state checked: $kind" && has review-kitty "kitten icat --align left $run/01-checked/$kind.png" || exit 1; done; echo 0)" "KITTY_WINDOW_ID: old, new and diff each labelled and shown through kitten icat"
check "$(! has review-kitty 00-normal; echo $?)" "a state that does not differ is not shown"
tool review-term "${review_env[@]}" TERM=xterm-kitty -- -n review good
check "$(has review-term "kitten icat --align left $run/01-checked/new.png"; echo $?)" "TERM=xterm-kitty: shown through kitten icat"
tool review-plain "${review_env[@]}" -- -n review good
check "$(has review-plain "components/good, state checked: diff: $run/01-checked/diff.png" && ! has review-plain icat; echo $?)" "another terminal: the paths printed, no icat"
tool review-nokitten "${review_env[@]}" KITTY_WINDOW_ID=3 PATH="$work/tools" -- -n review good
check "$(has review-nokitten "components/good, state checked: old: $run/01-checked/old.png" && ! has review-nokitten 'icat --align'; echo $?)" "kitty without kitten or kitty: the paths printed"
tool review-new "${review_env[@]}" -- -n review clock
check "$(has review-new "components/clock, state ticking: new (no baseline): $fresh/00-ticking.png"; echo $?)" "no baseline: the new shots shown"
tool review-none "${review_env[@]}" -- -n review effects
check "$([ "${status[review-none]}" = 2 ] && has review-none 'nothing to review'; echo $?)" "no run of the mockup: said, status 2 (status ${status[review-none]})"

echo "plans have no baseline"
for command in review approve; do
    tool plan-$command -- -n $command plans/tall
    check "$([ "${status[plan-$command]}" = 2 ] && has plan-$command "plans/tall is a plan: plans have no baseline" && ! has plan-$command run-mockups.sh; echo $?)" "$command of a plan: refused, status 2, nothing run (status ${status[plan-$command]})"
done

echo "__exec, -n"
tool exec-dry H2S_SHELL_MODULES=/modules -- -n __exec mockups components/good
check "$(has exec-dry '-u H2S_SHELL_MODULES' && has exec-dry 'H2S_MOCKUP=components/good qs -p'; echo $?)" "__exec -n: the env command dropping H2S_SHELL_MODULES printed"

echo
if [ "$failures" = 0 ]; then
    echo "mockup-selftest.sh: every check passed"
    exit 0
fi
echo "mockup-selftest.sh: $failures check(s) FAILED"
exit 1
