#!/usr/bin/env bash
# NetworkManager's configuration files in the order it reads them, read only, as the user
# (the connectivity check address's reading: IntegrationRules.inForceCommand,
# ConnectivityRules.setting):
#
#   nm-config-files.sh [<base>]
#
# The files under <base> (none: the system's own; a suite: a scratch folder), named by their
# place on the system:
#   /usr/lib/NetworkManager/conf.d/*.conf, /run/NetworkManager/conf.d/*.conf,
#   /etc/NetworkManager/NetworkManager.conf, /etc/NetworkManager/conf.d/*.conf
# each folder by name (C locale), names starting with "." skipped, a name in a later folder
# hiding the same name in an earlier one (NetworkManager.conf(5)). One record per file:
#
#   file TAB <path> TAB text        its lines follow, each after a "|", then
#   end TAB <path>
#   file TAB <path> TAB unreadable  not a regular file, not readable, or over 64 KiB
#   unknown TAB <why>               a folder that cannot be listed, a name it cannot print
#   done                            last: the listing is whole
#
# Nothing is written, nothing run as root.
set -u
export LC_ALL=C
shopt -s nullglob

base=${1:-}
max_bytes=65536

record() {
    local place=$1 path=$base$1 text
    if [ ! -f "$path" ] || [ ! -r "$path" ]; then
        printf 'file\t%s\tunreadable\n' "$place"
        return
    fi
    # The "x" keeps the final line breaks; no "x" means head failed
    text=$(head -c $((max_bytes + 1)) -- "$path" 2> /dev/null && printf x)
    if [ "${text: -1}" != x ] || [ $((${#text} - 1)) -gt "$max_bytes" ]; then
        printf 'file\t%s\tunreadable\n' "$place"
        return
    fi
    text=${text%x}
    printf 'file\t%s\ttext\n' "$place"
    printf '%s' "$text" | while IFS= read -r line || [ -n "$line" ]; do
        printf '|%s\n' "$line"
    done
    printf 'end\t%s\n' "$place"
}

# names <folder>: the .conf names NetworkManager takes from a folder (its place on the
# system), one per line, sorted; a folder there but not listable is a problem
names() {
    local folder=$base$1 entry name
    [ -e "$folder" ] || return 0
    if [ ! -d "$folder" ] || [ ! -r "$folder" ] || [ ! -x "$folder" ]; then
        printf 'unknown\t%s cannot be listed\n' "$1"
        return 0
    fi
    for entry in "$folder"/*.conf; do
        name=${entry##*/}
        case "$name" in
            *$'\t'* | *$'\n'*) printf 'unknown\ta name in %s cannot be printed\n' "$1"; continue ;;
        esac
        printf 'name\t%s\n' "$name"
    done
}

lib=/usr/lib/NetworkManager/conf.d
run=/run/NetworkManager/conf.d
etc=/etc/NetworkManager/conf.d
lib_names=$(names "$lib")
run_names=$(names "$run")
etc_names=$(names "$etc")
# The problems first: the shell takes the whole reading as unknown then
printf '%s\n' "$lib_names" "$run_names" "$etc_names" | grep '^unknown' || true

# has <names> <name>
has() {
    printf '%s\n' "$1" | grep -qxF "name	$2"
}

while IFS=$'\t' read -r kind name; do
    [ "$kind" = name ] || continue
    has "$run_names" "$name" || has "$etc_names" "$name" || record "$lib/$name"
done <<< "$lib_names"
while IFS=$'\t' read -r kind name; do
    [ "$kind" = name ] || continue
    has "$etc_names" "$name" || record "$run/$name"
done <<< "$run_names"
main=/etc/NetworkManager/NetworkManager.conf
if [ -e "$base$main" ] || [ -L "$base$main" ]; then
    record "$main"
fi
while IFS=$'\t' read -r kind name; do
    [ "$kind" = name ] || continue
    record "$etc/$name"
done <<< "$etc_names"
echo done
