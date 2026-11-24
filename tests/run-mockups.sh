#!/usr/bin/env bash
# Runs mockups (mockup.qml, mockups/<kind>/<name>/Mockup.qml) headless: each in a private
# headless compositor of its own (tests/headless.sh), side by side, stepping through its
# scenes over IPC.
#
#   tests/run-mockups.sh --load-only [<kind>/<name>…]   every scene is reached and nothing errs
#   tests/run-mockups.sh --shoot [<kind>/<name>…]       the same, and a PNG of each scene
#   tests/run-mockups.sh --compare [<kind>/<name>…]     the same, each PNG compared with the
#                                                       mockup's baseline
#   tests/run-mockups.sh --approve <kind>/<name>…       this tree's last run's shots become
#                                                       the mockup's baseline
#   tests/run-mockups.sh --by-system [<kind>/<name>…]   --compare on Arch, --load-only on
#                                                       any other system (tests/run-all.sh's
#                                                       part, tests/affected.sh's command)
#   tests/run-mockups.sh -j <n> …                       at most <n> mockups at once (default:
#                                                       half the processors, at most 16, and
#                                                       no more than memory allows)
#
# With no name: every component and view mockup (mockups/components/*, mockups/views/*).
# --by-system takes the system as tests/run-system.sh does (scripts/distribution.sh,
# H2S_DISTRIBUTION_ROOT before the paths it reads), and says which mode it took: the
# baselines are drawn on Arch, and another system's libraries and fonts draw other pixels,
# so elsewhere every scene is only reached; a system that cannot be told is load-only too.
# With no name and no component or view mockup in the tree it has nothing to check, and
# says so with status 0 (the other modes: status 2).
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
# (the pid in its name a live run-mockups.sh). A mockup that is NOT RUN for its renderer, a
# missing font or an unreadable process leaves no shot. Each run folder holds origin.txt (the
# tree that made it, its commit, a checksum of its uncommitted changes and of the mockup's
# file), and, when the mockup passed, run.txt: the environment it was drawn in and a line per
# scene (below). <kind>/<name>/last-run-<hash of the tree's path> names the last run this
# tree made of the mockup, whatever came of it: the shots folder may be shared by checkouts.
# The origin is taken as the mockup starts and again when it ends; a tree changed in between
# (its baselines aside, which --approve writes) makes the mockup NOT RUN, with no run.txt.
#
# --compare, the baseline: mockups/<kind>/<name>/baseline/ (H2S_MOCKUP_BASELINES=<dir> reads
# and writes <dir>/<kind>/<name>/baseline/ instead: the self-test's), holding <NN>-<scene>.png
# per scene and manifest.txt:
#   environment <key> <value>          what the scenes were drawn with: quickshell (its
#                                      --version; none is NOT RUN), renderer (the OpenGL
#                                      renderer line: Mesa's and LLVM's versions, the
#                                      processor's vector width), backend, qt-core, qt-gui,
#                                      qt-quick, qt-svg, freetype, fontconfig and harfbuzz (the
#                                      sha256 and path of the library files Quickshell's
#                                      process maps), font:<family>[:bold] for each family of
#                                      the built-in theme and font:sans-serif, font:monospace,
#                                      font:emoji (the sha256 and path of the file fontconfig
#                                      gives, in the private HOME), font-rendering
#                                      (fontconfig's hinting, antialiasing, subpixel order and
#                                      LCD filter for the theme's family)
#   scene <NN> <scene> <w>x<h> <sha256> one per scene, in order
# A scene matches when its PNG decodes to the same RGBA, pixel for pixel, as the baseline's
# (exact: there is no tolerance; byte-identical files are not decoded). A scene that does not
# gets, in the run folder, <NN>-<scene>/old.png, new.png and diff.png (the changed pixels red
# over a faded old) and <NN>-<scene>-review.png (old | new | diff, side by side; small shots
# enlarged, pixel for pixel), and the verdict names its count of differing pixels and that
# file (a scene whose size changed differs, whatever its count). The verdict per mockup:
# PASS; FAIL with each differing scene, its count and review file, or a scene list not the
# baseline's, a baseline file that is not the manifest's (its sha256), a baseline PNG over
# 300 KB or more than 30 scenes (the baseline's files are looked at before the environment);
# NOT RUN (status 2) with the reason for a mockup without a baseline, or one whose
# environment is not the baseline's ("environment changed since the baseline: qt-core: … →
# …"): its shots are kept, to be looked at and approved. The baselines together over 15 MB
# FAIL the run.
#
# --approve takes, of each named mockup, the last run this tree made of it (--shoot or
# --compare, with the same H2S_MOCKUP_BASE and H2S_MOCKUP_SHOTS), checks its PNGs against
# run.txt and the limits, and replaces the baseline with them: its PNGs and manifest.txt.
# It refuses that run when it did not pass or left no shots (never taking an older one), was
# made at another commit or with other uncommitted changes or another Mockup.qml than the
# tree has now, or was not drawn with llvmpipe. It changes files in the tree, to be committed
# with the code change that changed the look, once the review images were looked at.
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

usage() {
    echo "usage: tests/run-mockups.sh --load-only | --shoot | --compare [-j <mockups at once>] [<kind>/<name>…]" >&2
    echo "       tests/run-mockups.sh --approve <kind>/<name>…" >&2
    echo "       tests/run-mockups.sh --by-system [-j <mockups at once>] [<kind>/<name>…]" >&2
    exit 2
}
mode=""
jobs=""
while [ $# -gt 0 ]; do
    case "$1" in
        --load-only | --shoot | --compare | --approve | --by-system)
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
by_system=0
if [ "$mode" = by-system ]; then
    by_system=1
    # shellcheck source=../scripts/distribution.sh
    source "$REPO/scripts/distribution.sh" || { echo "run-mockups.sh: cannot read scripts/distribution.sh; nothing was run" >&2; exit 2; }
    if distribution_detect "$REPO" "" "${H2S_DISTRIBUTION_ROOT:-}"; then
        system=$distribution_id
    else
        system="unknown ($distribution_problem)"
    fi
    if [ "$system" = arch ]; then mode=compare; else mode=load-only; fi
    echo "run-mockups.sh: the system is $system: --$mode"
fi

base=${H2S_MOCKUP_BASE:-mockups}
case "$base" in
    mockups | tests/fixtures/mockups) ;;
    *) echo "run-mockups.sh: H2S_MOCKUP_BASE is '$base': mockups or tests/fixtures/mockups" >&2; exit 2 ;;
esac
baselines_root=${H2S_MOCKUP_BASELINES:-$REPO/$base}
[[ "$baselines_root" == /* ]] || { echo "run-mockups.sh: H2S_MOCKUP_BASELINES is '$baselines_root': an absolute path" >&2; exit 2; }
# The limits on a baseline: a PNG (KB), a mockup's scenes, all baselines together (MB)
limit_png_kb=300
limit_scenes=30
limit_total_mb=15
renderer=${H2S_MOCKUP_RENDERER:-llvmpipe}
case "$renderer" in
    llvmpipe) renderer_env=(QSG_RHI_BACKEND=opengl LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe QSG_INFO=1) ;;
    software) renderer_env=(QT_QUICK_BACKEND=software) ;;
    *) echo "run-mockups.sh: H2S_MOCKUP_RENDERER is '$renderer': software or llvmpipe" >&2; exit 2 ;;
esac

# scenes_of <manifest or run.txt>: its scene lines, "<NN> <scene> <w>x<h> <sha256>"
scenes_of() { awk '$1 == "scene" { print $2, $3, $4, $5 }' "$1"; }
# sha256_of <file>
sha256_of() {
    local sum
    sum=$(sha256sum < "$1") || return 1
    echo "${sum%% *}"
}
# environment_changes <baseline's manifest> <run.txt>: each environment key whose value differs,
# "<key>: <old> → <new>", joined with "; " (nothing when they agree)
environment_changes() {
    awk 'FNR == 1 { file++ }
        $1 == "environment" {
            key = $2
            value = $0
            sub(/^environment [^ ]+ ?/, "", value)
            values[file, key] = value
            if (!(key in seen)) { seen[key] = 1; keys[++count] = key }
        }
        END {
            for (i = 1; i <= count; i++) {
                key = keys[i]
                old = ((1, key) in values) ? values[1, key] : "(none)"
                new = ((2, key) in values) ? values[2, key] : "(none)"
                if (old != new) printf "%s%s: %s → %s", (said++ ? "; " : ""), key, old, new
            }
        }' "$1" "$2"
}

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
    # not_run_keeping <reason>: the same, its shots kept (no baseline yet, or another
    # environment's: they are what a new baseline is approved from)
    not_run_keeping() {
        echo "NOT RUN  $name — $*${shots:+; shots: $shots}"
        exit 2
    }
    reasons=()
    differences=()

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

    # What the scenes are drawn with, for the baseline's manifest (shots only): Quickshell, and
    # the font files fontconfig gives in the private HOME; the renderer and the libraries are
    # added once the window is drawn
    environment=$work/environment.txt
    if [ -n "$shots" ]; then
        # (Some builds say their version on standard error)
        quickshell_version=$("${isolated[@]}" timeout 10 "$LOCKTEST_QS" --version 2>&1 < /dev/null | grep -m 1 .)
        [ -n "$quickshell_version" ] || not_run "Quickshell names no version ($LOCKTEST_QS --version): what draws the scenes cannot be told"
        {
            echo "environment backend $renderer"
            echo "environment quickshell $quickshell_version"
        } > "$environment"
        # Every family the built-in theme names, regular and bold, each of which must be
        # installed; then the fallbacks Qt draws from where those lack a glyph
        mapfile -t theme_families < <(sed -n 's/^.*"family": *"\([^"]*\)".*$/\1/p' "$REPO/singletons/ThemeBuiltin.qml" | LC_ALL=C sort -u)
        [ ${#theme_families[@]} -gt 0 ] || not_run "the theme's font family is not in singletons/ThemeBuiltin.qml"
        font_patterns=()
        for family in "${theme_families[@]}"; do font_patterns+=("theme|$family" "theme|$family:bold"); done
        font_patterns+=("fallback|sans-serif" "fallback|monospace" "fallback|emoji")
        for entry in "${font_patterns[@]}"; do
            pattern=${entry#*|}
            family=${pattern%:bold}
            answer=$("${isolated[@]}" timeout 10 "$LOCKTEST_FC_MATCH" -f '%{family}|%{file}' "$pattern" 2> /dev/null)
            families=${answer%%|*}
            font_file=${answer#*|}
            # fontconfig always answers with some font: the theme's must be the one
            [ "${entry%%|*}" = fallback ] || [[ ",$families," == *",$family,"* ]] \
                || not_run "the theme's font '$family' is not installed (fontconfig gives '${families:-nothing}' for '$pattern')"
            [ -f "$font_file" ] || not_run "fontconfig names no font file for '$pattern' (${font_file:-nothing})"
            echo "environment font:${pattern// /-} $(sha256_of "$font_file") $font_file" >> "$environment"
        done
        # How fontconfig has text drawn (hinting, antialiasing, subpixel order, LCD filter)
        echo "environment font-rendering $("${isolated[@]}" timeout 10 "$LOCKTEST_FC_MATCH" \
            -f 'hinting=%{hinting} hintstyle=%{hintstyle} antialias=%{antialias} rgba=%{rgba} lcdfilter=%{lcdfilter} autohint=%{autohint} embeddedbitmap=%{embeddedbitmap}' \
            "${theme_families[0]}" 2> /dev/null)" >> "$environment"
    fi
    # The library files Quickshell's process maps (its pid: the one under the started chain,
    # cap, env, setpriv, timeout, that maps Qt Core); while it runs
    children_of() {
        local stat line parent
        local -A wanted=()
        for parent in "$@"; do wanted[$parent]=1; done
        for stat in /proc/[0-9]*/stat; do
            { read -r line < "$stat"; } 2> /dev/null || continue
            read -r _ parent _ <<< "${line##*) }"
            [ -n "${wanted[$parent]:-}" ] || continue
            stat=${stat#/proc/}
            echo "${stat%/stat}"
        done
    }
    libraries_environment() {
        local -a level=("$1") next
        local depth pid found="" maps entry path
        for depth in 1 2 3 4 5 6 7 8; do
            for pid in "${level[@]}"; do
                grep -q '/libQt6Core\.so' "/proc/$pid/maps" 2> /dev/null && { found=$pid; break 2; }
            done
            mapfile -t next < <(children_of "${level[@]}")
            [ ${#next[@]} -gt 0 ] || break
            level=("${next[@]}")
        done
        [ -n "$found" ] || return 1
        maps=$(awk '{ print $6 }' "/proc/$found/maps" 2> /dev/null | LC_ALL=C sort -u)
        # By content: a rebuild of the same version counts
        for entry in qt-core:libQt6Core qt-gui:libQt6Gui qt-quick:libQt6Quick qt-svg:libQt6Svg freetype:libfreetype \
            fontconfig:libfontconfig harfbuzz:libharfbuzz; do
            path=$(grep -m 1 "/${entry#*:}\.so" <<< "$maps")
            if [ -n "$path" ] && [ -f "$path" ]; then
                echo "environment ${entry%%:*} $(sha256_of "$path") $path"
            else
                echo "environment ${entry%%:*} (not loaded)"
            fi
        done
    }

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
            if [ "$answered" = 0 ] && [ -n "$shots" ]; then
                libraries=$(libraries_environment "$quickshell_pid") \
                    || not_run "cannot tell which libraries Quickshell draws with: no process under it maps Qt Core"
                echo "$libraries" >> "$environment"
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

    # The run's record (run.txt): the environment, then each scene's size and checksum
    if [ -n "$shots" ]; then
        record=$shots/run.txt
        {
            echo "# $name: the shots of this run and what they were drawn with (tests/run-mockups.sh)"
            if [ "$renderer" = llvmpipe ]; then
                echo "environment renderer $(grep -o 'OpenGL VENDOR: .*' "$log" | head -n 1)"
            else
                echo "environment renderer Qt Quick's software backend"
            fi
            cat "$environment"
            for line in "${lines[@]}"; do
                read -r _ index scene _ size <<< "$line"
                number=$(printf '%02d' "$index")
                echo "scene $number $scene $size $(sha256_of "$shots/$number-$scene.png")"
            done
        } > "$record"
    fi

    # pixels_differing <old> <new> <width> <height>: how many pixels differ, the two decoded
    # to 16-bit RGBA on a transparent canvas of that size (the larger of the two's)
    pixels_differing() {
        local side file
        for side in old new; do
            [ "$side" = old ] && file=$1 || file=$2
            "${isolated[@]}" timeout 60 "$LOCKTEST_MAGICK" "$file" -alpha set -background none -gravity NorthWest \
                -extent "$3x$4" -depth 16 "RGBA:$work/$side.rgba" 2> "$work/magick.log" || return 1
        done
        # cmp -l: a line per differing byte, by offset; 8 bytes a pixel
        cmp -l "$work/old.rgba" "$work/new.rgba" | awk 'BEGIN { last = -1 } { pixel = int(($1 - 1) / 8); if (pixel != last) { count++; last = pixel } } END { print count + 0 }'
    }
    # review_images <old> <new> <width> <height> <folder> <review file>: old.png, new.png and
    # diff.png in the folder, and old | new | diff side by side, enlarged pixel for pixel
    # while a panel is narrower than 240 px (at most 8 times)
    review_images() {
        local old=$1 new=$2 width=$3 height=$4 folder=$5 review=$6 scale
        mkdir -p "$folder" && cp -- "$old" "$folder/old.png" && cp -- "$new" "$folder/new.png" || return 1
        "${isolated[@]}" timeout 60 "$LOCKTEST_MAGICK" "$old" -alpha set -background none -gravity NorthWest -extent "${width}x$height" "$work/old-canvas.png" \
            && "${isolated[@]}" timeout 60 "$LOCKTEST_MAGICK" "$new" -alpha set -background none -gravity NorthWest -extent "${width}x$height" "$work/new-canvas.png" \
            && "${isolated[@]}" timeout 60 "$LOCKTEST_MAGICK" "$work/old-canvas.png" "$work/new-canvas.png" \
                -fx '(u.r != v.r || u.g != v.g || u.b != v.b || u.a != v.a) ? 1 : 0' -alpha off "$work/mask.png" \
            && "${isolated[@]}" timeout 60 "$LOCKTEST_MAGICK" "$work/old-canvas.png" -background white -alpha remove -alpha off \
                -fill white -colorize 70% \( -size "${width}x$height" xc:red \) "$work/mask.png" -composite "$folder/diff.png" \
            || return 1
        scale=$((240 / width))
        [ "$scale" -ge 1 ] || scale=1
        [ "$scale" -le 8 ] || scale=8
        "${isolated[@]}" timeout 60 "$LOCKTEST_MAGICK" "$work/old-canvas.png" "$work/new-canvas.png" "$folder/diff.png" \
            -background gray50 -alpha remove -alpha off -scale "$((scale * 100))%" \
            -bordercolor gray50 -border 4 +append +repage "$review"
    }

    # --compare: each scene against the baseline's
    if [ "$mode" = compare ]; then
        baseline=$baselines_root/$name/baseline
        manifest=$baseline/manifest.txt
        [ -f "$manifest" ] || not_run_keeping "no baseline ($manifest): look at the shots, then tests/run-mockups.sh --approve $name"
        mapfile -t old_scenes < <(scenes_of "$manifest")
        # The baseline's own files first: a baseline that is not what was approved fails
        # whatever the environment
        for entry in "${old_scenes[@]}"; do
            read -r number scene _ sum <<< "$entry"
            file=$baseline/$number-$scene.png
            [ -f "$file" ] || { differences+=("baseline/$number-$scene.png is missing"); continue; }
            bytes=$(stat -c %s -- "$file")
            [ "$bytes" -le $((limit_png_kb * 1024)) ] \
                || differences+=("baseline/$number-$scene.png is $((bytes / 1024)) KB, over the limit of $limit_png_kb KB: crop the scene to its subject")
            [ "$(sha256_of "$file")" = "$sum" ] || differences+=("baseline/$number-$scene.png is not the approved file: its sha256 is not the manifest's")
        done
        changes=$(environment_changes "$manifest" "$record")
        if [ -n "$changes" ]; then
            [ ${#differences[@]} -eq 0 ] || {
                echo "FAIL     $name ($((SECONDS - started)) s; shots: $shots)"
                printf '           %s\n' "${differences[@]}" "(and the environment changed since the baseline: $changes)"
                exit 1
            }
            not_run_keeping "environment changed since the baseline: $changes"
        fi
        mapfile -t new_scenes < <(scenes_of "$record")
        [ ${#old_scenes[@]} -le "$limit_scenes" ] || differences+=("the baseline has ${#old_scenes[@]} scenes, over the limit of $limit_scenes")
        [ ${#new_scenes[@]} -le "$limit_scenes" ] || differences+=("the mockup has ${#new_scenes[@]} scenes, over the limit of $limit_scenes")
        old_names=$(printf '%s\n' "${old_scenes[@]}" | awk '{ print $2 }' | paste -s -d ' ')
        new_names=$(printf '%s\n' "${new_scenes[@]}" | awk '{ print $2 }' | paste -s -d ' ')
        [ "$old_names" = "$new_names" ] || differences+=("the scenes are not the baseline's: baseline '$old_names', now '$new_names'")
        for entry in "${old_scenes[@]}"; do
            read -r number scene _ <<< "$entry"
            file=$baseline/$number-$scene.png
            [ -f "$file" ] || continue
            shot=$shots/$number-$scene.png
            # (A scene the mockup no longer has: the scene lists above)
            [ -f "$shot" ] || continue
            cmp -s -- "$file" "$shot" && continue
            new_size=$("${isolated[@]}" "$LOCKTEST_MAGICK" identify -format '%wx%h' "$shot" 2> /dev/null)
            old_size=$("${isolated[@]}" "$LOCKTEST_MAGICK" identify -format '%wx%h' "$file" 2> /dev/null)
            if ! [[ "$old_size" =~ ^[0-9]+x[0-9]+$ && "$new_size" =~ ^[0-9]+x[0-9]+$ ]]; then
                differences+=("scene '$scene': the baseline's PNG or the shot cannot be read (${old_size:-?} and ${new_size:-?})")
                continue
            fi
            width=$(( ${old_size%x*} > ${new_size%x*} ? ${old_size%x*} : ${new_size%x*} ))
            height=$(( ${old_size#*x} > ${new_size#*x} ? ${old_size#*x} : ${new_size#*x} ))
            count=$(pixels_differing "$file" "$shot" "$width" "$height") \
                || { differences+=("scene '$scene': cannot be compared: $(head -c 300 "$work/magick.log")"); continue; }
            # (A size that changed fails on its own: the canvas can hide it, transparent on both)
            [ "$count" = 0 ] && [ "$old_size" = "$new_size" ] && continue
            review=$shots/$number-$scene-review.png
            review_images "$file" "$shot" "$width" "$height" "$shots/$number-$scene" "$review" > "$work/review.log" 2>&1 \
                || review="(none: $(head -c 300 "$work/review.log"))"
            case $count in
                1) pixels="1 pixel differs" ;;
                *) pixels="$count pixels differ" ;;
            esac
            [ "$old_size" = "$new_size" ] || pixels="$pixels (the size was $old_size, is $new_size)"
            differences+=("scene '$scene': $pixels; review: $review")
        done
        if [ ${#differences[@]} -gt 0 ]; then
            echo "FAIL     $name ($((SECONDS - started)) s; shots: $shots)"
            printf '           %s\n' "${differences[@]}"
            exit 1
        fi
        echo "PASS     $name (${#lines[@]} scenes, the same as the baseline, $((SECONDS - started)) s)"
        exit 0
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
# shots_root: where the runs' shots are (--shoot, --compare, --approve)
shots_root=${H2S_MOCKUP_SHOTS:-${XDG_CACHE_HOME:-${HOME:?}/.cache}/h2s-shell-mockups}
[[ "$shots_root" == /* ]] || { echo "run-mockups.sh: H2S_MOCKUP_SHOTS is '$shots_root': an absolute path" >&2; exit 2; }
[ "$base" = mockups ] || shots_root=$shots_root/fixtures

# The shots root is shared by every checkout that uses it: each run folder says which tree,
# at which commit and with which uncommitted changes, made it (origin.txt), and each mockup's
# folder names the last run this tree made of it (last-run-<a hash of the tree's path>),
# whatever came of it. --approve takes only that run, and only while the tree is as it was
tree_key=$(printf '%s' "$REPO" | sha256sum | cut -c 1-16)
# tree_origin: this tree's path, its commit and a checksum of its uncommitted changes (the
# diff against HEAD and each untracked file's checksum), the mockups' baselines left out: they
# are what --approve writes, and what a baseline is drawn from is the rest
tree_origin() {
    local commit changes
    local -a outside_baselines=(-- . ':(exclude,glob)**/baseline/**')
    commit=$(git -C "$REPO" rev-parse --verify -q HEAD 2> /dev/null) || commit="(none)"
    changes=$({
        git -C "$REPO" diff HEAD --binary "${outside_baselines[@]}" 2> /dev/null
        (cd "$REPO" && git ls-files -z -o --exclude-standard "${outside_baselines[@]}" 2> /dev/null | xargs -0 -r sha256sum --)
    } | sha256sum)
    echo "tree $REPO"
    echo "commit $commit"
    echo "changes ${changes%% *}"
}
# mockup_origin <kind>/<name>: the tree's origin and the checksum of the mockup's file
mockup_origin() {
    tree_origin
    echo "mockup $(sha256_of "$REPO/$base/$1/Mockup.qml")"
}

# ---- --approve: the last run's shots become the baseline -----------------------------
# approve <kind>/<name>: its line, and the status (0 approved, 1 refused, 2 no run to take)
approve() {
    local name=$1 run run_id record baseline entry number scene size sum file bytes key value now
    local -a scenes problems=()
    if ! { read -r run_id < "$shots_root/$name/last-run-$tree_key"; } 2> /dev/null; then
        echo "NOT DONE $name — no run of it from this tree in $shots_root/$name: tests/run-mockups.sh --shoot $name first"
        return 2
    fi
    if ! [[ "$run_id" =~ ^[0-9]{8}-[0-9]{6}-[0-9]+$ ]]; then
        echo "REFUSED  $name — $shots_root/$name/last-run-$tree_key does not name a run ('$run_id')"
        return 1
    fi
    run=$shots_root/$name/$run_id
    if [ ! -d "$run" ]; then
        echo "REFUSED  $name — the last run from this tree ($run_id) left no shots: it was NOT RUN, or its shots were pruned; run it again"
        return 1
    fi
    record=$run/run.txt
    if [ ! -f "$record" ]; then
        echo "REFUSED  $name — the last run from this tree ($run) did not pass (no run.txt): look at its verdict, run it again"
        return 1
    fi
    now=$(mockup_origin "$name")
    [ "$(sed -n 's/^commit //p' <<< "$now")" != "(none)" ] || problems+=("this tree's commit cannot be told (git): which code drew the shots cannot be checked")
    for key in tree commit changes mockup; do
        value=$(sed -n "s/^$key //p" "$run/origin.txt" 2> /dev/null)
        [ "$value" = "$(sed -n "s/^$key //p" <<< "$now")" ] && continue
        case $key in
            tree) problems+=("it was made from another tree (${value:-unknown}), not this one ($REPO)") ;;
            commit) problems+=("it was made at commit ${value:-unknown}; this tree is at $(sed -n 's/^commit //p' <<< "$now")") ;;
            changes) problems+=("this tree's uncommitted changes are not the ones it was made with") ;;
            mockup) problems+=("its Mockup.qml is not the current one") ;;
        esac
    done
    grep -q -x 'environment backend llvmpipe' "$record" \
        || problems+=("it was not drawn with llvmpipe ($(sed -n 's/^environment backend //p' "$record")): a baseline is drawn with the baseline renderer")
    mapfile -t scenes < <(scenes_of "$record")
    [ ${#scenes[@]} -gt 0 ] || problems+=("its run.txt names no scene")
    [ ${#scenes[@]} -le "$limit_scenes" ] || problems+=("it has ${#scenes[@]} scenes, over the limit of $limit_scenes")
    for entry in "${scenes[@]}"; do
        read -r number scene size sum <<< "$entry"
        file=$run/$number-$scene.png
        if [ ! -f "$file" ]; then problems+=("$number-$scene.png is missing"); continue; fi
        [ "$(sha256_of "$file")" = "$sum" ] || problems+=("$number-$scene.png is not the file run.txt names (its sha256)")
        bytes=$(stat -c %s -- "$file")
        [ "$bytes" -le $((limit_png_kb * 1024)) ] \
            || problems+=("$number-$scene.png is $((bytes / 1024)) KB, over the limit of $limit_png_kb KB: crop the scene to its subject")
    done
    if [ ${#problems[@]} -gt 0 ]; then
        echo "REFUSED  $name — the run $run:"
        printf '           %s\n' "${problems[@]}"
        return 1
    fi
    baseline=$baselines_root/$name/baseline
    mkdir -p -- "$baseline" || { echo "REFUSED  $name — cannot create $baseline"; return 1; }
    find "$baseline" -maxdepth 1 -type f \( -name '*.png' -o -name manifest.txt \) -delete
    for entry in "${scenes[@]}"; do
        read -r number scene _ <<< "$entry"
        cp -- "$run/$number-$scene.png" "$baseline/" || { echo "REFUSED  $name — cannot copy into $baseline"; return 1; }
    done
    {
        echo "# The approved baseline of $name: a PNG per scene (<NN>-<scene>.png), compared pixel"
        echo "# for pixel by tests/run-mockups.sh --compare, and what it was drawn with (a run drawn"
        echo "# otherwise is NOT RUN). Written by tests/run-mockups.sh --approve; never by hand."
        grep -v '^#' "$record"
    } > "$baseline/manifest.txt"
    echo "APPROVED $name — ${#scenes[@]} scenes from $run into $baseline"
}
if [ "$mode" = approve ]; then
    [ ${#names[@]} -gt 0 ] || { echo "run-mockups.sh: --approve needs the mockups' names; nothing was approved" >&2; exit 2; }
    refused=0 no_run=0
    for name in "${names[@]}"; do
        approve "$name"
        case $? in
            0) ;;
            2) no_run=1 ;;
            *) refused=1 ;;
        esac
    done
    [ "$refused" = 1 ] && exit 1
    [ "$no_run" = 1 ] && exit 2
    exit 0
fi

if [ ${#names[@]} = 0 ]; then
    # Planning mockups only by name: no test run includes them
    mapfile -t names < <(cd "$REPO/$base" 2> /dev/null && find components views -mindepth 2 -maxdepth 2 -name Mockup.qml -printf '%h\n' 2> /dev/null \
        | grep -E '^(components|views)/[a-z0-9-]+$' | LC_ALL=C sort)
    if [ ${#names[@]} = 0 ]; then
        echo "run-mockups.sh: no component or view mockup in $base/: nothing to run"
        exit $((by_system ? 0 : 2))
    fi
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

run_id=$(date -u +%Y%m%d-%H%M%S)-$$
[ "$mode" != load-only ] || shots_root=""
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
        # Taken as the mockup starts, and again when it has ended (below): the tree it loads is
        # the tree as it is then
        mockup_origin "$name" > "$work/origin-$index.txt"
        cp -- "$work/origin-$index.txt" "$shots/origin.txt"
        echo "${shots##*/}" > "$shots_root/$name/last-run-$tree_key"
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
    # The tree changed while the mockup ran: what it drew is not of the tree its origin.txt
    # names, so no verdict is given, and its shots cannot be approved
    if [ -n "$shots_root" ] && [ "$(mockup_origin "${names[$index]}")" != "$(cat "$work/origin-$index.txt")" ]; then
        rm -f -- "$(shots_of "${names[$index]}")/run.txt"
        echo "NOT RUN  ${names[$index]} — the tree changed while it ran (its commit, its uncommitted changes or the mockup's file): run it again" \
            > "$work/mockup-$index.out"
        statuses[index]=2
    fi
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
# The baselines together, within their limit (--compare)
if [ "$mode" = compare ]; then
    total=$(find "$baselines_root" -path '*/baseline/*.png' -type f -printf '%s\n' 2> /dev/null | awk '{ sum += $1 } END { print sum + 0 }')
    if [ "$total" -gt $((limit_total_mb * 1024 * 1024)) ]; then
        echo "  FAIL     the baselines in $baselines_root: $((total / 1024 / 1024)) MB together, over the limit of $limit_total_mb MB"
        failed=1
    fi
fi
[ "$failed" = 1 ] && exit 1
[ "$not_run" = 1 ] && exit 2
exit 0
