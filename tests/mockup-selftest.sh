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
#     on trees in git, an element the main tree removed not offered by a tree that only lags
#     behind, a copy whose tree lags behind another working tree's left out; two working
#     trees' different copies each listed, in list <element> too;
#     list <element> with each state's description; search in names and descriptions of
#     elements, states and scenes, any case (Polish letters in the C locale), every word, no
#     match status 1;
#   - tests/mockup-about.sh: the fixtures' about.txt read, each broken form (missing, no
#     description, the wrong keyword, a bad, a repeated, an empty or an undescribed name, too long, a
#     second description, an unknown keyword, over 30 states) refused, naming the line; every
#     element of mockups/ as the format says;
#   - a name or a unique part of one; a part that matches several is refused;
#   - close picks only instances whose config is this tree's mockup.qml, by the name each
#     answers over IPC: never another tree's mockup, never the shell, never an instance that
#     answers no name (with -n the commands printed, without it `qs kill --pid` run); with
#     --main and --also, by list's own rule, in those trees: a plan an old tool started in a
#     working tree (IPC name planning/<name>) marked open by list and closed by close, with
#     and without the element named, by this tool; one run from a working tree holding the
#     main copy unchanged marked open too; a running mockup no tree lists closed by its name;
#   - open, -n: through Hyprland's exec when Hyprland is there, else setsid; every address
#     form (<element>, <kind>/<name>, <element>/<state>, <kind>/<name>/<state>, a part, with
#     and without the word open) built into the right __exec; a state or scene about.txt does
#     not declare, a malformed address and a state name a shell would read (; & | $( ) `)
#     refused before any command is built; an instance already running is said, --restart
#     closes it first; a name under planning/ (the plans' old folder) refused;
#   - open gallery (and the bare word): __exec gallery, the entry started with
#     H2S_MOCKUP=gallery and found running by that name; gallery/<state>, review gallery and
#     approve gallery refused (no states, no baseline of its own);
#   - --theme: passed to the entry as H2S_MOCKUP_THEME (with or without a state, a name with
#     a space), "default" with no file, an unknown theme refused with the list of the theme
#     files, a quote refused, refused for other commands;
#   - help: the exact text at COLUMNS=80, no line over 80 columns, the same for -h and --help
#     after every command, the command named by H2S_MOCKUP_COMMAND; wrong commands, options and
#     argument counts: the message and the usage line on standard error only, status 2;
#   - the tree whose copy is taken (--main, --also, on fixture trees with stand-in tools): the
#     main tree's, one working tree's different copy (said), an element only in one working
#     tree (said, an old-layout one too), several different copies: refused with their labels;
#     in git, a tree that only lags behind the main one or another working tree holds no copy,
#     two trees on one branch hold one (said); that tree's tool runs with the same arguments
#     less --main and --also; a whole name before a part of a longer one;
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
for tool in bash env sed grep awk readlink dirname cut tr sort seq sleep sha256sum setsid stty cat diff git; do
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
              [not merged: side]
              scenes: one
  both        (no description)
              [not merged: old]
              old layout: no about.txt, its scenes not
              declared
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
Open: tools/mockup.sh open alpha   one state: tools/mockup.sh open alpha/rest
EXPECTED
check "$(diff "$work/one.expected" "$work/one.out" > "$work/one.diff"; echo $?)" "list <element>: each state with its description, the command named by H2S_MOCKUP_COMMAND $(cat "$work/one.diff")"
tool one-fresh COLUMNS=60 -- list fresh "${over[@]}"
check "$(has one-fresh 'Plan fresh — A plan only in a working tree' && has one-fresh '[not merged: side]' && has one-fresh '  start  The start' && has one-fresh 'open fresh/start'; echo $?)" "list <plan> not merged: its note and scenes, --scene"
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
check "$([ $? = 1 ] && [ "${about_errors[*]}" = "about.txt line 2: a second description about.txt line 3: the state 'a' has a description of 101 characters, over 100 about.txt line 4: 'label:' is not 'description:', 'state:', 'family:' or 'parent:'" ]; echo $?)" "a second description, a state's 101 characters and an unknown keyword, each named (${about_errors[*]})"
{ echo "description: d"; for i in $(seq 31); do echo "state: s$i The state $i"; done; } > "$about_dir/about.txt"
about_read "$about_dir" state
check "$([ $? = 1 ] && [ "${about_errors[*]}" = "about.txt: 31 states, over 30" ]; echo $?)" "31 states: over the limit"
# The gallery's family and parent: read when declared, each once, a part without a family
printf 'description: d\nfamily: fields\nstate: a A\n' > "$about_dir/about.txt"
about_read "$about_dir" state
check "$([ $? = 0 ] && [ "$about_family|$about_parent" = "fields|" ]; echo $?)" "a family: read ($about_family|$about_parent)"
printf 'description: d\nparent: input-field\nstate: a A\n' > "$about_dir/about.txt"
about_read "$about_dir" state
check "$([ $? = 0 ] && [ "$about_family|$about_parent" = "|input-field" ]; echo $?)" "a parent: read ($about_family|$about_parent)"
printf 'description: d\nfamily: a\nfamily: b\nparent: x\nparent: Bad_Name\nstate: a A\n' > "$about_dir/about.txt"
about_read "$about_dir" state
check "$([ $? = 1 ] && [ "${about_errors[*]}" = "about.txt line 3: a second family about.txt line 5: a second parent about.txt: a family and a parent: a part takes its parent's family" ]; echo $?)" "a second family, a second parent, both together: each named (${about_errors[*]})"
printf 'description: d\nparent: Bad_Name\nstate: a A\n' > "$about_dir/about.txt"
about_read "$about_dir" state
check "$([ $? = 1 ] && [ "${about_errors[*]}" = "about.txt line 2: the parent 'Bad_Name' is not lowercase letters, digits and '-'" ]; echo $?)" "a parent not lowercase: refused (${about_errors[*]})"
printf 'description: d\nparent: about\nstate: a A\n' > "$about_dir/about.txt"
about_read "$about_dir" state
check "$([ $? = 1 ] && [ "${about_errors[*]}" = "about.txt: the parent is the element itself" ]; echo $?)" "the element its own parent: refused (${about_errors[*]})"
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
tool open-hypr HYPRLAND_INSTANCE_SIGNATURE=test -- -n open clock/first
dispatch=$(printf '%q' "hl.dsp.exec_cmd(\"'$TOOL' '__exec' 'tests/fixtures/mockups' 'components/clock' 'first'\")")
check "$(has open-hypr "hyprctl dispatch $dispatch" && [ ! -s "$work/state-open-hypr/hyprctl.log" ]; echo $?)" "-n under Hyprland: the exec dispatch printed, of this tool's __exec with the state, nothing run"
tool open-setsid -- -n open components/clock
check "$(has open-setsid "setsid -f $TOOL __exec tests/fixtures/mockups components/clock >" ; echo $?)" "-n without Hyprland: setsid printed"
# Every address form: <address>|the __exec arguments expected after the base
for entry in \
    "clock|components/clock" \
    "components/clock|components/clock" \
    "clock/first|components/clock first" \
    "components/clock/first|components/clock first" \
    "cloc/first|components/clock first" \
    "tall|plans/tall" \
    "plans/tall|plans/tall" \
    "tall/second|plans/tall second" \
    "plans/tall/second|plans/tall second"; do
    IFS='|' read -r address expected <<< "$entry"
    tool open-address -- -n open "$address"
    check "$([ "${status[open-address]}" = 0 ] && has open-address "setsid -f $TOOL __exec tests/fixtures/mockups $expected >"; echo $?)" "open $address: __exec $expected"
    tool open-address-short -- -n "$address"
    check "$(has open-address-short "setsid -f $TOOL __exec tests/fixtures/mockups $expected >"; echo $?)" "$address with no command: the same as open"
done
tool open-unknown-state -- -n open clock/nope
check "$([ "${status[open-unknown-state]}" = 2 ] && has open-unknown-state 'components/clock has no state "nope"; its states: first' && ! has open-unknown-state setsid; echo $?)" "a state about.txt does not declare: refused with the states (status ${status[open-unknown-state]})"
tool open-unknown-scene -- -n open tall/fourth
check "$([ "${status[open-unknown-scene]}" = 2 ] && has open-unknown-scene 'plans/tall has no scene "fourth"; its scenes: first, second, third'; echo $?)" "a scene about.txt does not declare: refused with the scenes"
for bad in 'clock/' 'a/b/c' 'components/clock/first/more' '/first'; do
    tool open-bad-address -- -n open "$bad"
    check "$([ "${status[open-bad-address]}" = 2 ] && has open-bad-address "Usage: tests/mockup.sh" && ! has open-bad-address setsid; echo $?)" "address $bad: refused with the usage (status ${status[open-bad-address]})"
done
tool open-running HYPRLAND_INSTANCE_SIGNATURE=test -- -n open good
check "$(has open-running 'components/good is already running (pid 4194301)' && ! has open-running hyprctl; echo $?)" "a running mockup: said, not started again"
tool open-restart HYPRLAND_INSTANCE_SIGNATURE=test -- -n open good --restart
check "$(has open-restart 'qs kill --pid 4194301' && has open-restart 'hyprctl dispatch'; echo $?)" "--restart: closed, then started"
tool open-badstate -- -n open 'clock/a b'
check "$([ "${status[open-badstate]}" = 2 ]; echo $?)" "a state with whitespace is refused (status ${status[open-badstate]})"
tool open-state-option -- -n open clock --state first
check "$([ "${status[open-state-option]}" = 2 ] && has open-state-option 'unknown option --state'; echo $?)" "--state is no option (the address names the state)"
tool open-planning -- -n open planning/idea
check "$([ "${status[open-planning]}" = 2 ] && has open-planning 'mockups/planning/ is now mockups/plans/' && has open-planning 'plans/idea'; echo $?)" "a name under planning/ is refused with the move to make (status ${status[open-planning]})"
for hostile in 'x;id' 'x&&id' 'x|id' '$(id)' 'x`id`'; do
    tool open-hostile HYPRLAND_INSTANCE_SIGNATURE=test -- -n open "clock/$hostile"
    check "$([ "${status[open-hostile]}" = 2 ] && ! has open-hostile hyprctl && ! has open-hostile setsid; echo $?)" "a state a shell would read ($hostile) is refused before any command is built (status ${status[open-hostile]})"
done
tool open-gallery -- -n open gallery
check "$([ "${status[open-gallery]}" = 0 ] && has open-gallery "setsid -f $TOOL __exec tests/fixtures/mockups gallery >"; echo $?)" "open gallery: __exec gallery (status ${status[open-gallery]})"
tool open-gallery-short -- -n gallery
check "$(has open-gallery-short "setsid -f $TOOL __exec tests/fixtures/mockups gallery >"; echo $?)" "gallery with no command: the same as open"
tool open-gallery-run -- open gallery
envs=$work/state-open-gallery-run/env.txt
check "$([ -f "$envs" ] && grep -q -x 'H2S_MOCKUP=gallery' "$envs" && ! grep -q -E '^H2S_MOCKUP_(STATE|SCENE)=' "$envs" && has open-gallery-run 'Opened gallery'; echo $?)" "open gallery: the entry gets H2S_MOCKUP=gallery, no state; found running by its name"
tool open-gallery-state -- -n open gallery/idle
check "$([ "${status[open-gallery-state]}" = 2 ] && has open-gallery-state 'the gallery has no states' && ! has open-gallery-state setsid; echo $?)" "gallery/<state>: refused, the gallery has no states (status ${status[open-gallery-state]})"
for command in review approve; do
    tool gallery-$command -- -n $command gallery
    check "$([ "${status[gallery-$command]}" = 2 ] && has gallery-$command 'the gallery has no baseline of its own' && ! has gallery-$command run-mockups; echo $?)" "$command gallery: refused, no baseline of its own (status ${status[gallery-$command]})"
done
tool gallery-exec-state -- -n __exec mockups gallery idle
check "$([ "${status[gallery-exec-state]}" = 2 ]; echo $?)" "__exec gallery with a state: refused"
tool open-run H2S_SHELL_MODULES=/modules H2S_SHELL_HELPER=/helper H2S_MOCKUP_SHOT=1 KEPT=yes -- open components/clock/first
envs=$work/state-open-run/env.txt
check "$([ -f "$envs" ] && grep -q -x 'H2S_MOCKUP=components/clock' "$envs" && grep -q -x 'H2S_MOCKUP_STATE=first' "$envs" \
    && ! grep -q '^H2S_MOCKUP_SCENE=' "$envs" \
    && grep -q -x 'H2S_MOCKUP_BASE=tests/fixtures/mockups' "$envs" && grep -q -x 'KEPT=yes' "$envs"; echo $?)" "open: the entry gets H2S_MOCKUP, the state (H2S_MOCKUP_STATE) and the base, the rest of the environment kept"
tool open-plan -- open tall/second
envs=$work/state-open-plan/env.txt
check "$([ -f "$envs" ] && grep -q -x 'H2S_MOCKUP=plans/tall' "$envs" && grep -q -x 'H2S_MOCKUP_SCENE=second' "$envs" \
    && ! grep -q '^H2S_MOCKUP_STATE=' "$envs"; echo $?)" "open of a plan: the scene goes as H2S_MOCKUP_SCENE"
check "$([ -f "$envs" ] && ! grep -q -E '^(H2S_SHELL_MODULES|H2S_SHELL_HELPER|H2S_MOCKUP_SHOT|H2S_MOCKUP_SHOTS)=' "$envs"; echo $?)" "open: the inherited H2S_* variables are dropped (H2S_SHELL_MODULES, H2S_SHELL_HELPER, H2S_MOCKUP_SHOT)"
check "$(log_of open-run qs | grep -q -x -F "qs -p $ENTRY" && has open-run 'Opened components/clock (pid 4194398)'; echo $?)" "open: qs -p <tree>/mockup.qml, then found running"

echo "--theme"
mkdir -p "$work/config/h2s_shell/themes"
: > "$work/config/h2s_shell/themes/ocean.json"
: > "$work/config/h2s_shell/themes/Power save.json"
tool theme-run XDG_CONFIG_HOME="$work/config" -- open clock --theme ocean
envs=$work/state-theme-run/env.txt
check "$([ -f "$envs" ] && grep -q -x 'H2S_MOCKUP_THEME=ocean' "$envs" && grep -q -x 'H2S_MOCKUP=components/clock' "$envs" && ! grep -q '^H2S_MOCKUP_STATE=' "$envs"; echo $?)" "--theme: the entry gets H2S_MOCKUP_THEME, no state"
tool theme-hypr XDG_CONFIG_HOME="$work/config" HYPRLAND_INSTANCE_SIGNATURE=test -- -n open tall/second --theme 'Power save'
dispatch=$(printf '%q' "hl.dsp.exec_cmd(\"'$TOOL' '__exec' 'tests/fixtures/mockups' 'plans/tall' 'second' 'Power save'\")")
check "$(has theme-hypr "hyprctl dispatch $dispatch"; echo $?)" "--theme with a scene, a name with a space: both in the exec dispatch"
tool theme-default -- -n open clock --theme default
check "$([ "${status[theme-default]}" = 0 ] && has theme-default "__exec tests/fixtures/mockups components/clock '' default"; echo $?)" "--theme default, no theme file needed: passed with an empty state"
tool theme-unknown XDG_CONFIG_HOME="$work/config" -- -n open clock --theme sea
check "$([ "${status[theme-unknown]}" = 2 ] && has theme-unknown 'no theme "sea"' && has theme-unknown 'the themes: default, Power save, ocean' && ! has theme-unknown setsid; echo $?)" "an unknown theme: refused with the list (status ${status[theme-unknown]})"
tool theme-hostile -- -n open clock --theme "a'b"
check "$([ "${status[theme-hostile]}" = 2 ] && ! has theme-hostile setsid; echo $?)" "a theme name with a quote: refused"
tool theme-list -- list --theme ocean
check "$([ "${status[theme-list]}" = 2 ] && has theme-list '--theme is for open'; echo $?)" "--theme with list: refused"
tool theme-exec -- -n __exec mockups components/good '' ocean
check "$(has theme-exec 'H2S_MOCKUP=components/good H2S_MOCKUP_THEME=ocean qs -p' && ! has theme-exec H2S_MOCKUP_STATE; echo $?)" "__exec with a theme and no state: H2S_MOCKUP_THEME only"

echo "help and usage errors"
cat > "$work/help.expected" << 'EXPECTED'
Usage: tests/mockup.sh <command> [<element>] [options]

Opens the shell's mockups on this screen: components and views in all their
states, plans with their scenes, and the gallery of every component.

Commands:
  list [<element>]        Every element by kind; with an element, each of its
                          states or scenes with its description
  search <text>...        The elements, states and scenes whose names or
                          descriptions contain every word
  open <element>          A component or view in all its states, a plan on its
                          first scene
  open <element>/<state>  One state of a component or view, or one scene of a
                          plan (<plan>/<scene>)
  open gallery            Every component in one scrollable window
  close [<element>]       Close it; with none named, every open mockup
  review <element>        Compare with the approved pictures, show what changed
  approve <element>       Make the reviewed pictures the approved ones
  help                    This help

Elements:
  pill, components/pill   a name, with its kind if two kinds share it, or a
                          unique part of a name
  pill/hover              one state of a component or view
  distribution-nixos/building
                          a plan, opened on that scene

Options:
  --restart               open: close it first if it is open
  --theme <name>          open: show it in that theme (one of your theme files)
  -n                      print the commands instead of running them
  -h, --help              this help

Examples:
  tests/mockup.sh list
  tests/mockup.sh search progress
  tests/mockup.sh open pill
  tests/mockup.sh open distribution-nixos/building
  tests/mockup.sh close
EXPECTED
tool help COLUMNS=80 -- help
check "$([ "${status[help]}" = 0 ] && diff "$work/help.expected" "$work/help.out" > "$work/help.diff"; echo $?)" "help: the text exactly, status 0 $(cat "$work/help.diff")"
check "$(! awk 'length > 80 { found = 1 } END { exit !found }' "$work/help.out"; echo $?)" "help: no line over 80 columns"
for words in "-h" "--help" "list -h" "search x --help" "open clock -h" "close -h" "review good -h" "approve -h" "-n open -h" "nothing-like-this -h"; do
    # shellcheck disable=SC2086  # the words
    tool help-option COLUMNS=80 -- $words
    check "$([ "${status[help-option]}" = 0 ] && diff -q "$work/help.expected" "$work/help-option.out" > /dev/null; echo $?)" "$words: the help, status 0"
done
tool help-named COLUMNS=80 H2S_MOCKUP_COMMAND=tools/mockup.sh -- -h
check "$(head -1 "$work/help-named.out" | grep -q -x -F 'Usage: tools/mockup.sh <command> [<element>] [options]' && has help-named '  tools/mockup.sh open pill'; echo $?)" "the help names H2S_MOCKUP_COMMAND"
usage_lines=$'Usage: tests/mockup.sh <command> [<element>] [options]\ntests/mockup.sh -h for help'
# usage_case <case> <arguments…>: the message and the usage on standard error only, status 2
usage_case() {
    local case=$1
    shift
    env -i HOME="$work/home" PATH="$work/fake:$work/tools" FAKE="$work/state-list" TERM=dumb \
        H2S_MOCKUP_BASE=tests/fixtures/mockups bash "$TOOL" "$@" > "$work/$case.stdout" 2> "$work/$case.stderr" < /dev/null
    status[$case]=$?
}
for entry in "frobnicate|\"frobnicate\" is neither a command nor an element" "--frob|unknown option --frob" "help more|help takes nothing more" \
    "list a b|list takes one element at most" "open|open takes one element" "open a b|open takes one element" \
    "review|review takes one element" "review good/normal|review takes an element, not one of its states or scenes (good/normal)" "close a b|close takes one element at most"; do
    IFS='|' read -r words message <<< "$entry"
    # shellcheck disable=SC2086  # the words
    usage_case usage $words
    check "$([ "${status[usage]}" = 2 ] && [ ! -s "$work/usage.stdout" ] \
        && [ "$(cat "$work/usage.stderr")" = "mockup.sh: $message"$'\n'"$usage_lines" ]; echo $?)" "$words: '$message' and the usage line on standard error, status 2 (status ${status[usage]}: $(cat "$work/usage.stderr"))"
done

echo "the tree whose copy is taken (--main, --also)"
# Each fixture tree's tool a stand-in that says which tree ran and with what
for t in main side old pin; do
    mkdir -p "$trees/$t/tests"
    printf '#!/usr/bin/env bash\necho "TOOL %s $*"\n' "$t" > "$trees/$t/tests/mockup.sh"
    chmod +x "$trees/$t/tests/mockup.sh"
done
element main components/delta "description: Delta" "state: rest At rest"
element pin components/delta "description: Delta" "state: rest At rest"
element side components/delta "description: Delta, changed" "state: rest At rest"
for entry in \
    "panel/only|0|TOOL main -n open panel/only|" \
    "delta|0|TOOL side -n open delta|Opening the working copy from side (not merged)" \
    "fresh/start|0|TOOL side -n open fresh/start|Opening the working copy from side (not merged)" \
    "legacy|0|TOOL old -n open legacy|Opening the working copy from old (not merged)" \
    "alpha|2||differs from the main tree's in several working trees" \
    "both|2||plans/both is in several working trees"; do
    IFS='|' read -r address want_status want_line want_note <<< "$entry"
    tool across -- -n open "$address" --theme default "${over[@]}"
    check "$([ "${status[across]}" = "$want_status" ] && { [ -z "$want_line" ] || has across "$want_line --theme default"; } \
        && { [ -z "$want_note" ] || has across "$want_note"; } && { [ -n "$want_note" ] || ! has across 'working copy'; } \
        && ! has across '--also'; echo $?)" "open $address across trees: ${want_line:-refused}${want_note:+ ($want_note)} (status ${status[across]}: $(out across | head -3 | paste -s -d ' '))"
done
tool across-list -- -n open alpha "${over[@]}"
check "$(has across-list '  side' && has across-list '  old' && ! has across-list '  pin'; echo $?)" "several different copies: their trees listed, not a tree with the same copy"
tool across-review -- -n review delta "${over[@]}"
check "$(has across-review 'Using the working copy from side (not merged)' && has across-review 'TOOL side -n review delta'; echo $?)" "review across trees: the working copy's tool"
tool across-here -- -n open clock --main "$REPO" --also "$trees/side=side"
check "$([ "${status[across-here]}" = 0 ] && has across-here "setsid -f $TOOL __exec tests/fixtures/mockups components/clock" && ! has across-here 'working copy'; echo $?)" "the main tree is this one: opened here"
echo "list and close: one rule for a running mockup (--main, --also)"
# An old tool's instance in a working tree: its IPC name under planning/, the plans' old folder
cp "$work/list.txt" "$work/list.saved"
printf 'Instance gggg:\n  Process ID: 4194307\n  Config path: %s\n' "$trees/old/mockup.qml" >> "$work/list.txt"
echo planning/legacy > "$work/name-4194307"
tool rule-list COLUMNS=60 -- list legacy "${over[@]}"
check "$(has rule-list 'Plan legacy (open)'; echo $?)" "list: a plan an old tool started in a working tree (IPC name planning/legacy) is open"
tool rule-close -- -n close legacy "${over[@]}"
check "$([ "$(grep '^qs kill' "$work/rule-close.out" | sed 's/ *$//')" = "qs kill --pid 4194307" ] && has rule-close 'Would close plans/legacy' && ! has rule-close 'TOOL'; echo $?)" "close <element>: the same instance found, by this tool, not the copy's tree's ($(out rule-close | paste -s -d ' '))"
tool rule-close-all -- -n close "${over[@]}"
check "$([ "$(grep '^qs kill' "$work/rule-close-all.out" | sed 's/ *$//' | sort | paste -s -d ,)" = "qs kill --pid 4194306,qs kill --pid 4194307" ] \
    && has rule-close-all 'Would close plans/legacy' && has rule-close-all 'Would close components/alpha'; echo $?)" "close: every mockup list marks open in the trees given, none of a tree not given ($(out rule-close-all | paste -s -d ' '))"
tool rule-close-none -- -n close panel "${over[@]}"
check "$(has rule-close-none 'views/panel is not running' && ! has rule-close-none 'qs kill'; echo $?)" "close <element> not running in any tree: said, nothing killed"
# A mockup run from a working tree that holds the main tree's copy unchanged (pin): listed
# under the main tree's entry, open there too
printf 'Instance hhhh:\n  Process ID: 4194308\n  Config path: %s\n' "$trees/pin/mockup.qml" >> "$work/list.txt"
echo views/panel > "$work/name-4194308"
tool rule-pin COLUMNS=60 -- list "${over[@]}"
check "$(grep -q -E '^  panel     \* A panel view' "$work/rule-pin.out"; echo $?)" "list: a mockup run from a tree holding the main copy unchanged is open ($(grep -E '^  panel' "$work/rule-pin.out"))"
tool rule-pin-close -- -n close panel "${over[@]}"
check "$([ "$(grep '^qs kill' "$work/rule-pin-close.out" | sed 's/ *$//')" = "qs kill --pid 4194308" ]; echo $?)" "close <element>: the same instance ($(out rule-pin-close | paste -s -d ' '))"
# A running mockup whose element no tree lists any more: close finds it by its name
echo views/removed > "$work/name-4194308"
tool rule-gone -- -n close removed "${over[@]}"
check "$([ "$(grep '^qs kill' "$work/rule-gone.out" | sed 's/ *$//')" = "qs kill --pid 4194308" ] && has rule-gone 'Would close views/removed'; echo $?)" "close <element> of an element no tree lists, still running: found by its name ($(out rule-gone | paste -s -d ' '))"
tool rule-gone-none -- -n close nothing-like-this "${over[@]}"
check "$([ "${status[rule-gone-none]}" = 2 ] && ! has rule-gone-none 'qs kill'; echo $?)" "close <element> neither listed nor running: refused, nothing killed (status ${status[rule-gone-none]})"
rm -f "$work/name-4194308"
mv "$work/list.saved" "$work/list.txt"
rm -f "$work/name-4194307"

# Trees in git: a working tree that only lags behind the main one (stale), or behind another
# working tree (lag), holds no copy of its own; two trees on one branch (work, ahead) hold one
gitwork=$work/git
mkdir -p "$gitwork"
g() { git -C "$1" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "${@:2}" > /dev/null 2>&1; }
git init -q "$gitwork/main" > /dev/null 2>&1
for name in kept gone; do
    mkdir -p "$gitwork/main/$fix/components/$name"
    printf 'description: %s\nstate: rest At rest\n' "$name" > "$gitwork/main/$fix/components/$name/about.txt"
    : > "$gitwork/main/$fix/components/$name/Mockup.qml"
done
mkdir -p "$gitwork/main/tests"
# The stand-in tool says which tree it is in
printf '#!/usr/bin/env bash\ntree=${0%%/tests/mockup.sh}\necho "TOOL ${tree##*/} $*"\n' > "$gitwork/main/tests/mockup.sh"
chmod +x "$gitwork/main/tests/mockup.sh"
: > "$gitwork/main/mockup.qml"
g "$gitwork/main" add -A && g "$gitwork/main" commit -q -m A
g "$gitwork/main" worktree add -q --detach "$gitwork/stale"
g "$gitwork/main" worktree add -q -b work "$gitwork/work"
echo "state: one More" >> "$gitwork/work/$fix/components/kept/about.txt"
mkdir -p "$gitwork/work/$fix/plans/new"
printf 'description: New, at first\nscene: zero The first\n' > "$gitwork/work/$fix/plans/new/about.txt"
: > "$gitwork/work/$fix/plans/new/Mockup.qml"
g "$gitwork/work" add -A && g "$gitwork/work" commit -q -m W1
g "$gitwork/main" worktree add -q --detach "$gitwork/lag" work
echo "state: two More" >> "$gitwork/work/$fix/components/kept/about.txt"
printf 'description: New\nscene: one The one\n' > "$gitwork/work/$fix/plans/new/about.txt"
g "$gitwork/work" add -A && g "$gitwork/work" commit -q -m W2
g "$gitwork/main" worktree add -q --detach "$gitwork/ahead" work
g "$gitwork/main" rm -q -r "$fix/components/gone" && g "$gitwork/main" commit -q -m B
git_over=(--main "$gitwork/main" --also "$gitwork/stale=stale" --also "$gitwork/lag=lag" --also "$gitwork/work=work" --also "$gitwork/ahead=ahead")
check "$([ -f "$gitwork/ahead/$fix/plans/new/about.txt" ] && [ ! -e "$gitwork/main/$fix/components/gone" ] && grep -q 'state: one' "$gitwork/lag/$fix/components/kept/about.txt" \
    && grep -q 'scene: zero' "$gitwork/lag/$fix/plans/new/about.txt"; echo $?)" "the git fixture trees are made"
tool git-kept -- -n open kept/two "${git_over[@]}"
check "$(has git-kept 'Opening the working copy from work (not merged; the same in ahead)' && has git-kept 'TOOL work -n open kept/two'; echo $?)" "a working tree's change: taken from it, the tree on the same branch said, a tree lagging behind it and a stale one not counted $(out git-kept | paste -s -d ' ')"
tool git-new -- -n open new "${git_over[@]}"
check "$(has git-new 'Opening the working copy from work (not merged; the same in ahead)' && has git-new 'TOOL work -n open new'; echo $?)" "an element only working trees added: taken from them"
tool git-gone -- -n open gone "${git_over[@]}"
check "$([ "${status[git-gone]}" = 2 ] && has git-gone 'no element matches "gone"' && ! has git-gone 'working copy'; echo $?)" "an element the main tree removed: no working tree that only lags behind offers it"
tool git-list COLUMNS=80 -- list "${git_over[@]}"
cat > "$work/git-list.expected" << EXPECTED
Components
  kept   kept
         states: rest
Plans
  new    New
         [not merged: work, ahead]
         scenes: one
EXPECTED
check "$(diff "$work/git-list.expected" "$work/git-list.out" > "$work/git-list.diff"; echo $?)" "list over git trees: an element the main tree removed not offered by the trees lagging behind, two trees on one branch one copy, a tree lagging behind another left out $(cat "$work/git-list.diff")"
# Two working trees each with a copy of its own: both listed, each with its states
element side plans/twice "description: Twice, the side copy" "scene: left The side scene"
element old plans/twice "description: Twice, the old copy" "scene: right The old scene"
tool twice COLUMNS=80 -- list twice "${over[@]}"
cat > "$work/twice.expected" << EXPECTED
Plan twice — Twice, the side copy
  [not merged: side]
  left  The side scene
Open: tests/mockup.sh open twice   one scene: tests/mockup.sh open twice/left
Plan twice — Twice, the old copy
  [not merged: old]
  right  The old scene
Open: tests/mockup.sh open twice   one scene: tests/mockup.sh open twice/right
EXPECTED
check "$(diff "$work/twice.expected" "$work/twice.out" > "$work/twice.diff"; echo $?)" "list <element> held differently by two working trees: each copy with its scenes $(cat "$work/twice.diff")"
tool twice-search COLUMNS=80 -- search right "${over[@]}"
check "$(has twice-search 'right  The old scene' && ! has twice-search 'left'; echo $?)" "search: the copy whose scene matches"
# Lower case by Unicode's rules whatever the locale (env -i: the C locale)
element side plans/meadow "description: Łąka i źródło" "scene: one The one"
tool polish -- search ŁĄKA "${over[@]}"
check "$(has polish 'meadow'; echo $?)" "search in Polish letters, any case, in the C locale"

# A whole name before a part of a longer one: the tool itself, copied into a fixture tree
real=$trees/real
mkdir -p "$real/tests"
cp "$TOOL" "$REPO/tests/mockup-about.sh" "$real/tests/"
: > "$real/mockup.qml"
element real components/pill "description: Pill" "state: idle Idle"
element real components/status-pill "description: Status pill" "state: idle Idle"
env -i HOME="$work/home" PATH="$work/fake:$work/tools" FAKE="$work/state-list" TERM=dumb H2S_MOCKUP_BASE=$fix \
    bash "$real/tests/mockup.sh" -n open pill/idle > "$work/exact.out" 2>&1
check "$(grep -q -F "__exec $fix components/pill idle" "$work/exact.out"; echo $?)" "pill, with status-pill beside it: the whole name taken $(cat "$work/exact.out")"
env -i HOME="$work/home" PATH="$work/fake:$work/tools" FAKE="$work/state-list" TERM=dumb H2S_MOCKUP_BASE=$fix \
    bash "$real/tests/mockup.sh" -n open ill > "$work/exact-part.out" 2>&1
check "$(grep -q 'matches several mockups' "$work/exact-part.out"; echo $?)" "a part of both names: refused"
tool across-none -- -n open nothing-like-this "${over[@]}"
check "$([ "${status[across-none]}" = 2 ] && has across-none 'no element matches'; echo $?)" "no element in any tree: refused"

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
