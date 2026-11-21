#!/usr/bin/env bash
# Checks tests/docs-check.sh — the documentation's rules lint — on stand-in trees of
# Markdown (a README.md and a docs/ each): a good one passes, each kind of bad one is found
# with its file, line and rule, and what only looks like a breach (a link in code, the word
# "Architecture", a heading naming both systems) is not. Then the lint on this checkout's
# own README.md and docs/, which must pass.
#
#   tests/docs-check-selftest.sh
#
# Needs only bash, coreutils, find, grep and awk. Takes no lock.
#
# Exit status: 0 when every check passed, 1 when one failed, 2 when it could not be set up.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
LINT=$REPO/tests/docs-check.sh
work=$(mktemp -d "${TMPDIR:-/tmp}/docs-check-self.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
failed=0
check() {
    local description=$1
    shift
    if "$@"; then echo "  PASS $description"; else echo "  FAIL $description"; failed=1; fi
}

# tree <name>: a stand-in checkout with a good README.md, docs/guide.md and notes/
tree() {
    local dir=$work/$1
    mkdir -p "$dir/docs/dev" "$dir/notes"
    echo "# notes" > "$dir/notes/tracker.md"
    cat > "$dir/README.md" << 'EOF'
# A shell

See the [guide](docs/guide.md), the [changes](CHANGELOG.md#unreleased) and
[the site](https://example.org/notes/page.html).

## Install

### NixOS

The flake.

### Arch Linux

The script, `~/.config/shell` by default.
EOF
    echo "# Changes" > "$dir/CHANGELOG.md"
    cat > "$dir/docs/guide.md" << 'EOF'
# Guide

The [architecture](dev/architecture.md), [back](../README.md), [here](#guide).

## Architecture

A heading named Architecture is not about Arch.

## Paths on NixOS and Arch

One heading naming both.

```
[not a link](../notes/tracker.md)
#### NixOS
```

Inline code is not a link either: `[x](../notes/tracker.md)`.

[ref]: dev/architecture.md
EOF
    echo "# Architecture" > "$dir/docs/dev/architecture.md"
}

# run <name> [options…]: OUTPUT and STATUS of the lint on that tree
run() {
    local name=$1
    shift
    OUTPUT=$("$LINT" --rules --root "$work/$name" "$@" 2>&1)
    STATUS=$?
}
status_is() { [ "$STATUS" = "$1" ]; }
says() { grep -q -- "$1" <<< "$OUTPUT"; }
findings_are() { [ "$(grep -c '^[^ ]*:[0-9]*: ' <<< "$OUTPUT")" = "$1" ]; }

tree good
run good
check "a good tree: status 0" status_is 0
check "a good tree: says passed, with the files it read" says "^docs-check: passed (3 files)$"
check "a good tree: no finding" findings_are 0

tree notes-link
echo "Working notes: [tracker](../notes/tracker.md)." >> "$work/notes-link/docs/guide.md"
echo "[todo]: notes/tracker.md" >> "$work/notes-link/README.md"
run notes-link
check "a link into notes/: status 1" status_is 1
check "a link into notes/: found in docs/, with its line" says "^docs/guide.md:21: notes-link: ../notes/tracker.md$"
check "a link into notes/: a reference definition in the README too" says "^README.md:15: notes-link: notes/tracker.md$"
check "a link into notes/: those two only" findings_are 2

tree broken
echo "Gone: [old](dev/gone.md#part)." >> "$work/broken/docs/guide.md"
run broken
check "a link to a missing file: status 1" status_is 1
check "a link to a missing file: named broken-link" says "^docs/guide.md:21: broken-link: dev/gone.md$"

tree environment
printf '%s\n' "Run it from /home/alice/src/shell." "Seen on the Framework 12 only." \
    "As on the owner's machine." "Or C:\\Users\\bob\\shell." >> "$work/environment/docs/dev/architecture.md"
printf '%s\n' '```' 'cd /Users/carol/shell' '```' >> "$work/environment/README.md"
run environment
check "a developer's environment: status 1" status_is 1
check "a developer's environment: a home path" says "^docs/dev/architecture.md:2: environment: Run it from /home/alice"
check "a developer's environment: a machine model" says "^docs/dev/architecture.md:3: environment: Seen on the Framework 12"
check "a developer's environment: the owner's machine" says "^docs/dev/architecture.md:4: environment: As on the owner's machine"
check "a developer's environment: a Windows home" says "^docs/dev/architecture.md:5: environment: "
check "a developer's environment: in a code block too" says "^README.md:16: environment: cd /Users/carol"
check "a developer's environment: those five only" findings_are 5

tree nixos-only
cat >> "$work/nixos-only/docs/guide.md" << 'EOF'

## Updating

### NixOS

`nix flake update`.

### Both

Restart.

## Removing

#### Arch

`pacman -R`.
EOF
run nixos-only
check "one system without the other: status 1" status_is 1
check "one system without the other: a NixOS heading alone" says "^docs/guide.md:24: systems: NixOS (no Arch heading beside it)$"
check "one system without the other: an Arch heading alone" says "^docs/guide.md:34: systems: Arch (no NixOS heading beside it)$"
check "one system without the other: the paired README is fine" findings_are 2

tree apart
cat >> "$work/apart/docs/guide.md" << 'EOF'

## Installing

### NixOS

The flake.

## Running

### Arch

The script.
EOF
run apart
check "the two systems under different parents: both found" findings_are 2

tree polish
echo "Ta funkcja jest gotowa." >> "$work/polish/docs/guide.md"
echo "Zażółć gęślą jaźń." >> "$work/polish/README.md"
run polish
check "text not in English: status 1" status_is 1
check "text not in English: a Polish word" says "^docs/guide.md:21: english: Ta funkcja jest gotowa.$"
check "text not in English: Polish letters" says "^README.md:15: english: "
check "text not in English: those two only" findings_are 2

run good --release
check "a wrong option: status 2" status_is 2
mkdir -p "$work/empty"
run empty
check "a tree with no README.md and no docs/: status 2" status_is 2

OUTPUT=$("$LINT" 2>&1)
STATUS=$?
echo "$OUTPUT" | sed 's/^/    /'
check "this checkout's README.md and docs/ keep the rules" status_is 0

echo
if [ "$failed" = 0 ]; then echo "docs-check self-test: passed"; else echo "docs-check self-test: FAILED"; fi
exit "$failed"
