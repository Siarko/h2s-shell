# shellcheck shell=sh
# The root step of the Hibernate section's Apply, where /etc is the machine's own: the delay
# before a sleep turns into hibernation, as sleep.conf's drop-in (HibernateRules). Never run by
# path: the shell reads this file and hands its text to the system's /bin/sh through pkexec as
# `sh -c <text> sh <base> <seconds>`. The drop-in's place is fixed here, under <base>: "" for
# the system, the only one root takes; a run as the user (a suite's stand-in) names a scratch
# folder. It writes the drop-in beside its place and renames it there (never half a file), and
# says what it wrote. Files made by it are readable, never writable by others (pkexec keeps
# the caller's umask).
set -eu; umask 022
[ $# -eq 2 ] || { echo 'not a request' >&2; exit 2; }
base=$1; seconds=$2
case "$seconds" in ''|*[!0-9]*) echo 'not a delay' >&2; exit 2;; esac
if [ "$(id -u)" = 0 ]; then
  [ -z "$base" ] || { echo 'not the system' >&2; exit 2; }
else
  # The same folders replace-lib.sh's take_base takes: plain, absolute, outside /etc, /usr, /var
  case "$base" in /*) ;; *) echo 'not a directory' >&2; exit 2;; esac
  case "$base" in */|*//*|*/.|*/..|*/./*|*/../*|*[!A-Za-z0-9/._-]*) echo 'not a directory' >&2; exit 2;; esac
  case "$base" in /etc|/etc/*|/usr|/usr/*|/var|/var/*) echo 'not a directory' >&2; exit 2;; esac
fi
directory=$base/etc/systemd/sleep.conf.d
if [ ! -d "$directory" ]; then mkdir -p -- "$directory"; chmod 0755 -- "$directory"; fi
file=$directory/h2s-shell.conf
temporary=$(mktemp -- "$file.XXXXXX")
printf '%s\n' '# Written by h2s-shell: Settings, When away, Hibernate' '[Sleep]' "HibernateDelaySec=$seconds" > "$temporary"
chmod 0644 -- "$temporary"
mv -f -- "$temporary" "$file"
echo "written $seconds"
