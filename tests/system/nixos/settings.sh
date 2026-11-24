# shellcheck shell=bash
# The flake's programs.h2s-shell.settingsFile (nix/settings.nix), evaluated for minimal
# systems, not built (tests/system/nixos/settings.nix): the fixture
# tests/fixtures/settings-nixos/settings.json gives the options and /etc files of the same
# values written by hand, and publishes /etc/h2s-shell/settings.json; a hand-written
# definition wins; a wrong version or value is an assertion naming it, an unknown key a
# warning. Evaluates only: builds nothing, links nothing, writes no lock file.
need nix "evaluates the flake's NixOS module"

work=$(mktemp -d "${TMPDIR:-/tmp}/system-settings.XXXXXX") || cannot_run "cannot create a temp dir"
trap 'rm -rf "$work"' EXIT
text=$(nix --extra-experimental-features "nix-command flakes" eval --raw --impure --no-write-lock-file \
    --expr "import $REPO/tests/system/nixos/settings.nix { repo = \"$REPO\"; }" 2> "$work/nix.log")
evaluated=0
[ -n "$text" ] && evaluated=1
[ "$evaluated" = 1 ] || tail -n 30 "$work/nix.log"
check "the module's settingsFile option evaluates" test "$evaluated" = 1
count=0
expected=
while IFS=$'\t' read -r verdict description detail; do
    [ -n "$verdict" ] || continue
    if [ "$verdict" = count ]; then
        expected=$description
        continue
    fi
    count=$((count + 1))
    [ "$verdict" = ok ] || echo "  $description: $detail"
    check "$description" test "$verdict" = ok
done <<< "$text"
# The expression counts its own lines: fewer read would mean some were lost
check "every check reported ($count of ${expected:-none})" test "$count" = "${expected:-x}"
check "… forty at least" test "$count" -ge 40
