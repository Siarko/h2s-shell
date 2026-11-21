#!/usr/bin/env bash
# Checks tests/affected.sh: that every tracked file of this tree is placed and the map is
# true (affected.sh --check), what a few changes of this tree select, and — in made-up
# repositories with a copy of the script — the closure (a suite covers what it uses,
# transitively), the map's targets, the lock closure, the default range (the nearest
# segment-* or master merge-base, working tree and untracked files included), explicit
# ranges, the fallback for a file placed nowhere, --check's findings and --run's verdict.
# Nothing is run but stand-in runners.
#
# Exit status: 0 when every check passed, 1 otherwise.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/affected-selftest.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$work"' EXIT
failed=0
check() {
    local description=$1
    shift
    if "$@"; then echo "  PASS $description"; else echo "  FAIL $description"; failed=1; fi
}
# run <tree> <arguments…>: OUTPUT (stdout), ERRORS (stderr), STATUS
run() {
    local tree=$1
    shift
    OUTPUT=$(cd "$tree" && tests/affected.sh "$@" 2> "$work/stderr")
    STATUS=$?
    ERRORS=$(cat "$work/stderr")
}
is() { [ "$OUTPUT" = "$1" ]; }
has_line() { grep -qxF -- "$1" <<< "$OUTPUT"; }
has() { grep -qF -- "$1" <<< "$OUTPUT"; }

echo "This tree:"
run "$REPO" --check
check "every tracked file is placed and the map is true" [ "$STATUS" = 0 ]
[ "$STATUS" = 0 ] || printf '%s\n' "$OUTPUT" | sed 's/^/    /'
run "$REPO" --files notes/tracker.md
check "a note selects nothing" is ""
run "$REPO" --files tests/TestCase.qml
check "TestCase selects every unit suite" has_line "tests/run-unit.sh"
check "… and both module fixture parts" [ "$(grep -c '^tests/run-modules.sh ' <<< "$OUTPUT")" = 2 ]
run "$REPO" --files singletons/Theme.qml
check "Theme selects the suites that read it" bash -c 'grep -q "^tests/run-unit.sh .*ThemeTest" <<< "$1" && grep -q "ButtonKindsTest" <<< "$1"' _ "$OUTPUT"
check "… and not a pure rules suite" bash -c '! grep -qw FormatTest <<< "$1"' _ "$OUTPUT"
run "$REPO" --files singletons/Format.qml
check "Format selects FormatTest" has "FormatTest"
run "$REPO" --files tests/lock/tests/relock.sh
check "a scenario selects itself" is "tests/lock/run.sh relock"
run "$REPO" --files scripts/launch.sh
check "the launcher selects its self-test" has_line "tests/launcher-selftest.sh"
check "… and the restart and supervisor scenarios" bash -c 'grep -q "^tests/lock/run.sh .*restart-kill-locked.*supervisor" <<< "$1"' _ "$OUTPUT"
run "$REPO" --files scripts/lock-auth-methods.sh
check "the methods script selects the methods scenarios" has_line "tests/lock/run.sh methods-empty methods-fail methods-fprintd methods-hang methods-script"
run "$REPO" --files tests/run-all.sh
check "a runner selects its self-test" is "tests/run-all-selftest.sh"
run "$REPO" --files nowhere/new-file.txt
check "a file placed nowhere selects every unit suite" is "tests/run-unit.sh"
check "… and is named" grep -q "nowhere/new-file.txt is placed nowhere" <<< "$ERRORS"

# ---- A made-up repository --------------------------------------------------------------
tree=$work/tree
mkdir -p "$tree/tests/lock/tests" "$tree/singletons" "$tree/screensaver" "$tree/notes" "$tree/scripts" "$tree/fixtures/mod"
cp "$REPO/tests/affected.sh" "$REPO/tests/count-suites.sh" "$tree/tests/"
cat > "$tree/tests.qml" << 'EOF'
Item {
    property var _a: ATest {}
    property var _b: BTest {}
    property var _surface: SurfaceTest {}
}
EOF
cat > "$tree/tests/ATest.qml" << 'EOF'
import qs.singletons
TestCase { function test() { return A.value } }
EOF
cat > "$tree/tests/BTest.qml" << 'EOF'
import qs.singletons
// A is named in this comment only: not a dependency
TestCase { function test() { return B.value + "A" } }
EOF
cat > "$tree/tests/SurfaceTest.qml" << 'EOF'
import qs.screensaver
TestCase { Surface {} }
EOF
echo 'Item {}' > "$tree/tests/TestCase.qml"
echo 'Item { property int value: B.value; property string script: "/scripts/run.sh" }' > "$tree/singletons/A.qml"
echo 'Item { property int value: 1 }' > "$tree/singletons/B.qml"
echo 'Item {}' > "$tree/singletons/Shared.qml"
echo 'Item {}' > "$tree/tests-modules.qml"
printf 'import qs.singletons\nItem { Shared {} }\n' > "$tree/screensaver/Surface.qml"
echo 'module' > "$tree/fixtures/mod/main.qml"
echo 'echo run' > "$tree/scripts/run.sh"
echo 'notes' > "$tree/notes/plan.md"
for name in one two three; do echo 'echo PASS' > "$tree/tests/lock/tests/$name.sh"; done
cat > "$tree/tests/run-all.sh" << 'EOF'
parts=(
    "unit suites|tests/run-unit.sh"
    "module fixture suites|tests/run-modules.sh fixtures/mod"
    "lock bed|tests/lock/run.sh"
)
EOF
# Stand-in runners: they record how they were called; a file "fail" makes the unit one fail
for runner in tests/run-unit.sh tests/run-modules.sh tests/lock/run.sh tests/x-selftest.sh; do
    printf '#!/usr/bin/env bash\necho "%s $*" >> calls\n[ "%s" != tests/run-unit.sh ] || [ ! -e fail ]\n' "$runner" "$runner" > "$tree/$runner"
    chmod +x "$tree/$runner"
done
cat > "$tree/tests/affected-map.txt" << 'EOF'
@lock-roots screensaver/*
notes/* none
.gitignore none
tests/run-all.sh self:tests/x-selftest.sh
tests/affected* self:tests/x-selftest.sh
tests/count-suites.sh unit:all
tests.qml unit:all
tests/TestCase.qml unit:all modules:all
tests-modules.qml modules:all
tests/run-unit.sh unit:all
tests/run-modules.sh modules:all
tests/lock/run.sh lock:all
tests/x-selftest.sh none
scripts/run.sh lock:two
@lock lock:two
EOF
printf 'calls\nfail\n' > "$tree/.gitignore"
git -C "$tree" init -q -b master
git -C "$tree" -c user.name=t -c user.email=t@t add -A
git -C "$tree" -c user.name=t -c user.email=t@t commit -q -m base
commit() { git -C "$tree" -c user.name=t -c user.email=t@t commit -q -am "$1"; }

echo "A made-up repository:"
run "$tree" --check
check "--check passes on a tree whose files are all placed" [ "$STATUS" = 0 ]
[ "$STATUS" = 0 ] || printf '%s\n%s\n' "$OUTPUT" "$ERRORS" | sed 's/^/    /'
run "$tree" --files singletons/B.qml
check "a singleton used through another selects both suites" is "tests/run-unit.sh ATest BTest"
run "$tree" --files singletons/A.qml
check "a comment and a string name nothing" is "tests/run-unit.sh ATest"
run "$tree" --files scripts/run.sh
check "a script named by a suite's subject selects the suite, and the map adds its scenario" \
    is "$(printf 'tests/run-unit.sh ATest\ntests/lock/run.sh two')"
run "$tree" --files singletons/Shared.qml
check "the lock closure selects the scenarios the map does not name, and those given @lock" \
    is "$(printf 'tests/run-unit.sh SurfaceTest\ntests/lock/run.sh one three two')"
run "$tree" --files fixtures/mod/main.qml
check "a module part's file selects that part" is "tests/run-modules.sh fixtures/mod"
run "$tree" --files tests/TestCase.qml
check "modules:all and unit:all" is "$(printf 'tests/run-unit.sh\ntests/run-modules.sh fixtures/mod')"
run "$tree" --files notes/plan.md
check "a none file selects nothing" bash -c '[ -z "$1" ] && [ "$2" = 0 ]' _ "$OUTPUT" "$STATUS"
run "$tree" --files tests/lock/tests/three.sh tests/x-selftest.sh
check "a scenario and a self-test select themselves" is "$(printf 'tests/x-selftest.sh\ntests/lock/run.sh three')"

# The default range: from the nearest segment-* or master merge-base, plus the working tree
git -C "$tree" checkout -q -b segment-a
echo 'Item { property int value: 2 }' > "$tree/singletons/B.qml"
commit "segment: B"
git -C "$tree" checkout -q -b work
echo 'Item { property int value: B.value + 3; property string script: "/scripts/run.sh" }' > "$tree/singletons/A.qml"
commit "work: A"
run "$tree"
check "the branch against segment-a, not master: A's change only" is "tests/run-unit.sh ATest"
echo 'more notes' >> "$tree/notes/plan.md"
echo 'echo PASS' > "$tree/tests/lock/tests/four.sh"
run "$tree"
check "the working tree and untracked files count" is "$(printf 'tests/run-unit.sh ATest\ntests/lock/run.sh four')"
git -C "$tree" checkout -q notes/plan.md
rm "$tree/tests/lock/tests/four.sh"
run "$tree" "master..work"
check "an explicit range" is "tests/run-unit.sh ATest BTest"
run "$tree" "HEAD^!"
check "a single commit, as git diff takes it" is "tests/run-unit.sh ATest"
run "$tree" "no-such-ref..HEAD"
check "a range git cannot read: status 2" [ "$STATUS" = 2 ]
run "$tree" --bogus
check "a wrong option: status 2" [ "$STATUS" = 2 ]
run "$tree" --why --files singletons/B.qml
check "--why names each file and what it selects" is "$(printf 'singletons/B.qml\tunit:ATest unit:BTest')"
git -C "$tree" checkout -q master
run "$tree"
check "on master, against a segment-* branch made from it: the working tree only" bash -c '[ "$1" = 0 ] && [ -z "$2" ]' _ "$STATUS" "$OUTPUT"
git -C "$tree" branch -q -D segment-a work
run "$tree"
check "on master, with no other branch to compare with: status 2, a range asked for" \
    bash -c '[ "$1" = 2 ] && grep -q "name a range" <<< "$2"' _ "$STATUS" "$ERRORS"

# --run: every command runs, through the runners; a failing one fails the run
rm -f "$tree/calls"
run "$tree" --run --files singletons/Shared.qml
check "--run runs each command" bash -c '[ "$1" = 0 ] && [ "$(cat "$2/calls")" = "$(printf "tests/run-unit.sh SurfaceTest\ntests/lock/run.sh one three two")" ]' _ "$STATUS" "$tree"
rm -f "$tree/calls"
touch "$tree/fail"
run "$tree" --run --files singletons/Shared.qml
check "--run: a failing command fails the run, the others still run" \
    bash -c '[ "$1" = 1 ] && [ "$(wc -l < "$2/calls")" = 2 ] && grep -q "FAILED" <<< "$3"' _ "$STATUS" "$tree" "$OUTPUT"
rm -f "$tree/fail"

# --check finds what is not placed and map lines that are not true
echo 'stray' > "$tree/stray.txt"
git -C "$tree" add stray.txt
echo 'gone/* none' >> "$tree/tests/affected-map.txt"
echo 'notes/* unit:NoSuchTest lock:nothing* self:tests/missing.sh' >> "$tree/tests/affected-map.txt"
run "$tree" --check
check "--check fails" [ "$STATUS" = 1 ]
check "… naming a tracked file placed nowhere" has "not placed: stray.txt"
check "… a pattern that matches no file" has "'gone/*' matches no file"
check "… a suite tests.qml does not register" has "unit:NoSuchTest is no suite"
check "… a scenario glob that names none" has "lock:nothing* names no scenario"
check "… a self-test that is not there" has "self:tests/missing.sh is not an executable"

echo
if [ "$failed" = 0 ]; then echo "affected-selftest.sh: passed"; else echo "affected-selftest.sh: FAILED"; fi
exit "$failed"
