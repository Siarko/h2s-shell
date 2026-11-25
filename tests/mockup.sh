#!/usr/bin/env bash
# The mockups on a screen (mockup.qml, mockups/<kind>/<name>/Mockup.qml), for the maintainer:
# list them, open and close them on this machine's display, review a comparison's images and
# approve them. The headless runs are tests/run-mockups.sh's.
#
#   tests/mockup.sh [-n] [list]           the tree's mockups, their kind and title; "*" marks
#                                         a running one
#   tests/mockup.sh [-n] [open] <name> [--state <s> | --scene <s>] [--restart]
#                                         start the mockup on the display (a component or view
#                                         on a state, a plan on a scene); if it already runs,
#                                         say so, or with --restart close it and start it again
#   tests/mockup.sh [-n] close [<name>]   close that mockup (with no name: every running
#                                         mockup of this tree)
#   tests/mockup.sh [-n] review <name>    compare it with its baseline (tests/run-mockups.sh
#                                         --compare), then show each differing state's old, new
#                                         and diff images
#   tests/mockup.sh [-n] approve <name>   the reviewed run becomes the baseline
#                                         (tests/run-mockups.sh --approve)
#     <name>        <kind>/<name> (components, views, plans), or a unique part of one
#                   (e.g. "pill"); planning/, the plans' old folder, is refused
#     -n            print the commands instead of running them (review still shows the images
#                   of the last run there is)
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
    sed -n '6,22p' "$SELF" >&2
    exit 2
}

dry=0
restart=0
first=""
first_option=""
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
        -h | --help) sed -n '2,40p' "$SELF"; exit 0 ;;
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

# title <kind>/<name>: MOCKUP.md's first heading, else the first comment line of Mockup.qml
title() {
    local folder=$REPO/$base/$1 t=""
    [ -f "$folder/MOCKUP.md" ] && t=$(grep -m1 '^#' "$folder/MOCKUP.md" | sed 's/^#* *//')
    [ -n "$t" ] || t=$(grep -m1 -E '^[[:space:]]*//' "$folder/Mockup.qml" | sed -E 's|^[[:space:]]*//+[[:space:]]*||')
    echo "$t"
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

cmd_list() {
    local n kind mark t running_now count=0
    running_now=$(running)
    while IFS= read -r n; do
        count=$((count + 1))
        kind=${n%%/*}
        kind=${kind%s}
        mark=" "
        awk -v n="$n" '$2 == n { found = 1 } END { exit !found }' <<< "$running_now" && mark="*"
        t=$(title "$n")
        printf '%s %-36s %-9s %s\n' "$mark" "$n" "$kind" "$t"
    done < <(all_names)
    [ "$count" -gt 0 ] || echo "No mockup in $REPO/$base"
    # A tree still in the old layout: its plans would be missing without a word
    [ ! -d "$REPO/$base/planning" ] \
        || echo "mockup.sh: $base/planning/ is the plans' old folder, not listed: git mv it to $base/plans/" >&2
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

cmd_review() {
    local name shots_root tree_key run_id run inline=0 icat="" folder one label kind file
    local -a images=()
    name=$(resolve "$1") || exit 2
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

case "${args[0]:-list}" in
    list) [ ${#args[@]} -eq 1 ] || [ ${#args[@]} -eq 0 ] || usage; cmd_list ;;
    close) [ ${#args[@]} -le 2 ] || usage; cmd_close "${args[@]:1}" ;;
    open) [ ${#args[@]} -eq 2 ] || { echo "mockup.sh: open needs one name" >&2; exit 2; }
        cmd_open "${args[1]}" ;;
    review) [ ${#args[@]} -eq 2 ] || { echo "mockup.sh: review needs one name" >&2; exit 2; }
        cmd_review "${args[1]}" ;;
    approve) [ ${#args[@]} -eq 2 ] || { echo "mockup.sh: approve needs one name" >&2; exit 2; }
        name=$(resolve "${args[1]}") || exit 2
        run "$REPO/tests/run-mockups.sh" --approve "$name" ;;
    *) [ ${#args[@]} -eq 1 ] || usage; cmd_open "${args[0]}" ;;
esac
