#!/usr/bin/env bash
# Checks tests/affected.sh: that every tracked file of this tree is placed and the map is
# true (affected.sh --check), what a few changes of this tree select, and — in made-up
# repositories with a copy of the script — the closure (a suite covers what it uses,
# transitively), the map's targets, the lock closure, the default range (the nearest
# segment-* or master merge-base, working tree and untracked files included), the mockups
# (a mockup covers its folder's closure, the kit and the entry all, planning none), explicit
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
# run <tree> <arguments…>: OUTPUT (stdout), ERRORS (stderr), STATUS. In this tree every
# file selects the notes guard (the map's "+*" line): GUARDED says whether it did, and its
# line is left out of OUTPUT, so the checks read what the file itself selects
GUARD=tests/notes-ref-check-selftest.sh
run() {
    local tree=$1
    shift
    OUTPUT=$(cd "$tree" && tests/affected.sh "$@" 2> "$work/stderr")
    STATUS=$?
    ERRORS=$(cat "$work/stderr")
    GUARDED=0
    if [ "$tree" = "$REPO" ] && grep -qxF "$GUARD" <<< "$OUTPUT"; then
        GUARDED=1
        OUTPUT=$(grep -vxF "$GUARD" <<< "$OUTPUT")
    fi
}
is() { [ "$OUTPUT" = "$1" ]; }
has_line() { grep -qxF -- "$1" <<< "$OUTPUT"; }
has() { grep -qF -- "$1" <<< "$OUTPUT"; }

echo "This tree:"
run "$REPO" --check
check "every tracked file is placed and the map is true" [ "$STATUS" = 0 ]
[ "$STATUS" = 0 ] || printf '%s\n' "$OUTPUT" | sed 's/^/    /'
run "$REPO" --files .gitignore
check "a file that needs no test selects nothing" is ""
check "… but the notes guard, as every file does" [ "$GUARDED" = 1 ]
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
check "… and the notes guard" [ "$GUARDED" = 1 ]
run "$REPO" --files scripts/launch.sh
check "the launcher selects its self-test" has_line "tests/launcher-selftest.sh"
check "… and the restart and supervisor scenarios" bash -c 'grep -q "^tests/lock/run.sh .*restart-kill-locked.*supervisor" <<< "$1"' _ "$OUTPUT"
run "$REPO" --files tests/lock/launcher.sh
check "the bed's launcher selects the supervisor, restart and launcher scenarios" \
    bash -c 'grep -q "^tests/lock/run.sh .*harness .*modules-launcher .*restart-kill-locked .*supervisor" <<< "$1"' _ "$OUTPUT"
run "$REPO" --files singletons/lock/PamMethod.qml
check "a lock change runs the scenarios the map also names (harness, restart-*, supervisor)" \
    bash -c 'grep -q "^tests/lock/run.sh .*harness .*modules-discovery .*modules-launcher .*restart-crash-locked .*supervisor" <<< "$1"' _ "$OUTPUT"
run "$REPO" --files tests/lock/seams/TestSeams.qml
check "the bed's seams select the whole bed" has_line "tests/lock/run.sh"
run "$REPO" --files scripts/lock-auth-methods.sh
check "the methods script selects the methods scenarios" has_line "tests/lock/run.sh methods-empty methods-fail methods-fprintd methods-hang methods-script"
run "$REPO" --files tests/run-all.sh
check "a runner selects its self-test" is "tests/run-all-selftest.sh"
run "$REPO" --files nowhere/new-file.txt
check "a file placed nowhere selects everything" bash -c '[ "$(head -n 1 <<< "$1")" = tests/run-unit.sh ] && [ "$(grep -c "^tests/run-modules.sh" <<< "$1")" = 2 ] && [ "$(tail -n 1 <<< "$1")" = tests/lock/run.sh ]' _ "$OUTPUT"
check "… and is named" grep -q "nowhere/new-file.txt is placed nowhere" <<< "$ERRORS"

# ---- A made-up repository --------------------------------------------------------------
tree=$work/tree
mkdir -p "$tree/tests/lock/tests" "$tree/singletons" "$tree/screensaver" "$tree/site" "$tree/scripts" "$tree/fixtures/mod"
cp "$REPO/tests/affected.sh" "$REPO/tests/count-suites.sh" "$tree/tests/"
cat > "$tree/tests.qml" << 'EOF'
Item {
    property var _a: ATest {}
    property var _b: BTest {}
    property var _surface: SurfaceTest {}
    property var _c: CTest {}
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
# A lazy list: the views it quotes are loaded when shown, the singleton it uses is not
mkdir -p "$tree/views"
echo 'Item { property string view: "views/V.qml"; property int value: Helper.value }' > "$tree/singletons/Reg.qml"
echo 'Item { property int value: 1 }' > "$tree/singletons/Helper.qml"
echo 'Item {}' > "$tree/views/V.qml"
echo 'Item { property int value: Reg.value }' > "$tree/singletons/C.qml"
printf 'import qs.singletons\nTestCase { function test() { return C.value } }\n' > "$tree/tests/CTest.qml"
echo 'Item {}' > "$tree/singletons/Orphan.qml"
echo 'Item {}' > "$tree/screensaver/Old.qml"
echo 'Item {}' > "$tree/tests-modules.qml"
printf 'import qs.singletons\nItem { Shared {} Old {} }\n' > "$tree/screensaver/Surface.qml"
echo 'module' > "$tree/fixtures/mod/main.qml"
echo 'echo run' > "$tree/scripts/run.sh"
echo 'page' > "$tree/site/page.md"
# Mockups: a component one that draws a pill (with its baseline), a view one that does not,
# a planning one that does, the kit and the entry
mkdir -p "$tree/components" "$tree/mockups/kit" "$tree/mockups/components/pill/baseline" "$tree/mockups/views/panel" "$tree/mockups/planning/idea"
echo 'Item {}' > "$tree/components/Pill.qml"
echo 'Item {}' > "$tree/mockups/kit/MockupWindow.qml"
echo 'Item {}' > "$tree/mockup.qml"
printf 'import qs.components\nimport qs.mockups.kit\nMockupWindow { Pill {} }\n' > "$tree/mockups/components/pill/Mockup.qml"
echo 'scene 00 normal 10x10 0' > "$tree/mockups/components/pill/baseline/manifest.txt"
echo 'png' > "$tree/mockups/components/pill/baseline/00-normal.png"
printf 'import qs.mockups.kit\nMockupWindow {}\n' > "$tree/mockups/views/panel/Mockup.qml"
printf 'import qs.components\nimport qs.mockups.kit\nMockupWindow { Pill {} }\n' > "$tree/mockups/planning/idea/Mockup.qml"
echo 'notes' > "$tree/mockups/planning/idea/MOCKUP.md"
for name in one two three; do echo 'echo PASS' > "$tree/tests/lock/tests/$name.sh"; done
cat > "$tree/tests/run-all.sh" << 'EOF'
parts=(
    "unit suites|tests/run-unit.sh"
    "module fixture suites|tests/run-modules.sh fixtures/mod"
    "lock bed|tests/lock/run.sh"
)
EOF
# Stand-in runners: they record how they were called; a file "fail" makes the unit one fail
for runner in tests/run-unit.sh tests/run-modules.sh tests/lock/run.sh tests/x-selftest.sh tests/run-mockups.sh; do
    printf '#!/usr/bin/env bash\necho "%s $*" >> calls\n[ "%s" != tests/run-unit.sh ] || [ ! -e fail ]\n' "$runner" "$runner" > "$tree/$runner"
    chmod +x "$tree/$runner"
done
cat > "$tree/tests/affected-map.txt" << 'EOF'
@lock-roots screensaver/*
site/* none
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
tests/run-mockups.sh none
mockup.qml mockup:all
mockups/kit/* mockup:all
scripts/run.sh lock:two
@not-lock three
@lazy singletons/Reg.qml
views/V.qml none
singletons/Orphan.qml unit:BTest
+singletons/[BHL]* lock:three
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
check "a singleton used through another selects both suites" is "$(printf 'tests/run-unit.sh ATest BTest\ntests/lock/run.sh three')"
run "$tree" --files singletons/A.qml
check "a comment and a string name nothing" is "tests/run-unit.sh ATest"
run "$tree" --files scripts/run.sh
check "a script named by a suite's subject selects the suite, and the map adds its scenario" \
    is "$(printf 'tests/run-unit.sh ATest\ntests/lock/run.sh two')"
run "$tree" --files singletons/Shared.qml
check "the lock closure selects every scenario but the @not-lock ones" \
    is "$(printf 'tests/run-unit.sh SurfaceTest\ntests/lock/run.sh one two')"
run "$tree" --files screensaver/Old.qml
check "… a scenario named on a line (two) and not (one), @not-lock left out" \
    is "$(printf 'tests/run-unit.sh SurfaceTest\ntests/lock/run.sh one two')"
run "$tree" --files singletons/Helper.qml
check "@lazy: a singleton a lazy file uses is followed" is "$(printf 'tests/run-unit.sh CTest\ntests/lock/run.sh three')"
run "$tree" --files views/V.qml
check "@lazy: a view it quotes is not, from a suite that does not name it" is ""
run "$tree" --files fixtures/mod/main.qml
check "a module part's file selects that part" is "tests/run-modules.sh fixtures/mod"
run "$tree" --files tests/TestCase.qml
check "modules:all and unit:all" is "$(printf 'tests/run-unit.sh\ntests/run-modules.sh fixtures/mod')"
run "$tree" --files site/page.md
check "a none file selects nothing" bash -c '[ -z "$1" ] && [ "$2" = 0 ]' _ "$OUTPUT" "$STATUS"
run "$tree" --files tests/lock/tests/three.sh tests/x-selftest.sh
check "a scenario and a self-test select themselves" is "$(printf 'tests/x-selftest.sh\ntests/lock/run.sh three')"
run "$tree" --files components/Pill.qml
check "a component selects the mockups that draw it, not a planning one" is "tests/run-mockups.sh --by-system components/pill"
run "$tree" --files mockups/components/pill/baseline/00-normal.png mockups/components/pill/baseline/manifest.txt
check "a mockup's baseline files select their mockup" is "tests/run-mockups.sh --by-system components/pill"
run "$tree" --files mockups/views/panel/Mockup.qml components/Pill.qml
check "two mockups, in one command" is "tests/run-mockups.sh --by-system components/pill views/panel"
run "$tree" --files mockups/kit/MockupWindow.qml
check "the kit selects every mockup" is "tests/run-mockups.sh --by-system"
run "$tree" --files mockup.qml
check "the entry selects every mockup" is "tests/run-mockups.sh --by-system"
run "$tree" --why --files mockups/planning/idea/Mockup.qml mockups/planning/idea/MOCKUP.md
check "a planning mockup is placed with none, and selects nothing" \
    is "$(printf 'mockups/planning/idea/MOCKUP.md\tnone\nmockups/planning/idea/Mockup.qml\tnone')"

# The default range: from the nearest segment-* or master merge-base, plus the working tree
git -C "$tree" checkout -q -b segment-a
echo 'Item { property int value: 2 }' > "$tree/singletons/B.qml"
commit "segment: B"
git -C "$tree" checkout -q -b work
echo 'Item { property int value: B.value + 3; property string script: "/scripts/run.sh" }' > "$tree/singletons/A.qml"
commit "work: A"
run "$tree"
check "the branch against segment-a, not master: A's change only" is "tests/run-unit.sh ATest"
echo 'more' >> "$tree/site/page.md"
echo 'echo PASS' > "$tree/tests/lock/tests/four.sh"
run "$tree"
check "the working tree and untracked files count" is "$(printf 'tests/run-unit.sh ATest\ntests/lock/run.sh four')"
git -C "$tree" checkout -q site/page.md
rm "$tree/tests/lock/tests/four.sh"
run "$tree" "master..work"
check "an explicit range" is "$(printf 'tests/run-unit.sh ATest BTest\ntests/lock/run.sh three')"
run "$tree" "HEAD^!"
check "a single commit, as git diff takes it" is "tests/run-unit.sh ATest"
run "$tree" "no-such-ref..HEAD"
check "a range git cannot read: status 2" [ "$STATUS" = 2 ]
run "$tree" --bogus
check "a wrong option: status 2" [ "$STATUS" = 2 ]
run "$tree" --why --files singletons/B.qml
check "--why names each file and what it selects" is "$(printf 'singletons/B.qml\tlock:three unit:ATest unit:BTest')"
git -C "$tree" checkout -q segment-a
run "$tree"
check "on a segment: against its own start from master" is "$(printf 'tests/run-unit.sh ATest BTest\ntests/lock/run.sh three')"
git -C "$tree" checkout -q work
git -C "$tree" branch -q -f segment-a work
run "$tree"
check "a branch merged into its segment: against where it was made" is "tests/run-unit.sh ATest"

# Two segments, the newer made from the older; a branch from the newer: its own change only
git -C "$tree" checkout -q -b segment-old master
echo 'Item { property int value: 5 }' > "$tree/singletons/Helper.qml"
commit "old segment: Helper"
git -C "$tree" checkout -q -b segment-new
echo 'Item { property int value: 2 }' > "$tree/singletons/Orphan.qml"
commit "new segment: Orphan"
git -C "$tree" checkout -q -b slice
echo 'Item { property int value: B.value + 4; property string script: "/scripts/run.sh" }' > "$tree/singletons/A.qml"
commit "slice: A"
run "$tree"
check "a branch from the newer of two segments: its own change only" is "tests/run-unit.sh ATest"
git -C "$tree" branch -q -f segment-new slice
run "$tree"
check "… and once merged into it" is "tests/run-unit.sh ATest"
git -C "$tree" checkout -q work
git -C "$tree" branch -q -D segment-old segment-new slice

# Paths the tree no longer has
git -C "$tree" checkout -q -b deletions
git -C "$tree" rm -q singletons/B.qml
commit "B gone"
run "$tree" "HEAD^!"
check "a deleted file selects the suites of the files still naming it" is "$(printf 'tests/run-unit.sh ATest BTest\ntests/lock/run.sh three')"
git -C "$tree" rm -q screensaver/Old.qml
commit "Old gone"
run "$tree" "HEAD^!"
check "a deleted lock file still selects the lock scenarios" is "$(printf 'tests/run-unit.sh SurfaceTest\ntests/lock/run.sh one two')"
git -C "$tree" rm -q singletons/Orphan.qml
commit "Orphan gone"
run "$tree" "HEAD^!"
check "a deleted QML file nothing names selects everything" \
    is "$(printf 'tests/run-unit.sh\ntests/run-modules.sh fixtures/mod\ntests/run-mockups.sh --by-system\ntests/lock/run.sh')"
git -C "$tree" rm -q -r mockups/views/panel
commit "the panel mockup gone"
run "$tree" "HEAD^!"
check "a deleted mockup has nothing to run" is ""
git -C "$tree" checkout -q work
git -C "$tree" branch -q -D deletions
git -C "$tree" checkout -q master
run "$tree"
check "on master, every other branch containing it: status 2, a range asked for" \
    bash -c '[ "$1" = 2 ] && grep -q "name a range" <<< "$2"' _ "$STATUS" "$ERRORS"
git -C "$tree" branch -q -D segment-a work
run "$tree"
check "on master, with no other branch to compare with: status 2, a range asked for" \
    bash -c '[ "$1" = 2 ] && grep -q "name a range" <<< "$2"' _ "$STATUS" "$ERRORS"

# --run: every command runs, through the runners; a failing one fails the run
rm -f "$tree/calls"
run "$tree" --run --files singletons/Shared.qml
check "--run runs each command" bash -c '[ "$1" = 0 ] && [ "$(cat "$2/calls")" = "$(printf "tests/run-unit.sh SurfaceTest\ntests/lock/run.sh one two")" ]' _ "$STATUS" "$tree"
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
echo 'Item {}' > "$tree/singletons/Loose.qml"
git -C "$tree" add singletons/Loose.qml
echo '@not-lock nobody*' >> "$tree/tests/affected-map.txt"
echo 'site/* unit:NoSuchTest lock:nothing* self:tests/missing.sh mockup:views/gone' >> "$tree/tests/affected-map.txt"
run "$tree" --check
check "--check fails" [ "$STATUS" = 1 ]
check "… naming a tracked file placed nowhere" has "not placed: stray.txt"
check "… and one only a + line matches" has "not placed: singletons/Loose.qml"
check "… an @not-lock glob that names no scenario" has "@not-lock nobody* names no scenario"
check "… a pattern that matches no file" has "'gone/*' matches no file"
check "… a suite tests.qml does not register" has "unit:NoSuchTest is no suite"
check "… a scenario glob that names none" has "lock:nothing* names no scenario"
check "… a self-test that is not there" has "self:tests/missing.sh is not an executable"
check "… a mockup that is not there" has "mockup:views/gone is no component or view mockup"

echo
if [ "$failed" = 0 ]; then echo "affected-selftest.sh: passed"; else echo "affected-selftest.sh: FAILED"; fi
exit "$failed"
