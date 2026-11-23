#!/usr/bin/env bash
# Checks the distributions' facts as the scripts read them:
#
# - every distributions/<id>/distribution.env is what scripts/distribution-env.py writes
#   from its distribution.json (status 1 of its --check otherwise), and the generator
#   refuses what the line format cannot carry;
# - scripts/distribution.sh tells the distribution as the shell does
#   (singletons/DistributionRules.qml): made-up system trees from the os-release fixtures of
#   tests/fixtures/distribution/, laid out as tests/DistributionReadingTest.qml lays them
#   out, with the same answers; the override; and what leaves it unknown.
#
# It needs bash, coreutils and a python3 (tests/lock/resolve.sh: the pinned one where there
# is nix, else the one on PATH). Nothing outside a temp directory is read but the checkout.
#
# Exit status: 0 when every check passed, 1 otherwise, 2 when it could not be set up.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/distribution-selftest.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'chmod -R u+rwx "$work" 2> /dev/null; rm -rf "$work"' EXIT
failed=0
check() {
    local description=$1
    shift
    if "$@"; then echo "  PASS $description"; else echo "  FAIL $description"; failed=1; fi
}

setup_error() { echo "distribution-selftest.sh: $*" >&2; exit 2; }
LOCKTEST_DIR=$REPO/tests/lock
LOCKTEST_NEED=python
temp_base=$work/temp
mkdir -p "$temp_base"
# shellcheck disable=SC2034  # read by resolve.sh
PROBE_TIMEOUT=5 probe=""
# shellcheck source=lock/resolve.sh
source "$LOCKTEST_DIR/resolve.sh"

status_is() { [ "$STATUS" = "$1" ]; }
says() { grep -q -- "$1" <<< "$OUTPUT"; }

# ---- The generated files ---------------------------------------------------------------
OUTPUT=$("$LOCKTEST_PYTHON" -I "$REPO/scripts/distribution-env.py" --check "$REPO" 2>&1)
STATUS=$?
check "every distribution.env is what the generator writes from its distribution.json" status_is 0
[ "$STATUS" = 0 ] || printf '%s\n' "$OUTPUT"

# A scratch copy: a changed distribution.json is noticed, and written again
mkdir -p "$work/copy/distributions" "$work/copy/scripts"
cp -r "$REPO/distributions/." "$work/copy/distributions/"
cp "$REPO/scripts/distribution.sh" "$work/copy/scripts/"
sed -i 's|"/usr/share/polkit-1/rules.d"|"/usr/local/share/polkit-1/rules.d"|' "$work/copy/distributions/arch/distribution.json"
OUTPUT=$("$LOCKTEST_PYTHON" -I "$REPO/scripts/distribution-env.py" --check "$work/copy" 2>&1)
STATUS=$?
check "a changed distribution.json: --check fails" status_is 1
check "… naming that distribution's file" says "arch/distribution.env differs"
"$LOCKTEST_PYTHON" -I "$REPO/scripts/distribution-env.py" "$work/copy" > /dev/null 2>&1
check "… written again, it holds the new value" grep -qx "polkitRulesDirectory=/usr/local/share/polkit-1/rules.d" \
    "$work/copy/distributions/arch/distribution.env"
check "… and the lists joined with \":\"" grep -qx "pamDirectories=/etc/pam.d:/usr/lib/pam.d" \
    "$work/copy/distributions/arch/distribution.env"
OUTPUT=$("$LOCKTEST_PYTHON" -I "$REPO/scripts/distribution-env.py" --check "$work/copy" 2>&1)
STATUS=$?
check "… then --check passes" status_is 0

refused() {
    mkdir -p "$work/bad/distributions/x"
    printf '%s' "$1" > "$work/bad/distributions/x/distribution.json"
    "$LOCKTEST_PYTHON" -I "$REPO/scripts/distribution-env.py" "$work/bad" > /dev/null 2>&1
    [ "$?" = 2 ] && [ ! -e "$work/bad/distributions/x/distribution.env" ]
}
check "the generator refuses a list entry with \":\"" refused '{"id": "x", "markers": ["/a:b"]}'
check "… a value with a line break" refused '{"id": "x", "label": "a\nb"}'
check "… a value that is no text, boolean or list" refused '{"id": "x", "count": 3}'
check "… a key that is no plain word" refused '{"id": "x", "a=b": "c"}'

# ---- Detection --------------------------------------------------------------------------
fixtures=$REPO/tests/fixtures/distribution
roots=$work/roots
mkdir -p "$roots"/{arch/etc,arch/usr/lib,nixos/etc,endeavouros/etc,usronly/usr/lib,mint/etc,unreadable/etc,none,lockedmark/etc,dirmark/etc/NIXOS,long/etc,empty/etc}
cp "$fixtures/arch.os-release" "$roots/arch/usr/lib/os-release"
ln -s ../usr/lib/os-release "$roots/arch/etc/os-release"
cp "$fixtures/nixos.os-release" "$roots/nixos/etc/os-release"
: > "$roots/nixos/etc/NIXOS"
cp "$fixtures/endeavouros.os-release" "$roots/endeavouros/etc/os-release"
cp "$fixtures/fedora.os-release" "$roots/usronly/usr/lib/os-release"
cp "$fixtures/linuxmint.os-release" "$roots/mint/etc/os-release"
cp "$fixtures/arch.os-release" "$roots/unreadable/etc/os-release"
chmod 000 "$roots/unreadable/etc/os-release"
cp "$fixtures/arch.os-release" "$roots/lockedmark/etc/os-release"
: > "$roots/lockedmark/etc/NIXOS"
chmod 000 "$roots/lockedmark/etc/NIXOS"
cp "$fixtures/arch.os-release" "$roots/dirmark/etc/os-release"
for _ in $(seq 9000); do echo "ID=arch"; done > "$roots/long/etc/os-release"
echo "<html>not os-release</html>" > "$roots/empty/etc/os-release"

detect() {
    OUTPUT=$("$REPO/scripts/distribution.sh" --root "$roots/$1" "${@:2}" 2>&1)
    STATUS=$?
}
expect() {
    detect "$1" "${@:4}"
    [ "$STATUS" = 0 ] && [ "$OUTPUT" = "id=$2"$'\n'"how=$3" ]
}
unknown() {
    detect "$@"
    [ "$STATUS" = 1 ] && [[ "$OUTPUT" == problem=* ]]
}
check "Arch, /etc/os-release a link to /usr/lib/os-release: arch, by ID" expect arch arch id
check "NixOS, an empty /etc/NIXOS: nixos, by the marker" expect nixos nixos marker
check "EndeavourOS (ID_LIKE=arch): arch, by ID_LIKE" expect endeavouros arch like
check "only /usr/lib/os-release, Fedora's: read, generic" expect usronly generic fallback
check "Linux Mint (ID_LIKE=\"ubuntu debian\"): generic" expect mint generic fallback
check "no os-release, no marker: generic" expect none generic fallback
check "/etc/NIXOS of mode 000 beside Arch's os-release: nixos (it exists)" expect lockedmark nixos marker
check "/etc/NIXOS a directory: nixos (it exists)" expect dirmark nixos marker
check "an os-release that cannot be read, no marker: unknown" unknown unreadable
check "an os-release too long: unknown" unknown long
check "an os-release without one assignment: unknown" unknown empty
check "the override names nixos on Arch: nixos" expect arch nixos override --id nixos
check "the override names generic on NixOS: generic" expect nixos generic override --id generic
check "an override that names no distribution: unknown" unknown arch --id windows
check "… saying so" says "H2S_DISTRIBUTION names no distribution: windows"

# A distribution.env that cannot be used: unknown, whatever the system says
sed -i 's/^id=arch$/id=other/' "$work/copy/distributions/arch/distribution.env"
OUTPUT=$("$work/copy/scripts/distribution.sh" --root "$roots/arch" 2>&1)
STATUS=$?
check "a distribution.env whose id is not its directory's: unknown" status_is 1
check "… naming it" says "distributions/arch/distribution.env cannot be used"
"$LOCKTEST_PYTHON" -I "$REPO/scripts/distribution-env.py" "$work/copy" > /dev/null 2>&1
echo 'not a line of facts' >> "$work/copy/distributions/nixos/distribution.env"
OUTPUT=$("$work/copy/scripts/distribution.sh" --root "$roots/arch" 2>&1)
STATUS=$?
check "a distribution.env with a line that is no key=value: unknown" status_is 1

# The facts handed to a script that sources it
OUTPUT=$(source "$REPO/scripts/distribution.sh" && distribution_detect "$REPO" "" "$roots/nixos" \
    && printf '%s\n' "${distribution_facts[setuidWrapperDirectory]}" "${distribution_facts[pamModuleDirectories]}")
check "sourced: NixOS's facts from its distribution.env" test "$OUTPUT" = $'/run/wrappers/bin\n/run/current-system/sw/lib/security/'

echo
if [ "$failed" = 0 ]; then echo "distribution self-test: passed"; else echo "distribution self-test: FAILED"; fi
exit "$failed"
