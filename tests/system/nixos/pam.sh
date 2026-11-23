# shellcheck shell=bash
# The flake's programs.h2s-shell.pam options (nix/pam.nix), evaluated for minimal systems,
# not built (tests/system/nixos/pam.nix): for each case of tests/fixtures/pam-nixos/cases.json
# the shell's lines in sudo's and polkit's files are the editor's (PamEditRules) for the same
# rows, above NixOS's own; then the assertions and warnings the options give. Evaluates
# only: builds nothing, links nothing, writes no lock file.
need nix "evaluates the flake's NixOS module"

work=$(mktemp -d "${TMPDIR:-/tmp}/system-pam.XXXXXX") || cannot_run "cannot create a temp dir"
trap 'rm -rf "$work"' EXIT
text=$(nix --extra-experimental-features "nix-command flakes" eval --raw --impure --no-write-lock-file \
    --expr "import $REPO/tests/system/nixos/pam.nix { repo = \"$REPO\"; }" 2> "$work/nix.log")
evaluated=0
[ -n "$text" ] && evaluated=1
[ "$evaluated" = 1 ] || tail -n 30 "$work/nix.log"
check "the module's PAM options evaluate" test "$evaluated" = 1
count=0
while IFS=$'\t' read -r verdict description detail; do
    [ -n "$verdict" ] || continue
    count=$((count + 1))
    [ "$verdict" = ok ] || echo "  $description: $detail"
    check "$description" test "$verdict" = ok
done <<< "$text"
# The case set and the checks: a short list would mean the expression lost some
check "every case and check reported ($count lines)" test "$count" -ge 40
