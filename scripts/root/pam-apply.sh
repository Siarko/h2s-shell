# shellcheck shell=sh
# The root step that writes a PAM file on Arch, or undoes it (PamApplyRules: when it may run
# and what its reply means). Joined after replace-lib.sh and run as `sh -c <text> sh <base>
# <arguments>…`; never run by path. Its places are fixed here, under <base> ("" for the
# system: take_base); every other argument is checked here:
#   write  <service> <candidate sha256> <current sha256 | absent> <text> [<name> <sha256>]…
#   remove polkit-1  <vendor sha256>    <current sha256>          [<name> <sha256>]…
#   undo   <service> <backup name>      <current sha256 | absent>
# Its last line on success, on stdout and stderr: `written|removed|restored <service>
# <sha256 in force | absent> <backup made>`; a refusal: `refused <code>` on stderr, exit 3.
[ $# -ge 1 ] || refuse arguments
take_base "$1"; shift
system=$base/etc/pam.d; vendor=$base/usr/lib/pam.d; backups=$base/var/lib/h2s-shell/pam-backup
pam_temporary=; backup_temporary=
trap 'for leftover in "$pam_temporary" "$backup_temporary"; do [ -z "$leftover" ] || rm -f -- "$leftover"; done' EXIT
is_name() { case "$1" in ''|[!A-Za-z0-9_]*|*[!A-Za-z0-9._@+-]*) return 1;; esac; [ ${#1} -le 255 ]; }
# Each included name where libpam finds it, as the trial read it
check_includes() {
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || refuse arguments
    is_name "$1" && is_hash "$2" || refuse arguments
    if [ -e "$system/$1" ] || [ -L "$system/$1" ]; then file="$system/$1"
    elif [ -e "$vendor/$1" ] || [ -L "$vendor/$1" ]; then file="$vendor/$1"
    else refuse included; fi
    [ -f "$file" ] || refuse included
    got=$(hash_of "$file") || refuse included
    [ "$got" = "$2" ] || refuse included
    shift 2
  done
}
# The current file (checked) into the backups; a name never taken twice (ln fails on a
# name that is there)
make_backup() {
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  suffix=
  if [ "$1" = absent ]; then suffix=.absent; fi
  backup_temporary=$(mktemp -- "$backups/.new.XXXXXX") || refuse backup
  if [ "$1" != absent ]; then cat -- "$target" > "$backup_temporary" || refuse backup; fi
  chmod 0600 -- "$backup_temporary" || refuse backup
  sync -- "$backup_temporary" || refuse backup
  count=0; extra=
  while :; do
    backup_name="$service.$stamp$extra$suffix"
    if ln -- "$backup_temporary" "$backups/$backup_name" 2> /dev/null; then break; fi
    count=$((count + 1)); [ "$count" -le 9 ] || refuse backup
    extra="-$count"
  done
  rm -f -- "$backup_temporary"; backup_temporary=
  sync -- "$backups" || refuse backup
}
# A new file beside the target, checked, renamed into place (never half a file; a rename
# replaces a link, never follows it)
new_file() { pam_temporary=$(mktemp -- "$system/.h2s-shell.XXXXXX") || refuse write; }
seal() {
  chmod 0644 -- "$pam_temporary" || refuse write
  got=$(hash_of "$pam_temporary") || refuse write
  if [ -n "$1" ] && [ "$got" != "$1" ]; then refuse hash; fi
  sync -- "$pam_temporary" || refuse write
}
settle() { sync -- "$system" 2> /dev/null || :; }
put_in_place() { mv -fT -- "$pam_temporary" "$target" || refuse write; pam_temporary=; settle; }
[ $# -ge 2 ] || refuse arguments
mode=$1; service=$2; shift 2
case "$service" in sudo|polkit-1) ;; *) refuse arguments;; esac
if [ -L "$system" ] || [ ! -d "$system" ]; then refuse system; fi
safe_dir "$system"
target=$system/$service
prepare_backups
take_lock
case "$mode" in
write)
  [ $# -ge 3 ] || refuse arguments
  want=$1; current=$2; text=$3; shift 3
  is_hash "$want" || refuse arguments
  [ "$current" = absent ] || is_hash "$current" || refuse arguments
  check_current "$target" "$current"
  check_includes "$@"
  new_file
  printf '%s' "$text" > "$pam_temporary" || refuse write
  seal "$want"
  make_backup "$current"
  put_in_place
  say "written $service $got $backup_name";;
remove)
  [ "$service" = polkit-1 ] && [ $# -ge 2 ] || refuse arguments
  want=$1; current=$2; shift 2
  is_hash "$want" && is_hash "$current" || refuse arguments
  source=$vendor/$service
  if [ -L "$source" ] || [ ! -f "$source" ]; then refuse vendor; fi
  got=$(hash_of "$source") || refuse vendor
  [ "$got" = "$want" ] || refuse vendor
  check_current "$target" "$current"
  check_includes "$@"
  make_backup "$current"
  rm -f -- "$target"; settle
  say "removed $service $want $backup_name";;
undo)
  [ $# -eq 2 ] || refuse arguments
  name=$1; current=$2
  stamp_pattern='[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z'
  case "$name" in "$service".*) ;; *) refuse arguments;; esac
  case "${name#"$service".}" in $stamp_pattern|$stamp_pattern-[1-9]|$stamp_pattern.absent|$stamp_pattern-[1-9].absent) ;; *) refuse arguments;; esac
  [ "$current" = absent ] || is_hash "$current" || refuse arguments
  source=$backups/$name
  if [ -L "$source" ] || [ ! -f "$source" ]; then refuse nobackup; fi
  check_current "$target" "$current"
  case "$name" in
  *.absent)
    make_backup "$current"
    rm -f -- "$target"; settle
    say "restored $service absent $backup_name";;
  *)
    new_file
    cat -- "$source" > "$pam_temporary" || refuse write
    seal ''
    make_backup "$current"
    put_in_place
    say "restored $service $got $backup_name";;
  esac;;
*) refuse arguments;;
esac
