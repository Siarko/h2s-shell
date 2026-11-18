#!/usr/bin/env bash
# Makes a test tree: a copy of this checkout in which the test seam files take the
# production ones' place, so that the shell started from it reads the test seams (stand-in
# tools, another PAM directory, short timings, the stand-in VPN provider, …) from its
# environment. The checkout itself, and the installed shell, read none of them: their
# seam files are constants. tests/lock/README.md, "The test tree", says what each file is,
# which variables count, and how to start the shell from such a tree by hand.
#
#   tests/test-tree.sh <dest>    <dest> must not exist, or be an empty directory, outside
#                                the checkout; prints the tree's path
#
# Swapped (the same names, read from the environment instead of fixed):
#   tests/lock/seams/TestSeams.qml      → singletons/TestSeams.qml
#   tests/lock/seams/TestSeamRules.qml  → singletons/TestSeamRules.qml (what each says)
#   tests/lock/seams/seams.sh           → scripts/seams.sh
# Everything else is the checkout as it is now, without .git and build results (result*).
# tests/lock/run.sh makes each run's copy with this script, then takes tests/lock out and
# puts PAM configs that only deny in pam/.
#
# Exit status: 0 with the tree made; 2 when it could not be made (nothing is left behind
# that this run created).
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd -P)
fail() { echo "test-tree.sh: $*" >&2; exit 2; }

[ $# -eq 1 ] && [ -n "$1" ] || { echo "usage: tests/test-tree.sh <dest>" >&2; exit 2; }
dest=$1
made=""
# Inside the checkout the copy would copy itself, and a running shell started from the
# checkout would reload on every file written. Judged before anything is created: the
# nearest existing ancestor's real path, with the missing rest appended
probe=$dest
rest=""
while [ ! -e "$probe" ]; do
    rest=/$(basename "$probe")$rest
    probe=$(dirname "$probe")
done
case "$rest/" in */../* | */./*) fail "$dest: no . or .. after the part that exists" ;; esac
real=$(cd "$probe" && pwd -P)$rest || fail "cannot enter $probe"
case "$real/" in "$REPO/"*) fail "$real is inside the checkout ($REPO)" ;; esac
if [ -e "$dest" ]; then
    [ -d "$dest" ] && [ -z "$(ls -A "$dest" 2> /dev/null)" ] || fail "$dest exists and is not an empty directory"
else
    mkdir -p "$dest" || fail "cannot create $dest"
    made=1
fi
dest=$(cd "$dest" && pwd -P) || fail "cannot enter $dest"
# Checked again on the made directory, in case a part of the path changed meanwhile
case "$dest/" in "$REPO/"*) [ -z "$made" ] || rmdir "$dest"; fail "$dest is inside the checkout ($REPO)" ;; esac

undo() { [ -n "$made" ] && rm -rf "$dest" || find "$dest" -mindepth 1 -delete 2> /dev/null; }
for entry in "$REPO"/* "$REPO"/.[!.]*; do
    [ -e "$entry" ] || continue
    case "$(basename "$entry")" in .git | result | result-*) continue ;; esac
    cp -a "$entry" "$dest/" || { undo; fail "cannot copy $entry into $dest"; }
done
seams=$REPO/tests/lock/seams
for pair in "TestSeams.qml singletons/TestSeams.qml" "TestSeamRules.qml singletons/TestSeamRules.qml" "seams.sh scripts/seams.sh"; do
    set -- $pair
    cp "$seams/$1" "$dest/$2" || { undo; fail "cannot put $1 into $dest/$2"; }
done
echo "$dest"
