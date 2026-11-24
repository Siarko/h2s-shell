#!/usr/bin/env bash
# The shell's file of a NixOS configuration that is the user's own, created as the user
# (distributions/nixos/NixosCreate.qml; a root-owned configuration's file is created by the
# root step instead, scripts/root/nixos-apply.sh's create):
#
#   nixos-create.sh <absolute folder>
#
# Writes {"version":1} as <folder>/h2s-shell.json only when nothing is there under that name
# (a file, a folder or a link, even one that leads nowhere): the new file is written beside
# it under a temporary name, then hard-linked into place — the link fails when the name is
# taken, so nothing is ever overwritten. Its last line says what it did:
#
#   created    exit 0
#   exists     exit 3   something is there already: nothing written
#   failed     exit 1   anything else (the folder is not there, or not writable)
set -u
export LC_ALL=C

folder=${1-}
name=h2s-shell.json

if [ $# -ne 1 ] || [ "${folder#/}" = "$folder" ] || [ ! -d "$folder" ]; then
    echo failed
    exit 1
fi
target=$folder/$name
if [ -e "$target" ] || [ -L "$target" ]; then
    echo exists
    exit 3
fi
umask 022
temporary=$(mktemp "$folder/.$name.XXXXXX" 2> /dev/null) || { echo failed; exit 1; }
if ! printf '{"version":1}\n' > "$temporary" || ! chmod 644 "$temporary"; then
    rm -f -- "$temporary"
    echo failed
    exit 1
fi
if ln -- "$temporary" "$target" 2> /dev/null; then
    rm -f -- "$temporary"
    echo created
    exit 0
fi
rm -f -- "$temporary"
if [ -e "$target" ] || [ -L "$target" ]; then
    echo exists
    exit 3
fi
echo failed
exit 1
