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
# are kept and any younger than a day; then, while the folder holds more than 500 MB
# (H2S_MOCKUP_SHOTS_LIMIT_MB), the oldest runs go, this run's never.
#
# The environment is fixed, so that a scene draws the same each time:
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

    # not_run <reason>, failed <reason>…: the verdict line, and the status
    not_run() { echo "NOT RUN  $name — $*"; exit 2; }
    reasons=()

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
        "$SETPRIV" --no-new-privs timeout 120 "$LOCKTEST_QS" -p "$REPO/mockup.qml" > "$log" 2>&1 < /dev/null &
    # (headless_cleanup ends it when this is interrupted)
    quickshell_pid=$!

    # Each new MOCKUP-SHOT line: the scene shot (--shoot), then `ipc call mockup next`
    # addressed to this instance; until the entry has ended (it ends itself on an error or
    # after its limit; the deadline here only guards a hang of this loop)
    answered=0
    instance=""
    deadline=$((SECONDS + 150))
    while kill -0 "$quickshell_pid" 2> /dev/null && [ $SECONDS -lt $deadline ]; do
        mapfile -t lines < <(grep -o 'MOCKUP-SHOT .*' "$log")
        if [ ${#lines[@]} -gt "$answered" ]; then
            [ -n "$instance" ] || instance=$(sed -n 's|.*/by-id/\([a-z0-9]*\)/log\.qslog.*|\1|p' "$log" | head -n 1)
            if [ -z "$instance" ]; then
                # The instance id comes in the log's first lines, before any shot
                sleep 0.05
                continue
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
    kill -0 "$quickshell_pid" 2> /dev/null && { kill -TERM "$quickshell_pid"; reasons+=("the entry did not end within 150 s"); }
    wait "$quickshell_pid"
    status=$?
    quickshell_pid=""
    capped=""
    memory_cap_hit "$headless_cap_unit" "$status" "$log" && capped=1
    # Without the terminal colours Quickshell's log lines carry, for the verdict's reasons
    sed -i 's/\x1b\[[0-9;]*m//g' "$log"
    headless_cap_unit=""

    # QSG_INFO's line: "OpenGL VENDOR: Mesa RENDERER: llvmpipe (LLVM …, 256 bits) VERSION: …";
    # looked for once a window was drawn (a shot line), not after a load error
    if [ "$renderer" = llvmpipe ] && grep -q 'MOCKUP-SHOT ' "$log" && ! grep -q 'RENDERER: llvmpipe' "$log"; then
        gl=$(grep -o 'OpenGL VENDOR: .*' "$log" | head -n 1)
        not_run "the renderer is not llvmpipe (${gl:-no OpenGL renderer named in the log}): Mesa's llvmpipe is not there, or another OpenGL driver was taken"
    fi
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

# prune_shots: of each mockup's runs the newest 20 and any younger than a day; then the
# oldest runs while the folder is over its limit, never this run's
prune_shots() {
    local limit_mb=${H2S_MOCKUP_SHOTS_LIMIT_MB:-500} folder old size
    [[ "$limit_mb" =~ ^[0-9]+$ ]] || { echo "  (shots not pruned: H2S_MOCKUP_SHOTS_LIMIT_MB is '$limit_mb', not a number of MB)"; return; }
    while IFS= read -r folder; do
        for old in $(find "$folder" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort -r | tail -n +21); do
            [ -z "$(find "$folder/$old" -maxdepth 0 -mmin +1440)" ] || rm -rf -- "${folder:?}/$old"
        done
    done < <(find "$shots_root" -mindepth 2 -maxdepth 2 -type d \( -path "$shots_root/components/*" -o -path "$shots_root/views/*" -o -path "$shots_root/planning/*" \))
    while :; do
        size=$(du -s -B1M -- "$shots_root" 2> /dev/null | awk '{ print $1 }')
        [ -n "$size" ] && [ "$size" -gt "$limit_mb" ] || break
        # The oldest run of any mockup: run folders are named by their time
        old=$(find "$shots_root" -mindepth 3 -maxdepth 3 -type d \( -path "$shots_root/components/*" -o -path "$shots_root/views/*" -o -path "$shots_root/planning/*" \) \
            ! -name "$run_id" -printf '%f %p\n' | LC_ALL=C sort | head -n 1 | cut -d ' ' -f 2-)
        [ -n "$old" ] || break
        rm -rf -- "$old"
    done
}
[ -n "$shots_root" ] && prune_shots

failed=0 not_run=0
for index in "${!names[@]}"; do
    case "${statuses[$index]}" in
        0) ;;
        1) failed=1 ;;
        *) not_run=1 ;;
    esac
done
echo
echo "Mockups ($((SECONDS - started)) s, --$mode, renderer $renderer):"
for index in "${!names[@]}"; do
    output=$(cat "$work/mockup-$index.out" 2> /dev/null)
    if grep -q -E '^(PASS|FAIL|NOT RUN) ' <<< "$output"; then
        sed -n '/^\(PASS\|FAIL\|NOT RUN\) /,$p' <<< "$output" | sed 's/^/  /'
    else
        # No verdict: it could not be set up (a set-up error names why) or was ended
        echo "  NOT RUN  ${names[$index]} — status ${statuses[$index]}: $(tail -n 5 <<< "$output" | tr '\n' ' ')"
        [ "${statuses[$index]}" = 1 ] || not_run=1
    fi
done
[ "$failed" = 1 ] && exit 1
[ "$not_run" = 1 ] && exit 2
exit 0
