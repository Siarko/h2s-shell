#!/usr/bin/env bash
# Builds the shell's helper (helper/: C++17, Qt 6 Core and DBus, CMake) from this checkout,
# outside it: into a directory of the user's cache, one per checkout, never into the tree.
# On NixOS the package builds it instead (nix/package.nix); on Arch install.sh runs this, and
# scripts/launch.sh runs it with --if-changed at each start, so an update that changes the
# helper's source rebuilds it.
#
#   scripts/build-helper.sh [--out DIR] [--if-changed] [--print-path]
#
#   --out DIR      where to build (an absolute path outside the checkout). The default is
#                  ${XDG_CACHE_HOME:-~/.cache}/h2s-shell/helper/<a hash of the checkout's path>
#   --if-changed   build only when the source (helper/, this script, the shell's version)
#                  differs from what the binary there was built from; a build of this
#                  same source that failed before is not tried again (run without it)
#   --print-path   print where the binary is, or would be, and build nothing
#
# Prints the binary's path on standard output when it is built or up to date; cmake's own
# output goes to <DIR>/build.log. The binary is replaced as a whole (renamed into place), so
# a helper running from it keeps running.
#
# It writes only into DIR, and refuses a DIR that is not absolute, lies inside the
# checkout, is a link or not a directory, or already holds something without the mark this
# script leaves there (.h2s-helper-build).
#
# Needs cmake, a C++ compiler and Qt 6's development files (Core, DBus); sha256sum, find,
# sort and xargs for the stamp. Exit status: 0 built or up to date, 1 the build failed,
# 2 refused, a wrong option, or a tool missing.
set -uo pipefail

repo=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd -P)
source_dir=$repo/helper
mark=.h2s-helper-build

say() { echo "build-helper.sh: $*" >&2; }
usage() { echo "usage: scripts/build-helper.sh [--out DIR] [--if-changed] [--print-path]" >&2; exit 2; }

out=""
if_changed=0
print_path=0
while [ $# -gt 0 ]; do
    case "$1" in
        --out) [ $# -ge 2 ] || usage; out=$2; shift ;;
        --if-changed) if_changed=1 ;;
        --print-path) print_path=1 ;;
        *) usage ;;
    esac
    shift
done

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

version=$(sed -n 's/.*readonly property string number: "\([^"]*\)".*/\1/p' "$repo/singletons/Version.qml" | head -n 1)
[ -n "$version" ] || { say "cannot read the shell's version from singletons/Version.qml"; exit 2; }
stamp=$({
    echo "version $version"
    sha256sum "$repo/scripts/build-helper.sh" | cut -d ' ' -f 1
    (cd "$repo" && find helper -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum)
} | sha256sum | cut -d ' ' -f 1)

mkdir -p "$out" || { say "cannot make $out"; exit 2; }
: > "$out/$mark"
# One build at a time in this directory (install.sh and a launcher may meet)
if command -v flock > /dev/null; then
    exec {lock_fd}> "$out/.lock" && flock "$lock_fd"
fi

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

say "building the helper ($version) in $out"
if ! { cmake -S "$source_dir" -B "$out/build" -DCMAKE_BUILD_TYPE=Release -DH2S_VERSION="$version" \
        && cmake --build "$out/build" --parallel; } > "$out/build.log" 2>&1; then
    echo "$stamp" > "$out/failed.stamp"
    tail -n 15 "$out/build.log" >&2
    say "the build failed; the whole log: $out/build.log"
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
