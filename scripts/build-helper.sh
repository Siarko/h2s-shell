#!/usr/bin/env bash
# Builds the shell's helper (helper/: C++17, Qt 6 Core and DBus, CMake) from this checkout,
# outside it: into a directory of the user's cache, one per checkout, never into the tree.
# On NixOS the package builds it instead (nix/package.nix); on Arch install.sh runs this, and
# scripts/launch.sh asks --status at each start and, when the source changed, runs it with
# --if-changed in the background for the next start (it never waits for a build).
# It runs as the user only, never as root: the helper is the user's program.
#
#   scripts/build-helper.sh [--out DIR] [--if-changed] [--time-limit S] [--print-path | --status]
#
#   --out DIR      where to build (an absolute path outside the checkout). The default is
#                  ${XDG_CACHE_HOME:-~/.cache}/h2s-shell/helper/<a hash of the checkout's path>
#   --if-changed   build only when the source (helper/ and this script) differs from what
#                  the binary there was built from; a build of this same source that failed
#                  (or ran out of time) before is not tried again (run without it)
#   --time-limit S the build's bound, in seconds (default 300): past it, it is ended and
#                  counts as failed
#   --print-path   print where the binary is, or would be, and build nothing
#   --status       print "current", "stale" (the source changed since the binary there was
#                  built), "failed" (this source failed to build) or "missing"; build nothing
#
# The version `h2s-helper --version` prints is the shell's at the helper's last build: a new
# shell version alone does not rebuild it (the protocol number is what the shell checks).
#
# Prints the binary's path on standard output when it is built or up to date; cmake's own
# output goes to <DIR>/build.log. The binary is replaced as a whole (renamed into place), so
# a helper running from it keeps running.
#
# It writes only into DIR, and refuses a DIR that is not absolute, lies inside the
# checkout, is a link or not a directory, already holds something without the mark this
# script leaves there (.h2s-helper-build), is not the user's, or lies in a directory others
# (group or anyone) can write to. DIR is made the user's alone (mode 700).
#
# Needs cmake, a C++ compiler and Qt 6's development files (Core, DBus); sha256sum, find,
# sort and xargs for the stamp. Exit status: 0 built or up to date, 1 the build failed,
# 2 refused, a wrong option, or a tool missing.
set -uo pipefail

repo=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd -P)
source_dir=$repo/helper
mark=.h2s-helper-build

say() { echo "build-helper.sh: $*" >&2; }
usage() { echo "usage: scripts/build-helper.sh [--out DIR] [--if-changed] [--time-limit S] [--print-path | --status]" >&2; exit 2; }

out=""
if_changed=0
print_path=0
status_only=0
time_limit=300
while [ $# -gt 0 ]; do
    case "$1" in
        --out) [ $# -ge 2 ] || usage; out=$2; shift ;;
        --if-changed) if_changed=1 ;;
        --print-path) print_path=1 ;;
        --status) status_only=1 ;;
        --time-limit) [ $# -ge 2 ] && [[ "$2" =~ ^[1-9][0-9]{0,4}$ ]] || usage; time_limit=$2; shift ;;
        *) usage ;;
    esac
    shift
done

[ "$(id -u)" != 0 ] || { say "refused: not as root (the helper is the user's program)"; exit 2; }
for tool in sha256sum find sort xargs; do
    command -v "$tool" > /dev/null || { say "$tool not found on PATH (the stamp of the helper's source)"; exit 2; }
done
[ -f "$source_dir/CMakeLists.txt" ] || { say "this checkout has no helper ($source_dir/CMakeLists.txt)"; exit 2; }

if [ -z "$out" ]; then
    key=$(printf '%s' "$repo" | sha256sum | cut -c 1-16)
    out=${XDG_CACHE_HOME:-$HOME/.cache}/h2s-shell/helper/$key
fi

# The directory, checked before anything is written
case "$out" in
    /*) ;;
    *) say "refused: $out is not an absolute path"; exit 2 ;;
esac
case "/$out/" in
    */../* | */./*) say "refused: $out has . or .. in it"; exit 2 ;;
esac
out=${out%/}
[ -n "$out" ] || { say "refused: / is not a build directory"; exit 2; }
# Where it really is: the nearest part that exists, links resolved, and the rest
existing=$out rest=""
while [ ! -e "$existing" ] && [ ! -L "$existing" ]; do
    rest=/${existing##*/}$rest
    existing=${existing%/*}
    [ -n "$existing" ] || existing=/
done
if [ "$existing" = "$out" ]; then
    if [ -L "$out" ] || [ ! -d "$out" ]; then
        say "refused: $out is a link or not a directory"
        exit 2
    fi
fi
real=$(cd -P -- "$existing" 2> /dev/null && pwd -P) || { say "refused: $existing cannot be entered"; exit 2; }
real=${real%/}$rest
case "$real/" in
    "$repo"/*) say "refused: $out is inside the checkout ($repo)"; exit 2 ;;
esac
if [ -d "$out" ] && [ ! -e "$out/$mark" ] && [ -n "$(ls -A "$out" 2> /dev/null)" ]; then
    say "refused: $out holds files this script did not make (no $mark in it)"
    exit 2
fi

binary=$out/h2s-helper
if [ "$print_path" = 1 ]; then
    echo "$binary"
    exit 0
fi

stamp=$({
    sha256sum "$repo/scripts/build-helper.sh" | cut -d ' ' -f 1
    (cd "$repo" && find helper -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum)
} | sha256sum | cut -d ' ' -f 1)

built_from=""
failed_from=""
[ -f "$out/source.stamp" ] && read -r built_from < "$out/source.stamp"
[ -f "$out/failed.stamp" ] && read -r failed_from < "$out/failed.stamp"
if [ "$status_only" = 1 ]; then
    if [ "$failed_from" = "$stamp" ]; then echo failed
    elif [ ! -x "$binary" ]; then echo missing
    elif [ "$built_from" = "$stamp" ]; then echo current
    else echo stale
    fi
    exit 0
fi

version=$(sed -n 's/.*readonly property string number: "\([^"]*\)".*/\1/p' "$repo/singletons/Version.qml" | head -n 1)
[ -n "$version" ] || { say "cannot read the shell's version from singletons/Version.qml"; exit 2; }

mkdir -p "$out" || { say "cannot make $out"; exit 2; }
# The user's alone, in a directory nobody else can write to (else another user could swap
# the binary the shell starts)
parent=$(dirname "$out")
if [ ! -O "$out" ] || [ -L "$out" ]; then
    say "refused: $out is not yours"
    exit 2
fi
if [ -n "$(find "$parent" -maxdepth 0 -perm /022 2> /dev/null)" ] || ! { [ -O "$parent" ] || [ "$(stat -c %u "$parent")" = 0 ]; }; then
    say "refused: $parent can be written by others, or is neither yours nor root's"
    exit 2
fi
chmod 700 "$out" || { say "cannot make $out yours alone"; exit 2; }
: > "$out/$mark"
# One build at a time in this directory (install.sh and a launcher may meet)
if command -v flock > /dev/null; then
    exec {lock_fd}> "$out/.lock" && flock "$lock_fd"
fi

# (Read again under the lock: another build may have ended while this one waited)
built_from=""
failed_from=""
[ -f "$out/source.stamp" ] && read -r built_from < "$out/source.stamp"
[ -f "$out/failed.stamp" ] && read -r failed_from < "$out/failed.stamp"
if [ "$if_changed" = 1 ]; then
    if [ -x "$binary" ] && [ "$built_from" = "$stamp" ]; then
        echo "$binary"
        exit 0
    fi
    if [ "$failed_from" = "$stamp" ]; then
        say "this source failed to build before (log: $out/build.log); scripts/build-helper.sh without --if-changed tries again"
        exit 1
    fi
fi

command -v cmake > /dev/null || { say "cmake not found on PATH (builds the helper)"; echo "$stamp" > "$out/failed.stamp"; exit 2; }

# Each cmake step under what is left of the bound (`timeout` from PATH; without it, unbounded)
deadline=$((SECONDS + time_limit))
bounded() {
    local left=$((deadline - SECONDS))
    [ "$left" -gt 0 ] || return 124
    if command -v timeout > /dev/null; then
        timeout -k 5 "$left" "$@"
    else
        "$@"
    fi
}
say "building the helper ($version) in $out"
status=0
{ bounded cmake -S "$source_dir" -B "$out/build" -DCMAKE_BUILD_TYPE=Release -DH2S_VERSION="$version" \
    && bounded cmake --build "$out/build" --parallel; } > "$out/build.log" 2>&1 || status=$?
if [ "$status" != 0 ]; then
    echo "$stamp" > "$out/failed.stamp"
    tail -n 15 "$out/build.log" >&2
    if [ "$status" = 124 ] || [ "$status" = 137 ]; then
        say "the build took longer than $time_limit s and was ended; the log: $out/build.log"
    else
        say "the build failed; the whole log: $out/build.log"
    fi
    exit 1
fi
if ! { cp -f "$out/build/h2s-helper" "$binary.new" && mv -f "$binary.new" "$binary"; }; then
    rm -f "$binary.new"
    echo "$stamp" > "$out/failed.stamp"
    say "the build ended without a binary to put in place"
    exit 1
fi
echo "$stamp" > "$out/source.stamp"
rm -f "$out/failed.stamp"
echo "$binary"
