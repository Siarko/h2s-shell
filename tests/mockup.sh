#!/usr/bin/env bash
# The mockups on a screen (mockup.qml, mockups/<kind>/<name>/Mockup.qml), for the maintainer:
# list them, open and close them on this machine's display, review a comparison's images and
# approve them. The headless runs are tests/run-mockups.sh's.
#
#   tests/mockup.sh help                  the usage, commands and options (also -h, --help
#                                         after any command)
#   tests/mockup.sh [list] [<element>] [--main <tree>] [--also <tree>=<label>]...
#                                         every element by kind (Components, Views, Plans):
#                                         its description and its states or scenes, read from
#                                         about.txt (a broken one says so); "*" marks an open
#                                         one; with an element, each of its states or scenes
#                                         with its description
#   tests/mockup.sh search <text>... [--main <tree>] [--also <tree>=<label>]...
#                                         the elements, states and scenes whose names or
#                                         descriptions contain every word, in any case (no
#                                         match: status 1)
#   tests/mockup.sh [-n] [open] <element>[/<state or scene>] [--restart] [--theme <name>]
#                                         start the mockup on the display: a component or view
#                                         in all its states or on one, a plan on its first
#                                         scene or on one; if it already runs, say so, or with
#                                         --restart close it and start it again; --theme shows
#                                         it in one of the user's theme files (or "default")
#   tests/mockup.sh [-n] open gallery [--restart] [--theme <name>]
#                                         every component and view in all their states in one
#                                         window (mockups/kit/Gallery.qml; no state of its own,
#                                         no baseline: review and approve refuse it)
#   tests/mockup.sh [-n] close [<element>] [--main <tree>] [--also <tree>=<label>]...
#                                         close that mockup (with none: every running
#                                         mockup of this tree, or of the --main and --also
#                                         trees)
#   tests/mockup.sh [-n] review <element> compare it with its baseline (tests/run-mockups.sh
#                                         --compare), then show each differing state's old, new
#                                         and diff images (not a plan: it has no baseline)
#   tests/mockup.sh [-n] approve <element> the reviewed run becomes the baseline
#                                         (tests/run-mockups.sh --approve; not a plan)
#     <element>     a name, <kind>/<name> (components, views, plans), or a unique part of a
#                   name (e.g. "pill"); planning/, the plans' old folder, is refused;
#                   <element>/<state> (also <kind>/<name>/<state>) names one state or scene
#     -n            print the commands instead of running them (review still shows the images
#                   of the last run there is)
#     --main <tree> list, search, open, close, review, approve: that shell tree's
#                   elements instead of this one's
#     --also <tree>=<label>
#                   list, search: also the elements the main tree lacks and that tree changed
#                   since it left the main tree's history (git; without git, every one),
#                   marked [not merged: <label>]: one entry for the trees holding the same
#                   copy, one more for a different copy, none for a copy whose tree only lags
#                   behind another's; a tree in the old layout (mockups/planning/, no
#                   about.txt) is read as well;
#                   close: the mockup closed in whichever of the --main and --also trees
#                   runs it (one rule with list's "*", whichever tree's tool started it);
#                   open, review, approve: the tree whose copy is taken — the
#                   main tree's, unless the --also trees that changed it since they left the
#                   main tree's history hold one copy (said on a line), or the one copy the
#                   --also trees added of an element the main tree lacks; several different
#                   copies: refused with their labels. Another tree's own tool then runs.
#
# Wrong commands and options print the usage line to standard error, status 2.
# list and search wrap to the terminal's width (COLUMNS, else the terminal's, else 80), with
# bold headings only on a terminal (and never with NO_COLOR); the commands they suggest name
# H2S_MOCKUP_COMMAND (tests/mockup.sh by default; the metadata forwarder sets its own).
#
# open starts the entry through Hyprland's exec when Hyprland is there (the window gets the
# session's environment), else detached with setsid. Either way the command it starts is this
# script again (__exec), which drops every H2S_* variable it inherited (the shell's own, such
# as H2S_SHELL_MODULES, and a stray H2S_MOCKUP_SHOT), then runs
#   H2S_MOCKUP=<kind>/<name> [H2S_MOCKUP_STATE=<s> | H2S_MOCKUP_SCENE=<s>] [H2S_MOCKUP_THEME=<t>]
#       qs -p <tree>/mockup.qml
#
# A running mockup is an instance in `qs list --all` whose config path is this tree's
# mockup.qml (or a --main or --also tree's), and its name what
# `qs ipc --pid <pid> call mockup name` answers (an older tool's planning/<name> read as
# plans/<name>); list marks it and close closes it by that one rule (mockups_running): close
# never picks by a pattern, and never the shell or a tree it was not given.
# Closing a mockup's window on the screen ends its process (mockup.qml).
#
# review shows the images inline when the terminal draws the kitty graphics protocol
# (KITTY_WINDOW_ID set, TERM=xterm-kitty, or the terminal answers the protocol's query), each
# labelled with the mockup, the state and old/new/diff, through `kitten icat`; otherwise, or
# without kitten, it prints their paths. A mockup with no baseline shows its new shots.
#
# H2S_MOCKUP_BASE, H2S_MOCKUP_SHOTS and H2S_MOCKUP_BASELINES are taken as tests/run-mockups.sh
# takes them.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd -P)
ENTRY=$REPO/mockup.qml
SELF=$REPO/tests/mockup.sh
# shellcheck source=mockup-about.sh
source "$REPO/tests/mockup-about.sh" || { echo "mockup.sh: cannot read tests/mockup-about.sh" >&2; exit 2; }

base=${H2S_MOCKUP_BASE:-mockups}
case "$base" in
    mockups | tests/fixtures/mockups) ;;
    *) echo "mockup.sh: H2S_MOCKUP_BASE is '$base': mockups or tests/fixtures/mockups" >&2; exit 2 ;;
esac

# ---- __exec: the command open starts (not for typing) ---------------------------------
# __exec <base> <kind>/<name> [<state or scene> [<theme>]]: drop the inherited H2S_*
# variables, run the entry (an empty state or scene: none)
if [ "${1:-}" = __exec ] || { [ "${1:-}" = -n ] && [ "${2:-}" = __exec ]; }; then
    dry=0
    [ "$1" = -n ] && { dry=1; shift; }
    shift
    [ $# -ge 2 ] && [ $# -le 4 ] || { echo "mockup.sh: __exec <base> <kind>/<name> [<state or scene> [<theme>]]" >&2; exit 2; }
    exec_base=$1 name=$2 first=${3:-} theme=${4:-}
    [ -z "$first" ] || [[ "$first" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "mockup.sh: __exec: state or scene '$first'" >&2; exit 2; }
    [ -z "$theme" ] || [[ "$theme" =~ ^[[:alnum:]_.\ -]+$ ]] || { echo "mockup.sh: __exec: theme '$theme'" >&2; exit 2; }
    [[ "$exec_base" =~ ^(mockups|tests/fixtures/mockups)$ ]] || { echo "mockup.sh: __exec: base '$exec_base'" >&2; exit 2; }
    [[ "$name" =~ ^((components|views|plans)/[a-z0-9-]+|gallery)$ ]] || { echo "mockup.sh: __exec: name '$name'" >&2; exit 2; }
    [ "$name" != gallery ] || [ -z "$first" ] || { echo "mockup.sh: __exec: the gallery has no state" >&2; exit 2; }
    unset_args=()
    while IFS= read -r variable; do
        unset_args+=(-u "$variable")
    done < <(compgen -e | grep -E '^H2S_' || true)
    set_args=(H2S_MOCKUP="$name")
    # A plan opens on a scene, a component or a view on a state
    if [ -n "$first" ]; then
        if [[ "$name" == plans/* ]]; then set_args+=(H2S_MOCKUP_SCENE="$first"); else set_args+=(H2S_MOCKUP_STATE="$first"); fi
    fi
    [ -z "$theme" ] || set_args+=(H2S_MOCKUP_THEME="$theme")
    [ "$exec_base" = mockups ] || set_args+=(H2S_MOCKUP_BASE="$exec_base")
    command=(env "${unset_args[@]}" "${set_args[@]}" qs -p "$ENTRY")
    if [ "$dry" = 1 ]; then printf '%q ' "${command[@]}"; echo; exit 0; fi
    exec "${command[@]}"
fi

cmdname=${H2S_MOCKUP_COMMAND:-tests/mockup.sh}

# help_text: the help, the same after every command (the forwarder adds its own lines)
help_text() {
    cat << EOF
Usage: $cmdname <command> [<element>] [options]

Opens the shell's mockups on this screen: components and views in all their
states, plans with their scenes, and the gallery of every component and view.

Commands:
  list [<element>]        Every element by kind; with an element, each of its
                          states or scenes with its description
  search <text>...        The elements, states and scenes whose names or
                          descriptions contain every word
  open <element>          A component or view in all its states, a plan on its
                          first scene
  open <element>/<state>  One state of a component or view, or one scene of a
                          plan (<plan>/<scene>)
  open gallery            Every component and view in one scrollable window
  close [<element>]       Close it; with none named, every open mockup
  review <element>        Compare with the approved pictures, show what changed
  approve <element>       Make the reviewed pictures the approved ones
  help                    This help

Elements:
  pill, components/pill   a name, with its kind if two kinds share it, or a
                          unique part of a name
  pill/hover-s            one state of a component or view
  distribution-nixos/building
                          a plan, opened on that scene

Options:
  --restart               open: close it first if it is open
  --theme <name>          open: show it in that theme (one of your theme files)
  -n                      print the commands instead of running them
  -h, --help              this help

Examples:
  $cmdname list
  $cmdname search progress
  $cmdname open pill
  $cmdname open distribution-nixos/building
  $cmdname close
EOF
}

# usage [<message>]: the message, the usage line and where the help is, on standard error;
# status 2
usage() {
    [ -z "${1:-}" ] || echo "mockup.sh: $1" >&2
    echo "Usage: $cmdname <command> [<element>] [options]" >&2
    echo "$cmdname -h for help" >&2
    exit 2
}

dry=0
restart=0
theme=""
main_tree=""
also_trees=()
args=()
# The arguments without --main and --also: what another tree's tool is handed
pass_args=()
while [ $# -gt 0 ]; do
    case "$1" in
        -n | --dry-run) dry=1; pass_args+=("$1"); shift ;;
        --restart) restart=1; pass_args+=("$1"); shift ;;
        --theme)
            theme=${2:-}
            # The name goes into the command line Hyprland runs through a shell: never a
            # character a shell reads
            [[ "$theme" =~ ^[[:alnum:]_.\ -]+$ ]] || usage "--theme needs a theme's name (letters, digits, spaces, '.', '_' and '-')"
            pass_args+=("$1" "$2")
            shift 2
            ;;
        --main)
            main_tree=${2:-}
            [ -d "$main_tree" ] || usage "--main needs a shell tree's folder"
            shift 2
            ;;
        --also)
            [[ "${2:-}" =~ ^(.+)=([A-Za-z0-9._-]+)$ ]] && [ -d "${BASH_REMATCH[1]}" ] \
                || usage "--also needs <tree folder>=<label> (a label of letters, digits, '.', '_' and '-')"
            also_trees+=("$2")
            shift 2
            ;;
        -h | --help) help_text; exit 0 ;;
        -*) usage "unknown option $1" ;;
        *) args+=("$1"); pass_args+=("$1"); shift ;;
    esac
done

# run <command…>: run it with its output dropped, or with -n print it
run() {
    if [ "$dry" = 1 ]; then printf '%q ' "$@"; echo; else "$@" > /dev/null; fi
}

# all_names: every mockup of the tree, <kind>/<name>, one per line
all_names() {
    local file
    for file in "$REPO/$base"/{components,views,plans}/*/Mockup.qml; do
        [ -f "$file" ] || continue
        file=${file%/Mockup.qml}
        echo "${file#"$REPO/$base/"}"
    done
}

# resolve <name or part>: the one mockup it names
resolve() {
    local want=$1 n
    local -a matches=() exact=()
    [ -n "$want" ] || { echo "mockup.sh: an empty name" >&2; return 1; }
    if [[ "$want" == planning/* ]]; then
        echo "mockup.sh: \"$want\": mockups/planning/ is now mockups/plans/ (git mv mockups/planning/${want#planning/} mockups/plans/${want#planning/}), the name plans/${want#planning/}" >&2
        return 1
    fi
    while IFS= read -r n; do
        [ "$n" = "$want" ] && { echo "$n"; return 0; }
        [ "${n#*/}" = "$want" ] && exact+=("$n")
        [[ "$n" == *"$want"* ]] && matches+=("$n")
    done < <(all_names)
    # A whole name before a part of a longer one ("pill", not "status-pill")
    [ ${#exact[@]} -gt 0 ] && matches=("${exact[@]}")
    case ${#matches[@]} in
        1) echo "${matches[0]}" ;;
        0) echo "mockup.sh: no mockup matches \"$want\" (tests/mockup.sh list)" >&2; return 1 ;;
        *) echo "mockup.sh: \"$want\" matches several mockups:" >&2; printf '  %s\n' "${matches[@]}" >&2; return 1 ;;
    esac
}

# resolve_or_gallery <name or part>: "gallery" for the gallery (when this tree has one),
# else resolve's answer
resolve_or_gallery() {
    if [ "$1" = gallery ]; then
        [ -f "$REPO/mockups/kit/Gallery.qml" ] && { echo gallery; return 0; }
        echo "mockup.sh: this tree has no gallery yet (mockups/kit/Gallery.qml)" >&2
        return 1
    fi
    resolve "$1"
}

# mockups_running <tree>...: "<pid>\t<tree>\t<name>" for each running mockup of those trees:
# an instance in `qs list --all` whose config path is one of their mockup.qml (as given or
# resolved), its name what it answers over IPC (`mockup name`): <kind>/<name> or gallery, an
# older tool's planning/<name> read as plans/<name>. The one rule list and close go by.
mockups_running() {
    local -A entry_of=()
    local tree pid path name
    for tree in "$@"; do
        entry_of[$tree/mockup.qml]=$tree
        entry_of[$(readlink -f "$tree/mockup.qml")]=$tree
    done
    while IFS=$'\t' read -r pid path; do
        tree=${entry_of[$path]:-}
        [ -n "$tree" ] || continue
        name=$(qs ipc --pid "$pid" call mockup name 2> /dev/null | tr -d '[:space:]')
        name=${name/#planning\//plans/}
        [[ "$name" =~ ^((components|views|plans)/[a-z0-9-]+|gallery)$ ]] && printf '%s\t%s\t%s\n' "$pid" "$tree" "$name"
    done < <(qs list --all 2> /dev/null | awk '
        /^[[:space:]]*Process ID:/ { pid = $NF }
        /^[[:space:]]*Config path:/ {
            path = $0
            sub(/^[[:space:]]*Config path:[[:space:]]*/, "", path)
            if (pid ~ /^[0-9]+$/) print pid "\t" path
            pid = ""
        }
        /^Instance / { pid = "" }')
    return 0
}

# running [<tree>...]: "<pid> <kind>/<name>" for each running mockup of those trees (this one
# by default)
running() {
    [ $# -gt 0 ] || set -- "$REPO"
    mockups_running "$@" | awk -F '\t' '{ print $1 " " $3 }'
}

pids_of() { running | awk -v n="$1" '$2 == n { print $1 }'; }

# ---- list and search ------------------------------------------------------------------
# The elements of the main tree (this one, or --main), then those an --also tree changed or
# added and the main tree lacks, one entry each by <kind>/<name> (a second one for another
# working tree's different copy): el_key, el_folder, el_desc (or what is wrong with about.txt),
# el_note (more errors, or the old layout), el_trees (the trees holding it, "|"-joined),
# el_labels (the --also labels; none for the main tree), and its states or scenes in
# el_state_names[<i>,<j>] and el_state_descs[<i>,<j>] (el_state_names[<i>,count] of them)
declare -a el_key=() el_desc=() el_note=() el_trees=() el_labels=() el_folder=()
declare -A el_index=() el_state_names=() el_state_descs=()

# old_description <folder>: an old-layout element's description, from MOCKUP.md's first
# heading or the first sentence of Mockup.qml's first comment
old_description() {
    local line=""
    if [ -f "$1/MOCKUP.md" ]; then
        line=$(grep -m 1 -E '^# ' "$1/MOCKUP.md")
        line=${line#\# }
        line=${line#Mockup: }
    fi
    if [ -z "$line" ] && [ -f "$1/Mockup.qml" ]; then
        # The first block of comment lines, joined, to its first full stop or colon
        line=$(awk '/^[[:space:]]*\/\/ / { sub(/^[[:space:]]*\/\/ /, ""); text = text (text ? " " : "") $0; next }
            text { exit } END { print text }' "$1/Mockup.qml")
        line=${line%%. *}
        line=${line%%: *}
        line=${line%[.:]}
    fi
    echo "${line:-(no description)}"
}

# add_tree <tree> [<label>]: its elements not seen yet (the main tree has no label)
add_tree() {
    local tree=$1 label=${2:-} old=0 folder kind key i word j
    [ -d "$tree/$base/planning" ] && old=1
    for folder in "$tree/$base"/{components,views,plans,planning}/*/; do
        [ -f "$folder/Mockup.qml" ] || continue
        folder=${folder%/}
        kind=${folder%/*}
        kind=${kind##*/}
        [ "$kind" = planning ] && kind=plans
        key=$kind/${folder##*/}
        if [ -n "$label" ]; then
            # In the main tree: its copy is the one listed
            [ -n "${el_index[$key]:-}" ] && [ -z "${el_labels[${el_index[$key]}]}" ] && continue
            # Not the tree's own: an element it only kept while the main tree removed or
            # renamed it (a pinned tree, a branch not rebased)
            changed_in "$tree" "$folder" || continue
            # In working trees so far: the same copy is one more tree holding it, another
            # copy is listed apart (drop_lagging leaves out one that only lags behind)
            local same=-1 k
            for k in "${!el_key[@]}"; do
                [ "${el_key[k]}" = "$key" ] || continue
                if diff -r -q "${el_folder[k]}" "$folder" > /dev/null 2>&1; then same=$k; break; fi
            done
            if [ "$same" -ge 0 ]; then
                el_labels[same]="${el_labels[same]}, $label"
                el_trees[same]="${el_trees[same]}|$tree"
                continue
            fi
        fi
        i=${#el_key[@]}
        [ -n "${el_index[$key]:-}" ] || el_index[$key]=$i
        el_folder[i]=$folder
        el_key[i]=$key
        el_trees[i]=$tree
        el_labels[i]=$label
        el_note[i]=""
        word=state
        [ "$kind" = plans ] && word=scene
        if [ "$old" = 1 ] && [ ! -e "$folder/about.txt" ]; then
            el_desc[i]=$(old_description "$folder")
            el_note[i]="old layout: no about.txt, its ${word}s not declared"
            continue
        fi
        if about_read "$folder" "$word"; then
            el_desc[i]=$about_description
        else
            el_desc[i]="(broken: ${about_errors[0]})"
            el_note[i]=$(printf '%s\n' "${about_errors[@]:1}")
        fi
        for j in "${!about_names[@]}"; do
            el_state_names[$i,$j]=${about_names[j]}
            el_state_descs[$i,$j]=${about_descriptions[j]}
        done
        el_state_names[$i,count]=${#about_names[@]}
    done
}

# given_trees: the trees list and close look in: --main's (else this one) and each --also's,
# resolved, one per line
given_trees() {
    local entry
    (cd "${main_tree:-$REPO}" && pwd -P)
    for entry in "${also_trees[@]}"; do (cd "${entry%=*}" && pwd -P); done
}

# mark_open: el_open[i]=1 for each element open in any of the given trees (mockups_running,
# asked once of all of them): the entry whose trees hold that tree, else, for a tree listed
# under no copy of it (one holding the main copy unchanged), the element's first entry
declare -A el_open=()
mark_open() {
    local -a trees=()
    local i pid tree name found
    mapfile -t trees < <(given_trees)
    while IFS=$'\t' read -r pid tree name; do
        found=""
        for i in "${!el_key[@]}"; do
            [ "${el_key[i]}" = "$name" ] || continue
            [[ "|${el_trees[i]}|" == *"|$tree|"* ]] && { found=$i; break; }
        done
        [ -n "$found" ] || found=${el_index[$name]:-}
        [ -z "$found" ] || el_open[$found]=1
    done < <(mockups_running "${trees[@]}")
    return 0
}

# drop_lagging: of two copies of an element in working trees, the one whose tree only lags
# behind the other's is left out
drop_lagging() {
    local i k
    local -a gone=()
    for i in "${!el_key[@]}"; do
        [ -n "${el_labels[i]}" ] || continue
        for k in "${!el_key[@]}"; do
            [ "$i" != "$k" ] && [ "${el_key[i]}" = "${el_key[k]}" ] && [ -n "${el_labels[k]}" ] || continue
            changed_in "${el_trees[i]%%|*}" "${el_folder[i]}" "${el_trees[k]%%|*}" || { gone+=("$i"); break; }
        done
    done
    for i in "${gone[@]}"; do unset "el_key[$i]"; done
    # The first copy left of each element is its index
    el_index=()
    for i in "${!el_key[@]}"; do
        [ -n "${el_index[${el_key[i]}]:-}" ] || el_index[${el_key[i]}]=$i
    done
}

# collect [quiet]: every element, main tree and --also trees, sorted (el_order) by kind and
# name; which are open asked unless quiet
collect() {
    local entry
    list_main=$(cd "${main_tree:-$REPO}" && pwd -P)
    add_tree "$list_main"
    for entry in "${also_trees[@]}"; do
        add_tree "$(cd "${entry%=*}" && pwd -P)" "${entry##*=}"
    done
    drop_lagging
    mapfile -t el_order < <(for i in "${!el_key[@]}"; do
        k=${el_key[i]}
        case ${k%%/*} in components) r=1 ;; views) r=2 ;; *) r=3 ;; esac
        echo "$r ${k#*/} $i"
    done | sort -k1,1n -k2,2 | awk '{ print $3 }')
    [ "${1:-}" = quiet ] || mark_open
}

# Output: the width to wrap at, and bold and dim only on a terminal
setup_output() {
    local size
    width=${COLUMNS:-}
    if ! [[ "$width" =~ ^[0-9]+$ ]]; then
        width=80
        if [ -t 1 ] && size=$(stty size < /dev/tty 2> /dev/null); then width=${size#* }; fi
    fi
    [[ "$width" =~ ^[0-9]+$ ]] && [ "$width" -ge 40 ] || width=40
    bold="" dim="" plain=""
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then
        bold=$'\e[1m' dim=$'\e[2m' plain=$'\e[0m'
    fi
}

# wrap <first prefix> <next prefix> <text> [<style>]: the text in words, each line within
# the width (a word longer than a line on its own)
wrap() {
    local first=$1 next=$2 text=$3 style=${4:-} prefix line="" word end=""
    local LC_ALL=C.UTF-8
    local -a words
    [ -n "$style" ] && end=$plain
    prefix=$first
    read -r -a words <<< "$text"
    for word in "${words[@]}"; do
        if [ -z "$line" ]; then
            line=$word
        elif [ $((${#prefix} + ${#line} + 1 + ${#word})) -le "$width" ]; then
            line="$line $word"
        else
            printf '%s%s%s%s\n' "$prefix" "$style" "$line" "$end"
            prefix=$next
            line=$word
        fi
    done
    [ -n "$line" ] && printf '%s%s%s%s\n' "$prefix" "$style" "$line" "$end"
    return 0
}

# kind_word <kind/name> [plural]: "Component", "View", "Plan" (or the plural)
kind_word() {
    local kind=${1%%/*}
    kind=${kind%s}
    kind=${kind^}
    [ -n "${2:-}" ] && kind=${kind}s
    echo "$kind"
}

# print_element <i> <name width> [<state index>...]: the element's line, its notes, then its
# states or scenes by name; with state indexes, those states each with its description
print_element() {
    local i=$1 w=$2 key mark=" " pad word j count names="" line
    shift 2
    key=${el_key[i]}
    [ -n "${el_open[$i]:-}" ] && mark="*"
    printf -v line '  %-*s%s ' "$w" "${key#*/}" "$mark"
    printf -v pad '%*s' $((w + 4)) ""
    wrap "$line" "$pad" "${el_desc[i]}"
    [ -z "${el_labels[i]}" ] || wrap "$pad" "$pad" "[not merged: ${el_labels[i]}]" "$dim"
    while IFS= read -r line; do
        [ -n "$line" ] && wrap "$pad" "$pad" "$line" "$dim"
    done <<< "${el_note[i]}"
    count=${el_state_names[$i,count]:-0}
    if [ $# -gt 0 ]; then
        local sw=0 sp
        for j in "$@"; do
            [ ${#el_state_names[$i,$j]} -gt "$sw" ] && sw=${#el_state_names[$i,$j]}
        done
        printf -v sp '%*s' $((sw + 2)) ""
        for j in "$@"; do
            printf -v line '%s%-*s  ' "$pad" "$sw" "${el_state_names[$i,$j]}"
            wrap "$line" "$pad$sp" "${el_state_descs[$i,$j]}"
        done
        return 0
    fi
    [ "$count" -gt 0 ] || return 0
    word=states
    [[ "$key" == plans/* ]] && word=scenes
    for ((j = 0; j < count; j++)); do
        names+="${names:+, }${el_state_names[$i,$j]}"
    done
    wrap "$pad$word: " "$pad$(printf '%*s' $((${#word} + 2)) "")" "$names"
}

# name_width: the widest element name, plus one
name_width() {
    local i k w=0
    for i in "$@"; do
        k=${el_key[i]#*/}
        [ ${#k} -gt "$w" ] && w=${#k}
    done
    echo $((w + 1))
}

# print_grouped <entry>...: "<i>[:<state index>,...]" entries under their kind headings
print_grouped() {
    local entry i kind heading="" w states
    local -a ids=()
    for entry in "$@"; do ids+=("${entry%%:*}"); done
    w=$(name_width "${ids[@]}")
    for entry in "$@"; do
        i=${entry%%:*}
        kind=$(kind_word "${el_key[i]}" s)
        if [ "$kind" != "$heading" ]; then
            printf '%s%s%s\n' "$bold" "$kind" "$plain"
            heading=$kind
        fi
        states=""
        [[ "$entry" == *:* ]] && states=${entry#*:}
        # shellcheck disable=SC2086  # the state indexes, comma-separated
        print_element "$i" "$w" ${states//,/ }
    done
}

# legend: the gallery's line, and what "*" means when one is open
legend() {
    local any=0 i text=""
    for i in "${!el_open[@]}"; do any=1; done
    [ -f "$list_main/mockups/kit/Gallery.qml" ] && text="Gallery: $cmdname open gallery"
    [ "$any" = 1 ] && text="${text:+$text    }* open now"
    [ -z "$text" ] || { echo; echo "$text"; }
}

# find_element <name or part>: its index (a <kind>/<name>, a name, or a unique part)
find_element() {
    local want=$1 i
    local -a exact=() parts=()
    [ -n "${el_index[$want]:-}" ] && { echo "${el_index[$want]}"; return 0; }
    for i in "${el_order[@]}"; do
        # One index per element: a second copy of it (another working tree's) is not another
        [ "${el_index[${el_key[i]}]}" = "$i" ] || continue
        [ "${el_key[i]#*/}" = "$want" ] && exact+=("$i")
        [[ "${el_key[i]}" == *"$want"* ]] && parts+=("$i")
    done
    [ ${#exact[@]} -gt 0 ] && parts=("${exact[@]}")
    case ${#parts[@]} in
        1) echo "${parts[0]}" ;;
        0) echo "mockup.sh: no element matches \"$want\" ($cmdname list)" >&2; return 1 ;;
        *) echo "mockup.sh: \"$want\" matches several elements:" >&2
           for i in "${parts[@]}"; do echo "  ${el_key[i]}" >&2; done
           return 1 ;;
    esac
}

cmd_list() {
    local i j count w line pad word address first
    setup_output
    collect
    if [ $# -eq 0 ]; then
        if [ ${#el_order[@]} -eq 0 ]; then echo "No mockup in $list_main/$base"; return 0; fi
        print_grouped "${el_order[@]}"
        legend
        return 0
    fi
    first=$(find_element "$1") || exit 2
    # Each copy, when working trees hold different ones
    for i in "${el_order[@]}"; do
        [ "${el_key[i]}" = "${el_key[first]}" ] || continue
        line="$(kind_word "${el_key[i]}") ${el_key[i]#*/}"
        [ -n "${el_open[$i]:-}" ] && line="$line (open)"
        wrap "$line — " "  " "${el_desc[i]}"
        [ -z "${el_labels[i]}" ] || wrap "  " "  " "[not merged: ${el_labels[i]}]" "$dim"
        while IFS= read -r line; do
            [ -n "$line" ] && wrap "  " "    " "$line" "$dim"
        done <<< "${el_note[i]}"
        count=${el_state_names[$i,count]:-0}
        w=0
        for ((j = 0; j < count; j++)); do
            [ ${#el_state_names[$i,$j]} -gt "$w" ] && w=${#el_state_names[$i,$j]}
        done
        printf -v pad '%*s' $((w + 4)) ""
        for ((j = 0; j < count; j++)); do
            printf -v line '  %-*s  ' "$w" "${el_state_names[$i,$j]}"
            wrap "$line" "$pad" "${el_state_descs[$i,$j]}"
        done
        word=state
        [[ "${el_key[i]}" == plans/* ]] && word=scene
        # Its address: the name alone, unless another kind has an element of that name
        address=${el_key[i]#*/}
        for j in "${el_order[@]}"; do
            [ "${el_key[j]}" != "${el_key[i]}" ] && [ "${el_key[j]#*/}" = "$address" ] && address=${el_key[i]}
        done
        line="Open: $cmdname open $address"
        [ "$count" -gt 0 ] && line="$line   one $word: $cmdname open $address/${el_state_names[$i,0]}"
        echo "$line"
    done
}

# matches <text> <word>...: whether the text holds every word, in any case
matches() {
    # Lower case by Unicode's rules (Polish letters too), whatever the caller's locale
    local LC_ALL=C.UTF-8
    local text=${1,,} word
    shift
    for word in "$@"; do [[ "$text" == *"${word,,}"* ]] || return 1; done
    return 0
}

cmd_search() {
    local i j count own all word missing
    local -a words=() found=() states missing_words
    read -r -a words <<< "$*"
    [ ${#words[@]} -gt 0 ] || { echo "mockup.sh: search needs a word" >&2; exit 2; }
    setup_output
    collect
    for i in "${el_order[@]}"; do
        own="${el_key[i]#*/} ${el_desc[i]}"
        count=${el_state_names[$i,count]:-0}
        # The element itself matches: shown whole
        if matches "$own" "${words[@]}"; then found+=("$i"); continue; fi
        all=$own
        for ((j = 0; j < count; j++)); do all+=" ${el_state_names[$i,$j]} ${el_state_descs[$i,$j]}"; done
        matches "$all" "${words[@]}" || continue
        # Through its states: those holding a word the element's own text lacks
        missing_words=()
        for word in "${words[@]}"; do matches "$own" "$word" || missing_words+=("$word"); done
        states=()
        for ((j = 0; j < count; j++)); do
            for word in "${missing_words[@]}"; do
                if matches "${el_state_names[$i,$j]} ${el_state_descs[$i,$j]}" "$word"; then states+=("$j"); break; fi
            done
        done
        found+=("$i:$(IFS=,; echo "${states[*]}")")
    done
    if [ ${#found[@]} -eq 0 ]; then
        echo "Nothing matches \"$*\" ($cmdname list shows everything)"
        exit 1
    fi
    print_grouped "${found[@]}"
}

kill_pids() {
    local pid i
    for pid in "$@"; do
        run qs kill --pid "$pid"
    done
    [ "$dry" = 1 ] && return
    for pid in "$@"; do
        for i in $(seq 30); do kill -0 "$pid" 2> /dev/null || break; sleep 0.1; done
    done
}

# parse_address <address>: its element (address_element) and its state or scene
# (address_first, or empty): <element>, <kind>/<name>, <element>/<state>, <kind>/<name>/<state>
parse_address() {
    local -a parts
    address_element="" address_first=""
    IFS=/ read -r -a parts <<< "$1"
    [[ "$1" != */ ]] || usage "\"$1\": a state or scene name after the \"/\""
    case ${#parts[@]} in
        1) address_element=${parts[0]} ;;
        2) if [[ "${parts[0]}" =~ ^(components|views|plans|planning)$ ]]; then address_element=$1
           else address_element=${parts[0]} address_first=${parts[1]}
           fi ;;
        3) [[ "${parts[0]}" =~ ^(components|views|plans|planning)$ ]] \
               || usage "\"$1\": <kind>/<name>/<state>, the kind components, views or plans"
           address_element=${parts[0]}/${parts[1]} address_first=${parts[2]} ;;
        *) usage "\"$1\": <element>, <element>/<state> or <kind>/<name>/<state>" ;;
    esac
    [ -n "$address_element" ] || usage "\"$1\": no element named"
    # The name goes into the command line Hyprland runs through a shell: letters, digits, "_"
    # and "-" only, never a character a shell reads
    [ -z "$address_first" ] || [[ "$address_first" =~ ^[A-Za-z0-9_-]+$ ]] \
        || usage "\"$address_first\": a state or scene name is letters, digits, '_' and '-'"
}

# element_only <command> <address>: the element it names (address_element); a state is refused
element_only() {
    parse_address "$2"
    [ -z "$address_first" ] || usage "$1 takes an element, not one of its states or scenes ($2)"
}

# ---- the tree whose copy is taken (--main, --also) -----------------------------------
# folder_in <tree> <kind>/<name>: the element's folder in that tree (a plan also under the
# old planning/), or nothing
folder_in() {
    local folder=$1/$base/$2
    [ -f "$folder/Mockup.qml" ] && { echo "$folder"; return 0; }
    folder=$1/$base/planning/${2#plans/}
    [[ "$2" == plans/* ]] && [ -f "$folder/Mockup.qml" ] && echo "$folder"
    return 0
}

# changed_in <tree> <folder> [<other tree>]: whether that tree changed the folder (a path in
# it) since it left the main tree's history (or the other tree's): committed, uncommitted or
# untracked. Without git or without a common history: yes. So a tree that only lags behind
# (a pinned tree, a branch not rebased) holds no copy of its own
declare -A tree_base=()
changed_in() {
    local tree=$1 path=${2#"$1"/} other=${3:-$list_main} base other_head
    if [ -z "${tree_base[$tree|$other]+set}" ]; then
        base=""
        if command -v git > /dev/null && other_head=$(git -C "$other" rev-parse -q --verify HEAD 2> /dev/null); then
            base=$(git -C "$tree" merge-base HEAD "$other_head" 2> /dev/null) || base=""
        fi
        tree_base[$tree|$other]=$base
    fi
    base=${tree_base[$tree|$other]}
    [ -n "$base" ] || return 0
    git -C "$tree" diff --quiet "$base" -- "$path" 2> /dev/null || return 0
    [ -n "$(git -C "$tree" ls-files --others --exclude-standard -- "$path" 2> /dev/null)" ]
}

# choose_tree <kind>/<name>: the tree whose copy is taken: the main tree's, unless the --also
# trees that changed it (less those that only lag behind another of them) hold one copy, the same files in each (several trees on one unmerged
# branch); an element the main tree lacks, the one copy the --also trees added. Of the trees
# holding that copy, this tree if it is one, else the first. Prints "<tree>\t<label>\t<the
# other trees' labels>" (no label: the main tree); several different copies: refused
choose_tree() {
    local key=$1 main_folder folder entry tree j picked=-1 others=""
    local -a found=() folders=() copies=()
    main_folder=$(folder_in "$list_main" "$key")
    for entry in "${also_trees[@]}"; do
        tree=$(cd "${entry%=*}" && pwd -P)
        [ "$tree" = "$list_main" ] && continue
        folder=$(folder_in "$tree" "$key")
        [ -n "$folder" ] || continue
        [ -n "$main_folder" ] && diff -r -q "$main_folder" "$folder" > /dev/null 2>&1 && continue
        changed_in "$tree" "$folder" || continue
        found+=("$tree"$'\t'"${entry##*=}")
        folders+=("$folder")
    done
    [ ${#found[@]} -gt 0 ] || { printf '%s\t\t\n' "$list_main"; return 0; }
    # A tree that only lags behind another holding a different copy holds none of its own
    local -a kept_found=() kept_folders=()
    local k lags
    for j in "${!found[@]}"; do
        lags=0
        for k in "${!found[@]}"; do
            [ "$j" != "$k" ] || continue
            diff -r -q "${folders[j]}" "${folders[k]}" > /dev/null 2>&1 && continue
            changed_in "${found[j]%%$'\t'*}" "${folders[j]}" "${found[k]%%$'\t'*}" || { lags=1; break; }
        done
        [ "$lags" = 1 ] && continue
        kept_found+=("${found[j]}")
        kept_folders+=("${folders[j]}")
    done
    found=("${kept_found[@]}") folders=("${kept_folders[@]}")
    # The copies: the first tree of each set of identical folders
    for j in "${!folders[@]}"; do
        local same=0 c
        for c in "${copies[@]}"; do
            diff -r -q "${folders[c]}" "${folders[j]}" > /dev/null 2>&1 && { same=1; break; }
        done
        [ "$same" = 1 ] || copies+=("$j")
    done
    if [ ${#copies[@]} -gt 1 ]; then
        if [ -n "$main_folder" ]; then
            echo "mockup.sh: $key differs from the main tree's in several working trees, each its own way; choose one with --tree:" >&2
        else
            echo "mockup.sh: $key is in several working trees, each its own way; choose one with --tree:" >&2
        fi
        for entry in "${found[@]}"; do echo "  ${entry#*$'\t'}" >&2; done
        exit 2
    fi
    for j in "${!found[@]}"; do
        [ "${found[j]%%$'\t'*}" = "$REPO" ] && picked=$j
    done
    [ "$picked" -ge 0 ] || picked=0
    for j in "${!found[@]}"; do
        [ "$j" = "$picked" ] || others+="${others:+, }${found[j]#*$'\t'}"
    done
    printf '%s\t%s\n' "${found[picked]}" "$others"
}

# across_trees <command> <element>: with --main or --also, the tree whose copy of the element is taken;
# another tree's own tool then runs on the same arguments (without --main and --also)
across_trees() {
    local i chosen tree label others verb=Using
    [ -n "$main_tree" ] || [ ${#also_trees[@]} -gt 0 ] || return 0
    [ "$1" = open ] && verb=Opening
    collect quiet
    i=$(find_element "$2") || exit 2
    chosen=$(choose_tree "${el_key[i]}") || exit 2
    IFS=$'\t' read -r tree label others <<< "$chosen"
    [ -z "$label" ] || echo "$verb the working copy from $label (not merged${others:+; the same in $others})"
    [ "$tree" = "$REPO" ] && return 0
    [ -x "$tree/tests/mockup.sh" ] || { echo "mockup.sh: no tests/mockup.sh in $tree" >&2; exit 2; }
    exec "$tree/tests/mockup.sh" "${pass_args[@]}"
}

# cmd_close [<element>]: by the rule list marks open by (mockups_running): in this tree, or
# with --main or --also in each of those trees, whichever tree's tool started it
cmd_close() {
    local name verb i across=0
    local -a lines=() pids=() trees=("$REPO") named=()
    verb=$([ "$dry" = 1 ] && echo "Would close" || echo Closed)
    if [ -n "$main_tree" ] || [ ${#also_trees[@]} -gt 0 ]; then
        across=1
        mapfile -t trees < <(given_trees)
    fi
    if [ $# -gt 0 ]; then
        element_only close "$1"
        if [ "$across" = 1 ] && [ "$address_element" != gallery ]; then
            [[ "$address_element" != planning/* ]] || { resolve "$address_element"; exit 2; }
            collect quiet
            if i=$(find_element "$address_element" 2> /dev/null); then
                name=${el_key[i]}
            else
                # No tree lists it any more, but it may still run: its whole name, or the
                # name without its kind, among the running ones
                mapfile -t named < <(running "${trees[@]}" | awk -v w="$address_element" '{ n = $2; sub(/^[^\/]*\//, "", n) } $2 == w || n == w { print $2 }' | sort -u)
                [ ${#named[@]} -eq 1 ] || { find_element "$address_element" > /dev/null; exit 2; }
                name=${named[0]}
            fi
        else
            name=$(resolve_or_gallery "$address_element") || exit 2
        fi
        mapfile -t pids < <(running "${trees[@]}" | awk -v n="$name" '$2 == n { print $1 }')
        [ ${#pids[@]} -gt 0 ] || { echo "$name is not running"; return; }
        kill_pids "${pids[@]}"
        echo "$verb $name"
    else
        mapfile -t lines < <(running "${trees[@]}")
        if [ ${#lines[@]} -eq 0 ]; then
            if [ "$across" = 1 ]; then echo "No mockup of these trees is running"; else echo "No mockup of this tree is running"; fi
            return
        fi
        mapfile -t pids < <(printf '%s\n' "${lines[@]}" | awk '{ print $1 }')
        kill_pids "${pids[@]}"
        printf '%s\n' "${lines[@]}" | awk -v w="$verb" '{ print w " " $2 }' | sort -u
    fi
}

# theme_check <name>: "default" or one of the user's theme files, else the list of them
theme_check() {
    local folder=${XDG_CONFIG_HOME:-${HOME:?}/.config}/h2s_shell/themes file
    local -a names=(default)
    [ "$1" = default ] || [ -f "$folder/$1.json" ] && return 0
    for file in "$folder"/*.json; do
        [ -f "$file" ] || continue
        file=${file##*/}
        [ "$file" = default.json ] || names+=("${file%.json}")
    done
    echo "mockup.sh: no theme \"$1\" in $folder; the themes: $(IFS=,; echo "${names[*]}" | sed 's/,/, /g')" >&2
    exit 2
}

cmd_open() {
    local name pids i command first word
    parse_address "$1"
    name=$(resolve_or_gallery "$address_element") || exit 2
    if [ "$name" = gallery ] && [ -n "$address_first" ]; then
        echo "mockup.sh: the gallery has no states: it shows every component and view in all theirs ($cmdname open gallery)" >&2
        exit 2
    fi
    first=$address_first
    # The state or scene must be one about.txt declares (a broken about.txt: the entry says)
    word=state
    [[ "$name" == plans/* ]] && word=scene
    if [ -n "$first" ] && [ "$name" != gallery ] && about_read "$REPO/$base/$name" "$word"; then
        local known=0 n
        for n in "${about_names[@]}"; do [ "$n" = "$first" ] && known=1; done
        if [ "$known" = 0 ]; then
            echo "mockup.sh: $name has no $word \"$first\"; its ${word}s: $(IFS=,; echo "${about_names[*]}" | sed 's/,/, /g')" >&2
            exit 2
        fi
    fi
    [ -z "$theme" ] || theme_check "$theme"
    [[ "$SELF" != *[\"\'\\]* ]] || { echo "mockup.sh: cannot start from a path with quotes or '\\': $SELF" >&2; exit 2; }
    mapfile -t pids < <(pids_of "$name")
    if [ ${#pids[@]} -gt 0 ]; then
        if [ "$restart" = 0 ]; then
            echo "$name is already running (pid ${pids[*]}); --restart starts it again"
            return
        fi
        kill_pids "${pids[@]}"
    fi
    local -a extra=()
    if [ -n "$theme" ]; then extra=("$first" "$theme")
    elif [ -n "$first" ]; then extra=("$first")
    fi
    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl > /dev/null; then
        command="'$SELF' '__exec' '$base' '$name'"
        for i in "${extra[@]}"; do command="$command '$i'"; done
        run hyprctl dispatch "hl.dsp.exec_cmd(\"$command\")"
    elif [ "$dry" = 1 ]; then
        printf 'setsid -f %q __exec %q %q' "$SELF" "$base" "$name"
        for i in "${extra[@]}"; do printf ' %q' "$i"; done
        printf ' >/dev/null 2>&1 </dev/null\n'
    else
        setsid -f "$SELF" __exec "$base" "$name" "${extra[@]}" > /dev/null 2>&1 < /dev/null
    fi
    [ "$dry" = 1 ] && return
    for i in $(seq 50); do
        mapfile -t pids < <(pids_of "$name")
        [ ${#pids[@]} -gt 0 ] && { echo "Opened $name (pid ${pids[*]})"; return; }
        sleep 0.1
    done
    echo "mockup.sh: started $name, but it is not in qs list yet (it may have failed: see its log)" >&2
    exit 1
}

# ---- review ---------------------------------------------------------------------------
# kitty_graphics: whether this terminal draws the kitty graphics protocol
kitty_graphics() {
    [ -n "${KITTY_WINDOW_ID:-}" ] && return 0
    [ "${TERM:-}" = xterm-kitty ] && return 0
    # The protocol's query, followed by a primary device attributes request that every
    # terminal answers: a terminal that draws the protocol answers the query first
    [ -t 0 ] && [ -t 1 ] || return 1
    { : < /dev/tty; } 2> /dev/null || return 1
    local saved reply=""
    saved=$(stty -g < /dev/tty 2> /dev/null) || return 1
    stty -icanon -echo min 0 time 10 < /dev/tty 2> /dev/null || return 1
    printf '\033_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\033\\\033[c' > /dev/tty
    IFS= read -r -d c -t 1 reply < /dev/tty
    stty "$saved" < /dev/tty 2> /dev/null
    [[ "$reply" == *"_Gi=31;OK"* ]]
}

# icat_command: the image display's command, or nothing
icat_command() {
    if command -v kitten > /dev/null; then echo kitten icat
    elif command -v kitty > /dev/null; then echo kitty +kitten icat
    fi
}

# no_baseline_for_plan <kind>/<name> <command>: a plan is refused (it has no baseline), and
# the gallery (made of baselined parts)
no_baseline_for_plan() {
    if [ "$1" = gallery ]; then
        echo "mockup.sh: the gallery has no baseline of its own: it is made of the components and views, each with its own; nothing to $2" >&2
        exit 2
    fi
    [[ "$1" == plans/* ]] || return 0
    echo "mockup.sh: $1 is a plan: plans have no baseline (they are not tested), nothing to $2" >&2
    exit 2
}

cmd_review() {
    local name shots_root tree_key run_id run inline=0 icat="" folder one label kind file
    local -a images=()
    name=$(resolve_or_gallery "$1") || exit 2
    no_baseline_for_plan "$name" review
    run "$REPO/tests/run-mockups.sh" --compare "$name"
    shots_root=${H2S_MOCKUP_SHOTS:-${XDG_CACHE_HOME:-${HOME:?}/.cache}/h2s-shell-mockups}
    [ "$base" = mockups ] || shots_root=$shots_root/fixtures
    tree_key=$(printf '%s' "$REPO" | sha256sum | cut -c 1-16)
    if ! { read -r run_id < "$shots_root/$name/last-run-$tree_key"; } 2> /dev/null \
        || ! [[ "$run_id" =~ ^[0-9]{8}-[0-9]{6}-[0-9]+$ ]] || [ ! -d "$shots_root/$name/$run_id" ]; then
        echo "No run of $name from this tree in $shots_root/$name: nothing to review"
        return 2
    fi
    run=$shots_root/$name/$run_id
    # Each differing state's old, new and diff; with no baseline, the new shots
    for folder in "$run"/[0-9][0-9]-*/; do
        [ -f "$folder/new.png" ] || continue
        one=${folder%/}
        one=${one##*/}
        for kind in old new diff; do
            [ -f "$folder/$kind.png" ] && images+=("$name, state ${one#[0-9][0-9]-}: $kind|$folder$kind.png")
        done
    done
    if [ ${#images[@]} -eq 0 ] && [ ! -f "${H2S_MOCKUP_BASELINES:-$REPO/$base}/$name/baseline/manifest.txt" ]; then
        for file in "$run"/[0-9][0-9]-*.png; do
            [ -f "$file" ] || continue
            [[ "$file" == *-review.png ]] && continue
            one=${file##*/}
            one=${one%.png}
            images+=("$name, state ${one#[0-9][0-9]-}: new (no baseline)|$file")
        done
    fi
    if [ ${#images[@]} -eq 0 ]; then
        echo "No state of $name differs in its last run ($run)"
        return 0
    fi
    if kitty_graphics; then
        icat=$(icat_command)
        if [ -n "$icat" ]; then inline=1
        else echo "(the terminal draws images, but neither kitten nor kitty is here: the paths)"
        fi
    fi
    local entry
    for entry in "${images[@]}"; do
        label=${entry%%|*}
        file=${entry#*|}
        if [ "$inline" = 1 ]; then
            echo "$label"
            # shellcheck disable=SC2086  # the command's words
            if [ "$dry" = 1 ]; then printf '%q ' $icat --align left "$file"; echo
            else $icat --align left "$file"
            fi
        else
            echo "$label: $file"
        fi
    done
}

command=${args[0]:-list}
shorthand=0
case "$command" in
    list | search | help | open | close | review | approve) ;;
    # A first word that is no command: the shorthand for open, if it names an element
    *) command=open; args=(open "${args[@]}"); shorthand=1 ;;
esac
[ -z "$theme" ] || [ "$command" = open ] || usage "--theme is for open"
# The tree whose copy is taken: for a named element, in each tree's own tool
if [[ "$command" =~ ^(open|close|review|approve)$ ]] && [ ${#args[@]} -ge 2 ]; then
    if [ "$command" = open ]; then parse_address "${args[1]}"; else element_only "$command" "${args[1]}"; fi
    # A first word that is neither a command nor part of any element's name
    if [ "$shorthand" = 1 ] && [ "$address_element" != gallery ]; then
        if [ -n "$main_tree" ] || [ ${#also_trees[@]} -gt 0 ]; then
            collect quiet
            keys=$(printf '%s\n' "${el_key[@]}")
        else
            keys=$(all_names)
        fi
        [[ "$keys" == *"${address_element#planning/}"* ]] || usage "\"${args[1]}\" is neither a command nor an element"
    fi
    # close needs no copy: it closes the element in whichever of the trees it runs
    if [ "$command" != close ]; then
        [ "$address_element" = gallery ] || across_trees "$command" "$address_element"
        main_tree="" also_trees=()
    fi
fi

case "$command" in
    help) [ ${#args[@]} -eq 1 ] || usage "help takes nothing more"; help_text ;;
    list) [ ${#args[@]} -le 2 ] || usage "list takes one element at most"; cmd_list "${args[@]:1}" ;;
    search) cmd_search "${args[@]:1}" ;;
    close) [ ${#args[@]} -le 2 ] || usage "close takes one element at most"
        cmd_close "${args[@]:1}" ;;
    open) [ ${#args[@]} -eq 2 ] || usage "open takes one element"
        cmd_open "${args[1]}" ;;
    review) [ ${#args[@]} -eq 2 ] || usage "review takes one element"
        cmd_review "$address_element" ;;
    approve) [ ${#args[@]} -eq 2 ] || usage "approve takes one element"
        name=$(resolve_or_gallery "$address_element") || exit 2
        no_baseline_for_plan "$name" approve
        run "$REPO/tests/run-mockups.sh" --approve "$name" ;;
esac
