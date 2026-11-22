#!/usr/bin/env bash
# Checks tests/notes-ref-check.sh — no tracked file mentions the working notes — on stand-in
# git trees: a clean one passes; each kind of mention is found with its file and line; what
# only looks like one (a module named notes, "src/notes/", the word, "notes.db") is not;
# CHANGELOG.md's released sections and the check's own files are left alone; the allowance
# reports what it lists, and fails on more mentions than it allows and on counts that are
# too high. Then the check on this checkout, which must pass.
#
#   tests/notes-ref-check-selftest.sh
#
# Needs only bash, coreutils, git, grep, awk and sed. Takes no lock.
#
# Exit status: 0 when every check passed, 1 when one failed, 2 when it could not be set up.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
CHECK=$REPO/tests/notes-ref-check.sh
work=$(mktemp -d "${TMPDIR:-/tmp}/notes-ref-self.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
failed=0
check() {
    local description=$1
    shift
    if "$@"; then echo "  PASS $description"; else echo "  FAIL $description"; failed=1; fi
}
command -v git > /dev/null || { echo "notes-ref-check self-test: no git" >&2; exit 2; }
word=notes

# tree <name>: a stand-in git tree with nothing to find, everything tracked
tree() {
    local dir=$work/$1
    mkdir -p "$dir/tests" "$dir/src"
    cat > "$dir/src/Module.qml" << EOF
// A module named $word, installed from src/$word/: no mention
property string path: versions + "/$word/0.3.0"
property string data: "$word.db"
// Release $word are in the changelog.
EOF
    cat > "$dir/CHANGELOG.md" << EOF
# Changelog

## [Unreleased]

- Something.

## [1.0.0] - 2026-01-01

- A plan ($word/plans/x.md), as released.
EOF
    cat > "$dir/tests/notes-ref-check.sh" << EOF
# looks for $word/ and ../$word
EOF
    git -C "$dir" init -q
    git -C "$dir" add -A
}

# run <name> [options…]: OUTPUT and STATUS of the check on that tree
run() {
    local name=$1
    shift
    OUTPUT=$("$CHECK" --root "$work/$name" "$@" 2>&1)
    STATUS=$?
}
status_is() { [ "$STATUS" = "$1" ]; }
says() { grep -q -- "$1" <<< "$OUTPUT"; }
findings_are() { [ "$(grep -cE '^[^ ]+:[0-9]+: ' <<< "$OUTPUT")" = "$1" ]; }
allow() { printf '%s\n' "$2" > "$work/$1/tests/notes-ref-allowance.txt"; git -C "$work/$1" add -A; }

tree clean
run clean
check "a clean tree: status 0" status_is 0
check "a clean tree: says passed" says "^notes-ref-check: passed$"
check "a clean tree: no finding (a module named so, src/…/, the word, .db, a released changelog line, its own files)" findings_are 0

tree found
cat > "$work/found/src/Thing.qml" << EOF
// Why: see $word/plans/thing.md
Item {}
EOF
printf '%s\n' 'excluded = [' "  ../$word" ']' > "$work/found/src/package.nix"
printf '%s\n' '#!/usr/bin/env bash' "mkdir -p \"\$tree/$word\"" "ls \"\${root}/$word/x\"" > "$work/found/src/run.sh"
sed -i "s|- Something.|- Something (./$word/a.md).|" "$work/found/CHANGELOG.md"
echo "untracked: $word/b.md" > "$work/found/src/untracked.txt"
git -C "$work/found" add src/Thing.qml src/package.nix src/run.sh CHANGELOG.md
run found
check "mentions: status 1" status_is 1
check "mentions: a path in a comment, with its line" says "^src/Thing.qml:1: // Why: see $word/plans/thing.md$"
check "mentions: ../ without a slash after" says "^src/package.nix:2:   ../$word$"
check "mentions: a variable's directory" says "^src/run.sh:2: "
check "mentions: a variable's directory in braces" says "^src/run.sh:3: "
check "mentions: in the changelog's Unreleased section" says "^CHANGELOG.md:5: "
check "mentions: those five only (not an untracked file)" findings_are 5
check "mentions: counted" says "^notes-ref-check: 5 finding(s)$"

tree allowed
printf '%s\n' "// $word/a.md" "// and $word/b.md" > "$work/allowed/src/Old.qml"
echo "// $word/c.md" > "$work/allowed/src/New.qml"
allow allowed "# a comment
2 src/Old.qml"
run allowed
check "an allowance: what it lists is no finding, the rest is" findings_are 1
check "an allowance: the file it does not list" says "^src/New.qml:1: "
allow allowed "2 src/Old.qml  # comment
1 src/New.qml"
run allowed
check "an allowance that covers all: status 0" status_is 0
check "an allowance that covers all: reported" says "^notes-ref-check: 3 allowed mention(s) in 2 file(s), listed in tests/notes-ref-allowance.txt$"
run allowed --list
check "--list: names each allowed mention" bash -c '[ "$(grep -c "^  allowed src/" <<< "$1")" = 3 ]' _ "$OUTPUT"
echo "// $word/d.md" >> "$work/allowed/src/New.qml"
run allowed
check "more mentions than allowed: status 1" status_is 1
check "more mentions than allowed: every one of them shown" findings_are 2
check "more mentions than allowed: said" says "^src/New.qml: 2 mentions, the allowance gives it 1$"
allow allowed "3 src/Old.qml
2 src/New.qml"
run allowed
check "a count higher than the mentions: status 1" status_is 1
check "a count higher than the mentions: lower it" says "src/Old.qml has 2 mentions now, not 3: lower its count$"
allow allowed "2 src/Old.qml
2 src/New.qml
1 src/Gone.qml"
run allowed
check "a file with no mention left: remove its line" says "src/Gone.qml has no mention now: remove its line$"
check "… the only finding" says "^notes-ref-check: 1 finding(s)$"
allow allowed "two src/Old.qml"
run allowed
check "an allowance line that is not <count> <path>: status 2" status_is 2

run clean --release
check "a wrong option: status 2" status_is 2
mkdir -p "$work/plain"
run plain
check "a directory that is no git tree: status 2" status_is 2

OUTPUT=$("$CHECK" 2>&1)
STATUS=$?
echo "$OUTPUT" | sed 's/^/    /'
check "this checkout mentions the notes nowhere beyond its allowance" status_is 0

echo
if [ "$failed" = 0 ]; then echo "notes-ref-check self-test: passed"; else echo "notes-ref-check self-test: FAILED"; fi
exit "$failed"
