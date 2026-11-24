# shellcheck shell=bash
# The flake's NixOS module (nix/module.nix), evaluated for a minimal system, not built:
# programs.h2s-shell.idle.hibernateDelay goes into the generated sleep.conf as
# HibernateDelaySec (the delay the Hibernate section names on NixOS), and without it
# sleep.conf says nothing of it; and the lock's PAM services start with the lock's marker
# line. Evaluates only: builds nothing, links nothing, writes no lock file.
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
      # The least a system evaluates with: modules read the type of the root filesystem
      fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
      system.stateVersion = "26.05";
    } extra ];
  }).config.environment.etc."systemd/sleep.conf".text;
in
  sleepConf { programs.h2s-shell.idle.hibernateDelay = "3h"; } + "\n----\n" + sleepConf { }'
text=$(nix --extra-experimental-features "nix-command flakes" eval --raw --impure --no-write-lock-file \
    --expr "$expression" 2> "$work/nix.log")
evaluated=0
[[ $text == *$'\n----\n'* ]] && evaluated=1
[ "$evaluated" = 1 ] || tail -n 20 "$work/nix.log"
with_delay=${text%%$'\n----\n'*}
without=${text#*$'\n----\n'}
# Both cases need the evaluation: without it, "says nothing of it" would hold vacuously
says_nothing_of_delay() { [ "$evaluated" = 1 ] && ! grep -q 'HibernateDelaySec' <<< "$without"; }
check "the module evaluates" test "$evaluated" = 1
check "idle.hibernateDelay = \"3h\": HibernateDelaySec=3h in sleep.conf" grep -qx 'HibernateDelaySec=3h' <<< "$with_delay"
check "… unset: sleep.conf says nothing of it" says_nothing_of_delay

# The lock's PAM services start with the lock's marker line, as the shipped pam/ configs do
# (LockIoRules.pamMarked watches only a stack whose first auth rule it is): for the password,
# NixOS's own stack follows it unchanged — the same as with the marker's rule turned off.
# shellcheck disable=SC2016
expression='
let
  flake = builtins.getFlake "path:'"$REPO"'";
  services = extra: (flake.inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ flake.nixosModules.default {
      programs.h2s-shell.enable = true;
      services.fprintd.enable = true;
      security.pam.u2f.enable = true;
      boot.loader.grub.enable = false;
      fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
      system.stateVersion = "26.05";
    } extra ];
  }).config.security.pam.services;
  marked = services { };
  unmarked = services { security.pam.services.h2s-shell-password.rules.auth.h2s-lock-started.enable = false; };
in
  builtins.concatStringsSep "\n----\n" [
    marked.h2s-shell-password.text marked.h2s-shell-fingerprint.text marked.h2s-shell-u2f.text
    unmarked.h2s-shell-password.text ]'
text=$(nix --extra-experimental-features "nix-command flakes" eval --raw --impure --no-write-lock-file \
    --expr "$expression" 2> "$work/nix-pam.log")
texts=()
while [[ $text == *$'\n----\n'* ]]; do texts+=("${text%%$'\n----\n'*}"); text=${text#*$'\n----\n'}; done
texts+=("$text")
pam_evaluated=0
[ "${#texts[@]}" = 4 ] && pam_evaluated=1
[ "$pam_evaluated" = 1 ] || tail -n 20 "$work/nix-pam.log"
# The first auth line, comments and white space as libpam reads them (NixOS ends each rule
# with a comment naming it)
first_auth() { sed -e 's/#.*//' -e 's/[[:space:]]\+/ /g' -e 's/^ //' -e 's/ $//' | grep -m1 '^auth '; }
marker_first() {
    [ "$pam_evaluated" = 1 ] || return 1
    first_auth <<< "$1" | grep -qxE 'auth \[default=ignore\] ([^ ]*/)?pam_echo\.so h2s-shell-lock\.started'
}
# The shipped line, word for word
shipped_first() {
    [ "$pam_evaluated" = 1 ] || return 1
    [ "$(first_auth <<< "$1")" = "$(first_auth < "$REPO/pam/password")" ]
}
rest_unchanged() {
    [ "$pam_evaluated" = 1 ] || return 1
    # Each as $( ) gives it, without trailing line breaks; the marker's line must be one
    # that goes
    local with without unmarked
    with=$(printf '%s' "${texts[0]}")
    without=$(grep -v 'pam_echo\.so h2s-shell-lock\.started' <<< "${texts[0]}")
    unmarked=$(printf '%s' "${texts[3]}")
    [ "$without" = "$unmarked" ] && [ "$without" != "$with" ]
}
check "the module evaluates with fingerprint and security key" test "$pam_evaluated" = 1
check "h2s-shell-password: the lock's marker is the first auth rule" marker_first "${texts[0]}"
check "… NixOS's own stack after it unchanged" rest_unchanged
check "h2s-shell-fingerprint: the shipped marker line first" shipped_first "${texts[1]}"
check "h2s-shell-u2f: the shipped marker line first" shipped_first "${texts[2]}"
