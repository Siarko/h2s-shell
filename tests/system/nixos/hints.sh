# shellcheck shell=bash
# Every option and package NixOS's facts name to the user (distributions/nixos/
# distribution.json, its "packages": the shell's hints about a missing package) exists: the
# option (and the one a package goes in) among a minimal system's options with the flake's module, the package in its
# nixpkgs. A name nixpkgs dropped or renamed fails here, not in a hint. Evaluates only:
# builds nothing, links nothing, writes no lock file.
need nix "evaluates the flake's NixOS module and its nixpkgs"

work=$(mktemp -d "${TMPDIR:-/tmp}/system-hints.XXXXXX") || cannot_run "cannot create a temp dir"
trap 'rm -rf "$work"' EXIT
# shellcheck disable=SC2016
expression='
let
  flake = builtins.getFlake "path:'"$REPO"'";
  lib = flake.inputs.nixpkgs.lib;
  system = lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ flake.nixosModules.default {
      boot.loader.grub.enable = false;
      fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
      system.stateVersion = "26.05";
    } ];
  };
  hints = (builtins.fromJSON (builtins.readFile "'"$REPO"'/distributions/nixos/distribution.json")).packages;
  line = name: kind: value: set:
    (if lib.hasAttrByPath (lib.splitString "." value) set then "ok" else "missing")
    + "\t" + name + ": the " + kind + " " + value + "\n";
  lines = name: entry:
    lib.optionalString (entry ? option) (line name "option" entry.option system.options)
    + lib.optionalString (entry ? package) (line name "package" entry.package system.pkgs)
    + lib.optionalString (entry ? "in") (line name "option" entry."in" system.options);
in
  lib.concatStrings (lib.mapAttrsToList lines hints)'
text=$(nix --extra-experimental-features "nix-command flakes" eval --raw --impure --no-write-lock-file \
    --expr "$expression" 2> "$work/nix.log")
[ -n "$text" ] || tail -n 20 "$work/nix.log"
check "NixOS's package hints evaluate" test -n "$text"
count=0
while IFS=$'\t' read -r verdict description; do
    [ -n "$verdict" ] || continue
    count=$((count + 1))
    check "named to the user on NixOS: $description exists" test "$verdict" = ok
done <<< "$text"
# The font's option, package and where it goes, the fingerprint's and the security key's options
check "every hint's name checked ($count)" test "$count" -ge 5
