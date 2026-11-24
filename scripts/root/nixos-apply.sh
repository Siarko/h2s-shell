# shellcheck shell=sh
# The root step of applying a NixOS build: the shell's settings file (<folder>/h2s-shell.json)
# written, and the system the user built switched to; and the build itself, for a
# configuration the user cannot build. Joined after replace-lib.sh,
# replace-file.sh and nixos-toplevel.sh, and run as `sh -c <text> sh <base> <arguments>…`; never run by path. Its
# places are fixed here, under <base> ("" for the system: take_base):
#   the tools        /run/current-system/sw/bin/{nix,nix-env,nix-store,systemctl,systemd-run}
#   the profile      /nix/var/nix/profiles/system (its links system-<n>-link)
#   the store        /nix/store
#   nixpkgs          the nixpkgs= entry of NIX_PATH in /etc/set-environment (classic only)
#   the backups      /var/lib/h2s-shell/nixos-backup/ (`h2s-shell.json.<UTC time>`,
#                    `.absent` when there was no file; root 0700, every one kept)
# Its arguments (a folder is plain and absolute; its real path is used, under <base>):
#   create  <folder>                    writes {"version":1} where there is no file
#   apply   <folder> <entry> <host | -> <current sha256 | absent> <candidate sha256>
#           <drvPath> <out path> <candidate JSON>
#   switch  <folder> <entry> <host | -> <candidate sha256> <drvPath> <out path>
#           <candidate JSON>
#   restore <folder> <backup name> <current sha256 | absent>
#   build   <folder> <entry> <host | -> <candidate sha256> <candidate JSON>
# <entry> is flake.nix (a flake, <host> its nixosConfigurations name) or the classic
# configuration's file in the folder (<host> -). create, apply and restore write, and only
# where every folder of the real path is root's and nobody else may write in it; switch
# writes nothing (a folder of the user's: the user wrote the file, it must hold the
# candidate; root reads it without following a link, without waiting and at most 64 KiB).
#
# apply and switch never rebuild: root evaluates the user's configuration with the candidate
# in place of the shell's file, exactly as the user's build did (nixos_toplevel), and goes on
# only when its drvPath and out path are the ones the user built — the configuration is
# unchanged since the build —; then apply writes the file (compare-and-swap, backup), and
# both set the system profile to that out path and run its switch-to-configuration (under
# systemd-run, as nixos-rebuild does, so that the activation outlives this run). The built
# system must be valid in the store (nix-store --check-validity), and no other
# switch-to-configuration unit may be active. A failure before the activation began puts
# back what was there: the profile at its generation before and the old file.
#
# The evaluation runs the configuration's Nix code as root (impure, so it may read any file
# root may read). For apply the configuration is root's own; for switch it is the user's, so
# the password authorizes running code any of the user's programs could have changed — as
# activating it does. For switch the evaluation's messages are not passed on (they could
# carry what such code read as root); for apply its last lines precede `refused evaluation`.
#
# build builds that system as root (nix build of nixos_toplevel, no link: the user's own
# build of the store path then holds it), for a root-owned configuration only (the same
# folder checks as a write), when the user's build cannot read it. It writes nothing but the
# store; its nix's progress (internal-json) passes on on stderr as it comes.
#
# The last line, on stdout and stderr:
#   created <sha256> <backup>                       exit 0
#   built <drvPath> <out path>                      exit 0 (build)
#   failed build                                    exit 1 (build: nix failed; its lines
#                                                   before say why)
#   applied <generation> <backup | ->               exit 0
#   applied-with-errors <generation> <backup | ->   exit 4 (switch-to-configuration's 4:
#                                                   some units did not start)
#   failed <generation> <backup | ->                exit 1 (the activation failed, or never
#                                                   started and the generation before could
#                                                   not be put back; the profile and the
#                                                   file kept)
#   restored <sha256 | absent> <backup made>        exit 1 after apply (the profile could not
#                                                   be set: the old file back), exit 0 for
#                                                   restore
#   not-activated <generation> <sha256 | absent | -> <backup made | ->
#                                                   exit 5: switch-to-configuration never
#                                                   started (systemd-run failed); the profile
#                                                   back at <generation>, the file back (-
#                                                   for switch: nothing was written)
#   not-restored <sha256> <backup>                  exit 6: the profile not set or not
#                                                   activated, but the old file could not be
#                                                   put back: the candidate (<sha256>) is
#                                                   still written, the old one in <backup>
#   failed unknown <backup | ->                     exit 1: a program it runs gone or not
#                                                   executable mid-run (never exit 126/127)
#   refused <code>                                  exit 3, on stderr; nothing switched, and
#                                                   nothing written (the codes: arguments,
#                                                   paths, folder, owner, json, hash, link,
#                                                   changed, unreadable, tools, entry,
#                                                   nixpath, evaluation, notbuilt, profile
#                                                   (switch: the profile not set), backup,
#                                                   nobackup, busy, lock, write)

# The generic tools from the system's fixed places, never the caller's PATH
PATH=/run/current-system/sw/bin:/usr/bin:/bin; export PATH
unset NIX_PATH
unit=nixos-rebuild-switch-to-configuration
[ $# -ge 1 ] || refuse arguments
take_base "$1"; shift
bin=$base/run/current-system/sw/bin; profile=$base/nix/var/nix/profiles/system
store=$base/nix/store; backups=$base/var/lib/h2s-shell/nixos-backup
max_bytes=65536
prefix=h2s-shell.json
work=
# Under set -e a program not found or not executable ends the shell with 127 or 126, which
# the shell reads as pkexec's own answers (a prompt dismissed, not authorised: nothing ran);
# this step never ends with either: such an end says `failed`, exit 1 (what it wrote is kept,
# its backup named when made)
trap 'end_status=$?; clean_up; [ -z "$work" ] || rm -rf -- "$work"
  case "$end_status" in 126|127) say "failed unknown ${backup_name:--}"; exit 1;; esac' EXIT

# The system the user built is nixos_toplevel (nixos-toplevel.sh, joined before this file),
# evaluated here with the same inputs as the user's build.

is_host() { case "$1" in ''|*[!A-Za-z0-9_-]*) return 1;; esac; [ ${#1} -le 253 ]; }
is_entry() { case "$1" in ''|[!A-Za-z0-9_]*|*[!A-Za-z0-9._-]*) return 1;; *.nix) ;; *) return 1;; esac; [ ${#1} -le 255 ]; }
# check_entry <entry> <host | ->: a flake and its host, or a classic file and no host
check_entry() {
  is_entry "$1" || refuse arguments
  if [ "$1" = flake.nix ]; then is_host "$2" || refuse arguments
  else [ "$2" = - ] || refuse arguments; fi
}
# is_store_path <path> <drv | out>: <store>/<32 base-32 letters>-<name>, a .drv or not
is_store_path() {
  store_name=${1#"$store"/}
  [ "$store_name" != "$1" ] || return 1
  case "$store_name" in .*|*[!A-Za-z0-9+._?=-]*) return 1;; esac
  store_hash=${store_name%%-*}
  [ "$store_hash" != "$store_name" ] && [ ${#store_hash} -eq 32 ] || return 1
  case "$store_hash" in *[!0-9abcdfghijklmnpqrsvwxyz]*) return 1;; esac
  case "$2:$store_name" in drv:*.drv|out:*) ;; *) return 1;; esac
  [ "$2" = drv ] || case "$store_name" in *.drv) return 1;; esac
}

# take_folder <folder>: its real path in $folder, plain and under the base; the target in it
take_folder() {
  is_plain "$1" || refuse paths
  folder=$(cd -P -- "$1" 2> /dev/null && pwd -P) || refuse folder
  is_plain "$folder" || refuse paths
  case "$folder" in "$base"/*) ;; *) refuse paths;; esac
  target=$folder/$prefix
}

# folder_safe: every folder from the base (/ for the system) down to the real folder the
# owner's and not writable by others, so nobody but root can swap a part between the checks
# and the writes
folder_safe() {
  chain_part=$base; chain_rest=${folder#"$base"/}
  safe_dir "${chain_part:-/}"
  while [ -n "$chain_rest" ]; do
    chain_part=$chain_part/${chain_rest%%/*}
    case "$chain_rest" in */*) chain_rest=${chain_rest#*/};; *) chain_rest=;; esac
    safe_dir "$chain_part"
  done
}

# check_user_file <file> <sha256>: a file in a folder of the user's holds the candidate.
# Read without following a link, without blocking (a FIFO swapped in gives nothing) and at
# most one byte over the cap, under a time limit: the user may change the folder meanwhile.
check_user_file() {
  if [ -L "$1" ]; then refuse link; fi
  [ -e "$1" ] || refuse changed
  timeout 10 dd if="$1" of="$work/user-file" bs=$((max_bytes + 1)) count=1 iflag=nonblock,nofollow,fullblock 2> /dev/null || refuse unreadable
  got=$(hash_of "$work/user-file") || refuse unreadable
  [ "$got" = "$2" ] || refuse changed
}

# check_text <json> <sha256>: the candidate as the shell sends it (an argument holds no NUL)
check_text() {
  [ ${#1} -le "$max_bytes" ] || refuse json
  case "$1" in "{"*) ;; *) refuse json;; esac
  is_hash "$2" || refuse arguments
}

# tool <name>: one of the system's programs, by its fixed place
tool() {
  if [ ! -f "$bin/$1" ] || [ ! -x "$bin/$1" ]; then refuse tools; fi
}

# evaluate <entry> <host | -> <json> <sha256>: the configuration with the candidate, as
# root; refused unless it is the system the user built ($want_drv, $want_out), and built
evaluate() {
  eval_entry=$1; eval_host=$2; eval_text=$3; eval_sha=$4
  printf '%s' "$eval_text" > "$work/candidate/$prefix" || refuse write
  got=$(hash_of "$work/candidate/$prefix") || refuse write
  [ "$got" = "$eval_sha" ] || refuse hash
  toplevel_inputs "$folder" "$eval_entry" "$eval_host"
  if [ -n "$flake" ]; then
    # nix's git opens a repository only of the one running, unless it is a safe directory
    printf '[safe]\n\tdirectory = %s\n' "$folder" > "$work/home/.gitconfig" || refuse write
    set --
  else
    set -- -I "nixpkgs=$nixpkgs" -I "nixos-config=$nixos_config"
  fi
  if ! toplevel_paths "$bin/nix" "$work/home" "$base/root/.cache" "$work/candidate/$prefix" "$@" > "$work/result" 2> "$work/log"; then
    if [ "$op" = apply ]; then tail -n 40 -- "$work/log" >&2 || :; fi
    refuse evaluation
  fi
  read -r built_drv built_out < "$work/result" || refuse evaluation
  [ "$built_drv" = "$want_drv" ] && [ "$built_out" = "$want_out" ] || refuse changed
  if [ -L "$want_out" ] || [ ! -d "$want_out" ] || [ ! -f "$want_out/bin/switch-to-configuration" ] \
      || [ ! -x "$want_out/bin/switch-to-configuration" ]; then refuse notbuilt; fi
  env -i PATH="$PATH" HOME="$work/home" LC_ALL=C "$bin/nix-store" --check-validity -- "$want_out" < /dev/null > /dev/null 2>&1 || refuse notbuilt
  # Another activation running (nixos-rebuild's own uses the same unit)
  if env -i PATH="$PATH" LC_ALL=C "$bin/systemctl" is-active --quiet -- "$unit.service" < /dev/null > /dev/null 2>&1; then refuse busy; fi
}

# start_work: root's private scratch folder ($work), removed at the end
start_work() {
  work=$(mktemp -d) || refuse write
  mkdir -- "$work/candidate" "$work/home" || refuse write
}

# put_back <backup | ->: the old file back after the candidate was written and nothing was
# activated; its line's words in $put_back ("<sha256 | absent> <backup made>", or "- -" when
# nothing was written). Run apart, so that a refusal there does not end this run as if
# nothing had been written: then `not-restored`, exit 6.
put_back() {
  put_back="- -"
  [ "$1" != - ] || return 0
  if ( trap clean_up EXIT; restore "$1" "$candidate_sha"; printf '%s %s\n' "$restored" "$backup_name" > "$work/put-back" ); then
    read -r put_back < "$work/put-back" || put_back="unknown unknown"
  else
    say "not-restored $candidate_sha $1"
    exit 6
  fi
}

# activate <backup | ->: the profile set to the built system, then its switch; the last line
# generation_of_profile: the generation the profile's link names, or "unknown"
generation_of_profile() {
  link=$(readlink -- "$profile") || link=
  generation=${link#system-}; generation=${generation%-link}
  case "$generation" in ''|*[!0-9]*) generation=unknown;; esac
}

activate() {
  generation_of_profile; before=$generation
  if ! env -i PATH="$PATH" HOME="$work/home" LC_ALL=C "$bin/nix-env" -p "$profile" --set "$want_out" < /dev/null >&2; then
    [ "$1" != - ] || refuse profile
    put_back "$1"
    say "restored $put_back"
    exit 1
  fi
  generation_of_profile
  # switch-to-configuration writes a mark when it starts: a failure without it is
  # systemd-run's own (the unit not started), and nothing was activated
  code=0
  env -i PATH="$PATH" LC_ALL=C "$bin/systemd-run" --collect --no-ask-password --pipe --quiet \
    --service-type=exec --unit="$unit" --wait \
    -- /bin/sh -c ': > "$1"; exec "$2" switch' sh "$work/started" "$want_out/bin/switch-to-configuration" < /dev/null >&2 || code=$?
  if [ "$code" != 0 ] && [ ! -e "$work/started" ] && [ "$before" != unknown ]; then
    # Nothing activated and the boot loader untouched: the generation before comes back, so
    # the profile names the system in force, as before this run
    if env -i PATH="$PATH" HOME="$work/home" LC_ALL=C "$bin/nix-env" -p "$profile" --switch-generation "$before" < /dev/null >&2; then
      put_back "$1"
      say "not-activated $before $put_back"
      exit 5
    fi
  fi
  case "$code" in
  0) say "applied $generation $1";;
  4) say "applied-with-errors $generation $1"; exit 4;;
  *) say "failed $generation $1"; exit 1;;
  esac
}

[ $# -ge 2 ] || refuse arguments
op=$1; shift
case "$op" in
create)
  [ $# -eq 1 ] || refuse arguments
  take_folder "$1"; folder_safe
  prepare_backups; take_lock
  check_current "$target" absent
  new_file
  printf '{"version":1}\n' > "$new_temporary" || refuse write
  seal ''
  make_backup absent
  put_in_place
  say "created $got $backup_name";;
apply)
  [ $# -eq 8 ] || refuse arguments
  current=$4; candidate_sha=$5; want_drv=$6; want_out=$7; json=$8
  [ "$current" = absent ] || is_hash "$current" || refuse arguments
  check_text "$json" "$candidate_sha"
  is_store_path "$want_drv" drv && is_store_path "$want_out" out || refuse arguments
  check_entry "$2" "$3"
  take_folder "$1"; folder_safe
  tool nix; tool nix-env; tool nix-store; tool systemctl; tool systemd-run
  prepare_backups; take_lock
  check_current "$target" "$current"
  start_work
  evaluate "$2" "$3" "$json" "$candidate_sha"
  check_current "$target" "$current"
  new_file
  printf '%s' "$json" > "$new_temporary" || refuse write
  seal "$candidate_sha"
  make_backup "$current"
  put_in_place
  activate "$backup_name";;
switch)
  [ $# -eq 7 ] || refuse arguments
  candidate_sha=$4; want_drv=$5; want_out=$6; json=$7
  check_text "$json" "$candidate_sha"
  is_store_path "$want_drv" drv && is_store_path "$want_out" out || refuse arguments
  check_entry "$2" "$3"
  take_folder "$1"
  tool nix; tool nix-env; tool nix-store; tool systemctl; tool systemd-run
  prepare_backups; take_lock
  start_work
  check_user_file "$target" "$candidate_sha"
  evaluate "$2" "$3" "$json" "$candidate_sha"
  activate -;;
build)
  [ $# -eq 5 ] || refuse arguments
  candidate_sha=$4; json=$5
  check_text "$json" "$candidate_sha"
  check_entry "$2" "$3"
  take_folder "$1"; folder_safe
  tool nix
  start_work
  printf '%s' "$json" > "$work/candidate/$prefix" || refuse write
  got=$(hash_of "$work/candidate/$prefix") || refuse write
  [ "$got" = "$candidate_sha" ] || refuse hash
  toplevel_inputs "$folder" "$2" "$3"
  if [ -n "$flake" ]; then
    printf '[safe]\n\tdirectory = %s\n' "$folder" > "$work/home/.gitconfig" || refuse write
    set --
  else
    set -- -I "nixpkgs=$nixpkgs" -I "nixos-config=$nixos_config"
  fi
  code=0
  env -i PATH="$PATH" HOME="$work/home" XDG_CACHE_HOME="$base/root/.cache" LC_ALL=C \
    H2S_FLAKE="$flake" H2S_HOST="$toplevel_host" H2S_CANDIDATE="$work/candidate/$prefix" \
    "$bin/nix" build --impure --extra-experimental-features 'nix-command flakes' "$@" \
    --log-format internal-json -v --no-link --json --expr "$nixos_toplevel" > "$work/result" < /dev/null || code=$?
  if [ "$code" != 0 ]; then say "failed build"; exit 1; fi
  # [{"drvPath":"<drv>","outputs":{"out":"<out>"}}]: nix's own JSON, one derivation
  built_drv=$(sed -n 's/^\[{"drvPath":"\([^"]*\)","outputs":{"out":"\([^"]*\)"}}\]$/\1/p' "$work/result")
  built_out=$(sed -n 's/^\[{"drvPath":"\([^"]*\)","outputs":{"out":"\([^"]*\)"}}\]$/\2/p' "$work/result")
  is_store_path "$built_drv" drv && is_store_path "$built_out" out || { say "failed build"; exit 1; }
  say "built $built_drv $built_out";;
restore)
  [ $# -eq 3 ] || refuse arguments
  [ "$3" = absent ] || is_hash "$3" || refuse arguments
  take_folder "$1"; folder_safe
  check_backup_name "$2"
  prepare_backups; take_lock
  restore "$2" "$3"
  say "restored $restored $backup_name";;
*) refuse arguments;;
esac
