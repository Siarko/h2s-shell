# shellcheck shell=sh
# The root step of EtcFiles (distributions/EtcFiles.qml; EtcFilesRules: when it may run and
# what its reply means): one of the shell's own files in /etc written, removed, or put back
# from a backup, where /etc is the machine's own. Joined after replace-lib.sh and
# replace-file.sh and run as `sh -c <text> sh <base> <arguments>…`; never run by path. The
# files it may write are fixed here, one per change kind, under <base> ("" for the system:
# take_base), in a folder whose parent is already there:
#   sleep.hibernateDelay      /etc/systemd/sleep.conf.d/h2s-shell.conf
#   network.connectivityUri   /etc/NetworkManager/conf.d/90-h2s-connectivity.conf
#                             (NetworkManager then reads its configuration again:
#                             reload_networkmanager)
# and their backups in /var/lib/h2s-shell/backup/<kind>/ (`<file name>.<UTC time>`,
# `.absent` when there was no file; every one kept). Its arguments:
#   write  <kind> <sha256 of the text> <current sha256 | absent> <text>
#   remove <kind> <current sha256>
#   undo   <kind> <backup name> <current sha256 | absent>
# A text is exactly the kind's template for the value it holds (shell_text; EtcFilesRules'
# shellText), so a run writes nothing but the shell's own file; the file written must have
# the sha256 the shell computed. Undo puts a backup's content back as a file of root's,
# mode 0644. Its last line on success,
# on stdout and stderr: `written|removed|restored <kind> <sha256 in force | absent> <backup
# made>`; a refusal: `refused <code>` on stderr, exit 3.
[ $# -ge 1 ] || refuse arguments
take_base "$1"; shift
max_bytes=65536
# shell_text <text>: the kind's template for the value in it, exactly ($kind set)
shell_text() {
  [ ${#1} -le "$max_bytes" ] || return 1
  case "$kind" in
  sleep.hibernateDelay)
    seconds=${1##*HibernateDelaySec=}; seconds=${seconds%"$newline"}
    case "$seconds" in ''|0*|*[!0-9]*) return 1;; esac
    [ ${#seconds} -le 9 ] || return 1
    [ "$1" = "# Written by h2s-shell: Settings, When away, Hibernate$newline[Sleep]${newline}HibernateDelaySec=$seconds$newline" ];;
  network.connectivityUri)
    # http(s)://<host>[:<port>][/<path>]: letters, digits, dots and hyphens in the host,
    # nothing in the path that breaks its line (blanks, control characters, quotes, "\")
    head="# Written by h2s-shell (Settings > System > Network)$newline[connectivity]${newline}uri="
    uri=${1#"$head"}; uri=${uri%"$newline"}
    [ "$1" = "$head$uri$newline" ] || return 1
    case "$uri" in http://*) rest=${uri#http://};; https://*) rest=${uri#https://};; *) return 1;; esac
    authority=${rest%%/*}; host=${authority%%:*}
    case "$host" in ''|*[!A-Za-z0-9.-]*) return 1;; esac
    if [ "$authority" != "$host" ]; then
      port=${authority#*:}
      case "$port" in ''|*[!0-9]*) return 1;; esac
    fi
    case "$rest" in
    */*) case "/${rest#*/}" in *[[:space:][:cntrl:]\"\'\\]*) return 1;; esac;;
    esac;;
  *) return 1;;
  esac
}
newline='
'
[ $# -ge 2 ] || refuse arguments
mode=$1; kind=$2; shift 2
case "$kind" in
sleep.hibernateDelay) parent=$base/etc/systemd; folder=$parent/sleep.conf.d; prefix=h2s-shell.conf;;
network.connectivityUri) parent=$base/etc/NetworkManager; folder=$parent/conf.d; prefix=90-h2s-connectivity.conf;;
*) refuse arguments;;
esac
# reload_networkmanager: NetworkManager reads its configuration again, through its own nmcli
# at a fixed place under <base> (a suite's stand-in under its scratch base; the system's as
# root); a failure leaves the file as written and says so before the last line
reload_networkmanager() {
  for program in "$base/run/current-system/sw/bin/nmcli" "$base/usr/bin/nmcli"; do
    [ -x "$program" ] || continue
    "$program" general reload conf > /dev/null 2>&1 && return 0
    echo "warning: NetworkManager did not read its configuration again" >&2
    return 0
  done
  echo "warning: no nmcli: NetworkManager did not read its configuration again" >&2
}
# after_change: what the kind needs once its file changed
after_change() {
  case "$kind" in network.connectivityUri) reload_networkmanager;; esac
}
target=$folder/$prefix; backups=$base/var/lib/h2s-shell/backup/$kind
trap clean_up EXIT
case "$mode" in
write)
  [ $# -eq 3 ] || refuse arguments
  want=$1; current=$2; text=$3
  is_hash "$want" || refuse arguments
  [ "$current" = absent ] || is_hash "$current" || refuse arguments
  shell_text "$text" || refuse arguments;;
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
  after_change
  say "written $kind $got $backup_name";;
remove)
  check_current "$target" "$current"
  make_backup "$current"
  rm -f -- "$target"; settle
  after_change
  say "removed $kind absent $backup_name";;
undo)
  restore "$name" "$current"
  after_change
  say "restored $kind $restored $backup_name";;
esac
