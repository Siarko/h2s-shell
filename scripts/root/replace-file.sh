# shellcheck shell=sh
# The steps of a root script that replaces one system file and keeps what it replaced
# (pam-apply.sh, etc-files.sh): joined after replace-lib.sh and before the script's own; never
# run by path. The script sets, before it uses them:
#   target    the file replaced (the script checks its folder)
#   backups   the backups' folder (prepare_backups, take_lock)
#   prefix    the name every backup of this file starts with
# and calls `trap clean_up EXIT`. A backup is named <prefix>.<UTC stamp>[-<n>][.absent]
# (`.absent`: there was no file); every one is kept.
new_temporary=; backup_temporary=
clean_up() { for leftover in "$new_temporary" "$backup_temporary"; do [ -z "$leftover" ] || rm -f -- "$leftover"; done; }

# make_backup <current sha256 | absent>: the target as it is (checked before) into the
# backups, its name in $backup_name; a name never taken twice (ln fails on a name that is
# there)
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
    backup_name="$prefix.$stamp$extra$suffix"
    if ln -- "$backup_temporary" "$backups/$backup_name" 2> /dev/null; then break; fi
    count=$((count + 1)); [ "$count" -le 9 ] || refuse backup
    extra="-$count"
  done
  rm -f -- "$backup_temporary"; backup_temporary=
  sync -- "$backups" || refuse backup
}

# A new file beside the target ($new_temporary), checked by seal, renamed into place by
# put_in_place (never half a file; a rename replaces a link, never follows it)
new_file() { new_temporary=$(mktemp -- "${target%/*}/.h2s-shell.XXXXXX") || refuse write; }
# seal <sha256 | "">: the new file 0644, its bytes checked (against the sha256 when given),
# flushed; its sha256 left in $got
seal() {
  chmod 0644 -- "$new_temporary" || refuse write
  got=$(hash_of "$new_temporary") || refuse write
  if [ -n "$1" ] && [ "$got" != "$1" ]; then refuse hash; fi
  sync -- "$new_temporary" || refuse write
}
settle() { sync -- "${target%/*}" 2> /dev/null || :; }
put_in_place() { mv -fT -- "$new_temporary" "$target" || refuse write; new_temporary=; settle; }

# check_backup_name <name>: one of the target's backups, as make_backup names them
check_backup_name() {
  stamp_pattern='[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z'
  case "$1" in "$prefix".*) ;; *) refuse arguments;; esac
  case "${1#"$prefix".}" in $stamp_pattern|$stamp_pattern-[1-9]|$stamp_pattern.absent|$stamp_pattern-[1-9].absent) ;; *) refuse arguments;; esac
}

# restore <backup name> <current sha256 | absent>: the backup (checked by check_backup_name)
# back in place of the target as the shell read it, the target first kept as a backup of its
# own; what is in force after it in $restored (its sha256, or absent)
restore() {
  source=$backups/$1
  if [ -L "$source" ] || [ ! -f "$source" ]; then refuse nobackup; fi
  check_current "$target" "$2"
  case "$1" in
  *.absent)
    make_backup "$2"
    rm -f -- "$target"; settle
    restored=absent;;
  *)
    new_file
    cat -- "$source" > "$new_temporary" || refuse write
    seal ''
    make_backup "$2"
    put_in_place
    restored=$got;;
  esac
}
