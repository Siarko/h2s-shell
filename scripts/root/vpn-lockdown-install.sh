# shellcheck shell=sh
# The root step that installs, removes or undoes the VPN blocking's script and its polkit rule
# on Arch (VpnLockdownInstallRules: when it may run and what its reply means). Joined after
# replace-lib.sh and run as `sh -c <text> sh <base> <arguments>…`; never run by path. Its
# places are fixed here, under <base> ("" for the system: take_base), and so are the files'
# names, the rule's template and the script's first lines. Its arguments:
#   apply <script op> <script current> <script sha256 | -> <rule op> <rule current>
#         <rule sha256 | -> <user | -> <script text | ->
#   undo  <stamp> <script current> <rule current>
# an op: write (with the sha256 the new file must have), remove or keep (`-`); a current: the
# file's sha256 as the shell read it, or `absent`. The rule is written only from the user
# (checked by a fixed pattern) and this script's own template, naming the script's fixed
# place, so a run can grant nothing but running that file; the script is written from the
# text given — the shell's scripts/h2s-vpn-lockdown as the shell read it, shown with the
# command — only when it starts as that script does and has the sha256 the shell computed.
# Each file built must have the sha256 the shell computed for it. Each run records what it
# left (`run.<stamp>`: the two sha256s or `absent`); Undo of a stamp needs the files to be
# exactly that. Its last line on success, on stdout and stderr: `applied|restored <script
# sha256 | absent> <rule sha256 | absent> <stamp>`; a refusal: `refused <code>` on stderr,
# exit 3.
[ $# -ge 1 ] || refuse arguments
take_base "$1"; shift
local_dir=$base/usr/local; libexec=$local_dir/libexec; rules=$base/usr/share/polkit-1/rules.d
backups=$base/var/lib/h2s-shell/vpn-lockdown-backup
script_name='h2s-vpn-lockdown'; rule_name='49-h2s-vpn-lockdown.rules'; max_bytes=65536
rule_marker='// Written by h2s-shell (Settings > System > Network > VPN > Password-free blocking).'
script_start='#!/bin/sh
# h2s-vpn-lockdown '
script_temporary=; rule_temporary=; backup_temporary=
trap 'for leftover in "$script_temporary" "$rule_temporary" "$backup_temporary"; do [ -z "$leftover" ] || rm -f -- "$leftover"; done' EXIT
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
check_user() {
  [ ${#1} -le 32 ] || refuse arguments
  case "$1" in ''|[!A-Za-z0-9_]*|*[!A-Za-z0-9_-]*) refuse arguments;; esac
}
check_script() {
  [ ${#1} -le "$max_bytes" ] || refuse arguments
  case "$1" in "$script_start"*) ;; *) refuse arguments;; esac
}
# The template (VpnLockdownRules.lockdownPolkitRule for one program)
rule_body() {
  printf '%s\n' "$rule_marker"
  printf "// Lets %s run h2s-vpn-lockdown, which only switches the shell's VPN blocking, without a password.\\n" "$user"
  printf 'polkit.addRule(function (action, subject) {\n'
  printf '    if (action.id == "org.freedesktop.policykit.exec" && subject.user == "%s" && subject.local && subject.active\n' "$user"
  printf '        && (action.lookup("program") == "%s"))\n' "$script_target"
  printf '        return polkit.Result.YES;\n});\n'
}
script_body() { printf '%s' "$script_text"; }
# A new file beside its target, from a body: its mode, the bytes checked (against $4 when
# given), flushed; its hash left in $got
build() {
  "$1" > "$2" || refuse write
  seal "$2" "$3" "$4"
}
seal() {
  chmod "$2" -- "$1" || refuse write
  got=$(hash_of "$1") || refuse write
  if [ -n "$3" ] && [ "$got" != "$3" ]; then refuse hash; fi
  sync -- "$1" || refuse write
}
# A stamp no backup or record has
taken() {
  for path in "$backups/run.$1" "$backups/$script_name.$1" "$backups/$script_name.$1.absent" "$backups/$rule_name.$1" "$backups/$rule_name.$1.absent"; do
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
  if [ "$script_current" = absent ]; then keep_file '' "$script_name.$stamp.absent" ''; else keep_file "$script_target" "$script_name.$stamp"; fi
  if [ "$rule_current" = absent ]; then keep_file '' "$rule_name.$stamp.absent" ''; else keep_file "$rule_target" "$rule_name.$stamp"; fi
  keep_file '' "run.$stamp" "$script_after $rule_after"
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
# The backup of a stamp put back into a new file beside its target: name, target, folder,
# mode, current; sets the op and the sha256 after
restore() {
  copy=$backups/$1.$stamp_given
  restored_op=keep; restored_after=$5; restored_temporary=
  if [ -f "$copy" ] && [ ! -L "$copy" ]; then
    restored_temporary=$(mktemp -- "$3/.h2s-shell.XXXXXX") || refuse write
    cat -- "$copy" > "$restored_temporary" || refuse write
    seal "$restored_temporary" "$4" ''; restored_after=$got
    if [ "$got" != "$5" ]; then restored_op=write; fi
  elif [ "$5" != absent ]; then restored_op=remove; restored_after=absent; fi
}
[ $# -ge 1 ] || refuse arguments
mode=$1; shift
if [ -L "$rules" ] || [ ! -d "$rules" ]; then refuse system; fi
safe_dir "$rules"
if [ -L "$local_dir" ] || [ ! -d "$local_dir" ]; then refuse system; fi
safe_dir "$local_dir"
if [ -L "$libexec" ]; then refuse owner; fi
[ -d "$libexec" ] || mkdir -m 0755 -- "$libexec" || refuse write
safe_dir "$libexec"
script_target=$libexec/$script_name; rule_target=$rules/$rule_name
prepare_backups
take_lock
case "$mode" in
apply)
  [ $# -eq 8 ] || refuse arguments
  script_op=$1; script_current=$2; script_want=$3; rule_op=$4; rule_current=$5; rule_want=$6
  user=$7; script_text=$8
  check_request "$script_op" "$script_current" "$script_want"
  check_request "$rule_op" "$rule_current" "$rule_want"
  [ "$script_op" != keep ] || [ "$rule_op" != keep ] || refuse arguments
  if [ "$script_op" = write ]; then check_script "$script_text"; else [ "$script_text" = - ] || refuse arguments; fi
  if [ "$rule_op" = write ]; then check_user "$user"; else [ "$user" = - ] || refuse arguments; fi
  check_current "$script_target" "$script_current"
  check_current "$rule_target" "$rule_current"
  script_after=$script_current; rule_after=$rule_current
  if [ "$script_op" = write ]; then
    script_temporary=$(mktemp -- "$libexec/.h2s-shell.XXXXXX") || refuse write
    build script_body "$script_temporary" 0755 "$script_want"; script_after=$got
  elif [ "$script_op" = remove ]; then script_after=absent; fi
  if [ "$rule_op" = write ]; then
    rule_temporary=$(mktemp -- "$rules/.h2s-shell.XXXXXX") || refuse write
    build rule_body "$rule_temporary" 0644 "$rule_want"; rule_after=$got
  elif [ "$rule_op" = remove ]; then rule_after=absent; fi
  kind=applied;;
undo)
  [ $# -eq 3 ] || refuse arguments
  stamp_given=$1; script_current=$2; rule_current=$3
  stamp_pattern='[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z'
  case "$stamp_given" in $stamp_pattern|$stamp_pattern-[1-9]) ;; *) refuse arguments;; esac
  [ "$script_current" = absent ] || is_hash "$script_current" || refuse arguments
  [ "$rule_current" = absent ] || is_hash "$rule_current" || refuse arguments
  # Each file's backup of that stamp (a copy, or a record of no file), and what that run left
  for name in "$script_name" "$rule_name"; do
    copy=$backups/$name.$stamp_given
    if [ -f "$copy" ] && [ ! -L "$copy" ]; then :
    elif [ -f "$copy.absent" ] && [ ! -L "$copy.absent" ]; then :
    else refuse nobackup; fi
  done
  record=$backups/run.$stamp_given
  if [ -L "$record" ] || [ ! -f "$record" ]; then refuse nobackup; fi
  left=$(cat -- "$record") || refuse nobackup
  [ "$left" = "$script_current $rule_current" ] || refuse changed
  check_current "$script_target" "$script_current"
  check_current "$rule_target" "$rule_current"
  restore "$script_name" "$script_target" "$libexec" 0755 "$script_current"
  script_op=$restored_op; script_after=$restored_after; script_temporary=$restored_temporary
  restore "$rule_name" "$rule_target" "$rules" 0644 "$rule_current"
  rule_op=$restored_op; rule_after=$restored_after; rule_temporary=$restored_temporary
  kind=restored;;
*) refuse arguments;;
esac
make_backups
put "$script_op" "$script_temporary" "$script_target" "$libexec"
if [ "$script_op" = write ]; then script_temporary=; fi
put "$rule_op" "$rule_temporary" "$rule_target" "$rules"
if [ "$rule_op" = write ]; then rule_temporary=; fi
say "$kind $script_after $rule_after $stamp"
