#!/usr/bin/env bash
# The mockups on a screen (mockup.qml, mockups/<kind>/<name>/Mockup.qml), for the maintainer:
# list them, open and close them on this machine's display, review a comparison's images and
# approve them. The headless runs are tests/run-mockups.sh's.
#
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
#   tests/mockup.sh [-n] [open] <name> [--state <s> | --scene <s>] [--restart]
#                                         start the mockup on the display (a component or view
#                                         on a state, a plan on a scene); if it already runs,
#                                         say so, or with --restart close it and start it again
#   tests/mockup.sh [-n] close [<name>]   close that mockup (with no name: every running
#                                         mockup of this tree)
#   tests/mockup.sh [-n] review <name>    compare it with its baseline (tests/run-mockups.sh
#                                         --compare), then show each differing state's old, new
#                                         and diff images (not a plan: it has no baseline)
#   tests/mockup.sh [-n] approve <name>   the reviewed run becomes the baseline
#                                         (tests/run-mockups.sh --approve; not a plan)
#     <name>        <kind>/<name> (components, views, plans), or a unique part of one
#                   (e.g. "pill"); planning/, the plans' old folder, is refused
#     -n            print the commands instead of running them (review still shows the images
#                   of the last run there is)
#     --main <tree> list, search: the elements of that shell tree instead of this one's
#     --also <tree>=<label>
#                   list, search: also the elements found only in that tree (in neither the
#                   main tree nor an earlier --also), marked [not merged: <label>]; a tree in
#                   the old layout (mockups/planning/, no about.txt) is read as well
#
# list and search wrap to the terminal's width (COLUMNS, else the terminal's, else 80), with
# bold headings only on a terminal (and never with NO_COLOR); the commands they suggest name
# H2S_MOCKUP_COMMAND (tests/mockup.sh by default; the metadata forwarder sets its own).
#
# open starts the entry through Hyprland's exec when Hyprland is there (the window gets the
# session's environment), else detached with setsid. Either way the command it starts is this
# script again (__exec), which drops every H2S_* variable it inherited (the shell's own, such
# as H2S_SHELL_MODULES, and a stray H2S_MOCKUP_SHOT), then runs
#   H2S_MOCKUP=<kind>/<name> [H2S_MOCKUP_STATE=<s> | H2S_MOCKUP_SCENE=<s>] qs -p <tree>/mockup.qml
#
# A running mockup is an instance in `qs list --all` whose config path is this tree's
# mockup.qml, and its name what `qs ipc --pid <pid> call mockup name` answers: close never
# picks by a pattern, and never the shell or another tree's mockups.
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
# __exec <base> <kind>/<name> [<state or scene>]: drop the inherited H2S_* variables, run the
# entry
if [ "${1:-}" = __exec ] || { [ "${1:-}" = -n ] && [ "${2:-}" = __exec ]; }; then
    dry=0
    [ "$1" = -n ] && { dry=1; shift; }
    shift
    [ $# -ge 2 ] || { echo "mockup.sh: __exec <base> <kind>/<name> [<state or scene>]" >&2; exit 2; }
    exec_base=$1 name=$2 first=${3:-}
    [ -z "$first" ] || [[ "$first" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "mockup.sh: __exec: state or scene '$first'" >&2; exit 2; }
    [[ "$exec_base" =~ ^(mockups|tests/fixtures/mockups)$ ]] || { echo "mockup.sh: __exec: base '$exec_base'" >&2; exit 2; }
    [[ "$name" =~ ^(components|views|plans)/[a-z0-9-]+$ ]] || { echo "mockup.sh: __exec: name '$name'" >&2; exit 2; }
    unset_args=()
    while IFS= read -r variable; do
        unset_args+=(-u "$variable")
    done < <(compgen -e | grep -E '^H2S_' || true)
    set_args=(H2S_MOCKUP="$name")
    # A plan opens on a scene, a component or a view on a state
    if [ -n "$first" ]; then
        if [[ "$name" == plans/* ]]; then set_args+=(H2S_MOCKUP_SCENE="$first"); else set_args+=(H2S_MOCKUP_STATE="$first"); fi
    fi
    [ "$exec_base" = mockups ] || set_args+=(H2S_MOCKUP_BASE="$exec_base")
    command=(env "${unset_args[@]}" "${set_args[@]}" qs -p "$ENTRY")
    if [ "$dry" = 1 ]; then printf '%q ' "${command[@]}"; echo; exit 0; fi
    exec "${command[@]}"
fi

usage() {
    awk '/^#   tests\/mockup.sh/ { on = 1 } on && /^#$/ { exit } on' "$SELF" >&2
    exit 2
}

dry=0
restart=0
first=""
first_option=""
main_tree=""
also_trees=()
args=()
while [ $# -gt 0 ]; do
    case "$1" in
        -n | --dry-run) dry=1; shift ;;
        --restart) restart=1; shift ;;
        --state | --scene)
            [ -z "$first_option" ] || { echo "mockup.sh: one of --state and --scene" >&2; exit 2; }
            first_option=${1#--}
            first=${2:-}
            # The name goes into the command line Hyprland runs through a shell: letters,
            # digits, "_" and "-" only, never a character a shell reads
            [[ "$first" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "mockup.sh: $1 needs a $first_option name of letters, digits, '_' and '-'" >&2; exit 2; }
            shift 2
            ;;
        --main)
            main_tree=${2:-}
            [ -d "$main_tree" ] || { echo "mockup.sh: --main needs a shell tree's folder" >&2; exit 2; }
            shift 2
            ;;
        --also)
            [[ "${2:-}" =~ ^(.+)=([A-Za-z0-9._-]+)$ ]] && [ -d "${BASH_REMATCH[1]}" ] \
                || { echo "mockup.sh: --also needs <tree folder>=<label> (a label of letters, digits, '.', '_' and '-')" >&2; exit 2; }
            also_trees+=("$2")
            shift 2
            ;;
        -h | --help) awk 'NR > 1 && /^set -uo/ { exit } NR > 1' "$SELF"; exit 0 ;;
        -*) echo "mockup.sh: unknown option $1" >&2; usage ;;
        *) args+=("$1"); shift ;;
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
    local -a matches=()
    [ -n "$want" ] || { echo "mockup.sh: an empty name" >&2; return 1; }
    if [[ "$want" == planning/* ]]; then
        echo "mockup.sh: \"$want\": mockups/planning/ is now mockups/plans/ (git mv mockups/planning/${want#planning/} mockups/plans/${want#planning/}), the name plans/${want#planning/}" >&2
        return 1
    fi
    while IFS= read -r n; do
        [ "$n" = "$want" ] && { echo "$n"; return 0; }
        [[ "$n" == *"$want"* ]] && matches+=("$n")
    done < <(all_names)
    case ${#matches[@]} in
        1) echo "${matches[0]}" ;;
        0) echo "mockup.sh: no mockup matches \"$want\" (tests/mockup.sh list)" >&2; return 1 ;;
        *) echo "mockup.sh: \"$want\" matches several mockups:" >&2; printf '  %s\n' "${matches[@]}" >&2; return 1 ;;
    esac
}

# instances: this tree's running entries, "<pid> <config path>" from `qs list --all`
instances() {
    local entry_real
    entry_real=$(readlink -f "$ENTRY")
    qs list --all 2> /dev/null | awk -v a="$ENTRY" -v b="$entry_real" '
        /^[[:space:]]*Process ID:/ { pid = $NF }
        /^[[:space:]]*Config path:/ {
            path = $0
            sub(/^[[:space:]]*Config path:[[:space:]]*/, "", path)
            if (pid ~ /^[0-9]+$/ && (path == a || path == b)) print pid
            pid = ""
        }
        /^Instance / { pid = "" }'
}

# running: "<pid> <kind>/<name>" for each running mockup of this tree, its name asked over IPC
running() {
    local pid name
    while IFS= read -r pid; do
        name=$(qs ipc --pid "$pid" call mockup name 2> /dev/null | tr -d '[:space:]')
        [[ "$name" =~ ^(components|views|plans)/[a-z0-9-]+$ ]] && echo "$pid $name"
    done < <(instances)
}

pids_of() { running | awk -v n="$1" '$2 == n { print $1 }'; }

# ---- list and search ------------------------------------------------------------------
# The elements of the main tree (this one, or --main), then those found only in an --also
# tree, one entry each by <kind>/<name>: el_key, el_desc (or what is wrong with about.txt),
# el_note (more errors, or the old layout), el_trees (the trees holding it, "|"-joined),
# el_labels (the --also labels; none for the main tree), and its states or scenes in
# el_state_names[<i>,<j>] and el_state_descs[<i>,<j>] (el_state_names[<i>,count] of them)
declare -a el_key=() el_desc=() el_note=() el_trees=() el_labels=()
declare -A el_index=() el_state_names=() el_state_descs=()
cmdname=${H2S_MOCKUP_COMMAND:-tests/mockup.sh}

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
        if [ -n "${el_index[$key]:-}" ]; then
            i=${el_index[$key]}
            # Only in working trees so far: one more tree holding it
            if [ -n "${el_labels[i]}" ] && [ -n "$label" ]; then
                el_labels[i]="${el_labels[i]}, $label"
                el_trees[i]="${el_trees[i]}|$tree"
            fi
            continue
        fi
        i=${#el_key[@]}
        el_index[$key]=$i
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

# mark_open: el_open[i]=1 for each element open in one of its trees, asked once of
# `qs list --all` and each instance of a known tree's entry over IPC
declare -A el_open=()
mark_open() {
    local -A entry_of=() open=()
    local i tree pid path name t
    for i in "${!el_key[@]}"; do
        IFS='|' read -r -a trees_of <<< "${el_trees[i]}"
        for tree in "${trees_of[@]}"; do
            entry_of[$tree/mockup.qml]=$tree
            entry_of[$(readlink -f "$tree/mockup.qml")]=$tree
        done
    done
    while IFS=$'\t' read -r pid path; do
        tree=${entry_of[$path]:-}
        [ -n "$tree" ] || continue
        name=$(qs ipc --pid "$pid" call mockup name 2> /dev/null | tr -d '[:space:]')
        name=${name/#planning\//plans/}
        [[ "$name" =~ ^(components|views|plans)/[a-z0-9-]+$ ]] && open[$tree|$name]=1
    done < <(qs list --all 2> /dev/null | awk '
        /^[[:space:]]*Process ID:/ { pid = $NF }
        /^[[:space:]]*Config path:/ {
            path = $0
            sub(/^[[:space:]]*Config path:[[:space:]]*/, "", path)
            if (pid ~ /^[0-9]+$/) print pid "\t" path
            pid = ""
        }
        /^Instance / { pid = "" }')
    for i in "${!el_key[@]}"; do
        IFS='|' read -r -a trees_of <<< "${el_trees[i]}"
        for t in "${trees_of[@]}"; do
            [ -n "${open[$t|${el_key[i]}]:-}" ] && el_open[$i]=1
        done
    done
    return 0
}

# collect: every element, main tree and --also trees, sorted (el_order) by kind and name
collect() {
    local entry
    list_main=$(cd "${main_tree:-$REPO}" && pwd -P)
    add_tree "$list_main"
    for entry in "${also_trees[@]}"; do
        add_tree "$(cd "${entry%=*}" && pwd -P)" "${entry##*=}"
    done
    mapfile -t el_order < <(for i in "${!el_key[@]}"; do
        k=${el_key[i]}
        case ${k%%/*} in components) r=1 ;; views) r=2 ;; *) r=3 ;; esac
        echo "$r ${k#*/} $i"
    done | sort -k1,1n -k2,2 | awk '{ print $3 }')
    mark_open
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
    local i j count w line pad word option
    setup_output
    collect
    if [ $# -eq 0 ]; then
        if [ ${#el_order[@]} -eq 0 ]; then echo "No mockup in $list_main/$base"; return 0; fi
        print_grouped "${el_order[@]}"
        legend
        return 0
    fi
    i=$(find_element "$1") || exit 2
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
    word=state option=--state
    [[ "${el_key[i]}" == plans/* ]] && word=scene option=--scene
    line="Open: $cmdname open ${el_key[i]}"
    [ "$count" -gt 0 ] && line="$line   one $word: $cmdname open ${el_key[i]} $option ${el_state_names[$i,0]}"
    echo "$line"
}

# matches <text> <word>...: whether the text holds every word, in any case
matches() {
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

cmd_close() {
    local name verb lines pids
    verb=$([ "$dry" = 1 ] && echo "Would close" || echo Closed)
    if [ $# -gt 0 ]; then
        name=$(resolve "$1") || exit 2
        mapfile -t pids < <(pids_of "$name")
        [ ${#pids[@]} -gt 0 ] || { echo "$name is not running"; return; }
        kill_pids "${pids[@]}"
        echo "$verb $name"
    else
        mapfile -t lines < <(running)
        [ ${#lines[@]} -gt 0 ] || { echo "No mockup of this tree is running"; return; }
        mapfile -t pids < <(printf '%s\n' "${lines[@]}" | awk '{ print $1 }')
        kill_pids "${pids[@]}"
        printf '%s\n' "${lines[@]}" | awk -v w="$verb" '{ print w " " $2 }' | sort -u
    fi
}

cmd_open() {
    local name pids i command
    name=$(resolve "$1") || exit 2
    # A plan has scenes, a component or a view states: the other option is a mistake
    if [[ "$name" == plans/* ]] && [ "$first_option" = state ]; then
        echo "mockup.sh: $name is a plan: it has scenes (--scene), not states" >&2; exit 2
    elif [[ "$name" != plans/* ]] && [ "$first_option" = scene ]; then
        echo "mockup.sh: $name is a ${name%%s/*}: it has states (--state), not scenes" >&2; exit 2
    fi
    [[ "$SELF" != *[\"\'\\]* ]] || { echo "mockup.sh: cannot start from a path with quotes or '\\': $SELF" >&2; exit 2; }
    mapfile -t pids < <(pids_of "$name")
    if [ ${#pids[@]} -gt 0 ]; then
        if [ "$restart" = 0 ]; then
            echo "$name is already running (pid ${pids[*]}); --restart starts it again"
            return
        fi
        kill_pids "${pids[@]}"
    fi
    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl > /dev/null; then
        command="'$SELF' '__exec' '$base' '$name'"
        [ -z "$first" ] || command="$command '$first'"
        run hyprctl dispatch "hl.dsp.exec_cmd(\"$command\")"
    elif [ "$dry" = 1 ]; then
        printf 'setsid -f %q __exec %q %q%s >/dev/null 2>&1 </dev/null\n' "$SELF" "$base" "$name" "${first:+ $first}"
    else
        setsid -f "$SELF" __exec "$base" "$name" ${first:+"$first"} > /dev/null 2>&1 < /dev/null
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

# no_baseline_for_plan <kind>/<name> <command>: a plan is refused (it has no baseline)
no_baseline_for_plan() {
    [[ "$1" == plans/* ]] || return 0
    echo "mockup.sh: $1 is a plan: plans have no baseline (they are not tested), nothing to $2" >&2
    exit 2
}

cmd_review() {
    local name shots_root tree_key run_id run inline=0 icat="" folder one label kind file
    local -a images=()
    name=$(resolve "$1") || exit 2
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

if [ -n "$main_tree" ] || [ ${#also_trees[@]} -gt 0 ]; then
    case "${args[0]:-list}" in
        list | search) ;;
        *) echo "mockup.sh: --main and --also are for list and search" >&2; exit 2 ;;
    esac
fi

case "${args[0]:-list}" in
    list) [ ${#args[@]} -le 2 ] || usage; cmd_list "${args[@]:1}" ;;
    search) cmd_search "${args[@]:1}" ;;
    close) [ ${#args[@]} -le 2 ] || usage; cmd_close "${args[@]:1}" ;;
    open) [ ${#args[@]} -eq 2 ] || { echo "mockup.sh: open needs one name" >&2; exit 2; }
        cmd_open "${args[1]}" ;;
    review) [ ${#args[@]} -eq 2 ] || { echo "mockup.sh: review needs one name" >&2; exit 2; }
        cmd_review "${args[1]}" ;;
    approve) [ ${#args[@]} -eq 2 ] || { echo "mockup.sh: approve needs one name" >&2; exit 2; }
        name=$(resolve "${args[1]}") || exit 2
        no_baseline_for_plan "$name" approve
        run "$REPO/tests/run-mockups.sh" --approve "$name" ;;
    *) [ ${#args[@]} -eq 1 ] || usage; cmd_open "${args[0]}" ;;
esac
