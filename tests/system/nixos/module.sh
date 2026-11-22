# shellcheck shell=bash
# The flake's NixOS module (nix/module.nix), evaluated for a minimal system, not built:
# programs.h2s-shell.idle.hibernateDelay goes into the generated sleep.conf as
# HibernateDelaySec (the delay the Hibernate section names on NixOS), and without it
# sleep.conf says nothing of it. Evaluates only: builds nothing, links nothing, writes no
# lock file.
need nix "evaluates the flake's NixOS module"

work=$(mktemp -d "${TMPDIR:-/tmp}/system-module.XXXXXX") || cannot_run "cannot create a temp dir"
trap 'rm -rf "$work"' EXIT
# shellcheck disable=SC2016
expression='
let
  flake = builtins.getFlake "path:'"$REPO"'";
  sleepConf = extra: (flake.inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ flake.nixosModules.default {
      programs.h2s-shell.enable = true;
      boot.loader.grub.enable = false;
      fileSystems."/".device = "/dev/null";
      system.stateVersion = "26.05";
    } extra ];
  }).config.environment.etc."systemd/sleep.conf".text;
in
  sleepConf { programs.h2s-shell.idle.hibernateDelay = "3h"; } + "\n----\n" + sleepConf { }'
text=$(nix --extra-experimental-features "nix-command flakes" eval --raw --impure --no-write-lock-file \
    --expr "$expression" 2> "$work/nix.log")
[ -n "$text" ] || tail -n 20 "$work/nix.log"
with_delay=${text%%----*}
without=${text#*----}
check "the module evaluates" test -n "$text"
check "idle.hibernateDelay = \"3h\": HibernateDelaySec=3h in sleep.conf" grep -qx 'HibernateDelaySec=3h' <<< "$with_delay"
check "… unset: sleep.conf says nothing of it" test "$(grep -c 'HibernateDelaySec' <<< "$without")" = 0
