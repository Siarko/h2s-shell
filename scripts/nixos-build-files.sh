#!/usr/bin/env bash
# The private folder of the user's NixOS build (distributions/nixos/NixosBuild.qml), as the
# user:
#
#   nixos-build-files.sh prepare <folder> <candidate JSON> <gitconfig text | "">
#   nixos-build-files.sh remove  <folder>
#
# <folder> is absolute, of plain names, and named h2s-shell-nixos-build (nothing else is ever
# removed). prepare removes what an earlier build left there (its GC root included), makes
# the folder anew, only the user's (0700), and writes the candidate as h2s-shell.json in it
# and, when given, home/.gitconfig (the scratch HOME nix runs with for a repository root
# owns). remove takes the folder away, and with it the GC root (result) that kept the built
# system. Its last line:
#
#   prepared | removed    exit 0
#   failed                exit 1
set -u
export LC_ALL=C
umask 077

fail() { echo failed; exit 1; }

op=${1-}
folder=${2-}
case "$folder" in
    /*/h2s-shell-nixos-build) ;;
    *) fail ;;
esac
case "$folder" in
    *[!A-Za-z0-9/._-]* | */./* | */../* | *//*) fail ;;
esac

case "$op" in
prepare)
    [ $# -eq 4 ] || fail
    rm -rf -- "$folder" 2> /dev/null || fail
    [ ! -e "$folder" ] && [ ! -L "$folder" ] || fail
    mkdir -m 0700 -- "$folder" || fail
    printf '%s' "$3" > "$folder/h2s-shell.json" || fail
    if [ -n "$4" ]; then
        mkdir -m 0700 -- "$folder/home" || fail
        printf '%s' "$4" > "$folder/home/.gitconfig" || fail
    fi
    echo prepared
    ;;
remove)
    [ $# -eq 2 ] || fail
    rm -rf -- "$folder" 2> /dev/null || fail
    [ ! -e "$folder" ] && [ ! -L "$folder" ] || fail
    echo removed
    ;;
*) fail ;;
esac
