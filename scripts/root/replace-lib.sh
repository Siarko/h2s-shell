# shellcheck shell=sh
# The start of every root script that replaces system files (pam-apply.sh,
# remember-install.sh). Never run by path: the shell reads this file and the script's own from
# its tree, joins the two texts (this one first) and hands them to the system's /bin/sh through
# pkexec as `sh -c <text> sh <arguments>…`, so the prompt shows what runs and root reads no
# file the user can write.
#
# Stop at the first failure, files made private (pkexec keeps the caller's umask), messages
# and sorting in the C locale.
set -eu; umask 077; export LC_ALL=C

# refuse <code>: `refused <code>` on stderr, exit 3
refuse() { echo "refused $1" >&2; exit 3; }

# say <line>: what was done, on stderr first (it reaches the shell even when stdout is gone),
# then on stdout
say() { printf '%s\n' "$1" >&2; printf '%s\n' "$1" || :; }

# take_base <base>: where the script's fixed places are. Run as root, only under "" (the
# system itself); run as the user (a suite's stand-in, never through pkexec), under a scratch
# folder holding the same tree: a plain absolute path outside /etc, /usr and /var. Sets $base,
# and $owner: who must own the folders written in (the one running).
take_base() {
  owner=$(id -u) || refuse owner
  base=$1
  if [ "$owner" = 0 ]; then
    [ -z "$base" ] || refuse paths
    return 0
  fi
  case "$base" in /*) ;; *) refuse paths;; esac
  case "$base" in */|*//*|*/.|*/..|*/./*|*/../*|*[!A-Za-z0-9/._-]*) refuse paths;; esac
  case "$base" in /etc|/etc/*|/usr|/usr/*|/var|/var/*) refuse paths;; esac
}

# safe_dir <dir>: no link, the owner's, nobody else may write in it
safe_dir() {
  if [ -L "$1" ] || [ ! -d "$1" ]; then refuse owner; fi
  facts=$(stat -c '%u %a' -- "$1") || refuse owner
  [ "${facts%% *}" = "$owner" ] || refuse owner
  [ $((0${facts#* } & 022)) -eq 0 ] || refuse owner
}

hash_of() { sum=$(sha256sum < "$1") || return 1; printf '%s\n' "${sum%% *}"; }
is_hash() { case "$1" in ''|*[!0-9a-f]*) return 1;; esac; [ ${#1} -eq 64 ]; }

# check_current <file> <sha256 | absent>: the file as the shell read it, never a link
check_current() {
  if [ -L "$1" ]; then refuse link; fi
  if [ "$2" = absent ]; then
    if [ -e "$1" ]; then refuse changed; fi
    return 0
  fi
  [ -f "$1" ] || refuse changed
  got=$(hash_of "$1") || refuse unreadable
  [ "$got" = "$2" ] || refuse changed
}

# prepare_backups: the backups' folder ($backups) made, it and its parent safe, 0700
prepare_backups() {
  if [ -L "${backups%/*}" ] || [ -L "$backups" ]; then refuse backup; fi
  mkdir -p -- "$backups" || refuse backup
  safe_dir "${backups%/*}"
  safe_dir "$backups"
  chmod 0700 -- "$backups" || refuse backup
}

# take_lock: one run at a time, from the first check to the last write, on the backups' lock
# file; a second run is refused, never waited for. flock says 1 for a lock held; anything else
# (no flock) is not "busy".
take_lock() {
  exec 9>> "$backups/.lock" || refuse backup
  flock -n 9 || { held=$?; [ "$held" -ne 1 ] || refuse busy; refuse lock; }
}
