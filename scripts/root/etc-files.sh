# shellcheck shell=sh
# The root step of EtcFiles (distributions/EtcFiles.qml; EtcFilesRules: when it may run and
# what its reply means): one of the shell's own files in /etc written, removed, or put back
# from a backup, where /etc is the machine's own. Joined after replace-lib.sh and
# replace-file.sh and run as `sh -c <text> sh <base> <arguments>…`; never run by path. The
# files it may write are fixed here, one per change kind, under <base> ("" for the system:
# take_base), in a folder whose parent is already there:
#   sleep.hibernateDelay   /etc/systemd/sleep.conf.d/h2s-shell.conf
# and their backups in /var/lib/h2s-shell/backup/<kind>/ (`<file name>.<UTC time>`,
# `.absent` when there was no file; every one kept). Its arguments:
#   write  <kind> <sha256 of the text> <current sha256 | absent> <text>
#   remove <kind> <current sha256>
#   undo   <kind> <backup name> <current sha256 | absent>
# A text is the shell's: its first line the marker, at most max_bytes, ending in a line
# break; the file written must have the sha256 the shell computed. Its last line on success,
# on stdout and stderr: `written|removed|restored <kind> <sha256 in force | absent> <backup
# made>`; a refusal: `refused <code>` on stderr, exit 3.
[ $# -ge 1 ] || refuse arguments
take_base "$1"; shift
marker='# Written by h2s-shell'; max_bytes=65536
[ $# -ge 2 ] || refuse arguments
mode=$1; kind=$2; shift 2
case "$kind" in
sleep.hibernateDelay) parent=$base/etc/systemd; folder=$parent/sleep.conf.d; prefix=h2s-shell.conf;;
*) refuse arguments;;
esac
target=$folder/$prefix; backups=$base/var/lib/h2s-shell/backup/$kind
trap clean_up EXIT
case "$mode" in
write)
  [ $# -eq 3 ] || refuse arguments
  want=$1; current=$2; text=$3
  is_hash "$want" || refuse arguments
  [ "$current" = absent ] || is_hash "$current" || refuse arguments
  [ ${#text} -le "$max_bytes" ] || refuse arguments
  case "$text" in "$marker"*) ;; *) refuse arguments;; esac
  case "$text" in *'
') ;; *) refuse arguments;; esac;;
remove)
  [ $# -eq 1 ] || refuse arguments
  current=$1
  is_hash "$current" || refuse arguments;;
undo)
  [ $# -eq 2 ] || refuse arguments
  name=$1; current=$2
  check_backup_name "$name"
  [ "$current" = absent ] || is_hash "$current" || refuse arguments;;
*) refuse arguments;;
esac
# The folders written in: never links, the owner's, nobody else may write in them; the
# file's folder made (0755) when it is not there
if [ -L "$parent" ] || [ ! -d "$parent" ]; then refuse system; fi
safe_dir "$parent"
prepare_backups
safe_dir "${backups%/*/*}"
take_lock
if [ "$mode" != remove ] && [ ! -e "$folder" ] && [ ! -L "$folder" ]; then mkdir -m 0755 -- "$folder" || refuse write; fi
if [ -L "$folder" ] || [ ! -d "$folder" ]; then refuse system; fi
safe_dir "$folder"
case "$mode" in
write)
  check_current "$target" "$current"
  new_file
  printf '%s' "$text" > "$new_temporary" || refuse write
  seal "$want"
  make_backup "$current"
  put_in_place
  say "written $kind $got $backup_name";;
remove)
  check_current "$target" "$current"
  make_backup "$current"
  rm -f -- "$target"; settle
  say "removed $kind absent $backup_name";;
undo)
  restore "$name" "$current"
  say "restored $kind $restored $backup_name";;
esac
