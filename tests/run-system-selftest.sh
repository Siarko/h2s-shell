#!/usr/bin/env bash
# Checks tests/run-system.sh itself: which system it reads from an os-release file, that a
# set which did not run is never a pass (an unknown system, the other system's check, an
# unknown name, an empty set, a check that could not run: status 2), and its verdict. It
# runs a copy of the runner beside made-up sets and made-up os-release files, so it runs
# the same on every system and starts neither nix nor pacman. The real check files are
# only read for syntax.
#
# Exit status: 0 when every check passed, 1 otherwise.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/run-system-selftest.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$work"' EXIT
failed=0
check() {
    local description=$1
    shift
    if "$@"; then echo "  PASS $description"; else echo "  FAIL $description"; failed=1; fi
}

mkdir -p "$work/tree/tests/system/nixos" "$work/tree/tests/system/arch" "$work/empty/tests/system/arch"
cp "$REPO/tests/run-system.sh" "$work/tree/tests/"
cp "$REPO/tests/run-system.sh" "$work/empty/tests/"
echo 'check "the nixos one ran" true' > "$work/tree/tests/system/nixos/one.sh"
echo 'check "the arch one ran" true' > "$work/tree/tests/system/arch/two.sh"
echo 'check "the arch one ran" true' > "$work/tree/tests/system/arch/three.sh"
printf 'ID=nixos\nNAME=NixOS\n' > "$work/nixos"
printf 'NAME="Arch Linux"\nID=arch\n' > "$work/arch"
printf 'ID=endeavouros\nID_LIKE=arch\n' > "$work/like"
printf 'ID="manjaro"\nID_LIKE="arch linux"\n' > "$work/like-quoted"
printf 'ID=fedora\nID_LIKE="rhel centos"\n' > "$work/fedora"
printf 'ID=other\nID_LIKE="archish debian"\n' > "$work/like-lookalike"
printf 'ID=archcraftish\nVERSION_ID=arch\nNAME=nixos\n' > "$work/lookalike"

# run <tree> <os-release file> [names…]: OUTPUT (both streams), STATUS
run() {
    local tree=$1 release=$2
    shift 2
    OUTPUT=$(H2S_OS_RELEASE="$release" "$work/$tree/tests/run-system.sh" "$@" 2>&1)
    STATUS=$?
}
status_is() { [ "$STATUS" = "$1" ]; }
says() { grep -q -- "$1" <<< "$OUTPUT"; }
silent_on() { ! grep -q -- "$1" <<< "$OUTPUT"; }
no_pass() { ! grep -q 'PASS' <<< "$OUTPUT"; }

run tree "$work/nixos"
check "ID=nixos: status 0" status_is 0
check "ID=nixos: the NixOS check ran" says "PASS the nixos one ran"
check "ID=nixos: no Arch check ran" silent_on "the arch one ran"
check "ID=nixos: the summary names the set and the check" says "^  PASS     one$"

run tree "$work/arch"
check "ID=arch: status 0" status_is 0
check "ID=arch: both Arch checks in the summary" test "$(grep -c '^  PASS     ' <<< "$OUTPUT")" = 2
check "ID=arch: no NixOS check ran" silent_on "the nixos one ran"

run tree "$work/like"
check "ID_LIKE=arch: the Arch set" says "^system: arch "
run tree "$work/like-quoted"
check "ID_LIKE=\"arch linux\", quoted: the Arch set" says "^system: arch "

run tree "$work/arch" two
check "a named check: status 0" status_is 0
check "a named check: only it ran" test "$(grep -c '^  PASS     ' <<< "$OUTPUT")" = 1

for release in fedora lookalike like-lookalike; do
    run tree "$work/$release"
    check "$release: status 2" status_is 2
    check "$release: no pass printed" no_pass
    check "$release: says there is no set for it" says "no set for this system"
done
run tree "$work/fedora"
check "fedora: the system found is named" says "ID=fedora"
run tree "$work/no-such-file"
check "no os-release file: status 2" status_is 2
check "no os-release file: no pass printed" no_pass

run tree "$work/arch" one
check "the other system's check: status 2" status_is 2
check "the other system's check: nothing ran" no_pass
check "the other system's check: says whose it is" says "'one' is a check of the nixos set, and this system is arch"
run tree "$work/arch" two one
check "one good name and the other system's: nothing ran" no_pass
run tree "$work/arch" nothing-like-it
check "an unknown name: status 2" status_is 2
check "an unknown name: nothing ran" no_pass
run tree "$work/arch" ../nixos/one
check "a name with a path in it: status 2" status_is 2
check "a name with a path in it: nothing ran" no_pass
run tree "$work/arch" ""
check "an empty name: status 2" status_is 2
run tree "$work/arch" --help
check "an option: status 2" status_is 2

run empty "$work/arch"
check "an empty set: status 2" status_is 2
check "an empty set: no pass printed" no_pass

echo 'check "this one fails" false' > "$work/tree/tests/system/arch/bad.sh"
run tree "$work/arch"
check "a failing check: status 1" status_is 1
check "a failing check: FAIL in the summary" says "^  FAIL     bad$"
check "a failing check: the others still ran" says "^  PASS     two$"
rm "$work/tree/tests/system/arch/bad.sh"

echo 'need no-such-program-here "what it is for"; check "never reached" true' > "$work/tree/tests/system/arch/needy.sh"
run tree "$work/arch"
check "a check missing its tool: status 2" status_is 2
check "a check missing its tool: NOT RUN, the tool named with its use" \
    says "^  NOT RUN  needy — no-such-program-here not found on PATH (what it is for)$"
check "a check missing its tool: it is not a pass" silent_on "PASS     needy"
echo 'check "this one fails" false' > "$work/tree/tests/system/arch/bad.sh"
run tree "$work/arch"
check "one failed, one could not run: status 1" status_is 1
rm "$work/tree/tests/system/arch/bad.sh" "$work/tree/tests/system/arch/needy.sh"

echo 'true' > "$work/tree/tests/system/arch/hollow.sh"
run tree "$work/arch" hollow
check "a check file that checks nothing: status 2, not a pass" status_is 2
rm "$work/tree/tests/system/arch/hollow.sh"

# The real sets: each system's directory holds a check, and every check file parses — on
# this machine too, where only one of the sets runs
for system in nixos arch; do
    real=0
    for file in "$REPO/tests/system/$system"/*.sh; do
        [ -f "$file" ] || continue
        real=$((real + 1))
        check "tests/system/$system/$(basename "$file") parses" bash -n "$file"
    done
    check "the $system set holds a check" test "$real" -gt 0
done

echo
if [ "$failed" = 0 ]; then echo "run-system self-test: passed"; else echo "run-system self-test: FAILED"; fi
exit "$failed"
