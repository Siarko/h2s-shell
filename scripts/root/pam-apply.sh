# shellcheck shell=sh
# The root step that writes a PAM file on Arch, or undoes it (PamApplyRules: when it may run
# and what its reply means). Joined after replace-lib.sh and replace-file.sh and run as
# `sh -c <text> sh <base> <arguments>…`; never run by path. Its places are fixed here, under
# <base> ("" for the system: take_base); every other argument is checked here:
#   write  <service> <candidate sha256> <current sha256 | absent> <text> [<name> <sha256>]…
#   remove polkit-1  <vendor sha256>    <current sha256>          [<name> <sha256>]…
#   undo   <service> <backup name>      <current sha256 | absent>
# Its last line on success, on stdout and stderr: `written|removed|restored <service>
# <sha256 in force | absent> <backup made>`; a refusal: `refused <code>` on stderr, exit 3.
[ $# -ge 1 ] || refuse arguments
take_base "$1"; shift
system=$base/etc/pam.d; vendor=$base/usr/lib/pam.d; backups=$base/var/lib/h2s-shell/pam-backup
trap clean_up EXIT
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
[ $# -ge 2 ] || refuse arguments
mode=$1; service=$2; shift 2
case "$service" in sudo|polkit-1) ;; *) refuse arguments;; esac
if [ -L "$system" ] || [ ! -d "$system" ]; then refuse system; fi
safe_dir "$system"
target=$system/$service; prefix=$service
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
  printf '%s' "$text" > "$new_temporary" || refuse write
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
  check_backup_name "$name"
  [ "$current" = absent ] || is_hash "$current" || refuse arguments
  restore "$name" "$current"
  say "restored $service $restored $backup_name";;
*) refuse arguments;;
esac
