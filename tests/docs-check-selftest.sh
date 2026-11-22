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

# tree <name>: a stand-in checkout with a good README.md and docs/guide.md, in a directory
# that holds a file beside it (outside.md), as a checkout may sit beside other repositories
tree() {
    local dir=$work/$1/checkout
    mkdir -p "$dir/docs/dev"
    echo "# beside the checkout" > "$work/$1/outside.md"
    cat > "$dir/README.md" << 'EOF'
# A shell

See the [guide](docs/guide.md), the [changes](CHANGELOG.md#unreleased) and
[the site](https://example.org/page.html).

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
[not a link](../../outside.md)
#### NixOS
```

Inline code is not a link either: `[x](../../outside.md)`.

[ref]: dev/architecture.md
EOF
    echo "# Architecture" > "$dir/docs/dev/architecture.md"
}

# run <name> [options…]: OUTPUT and STATUS of the lint on that tree
run() {
    local name=$1
    shift
    OUTPUT=$("$LINT" --rules --root "$work/$name/checkout" "$@" 2>&1)
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

ln -s "$work/good/checkout" "$work/good-link"
OUTPUT=$("$LINT" --rules --root "$work/good-link" 2>&1)
STATUS=$?
check "a good tree through a symbolic link: status 0 (its links stay inside)" status_is 0

tree outside
echo "Beside: [it](../../outside.md)." >> "$work/outside/checkout/docs/guide.md"
echo "[beside]: ../outside.md" >> "$work/outside/checkout/README.md"
echo "Gone too: [far](../../../nowhere.md)." >> "$work/outside/checkout/README.md"
run outside
check "a link out of the repository: status 1" status_is 1
check "a link out of the repository: found in docs/, though the file is there" says "^docs/guide.md:21: outside-link: ../../outside.md$"
check "a link out of the repository: a reference definition in the README too" says "^README.md:15: outside-link: ../outside.md$"
check "a link out of the repository: one to nothing is that, not a broken link" says "^README.md:16: outside-link: ../../../nowhere.md$"
check "a link out of the repository: those three only" findings_are 3

tree broken
echo "Gone: [old](dev/gone.md#part)." >> "$work/broken/checkout/docs/guide.md"
run broken
check "a link to a missing file: status 1" status_is 1
check "a link to a missing file: named broken-link" says "^docs/guide.md:21: broken-link: dev/gone.md$"

tree environment
printf '%s\n' "Run it from /home/alice/src/shell." "Seen on the Framework 12 only." \
    "As on the owner's machine." "Or C:\\Users\\bob\\shell." "Clone it into ~/src/shell." \
    >> "$work/environment/checkout/docs/dev/architecture.md"
printf '%s\n' '```' 'cd /Users/carol/shell' '```' >> "$work/environment/checkout/README.md"
run environment
check "a developer's environment: status 1" status_is 1
check "a developer's environment: a home path" says "^docs/dev/architecture.md:2: environment: Run it from /home/alice"
check "a developer's environment: a machine model" says "^docs/dev/architecture.md:3: environment: Seen on the Framework 12"
check "a developer's environment: the owner's machine" says "^docs/dev/architecture.md:4: environment: As on the owner's machine"
check "a developer's environment: a Windows home" says "^docs/dev/architecture.md:5: environment: "
check "a developer's environment: a checkout folder under ~" says "^docs/dev/architecture.md:6: environment: Clone it into ~/src/shell"
check "a developer's environment: in a code block too" says "^README.md:16: environment: cd /Users/carol"
check "a developer's environment: those six only" findings_are 6

tree nixos-only
cat >> "$work/nixos-only/checkout/docs/guide.md" << 'EOF'

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
cat >> "$work/apart/checkout/docs/guide.md" << 'EOF'

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
echo "Ta funkcja jest gotowa." >> "$work/polish/checkout/docs/guide.md"
echo "Zażółć gęślą jaźń." >> "$work/polish/checkout/README.md"
run polish
check "text not in English: status 1" status_is 1
check "text not in English: a Polish word" says "^docs/guide.md:21: english: Ta funkcja jest gotowa.$"
check "text not in English: Polish letters" says "^README.md:15: english: "
check "text not in English: those two only" findings_are 2

run good --release
check "a wrong option: status 2" status_is 2
mkdir -p "$work/empty/checkout"
run empty
check "a tree with no README.md and no docs/: status 2" status_is 2

OUTPUT=$("$LINT" 2>&1)
STATUS=$?
echo "$OUTPUT" | sed 's/^/    /'
check "this checkout's README.md and docs/ keep the rules" status_is 0

echo
if [ "$failed" = 0 ]; then echo "docs-check self-test: passed"; else echo "docs-check self-test: FAILED"; fi
exit "$failed"
