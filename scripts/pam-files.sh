#!/usr/bin/env bash
# PAM's files as PamStacks reads them (singletons/io/PamStackReader.qml), and polkit's as
# RememberedAdmin does (singletons/io/RememberedAdminReader.qml), read only:
#
#   pam-files.sh [<absolute path> ...]
#
# First the places, then one record per path asked:
#
#   directory TAB <path>            where libpam looks for a service, in order (the vendor
#                                   directory only where there is one)
#   faillock TAB <path>             pam_faillock's default faillock.conf
#   file TAB <path> TAB text        the file's lines follow, each after a "|", then
#   end TAB <path>
#   file TAB <path> TAB absent      known not to be there (ENOENT, ENOTDIR)
#   file TAB <path> TAB unreadable  there, or maybe there, but not readable by this user,
#                                   not a regular file, or larger than 64 KiB
#
# Telling "absent" from "unreadable" matters: libpam goes on to the next directory past a
# file that is not there, so a file that cannot be read leaves the stack unknown, never
# "without such lines" (PamStackRules.stack's reader contract). A path is absent only when
# its nearest existing ancestor is not a directory (ENOTDIR) or is a directory this user can
# search (ENOENT); a parent that cannot be searched, or a link that leads nowhere, is
# unreadable. A path that is not absolute or holds a tab or a line break gets no record (the
# shell takes a path without one as unreadable). Nothing is written, nothing run as root.
#
# The test seams (scripts/seams.sh: constants; a test tree has the test bed's in its place):
# the two PAM directories and faillock.conf's place.
source "$(dirname "$(readlink -f "$0")")/seams.sh" || { echo "pam-files: cannot read seams.sh" >&2; exit 1; }
set -u
export LC_ALL=C

max_bytes=65536

[ -z "$seam_system_pam_dir" ] || printf 'directory\t%s\n' "$seam_system_pam_dir"
[ -z "$seam_vendor_pam_dir" ] || printf 'directory\t%s\n' "$seam_vendor_pam_dir"
[ -z "$seam_faillock_conf" ] || printf 'faillock\t%s\n' "$seam_faillock_conf"

# absent <path>: the path is known not to be there
absent() {
    local probe=$1
    [ -L "$probe" ] && return 1
    while [ "$probe" != / ]; do
        probe=$(dirname "$probe")
        if [ -e "$probe" ]; then
            [ ! -d "$probe" ] && return 0
            [ -x "$probe" ]
            return
        fi
    done
    return 1
}

record() {
    local path=$1 text
    if [ ! -e "$path" ]; then
        if absent "$path"; then
            printf 'file\t%s\tabsent\n' "$path"
        else
            printf 'file\t%s\tunreadable\n' "$path"
        fi
        return
    fi
    if [ ! -f "$path" ] || [ ! -r "$path" ]; then
        printf 'file\t%s\tunreadable\n' "$path"
        return
    fi
    # The "x" keeps the final line breaks; no "x" means head failed
    text=$(head -c $((max_bytes + 1)) -- "$path" 2> /dev/null && printf x)
    if [ "${text: -1}" != x ] || [ $((${#text} - 1)) -gt "$max_bytes" ]; then
        printf 'file\t%s\tunreadable\n' "$path"
        return
    fi
    text=${text%x}
    printf 'file\t%s\ttext\n' "$path"
    printf '%s' "$text" | while IFS= read -r line || [ -n "$line" ]; do
        printf '|%s\n' "$line"
    done
    printf 'end\t%s\n' "$path"
}

for path in "$@"; do
    case "$path" in
        /*) ;;
        *) continue ;;
    esac
    case "$path" in
        *$'\t'* | *$'\n'*) continue ;;
    esac
    record "$path"
done
exit 0
