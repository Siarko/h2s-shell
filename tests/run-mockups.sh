#!/usr/bin/env bash
# Runs mockups (mockup.qml, mockups/<kind>/<name>/Mockup.qml) headless: each in a private
# headless compositor of its own (tests/headless.sh), side by side, stepping through its
# scenes over IPC.
#
#   tests/run-mockups.sh --load-only [<kind>/<name>…]   every scene is reached and nothing errs
#   tests/run-mockups.sh --shoot [<kind>/<name>…]       the same, and a PNG of each scene
#   tests/run-mockups.sh -j <n> …                       at most <n> mockups at once (default:
#                                                       half the processors, at most 16, and
#                                                       no more than memory allows)
#
# With no name: every component and view mockup (mockups/components/*, mockups/views/*).
# A planning mockup (mockups/planning/*) runs only when it is named. H2S_MOCKUP_BASE=
# tests/fixtures/mockups takes the runners' fixture mockups instead (the self-test's).
#
# A mockup passes when its entry reached every scene (a MOCKUP-SHOT line for each, in order,
# then MOCKUP-DONE) and exited 0, with no MOCKUP-ERROR, no TypeError or ReferenceError, and
# no line of the log naming the mockup's own folder (a QML warning from its files). With
# --shoot, each scene is cropped to the subject's bounds the entry gives (grim -g), made
# smaller losslessly (magick -strip, compression level 9), and written as
# <NN>-<scene>.png into
#   ${H2S_MOCKUP_SHOTS:-${XDG_CACHE_HOME:-~/.cache}/h2s-shell-mockups}/[fixtures/]<kind>/<name>/<run>/
# (<run>: the UTC date and time and this runner's pid). Of each mockup's runs the newest 20
# are kept and any younger than a day; then, while the runs together hold more than 500 MB
# (H2S_MOCKUP_SHOTS_LIMIT_MB), the oldest go; never this run or another runner's still going
# (the pid in its name a live run-mockups.sh). A mockup that is NOT RUN leaves no shot.
#
# The environment is fixed, so that a scene draws the same each time, given a mockup that
# keeps no time of its own (checked in its Mockup.qml, for components and views: no Timer,
# no read of the clock, no literal duration; mockups/kit/MockupWindow.qml):
#   - the renderer: Mesa's llvmpipe (software OpenGL) under Qt Quick's normal renderer
#     (QSG_RHI_BACKEND=opengl, LIBGL_ALWAYS_SOFTWARE=1, GALLIUM_DRIVER=llvmpipe), which draws
#     ShaderEffect, MultiEffect and layer.effect, and needs no GPU; a run whose log does not
#     name llvmpipe as the OpenGL renderer (QSG_INFO's line) is NOT RUN.
#     H2S_MOCKUP_RENDERER=software takes Qt Quick's software backend instead
#     (QT_QUICK_BACKEND=software), which draws none of those effects: for telling a
#     renderer's fault from a mockup's, never for a baseline;
#   - QT_HASH_SEED=0: the order in which glyphs go into the texture atlas follows Qt's hash
#     seed, random per process, and with it a few pixels of text under OpenGL;
#   - QT_SCALE_FACTOR=1, QT_ENABLE_HIGHDPI_SCALING=0, QT_FONT_DPI=96, TZ=UTC,
#     LANG=en_US.UTF-8;
#   - the compositor's output pinned to 1920x1200 at scale 1 (wlr-randr).
#
# Needs Quickshell, labwc, setpriv, setsid, timeout, grim, wlr-randr and magick, taken as the
# other runners take theirs (tests/lock/resolve.sh, the mockups need: the pinned
# tests/lock/tools.nix where there is a `nix` command, else PATH). Each Quickshell and its
# compositor run under the memory cap (tests/memory-cap.sh).
#
# Ends with a line per mockup: PASS, FAIL with the reasons, or NOT RUN with the reason.
# Exit status: 0 when every mockup passed, 1 when one failed, 2 when one could not be run
# (and none failed), the runner could not be set up (a missing tool is named), a name is
# not a mockup, or there was no mockup to run.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd -P)
# shellcheck disable=SC2034  # read by tests/headless.sh
HEADLESS_NAME=run-mockups.sh
# shellcheck disable=SC2034  # read by tests/headless.sh
HEADLESS_NEED=mockups

usage() { echo "usage: tests/run-mockups.sh --load-only | --shoot [-j <mockups at once>] [<kind>/<name>…]" >&2; exit 2; }
mode=""
jobs=""
while [ $# -gt 0 ]; do
    case "$1" in
        --load-only | --shoot)
            [ -z "$mode" ] || usage
            mode=${1#--}
            shift
            ;;
        -j)
            jobs=${2:-}
            [[ "$jobs" =~ ^[1-9][0-9]*$ ]] || { echo "run-mockups.sh: -j needs a number above 0" >&2; exit 2; }
            shift 2
            ;;
        -*) usage ;;
        *) break ;;
    esac
done
[ -n "$mode" ] || usage

base=${H2S_MOCKUP_BASE:-mockups}
case "$base" in
    mockups | tests/fixtures/mockups) ;;
    *) echo "run-mockups.sh: H2S_MOCKUP_BASE is '$base': mockups or tests/fixtures/mockups" >&2; exit 2 ;;
esac
renderer=${H2S_MOCKUP_RENDERER:-llvmpipe}
case "$renderer" in
    llvmpipe) renderer_env=(QSG_RHI_BACKEND=opengl LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe QSG_INFO=1) ;;
    software) renderer_env=(QT_QUICK_BACKEND=software) ;;
    *) echo "run-mockups.sh: H2S_MOCKUP_RENDERER is '$renderer': software or llvmpipe" >&2; exit 2 ;;
esac

# ---- One mockup, here (started by the runner below, which printed the tools) ------------
# Only when this runner's parent is the runner that started it (H2S_MOCKUP_ONE is
# "<its pid>:<kind>/<name>:<shots folder or ->"): a variable inherited from elsewhere does
# not turn a whole run into one mockup
one_mark=${H2S_MOCKUP_ONE:-}
if [ -n "$one_mark" ] && [ "${one_mark%%:*}" = "$PPID" ]; then
    one_mark=${one_mark#*:}
    name=${one_mark%%:*}
    shots=${one_mark#*:}
    [ "$shots" != - ] || shots=""
    # shellcheck source=headless.sh
    source "$REPO/tests/headless.sh"
    started=$SECONDS

    # not_run <reason>: the verdict line, and the status. What it shot goes: a picture from a
    # run that is not a test's must never be taken for one
    not_run() {
        [ -n "$shots" ] && rm -rf -- "$shots"
        echo "NOT RUN  $name — $*"
        exit 2
    }
    reasons=()

    # complete_log: the entry's log up to its last full line (a line still being written is
    # left for the next look)
    complete_log() {
        local text
        text=$(cat -- "$log"; echo .)
        text=${text%.}
        case "$text" in
            *$'\n') ;;
            *$'\n'*) text=${text%$'\n'*}$'\n' ;;
            *) text="" ;;
        esac
        printf '%s' "$text"
    }
    # renderer_ok: the entry's OpenGL renderer is llvmpipe (QSG_INFO's line: "OpenGL VENDOR:
    # Mesa RENDERER: llvmpipe (LLVM …, 256 bits) VERSION: …"), or the renderer is the
    # software backend; asked once a window was drawn, before its first shot is taken
    renderer_ok() { [ "$renderer" != llvmpipe ] || grep -q 'RENDERER: llvmpipe' "$log"; }
    renderer_not_ok() {
        local gl
        gl=$(sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -o 'OpenGL VENDOR: .*' | head -n 1)
        not_run "the renderer is not llvmpipe (${gl:-no OpenGL renderer named in the log}): Mesa's llvmpipe is not there, or another OpenGL driver was taken"
    }

    # The mockup keeps no time of its own (components and views): what its scene shows must
    # not depend on when the shot is taken. Its own file only; the shell's components take
    # their durations from Theme, which the entry makes instant
    if [[ "$name" != planning/* ]]; then
        source_file=$REPO/$base/$name/Mockup.qml
        code=$(sed 's|//.*$||' "$source_file")
        grep -q -E '(^|[^A-Za-z0-9_.])Timer[[:space:]]*\{' <<< "$code" && reasons+=("Mockup.qml has a Timer: a scene is set by the kit, never by time")
        grep -q -E 'Date\.now[[:space:]]*\(|new[[:space:]]+Date[[:space:]]*\([[:space:]]*\)' <<< "$code" \
            && reasons+=("Mockup.qml reads the clock (Date.now(), new Date()): a time shown is a fixed value (MockupWindow.now)")
        grep -q -E '(duration|interval)[[:space:]]*:[[:space:]]*[0-9]' <<< "$code" \
            && reasons+=("Mockup.qml has a literal duration: animations take Theme's durations, which the entry makes instant")
    fi

    headless_setup
    # The output's size and scale, pinned: the window must fit, and a scale other than 1
    # would scale the shots
    output=$("${isolated[@]}" WAYLAND_DISPLAY=wayland-0 timeout 10 "$LOCKTEST_WLR_RANDR" 2> "$work/wlr-randr.log" | awk '/^[^ ]/ { print $1; exit }')
    [ -n "$output" ] || not_run "wlr-randr names no output of the headless compositor: $(head -c 300 "$work/wlr-randr.log")"
    "${isolated[@]}" WAYLAND_DISPLAY=wayland-0 timeout 10 "$LOCKTEST_WLR_RANDR" --output "$output" --custom-mode 1920x1200 --scale 1 \
        > "$work/wlr-randr.log" 2>&1 || not_run "wlr-randr could not pin the output to 1920x1200 at scale 1: $(head -c 300 "$work/wlr-randr.log")"

    log=$work/mockup.log
    : > "$log"
    memory_cap_wrap quickshell
    headless_cap_unit=$MEMORY_CAP_UNIT
    # Above the entry's own limit on the shots (60 s); labwc's (540 s) outlasts this
    "${MEMORY_CAP_PREFIX[@]}" "${isolated[@]}" "${renderer_env[@]}" QT_SCALE_FACTOR=1 QT_ENABLE_HIGHDPI_SCALING=0 \
        QT_FONT_DPI=96 QT_HASH_SEED=0 TZ=UTC H2S_MOCKUP="$name" H2S_MOCKUP_BASE="$base" H2S_MOCKUP_SHOT=1 \
        WAYLAND_DISPLAY=wayland-0 QT_QPA_PLATFORM=wayland \
        "$SETPRIV" --no-new-privs timeout -k 5 120 "$LOCKTEST_QS" -p "$REPO/mockup.qml" > "$log" 2>&1 < /dev/null &
    # (headless_cleanup ends it when this is interrupted)
    quickshell_pid=$!

    # Each new MOCKUP-SHOT line: the scene shot (--shoot), then `ipc call mockup next`
    # addressed to this instance; until the entry has ended (it ends itself on an error or
    # after its limit; the deadline here only guards a hang of this loop)
    answered=0
    instance=""
    deadline=$((SECONDS + 150))
    while kill -0 "$quickshell_pid" 2> /dev/null && [ $SECONDS -lt $deadline ]; do
        mapfile -t lines < <(complete_log | grep -o 'MOCKUP-SHOT .*')
        if [ ${#lines[@]} -gt "$answered" ]; then
            [ -n "$instance" ] || instance=$(sed -n 's|.*/by-id/\([a-z0-9]*\)/log\.qslog.*|\1|p' "$log" | head -n 1)
            if [ -z "$instance" ]; then
                # The instance id comes in the log's first lines, before any shot
                sleep 0.05
                continue
            fi
            if [ "$answered" = 0 ] && ! renderer_ok; then
                kill -TERM "$quickshell_pid" 2> /dev/null
                wait "$quickshell_pid" 2> /dev/null
                quickshell_pid=""
                memory_cap_hit "$headless_cap_unit" 1 > /dev/null 2>&1
                renderer_not_ok
            fi
            if ! [[ "${lines[$answered]}" =~ ^MOCKUP-SHOT\ [0-9]+\ [^\ ]+\ [0-9]+,[0-9]+\ [0-9]+x[0-9]+$ ]]; then
                reasons+=("a shot line the runner cannot read: ${lines[$answered]}")
                break
            fi
            read -r _ index scene position size <<< "${lines[$answered]}"
            if [ -n "$shots" ]; then
                file=$shots/$(printf '%02d' "$index")-$scene.png
                if "${isolated[@]}" WAYLAND_DISPLAY=wayland-0 timeout 20 "$LOCKTEST_GRIM" -g "$position $size" -t png "$file" \
                    > "$work/grim.log" 2>&1; then
                    "${isolated[@]}" timeout 20 "$LOCKTEST_MAGICK" "$file" -strip -define png:compression-level=9 \
                        -define png:exclude-chunks=date,time "$file" > "$work/magick.log" 2>&1 \
                        || reasons+=("magick could not rewrite the shot of scene '$scene': $(head -c 300 "$work/magick.log")")
                else
                    reasons+=("grim could not shoot scene '$scene': $(head -c 300 "$work/grim.log")")
                fi
            fi
            answered=$((answered + 1))
            "${isolated[@]}" WAYLAND_DISPLAY=wayland-0 timeout 10 "$LOCKTEST_QS" ipc --id "$instance" call mockup next > /dev/null 2>&1
            continue
        fi
        # A condition polled (a new line in the log, the entry ending), not a fixed wait
        sleep 0.05
    done
    if kill -0 "$quickshell_pid" 2> /dev/null; then
        kill -TERM "$quickshell_pid"
        reasons+=("the entry did not end within 150 s")
        # (timeout -k: killed if it does not end on TERM)
    fi
    wait "$quickshell_pid"
    status=$?
    quickshell_pid=""
    capped=""
    memory_cap_hit "$headless_cap_unit" "$status" "$log" && capped=1
    # Without the terminal colours Quickshell's log lines carry, for the verdict's reasons
    sed -i 's/\x1b\[[0-9;]*m//g' "$log"
    headless_cap_unit=""

    # (A window drawn and no shot answered, the entry ended first: the renderer still counts)
    grep -q 'MOCKUP-SHOT ' "$log" && ! renderer_ok && renderer_not_ok
    [ -n "$capped" ] && reasons+=("quickshell: $(memory_cap_note)")
    [ "$status" = 0 ] || reasons+=("quickshell exited with status $status")
    grep -q 'MOCKUP-ERROR' "$log" && reasons+=("$(grep -o 'MOCKUP-ERROR.*' "$log" | head -n 1)")
    errors=$(grep -E 'TypeError|ReferenceError' "$log" | head -n 3)
    [ -n "$errors" ] && reasons+=("a TypeError or ReferenceError: $errors")
    # Quickshell names a file of the tree "@<path in the tree>" in a warning, a URL elsewhere
    own=$(grep -F -e "@$base/$name/" -e "/$base/$name/" "$log" | grep -v 'MOCKUP-ERROR' | head -n 3)
    [ -n "$own" ] && reasons+=("a line about the mockup's own files: $own")
    # Every scene in its order, once, then done
    mapfile -t lines < <(grep -o 'MOCKUP-SHOT .*' "$log")
    for index in "${!lines[@]}"; do
        read -r _ number _ <<< "${lines[$index]}"
        [ "$number" = "$index" ] || { reasons+=("shot line $index is for scene $number"); break; }
    done
    grep -q 'MOCKUP-DONE' "$log" || reasons+=("no MOCKUP-DONE: not every scene was reached (${#lines[@]} shot)")
    if [ -n "$shots" ]; then
        for line in "${lines[@]}"; do
            read -r _ index scene _ size <<< "$line"
            file=$shots/$(printf '%02d' "$index")-$scene.png
            [ -s "$file" ] || continue
            shot_size=$("${isolated[@]}" "$LOCKTEST_MAGICK" identify -format '%wx%h' "$file" 2> /dev/null)
            [ "$shot_size" = "$size" ] || reasons+=("the shot of scene '$scene' is ${shot_size:-unreadable}, the subject $size")
        done
    fi

    if [ ${#reasons[@]} -gt 0 ]; then
        echo "FAIL     $name ($((SECONDS - started)) s)"
        printf '           %s\n' "${reasons[@]}"
        echo "           the entry's log:"
        sed 's/^/             /' "$log" | tail -n 30
        exit 1
    fi
    echo "PASS     $name (${#lines[@]} scenes, $((SECONDS - started)) s)${shots:+; shots: $shots}"
    exit 0
fi

# ---- The run --------------------------------------------------------------------------
names=()
for name in "$@"; do
    [[ "$name" =~ ^(components|views|planning)/[a-z0-9-]+$ ]] \
        || { echo "run-mockups.sh: '$name' is not <kind>/<name> (the kind components, views or planning); nothing was run" >&2; exit 2; }
    [ -f "$REPO/$base/$name/Mockup.qml" ] \
        || { echo "run-mockups.sh: no mockup $name ($base/$name/Mockup.qml); nothing was run" >&2; exit 2; }
    names+=("$name")
done
if [ ${#names[@]} = 0 ]; then
    # Planning mockups only by name: no test run includes them
    mapfile -t names < <(cd "$REPO/$base" 2> /dev/null && find components views -mindepth 2 -maxdepth 2 -name Mockup.qml -printf '%h\n' 2> /dev/null \
        | grep -E '^(components|views)/[a-z0-9-]+$' | LC_ALL=C sort)
    [ ${#names[@]} -gt 0 ] || { echo "run-mockups.sh: no component or view mockup in $base/: nothing to run"; exit 2; }
fi

# Waited for as each ends (wait -n -p: bash 5.1)
if [ "${BASH_VERSINFO[0]}" -lt 5 ] || { [ "${BASH_VERSINFO[0]}" = 5 ] && [ "${BASH_VERSINFO[1]}" -lt 1 ]; }; then
    echo "run-mockups.sh: running mockups side by side needs bash 5.1 or later (wait -n -p); this is bash $BASH_VERSION" >&2
    exit 2
fi
# shellcheck source=headless.sh
source "$REPO/tests/headless.sh"
headless_resolve
echo "renderer: $renderer"

# At once: half the processors, at most 16, and no more than memory allows (a mockup's
# Quickshell about 0.3 GB resident, its labwc about 0.1 GB)
if [ -z "$jobs" ]; then
    jobs=$(( $(nproc 2> /dev/null || echo 2) / 2 ))
    [ "$jobs" -ge 1 ] || jobs=1
    [ "$jobs" -le 16 ] || jobs=16
    memory_jobs=$(memory_cap_jobs 500000)
    [ "$memory_jobs" -lt "$jobs" ] && jobs=$memory_jobs
fi

shots_root=""
run_id=$(date -u +%Y%m%d-%H%M%S)-$$
if [ "$mode" = shoot ]; then
    shots_root=${H2S_MOCKUP_SHOTS:-${XDG_CACHE_HOME:-${HOME:?}/.cache}/h2s-shell-mockups}
    [[ "$shots_root" == /* ]] || setup_error "H2S_MOCKUP_SHOTS is '$shots_root': an absolute path"
    [ "$base" = mockups ] || shots_root=$shots_root/fixtures
fi
# shots_of <name>: the mockup's folder for this run
shots_of() { echo "$shots_root/$1/$run_id"; }

# Short, as headless_setup's: the mockups' outputs, removed with the rest (headless_cleanup)
work=$(mktemp -d /tmp/ut.XXXXXX) || setup_error "cannot create a temp dir"
chmod 700 "$work"
started=$SECONDS
echo "run-mockups.sh: ${#names[@]} mockup(s), --$mode, at most $jobs at once"

declare -A index_of=()
statuses=()
running=()
stop_mockups() {
    trap '' INT TERM HUP
    local pid
    for pid in "${running[@]}"; do kill -TERM "$pid" 2> /dev/null; done
    for pid in "${running[@]}"; do wait "$pid" 2> /dev/null; done
    running=()
    headless_cleanup
}
trap stop_mockups EXIT
trap 'exit 130' INT TERM HUP

# start_mockup <index>: this runner on the one mockup, in the background; its output in the
# work dir. TERM (stop_mockups) ends it
start_mockup() {
    local index=$1 name=${names[$1]} shots=-
    if [ -n "$shots_root" ]; then
        shots=$(shots_of "$name")
        mkdir -p "$shots" || setup_error "cannot create the shots folder $shots"
    fi
    H2S_MOCKUP_ONE=$$:$name:$shots HEADLESS_QUIET_RESOLVE=1 LOCKTEST_QS=$LOCKTEST_QS H2S_TEST_TOOLS=$LOCKTEST_TOOL_SOURCE \
        H2S_MOCKUP_BASE=$base H2S_MOCKUP_RENDERER=$renderer "$REPO/tests/run-mockups.sh" "--$mode" \
        > "$work/mockup-$index.out" 2>&1 < /dev/null &
    index_of[$!]=$index
    running+=("$!")
}

next=0
while [ "$next" -lt ${#names[@]} ] || [ ${#running[@]} -gt 0 ]; do
    while [ "$next" -lt ${#names[@]} ] && [ ${#running[@]} -lt "$jobs" ]; do
        start_mockup "$next"
        next=$((next + 1))
    done
    finished=""
    wait -n -p finished "${running[@]}"
    status=$?
    [ -n "$finished" ] || setup_error "lost track of the mockups (wait said $status, ${#running[@]} listed as running)"
    index=${index_of[$finished]}
    statuses[index]=$status
    remaining=()
    for pid in "${running[@]}"; do [ "$pid" = "$finished" ] || remaining+=("$pid"); done
    running=("${remaining[@]}")
done

# A mockup that shot nothing leaves no empty folder
if [ -n "$shots_root" ]; then
    for name in "${names[@]}"; do rmdir -- "$(shots_of "$name")" "$shots_root/$name" 2> /dev/null; done
fi

# The run folders of every mockup (<kind>/<name>/<run>), one per line, "<run> <path>"; the
# set both the size and what goes are reckoned over
run_folders() {
    find "$shots_root" -mindepth 3 -maxdepth 3 -type d \( -path "$shots_root/components/*" \
        -o -path "$shots_root/views/*" -o -path "$shots_root/planning/*" \) -printf '%f %p\n' 2> /dev/null
}
# going <run>: the run is this one, or another runner's still going (the pid at the end of
# its name is a live run-mockups.sh): it is never pruned
going() {
    local pid=${1##*-} command
    [ "$1" = "$run_id" ] && return 0
    [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2> /dev/null || return 1
    command=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2> /dev/null)
    [[ "$command" == *run-mockups.sh* ]]
}
# prune_shots: of each mockup's runs the newest 20 and any younger than a day; then, while
# the runs together are over the limit, the oldest; never a run still going
prune_shots() {
    local limit_mb=${H2S_MOCKUP_SHOTS_LIMIT_MB:-500} folder run path size
    local -a paths
    [[ "$limit_mb" =~ ^[0-9]+$ ]] || { echo "  (shots not pruned: H2S_MOCKUP_SHOTS_LIMIT_MB is '$limit_mb', not a number of MB)"; return; }
    while IFS= read -r folder; do
        for run in $(find "$folder" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort -r | tail -n +21); do
            going "$run" && continue
            [ -z "$(find "$folder/$run" -maxdepth 0 -mmin +1440)" ] || rm -rf -- "${folder:?}/$run"
        done
    done < <(run_folders | cut -d ' ' -f 2- | sed 's|/[^/]*$||' | LC_ALL=C sort -u)
    while :; do
        mapfile -t paths < <(run_folders | cut -d ' ' -f 2-)
        [ ${#paths[@]} -gt 0 ] || break
        size=$(du -c -s -B1M -- "${paths[@]}" 2> /dev/null | awk 'END { print $1 }')
        [ -n "$size" ] && [ "$size" -gt "$limit_mb" ] || break
        # The oldest run of any mockup that is not still going: run folders are named by
        # their time
        path=""
        while read -r run path; do
            going "$run" || break
            path=""
        done < <(run_folders | LC_ALL=C sort)
        [ -n "$path" ] || break
        rm -rf -- "$path"
    done
}
[ -n "$shots_root" ] && prune_shots

failed=0 not_run=0
for index in "${!names[@]}"; do
    case "${statuses[$index]}" in
        0) ;;
        2) not_run=1 ;;
        *) failed=1 ;;
    esac
done
echo
echo "Mockups ($((SECONDS - started)) s, --$mode, renderer $renderer):"
for index in "${!names[@]}"; do
    output=$(cat "$work/mockup-$index.out" 2> /dev/null)
    if grep -q -E '^(PASS|FAIL|NOT RUN) ' <<< "$output"; then
        sed -n '/^\(PASS\|FAIL\|NOT RUN\) /,$p' <<< "$output" | sed 's/^/  /'
    else
        # No verdict: it could not be set up (status 2, a set-up error names why), or it
        # ended otherwise (a bash error, a signal): a failure, never a pass
        if [ "${statuses[$index]}" = 2 ]; then
            echo "  NOT RUN  ${names[$index]} — $(tail -n 5 <<< "$output" | tr '\n' ' ')"
            not_run=1
        else
            echo "  FAIL     ${names[$index]} — ended with status ${statuses[$index]} and no verdict: $(tail -n 5 <<< "$output" | tr '\n' ' ')"
            failed=1
        fi
    fi
done
[ "$failed" = 1 ] && exit 1
[ "$not_run" = 1 ] && exit 2
exit 0
