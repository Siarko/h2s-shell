# shellcheck shell=sh
# The root step that installs, removes or undoes the remembered administrator authorization
# on Arch (RememberInstallRules: when it may run and what its reply means). Joined after
# replace-lib.sh and run as `sh -c <text> sh <base> <arguments>…`; never run by path. Its
# places are fixed here, under <base> ("" for the system: take_base), and so are the files'
# names, markers and the longest length (RememberRules, the settings schema). Its arguments:
#   apply <rule op> <rule current> <rule sha256 | -> <conf op> <conf current> <conf sha256 | ->
#         <user | -> <timeout | -> <program | -> <seconds | ->
#   undo  <stamp> <rule current> <conf current>
# an op: write (with the sha256 the new file must have), remove or keep (`-`); a current: the
# file's sha256 as the shell read it, or `absent`. The rule is written only from the user, the
# timeout and the program (checked by fixed patterns), the conf only from the seconds (1 to
# max_seconds): the texts are this script's own templates, so a run can write nothing but the
# shell's rule and conf; the file it built must have the sha256 the shell computed for the
# same facts. Each run records what it left (`run.<stamp>`: the two sha256s or `absent`); Undo
# of a stamp needs the files to be exactly that. Its last line on success, on stdout and
# stderr: `applied|restored <rule sha256 | absent> <conf sha256 | absent> <stamp> <hup | nohup
# | none>` (polkitd told, telling it failed, the conf unchanged); a refusal: `refused <code>`
# on stderr, exit 3.
[ $# -ge 1 ] || refuse arguments
take_base "$1"; shift
rules=$base/usr/share/polkit-1/rules.d; conf=$base/etc/polkit-1; backups=$base/var/lib/h2s-shell/polkit-backup
systemctl=$base/usr/bin/systemctl
rule_name='40-h2s-shell.rules'; conf_name='polkitd.conf'; max_seconds=3600
rule_marker='// Written by h2s-shell'; conf_marker='# Written by h2s-shell'; action='org.freedesktop.policykit.exec'
rule_temporary=; conf_temporary=; backup_temporary=
trap 'for leftover in "$rule_temporary" "$conf_temporary" "$backup_temporary"; do [ -z "$leftover" ] || rm -f -- "$leftover"; done' EXIT
# One file's request: op, current, sha256
check_request() {
  case "$1" in
  write) is_hash "$3" || refuse arguments;;
  remove|keep) [ "$3" = - ] || refuse arguments;;
  *) refuse arguments;;
  esac
  [ "$2" = absent ] || is_hash "$2" || refuse arguments
  if [ "$1" = remove ] && [ "$2" = absent ]; then refuse arguments; fi
}
# The facts, as RememberRules takes them
check_user() {
  [ ${#1} -le 256 ] || refuse arguments
  name=${1%\$}
  case "$name" in ''|[!A-Za-z0-9_]*|*[!A-Za-z0-9_.-]*) refuse arguments;; esac
}
check_path() {
  [ ${#1} -le 4096 ] || refuse arguments
  case "$1" in /*) ;; *) refuse arguments;; esac
  case "$1" in */|*[!A-Za-z0-9/._+-]*) refuse arguments;; esac
}
check_seconds() {
  case "$1" in ''|0*|*[!0-9]*) refuse arguments;; esac
  [ ${#1} -le 9 ] && [ "$1" -le "$max_seconds" ] || refuse arguments
}
# The templates (RememberRules.ruleText, confText): a multi-call binary's program also needs
# the command line's first word to be the timeout
rule_body() {
  printf 'polkit.addRule(function(action, subject) {\n'
  printf '    if (action.id == "%s" && subject.user == "%s" &&\n' "$action" "$user"
  printf '        action.lookup("program") == "%s"' "$program"
  case "${program##*/}" in
  timeout) ;;
  *) printf ' &&\n        action.lookup("command_line").indexOf("%s ") == 0' "$timeout";;
  esac
  printf ')\n        return "auth_admin_keep";\n});\n'
}
conf_body() { printf '[Polkitd]\nExpirationSeconds=%s\n' "$seconds"; }
# A body behind its marker and its sha256, into a new file
marked() {
  sum=$("$2" | sha256sum) || refuse write
  is_hash "${sum%% *}" || refuse write
  { printf '%s %s\n' "$1" "${sum%% *}"; "$2"; } > "$3" || refuse write
}
# A new file beside its target: mode 0644, the bytes checked (against $2 when given),
# flushed; its hash left in $got
seal() {
  chmod 0644 -- "$1" || refuse write
  got=$(hash_of "$1") || refuse write
  if [ -n "$2" ] && [ "$got" != "$2" ]; then refuse hash; fi
  sync -- "$1" || refuse write
}
# A stamp no backup or record has
taken() {
  for path in "$backups/run.$1" "$backups/$rule_name.$1" "$backups/$rule_name.$1.absent" "$backups/$conf_name.$1" "$backups/$conf_name.$1.absent"; do
    if [ -e "$path" ] || [ -L "$path" ]; then return 0; fi
  done
  return 1
}
# Into the backups under $stamp: $1 a file to copy, or empty for none (and then $3 the
# text, for the record); ln fails on a name that is there
keep_file() {
  backup_temporary=$(mktemp -- "$backups/.new.XXXXXX") || refuse backup
  if [ -n "$1" ]; then cat -- "$1" > "$backup_temporary" || refuse backup
  else printf '%s' "$3" > "$backup_temporary" || refuse backup; fi
  chmod 0600 -- "$backup_temporary" || refuse backup
  sync -- "$backup_temporary" || refuse backup
  ln -- "$backup_temporary" "$backups/$2" 2> /dev/null || refuse backup
  rm -f -- "$backup_temporary"; backup_temporary=
}
# Both files as they are (checked before), and what this run leaves, under one stamp
make_backups() {
  stamp_base=$(date -u +%Y%m%dT%H%M%SZ)
  stamp=$stamp_base; count=0
  while taken "$stamp"; do
    count=$((count + 1)); [ "$count" -le 9 ] || refuse backup
    stamp="$stamp_base-$count"
  done
  if [ "$rule_current" = absent ]; then keep_file '' "$rule_name.$stamp.absent" ''; else keep_file "$rule_target" "$rule_name.$stamp"; fi
  if [ "$conf_current" = absent ]; then keep_file '' "$conf_name.$stamp.absent" ''; else keep_file "$conf_target" "$conf_name.$stamp"; fi
  keep_file '' "run.$stamp" "$rule_after $conf_after"
  sync -- "$backups" || refuse backup
}
# One file into place: op, the new file, the target, its folder. After the first file
# changed a failure is no longer "nothing changed"
placed=
put() {
  case "$1" in
  write) mv -fT -- "$2" "$3" || { [ -z "$placed" ] || refuse partial; refuse write; };;
  remove) rm -f -- "$3" || { [ -z "$placed" ] || refuse partial; refuse write; };;
  *) return 0;;
  esac
  placed=1
  sync -- "$4" 2> /dev/null || :
}
[ $# -ge 1 ] || refuse arguments
mode=$1; shift
for dir in "$rules" "$conf"; do
  if [ -L "$dir" ] || [ ! -d "$dir" ]; then refuse system; fi
  safe_dir "$dir"
done
rule_target=$rules/$rule_name; conf_target=$conf/$conf_name
prepare_backups
take_lock
case "$mode" in
apply)
  [ $# -eq 10 ] || refuse arguments
  rule_op=$1; rule_current=$2; rule_want=$3; conf_op=$4; conf_current=$5; conf_want=$6
  user=$7; timeout=$8; program=$9; seconds=${10}
  check_request "$rule_op" "$rule_current" "$rule_want"
  check_request "$conf_op" "$conf_current" "$conf_want"
  [ "$rule_op" != keep ] || [ "$conf_op" != keep ] || refuse arguments
  if [ "$rule_op" = write ]; then check_user "$user"; check_path "$timeout"; check_path "$program"
  else [ "$user" = - ] && [ "$timeout" = - ] && [ "$program" = - ] || refuse arguments; fi
  if [ "$conf_op" = write ]; then check_seconds "$seconds"
  else [ "$seconds" = - ] || refuse arguments; fi
  check_current "$rule_target" "$rule_current"
  check_current "$conf_target" "$conf_current"
  rule_after=$rule_current; conf_after=$conf_current
  if [ "$rule_op" = write ]; then
    rule_temporary=$(mktemp -- "$rules/.h2s-shell.XXXXXX") || refuse write
    marked "$rule_marker" rule_body "$rule_temporary"
    seal "$rule_temporary" "$rule_want"; rule_after=$got
  elif [ "$rule_op" = remove ]; then rule_after=absent; fi
  if [ "$conf_op" = write ]; then
    conf_temporary=$(mktemp -- "$conf/.h2s-shell.XXXXXX") || refuse write
    marked "$conf_marker" conf_body "$conf_temporary"
    seal "$conf_temporary" "$conf_want"; conf_after=$got
  elif [ "$conf_op" = remove ]; then conf_after=absent; fi
  kind=applied;;
undo)
  [ $# -eq 3 ] || refuse arguments
  stamp_given=$1; rule_current=$2; conf_current=$3
  stamp_pattern='[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z'
  case "$stamp_given" in $stamp_pattern|$stamp_pattern-[1-9]) ;; *) refuse arguments;; esac
  [ "$rule_current" = absent ] || is_hash "$rule_current" || refuse arguments
  [ "$conf_current" = absent ] || is_hash "$conf_current" || refuse arguments
  # Each file's backup of that stamp (a copy, or a record of no file), and what that run left
  for name in "$rule_name" "$conf_name"; do
    copy=$backups/$name.$stamp_given
    if [ -f "$copy" ] && [ ! -L "$copy" ]; then :
    elif [ -f "$copy.absent" ] && [ ! -L "$copy.absent" ]; then :
    else refuse nobackup; fi
  done
  record=$backups/run.$stamp_given
  if [ -L "$record" ] || [ ! -f "$record" ]; then refuse nobackup; fi
  left=$(cat -- "$record") || refuse nobackup
  [ "$left" = "$rule_current $conf_current" ] || refuse changed
  check_current "$rule_target" "$rule_current"
  check_current "$conf_target" "$conf_current"
  rule_op=keep; conf_op=keep; rule_after=$rule_current; conf_after=$conf_current
  copy=$backups/$rule_name.$stamp_given
  if [ -f "$copy" ] && [ ! -L "$copy" ]; then
    rule_temporary=$(mktemp -- "$rules/.h2s-shell.XXXXXX") || refuse write
    cat -- "$copy" > "$rule_temporary" || refuse write
    seal "$rule_temporary" ''; rule_after=$got
    if [ "$got" != "$rule_current" ]; then rule_op=write; fi
  elif [ "$rule_current" != absent ]; then rule_op=remove; rule_after=absent; fi
  copy=$backups/$conf_name.$stamp_given
  if [ -f "$copy" ] && [ ! -L "$copy" ]; then
    conf_temporary=$(mktemp -- "$conf/.h2s-shell.XXXXXX") || refuse write
    cat -- "$copy" > "$conf_temporary" || refuse write
    seal "$conf_temporary" ''; conf_after=$got
    if [ "$got" != "$conf_current" ]; then conf_op=write; fi
  elif [ "$conf_current" != absent ]; then conf_op=remove; conf_after=absent; fi
  kind=restored;;
*) refuse arguments;;
esac
make_backups
put "$rule_op" "$rule_temporary" "$rule_target" "$rules"
if [ "$rule_op" = write ]; then rule_temporary=; fi
put "$conf_op" "$conf_temporary" "$conf_target" "$conf"
if [ "$conf_op" = write ]; then conf_temporary=; fi
# polkitd reads its conf only at its start and on SIGHUP
reload=none
if [ "$conf_op" != keep ]; then
  if "$systemctl" kill -s HUP --kill-whom=main polkit.service >&2; then reload=hup; else reload=nohup; fi
fi
say "$kind $rule_after $conf_after $stamp $reload"
