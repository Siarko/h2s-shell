# shellcheck shell=sh
# The NixOS system a build of the shell's settings makes: the user's configuration with the
# shell's file (programs.h2s-shell.settingsFile) replaced by a candidate. One definition for
# every side that evaluates it: the root steps join this file before their own
# (nixos-apply.sh's check, nixos-build.sh) and the user's build reads nixos_toplevel out of
# it (NixBuildRules.expression), so the drvPath the user builds is the one root checks.
# Never run by path. NixBuildRules.expression takes the text between `nixos_toplevel='` and
# the next `'`: the expression holds no single quote.
#
# Its inputs come from the environment (nix --impure): H2S_FLAKE (the flake's reference,
# flake_ref's; "" for classic, <nixos-config> then), H2S_HOST (the flake's
# nixosConfigurations name), H2S_CANDIDATE (the candidate file's absolute path; its name
# h2s-shell.json, so that its store path is the real file's for the same content). Classic
# takes <nixpkgs> and <nixos-config> by -I.
nixos_toplevel='let
  flake = builtins.getEnv "H2S_FLAKE";
  candidate = /. + builtins.getEnv "H2S_CANDIDATE";
  configured = if flake != ""
    then (builtins.getFlake flake).nixosConfigurations.${builtins.getEnv "H2S_HOST"}
    else import <nixpkgs/nixos/lib/eval-config.nix> { system = builtins.currentSystem; modules = [ <nixos-config> ]; };
in (configured.extendModules {
  modules = [ ({ lib, ... }: { programs.h2s-shell.settingsFile = lib.mkForce candidate; }) ];
}).config.system.build.toplevel'

# What root's check prints of it (nix eval --apply): its drvPath and out path on one line
nixos_paths='toplevel: toplevel.drvPath + " " + toplevel.outPath + "\n"'

# flake_ref <real folder>: the reference of the flake in it, in $flake — git+file:// where
# the folder holds a .git (nix then sees only the files git knows, as nixos-rebuild does),
# path: otherwise (a bare path would always be path:). NixBuildRules.flakeRef is the same.
flake_ref() {
  flake=path:$1
  if [ -e "$1/.git" ]; then flake=git+file://$1; fi
}

# system_nixpkgs: the nixpkgs entry of the system's own NIX_PATH (<base>/etc/set-environment),
# in $nixpkgs; refused when there is none. NixBuildRules.systemNixpkgs reads the same.
system_nixpkgs() {
  nix_path=$(sed -n 's/^export NIX_PATH="\(.*\)"$/\1/p' "$base/etc/set-environment" 2> /dev/null | head -n 1) || nix_path=
  nixpkgs=
  while [ -n "$nix_path" ]; do
    nix_entry=${nix_path%%:*}
    case "$nix_path" in *:*) nix_path=${nix_path#*:};; *) nix_path=;; esac
    case "$nix_entry" in nixpkgs=*) nixpkgs=${nix_entry#nixpkgs=}; break;; esac
  done
  is_plain "$nixpkgs" || refuse nixpath
}

# toplevel_inputs <real folder> <entry> <host | ->: what nix is handed for the configuration
# in <folder> — a flake (<entry> flake.nix): $flake and $toplevel_host; classic: $flake and
# $toplevel_host empty, $nixpkgs (system_nixpkgs) and $nixos_config (<folder>/<entry>) for
# -I. Refused (entry) when that file is not there.
toplevel_inputs() {
  if [ "$2" = flake.nix ]; then
    [ -f "$1/flake.nix" ] || refuse entry
    flake_ref "$1"
    toplevel_host=$3; nixpkgs=; nixos_config=
  else
    [ -f "$1/$2" ] || refuse entry
    system_nixpkgs
    flake=; toplevel_host=; nixos_config=$1/$2
  fi
}

# toplevel_paths <nix> <home> <cache> <candidate> [<nix options>…]: nix eval of nixos_toplevel
# with $flake and $toplevel_host (toplevel_inputs') and the candidate's path, the way root
# runs it: an environment of PATH, HOME, XDG_CACHE_HOME and the inputs alone (no NIX_PATH,
# no NIX_CONFIG); "<drvPath> <out path>" on stdout, nix's messages on stderr
toplevel_paths() {
  paths_nix=$1; paths_home=$2; paths_cache=$3; paths_candidate=$4; shift 4
  env -i PATH="$PATH" HOME="$paths_home" XDG_CACHE_HOME="$paths_cache" LC_ALL=C \
    H2S_FLAKE="$flake" H2S_HOST="$toplevel_host" H2S_CANDIDATE="$paths_candidate" \
    "$paths_nix" eval --raw --impure --extra-experimental-features 'nix-command flakes' "$@" \
    --expr "$nixos_toplevel" --apply "$nixos_paths" < /dev/null
}
