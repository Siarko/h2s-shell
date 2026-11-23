# shellcheck shell=bash
# The flake's programs.h2s-shell.polkit.rememberAdmin (nix/remember.nix), evaluated for
# minimal systems, not built (tests/system/nixos/remember.nix): for each case of
# tests/fixtures/remember-nixos/cases.json polkit's rules file holds RememberRules' rule per
# user and polkitd.conf is RememberRules' conf or absent; the real package's coreutils in the
# rule; the assertions. Evaluates only: builds nothing, links nothing, writes no lock file.
need nix "evaluates the flake's NixOS module"

work=$(mktemp -d "${TMPDIR:-/tmp}/system-remember.XXXXXX") || cannot_run "cannot create a temp dir"
trap 'rm -rf "$work"' EXIT
text=$(nix --extra-experimental-features "nix-command flakes" eval --raw --impure --no-write-lock-file \
    --expr "import $REPO/tests/system/nixos/remember.nix { repo = \"$REPO\"; }" 2> "$work/nix.log")
evaluated=0
[ -n "$text" ] && evaluated=1
[ "$evaluated" = 1 ] || tail -n 30 "$work/nix.log"
check "the module's rememberAdmin option evaluates" test "$evaluated" = 1
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
# The expression counts its own lines: fewer read would mean some were lost; and each case
# of the fixture gives five
cases=$(grep -c '^      "name": ' "$REPO/tests/fixtures/remember-nixos/cases.json")
check "every case and check reported ($count of ${expected:-none})" test "$count" = "${expected:-x}"
check "… five lines per case of the fixture at least ($cases cases)" test "$count" -ge $((cases * 5))
