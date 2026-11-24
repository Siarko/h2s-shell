#!/usr/bin/env bash
# The system's NixOS configuration as distributions/nixos/NixosConfiguration.qml reads it
# (NixosConfigRules.readArgs asks, NixosConfigRules.records reads the answer), read only, as
# the user:
#
#   nixos-config.sh [<op> <absolute path>] ...
#
# One or more records per pair asked, in order:
#
#   exists TAB <path> TAB present     there (links followed) and readable (a folder: listable)
#   exists TAB <path> TAB unreadable  there, but not readable by this user
#   exists TAB <path> TAB absent      known not to be there (as pam-files.sh tells it)
#   exists TAB <path> TAB unknown     cannot be told (a parent that cannot be searched, a link
#                                     that leads nowhere)
#   file TAB <path> TAB text          the file's lines follow, each after a "|", then
#   end TAB <path>
#   file TAB <path> TAB absent | unreadable   as pam-files.sh's (larger than 64 KiB: unreadable)
#   sha256 TAB <path> TAB <hex> | unknown     a regular readable file's sha256
#   real TAB <path> TAB <real path> | unknown the path with every link resolved
#   chain TAB <path> TAB <part> TAB <uid> TAB <mode>
#                                     each folder of the real path from / down to it, its
#                                     owner and octal mode (stat); <uid> "unknown" when it
#                                     cannot be read, then
#   chainend TAB <path> TAB ok | unknown      unknown: the real path could not be found
#   list TAB <folder> TAB <name>      each entry of the folder (names with a tab or a line
#                                     break left out), then
#   listend TAB <folder> TAB ok | unreadable
#   link TAB <path> TAB <target> | unknown    one link's target (readlink)
#
# A pair whose op is not one of these, or whose path is not absolute or holds a tab or a line
# break, gets no record (the shell takes a path without its record as unknown). Nothing is
# written, nothing is run as root.
set -u
export LC_ALL=C

max_bytes=65536

# absent <path>: the path is known not to be there (pam-files.sh's)
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

exists() {
    local path=$1
    if [ -e "$path" ]; then
        if [ -d "$path" ]; then
            if [ -r "$path" ] && [ -x "$path" ]; then
                printf 'exists\t%s\tpresent\n' "$path"
            else
                printf 'exists\t%s\tunreadable\n' "$path"
            fi
        elif [ -r "$path" ]; then
            printf 'exists\t%s\tpresent\n' "$path"
        else
            printf 'exists\t%s\tunreadable\n' "$path"
        fi
    elif absent "$path"; then
        printf 'exists\t%s\tabsent\n' "$path"
    else
        printf 'exists\t%s\tunknown\n' "$path"
    fi
}

file() {
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

sha256() {
    local path=$1 sum
    if [ -f "$path" ] && [ -r "$path" ] && sum=$(sha256sum -- "$path" 2> /dev/null); then
        printf 'sha256\t%s\t%s\n' "$path" "${sum%% *}"
    else
        printf 'sha256\t%s\tunknown\n' "$path"
    fi
}

real() {
    local path=$1 resolved
    if resolved=$(readlink -e -- "$path" 2> /dev/null) && [ -n "$resolved" ]; then
        printf 'real\t%s\t%s\n' "$path" "$resolved"
    else
        printf 'real\t%s\tunknown\n' "$path"
    fi
}

chain() {
    local path=$1 resolved part rest owner
    if ! resolved=$(readlink -e -- "$path" 2> /dev/null) || [ -z "$resolved" ]; then
        printf 'chainend\t%s\tunknown\n' "$path"
        return
    fi
    part=/
    rest=${resolved#/}
    while :; do
        if owner=$(stat -c '%u %a' -- "$part" 2> /dev/null); then
            printf 'chain\t%s\t%s\t%s\t%s\n' "$path" "$part" "${owner% *}" "${owner#* }"
        else
            printf 'chain\t%s\t%s\tunknown\tunknown\n' "$path" "$part"
        fi
        [ -z "$rest" ] && break
        if [ "$part" = / ]; then
            part=/${rest%%/*}
        else
            part=$part/${rest%%/*}
        fi
        case "$rest" in
            */*) rest=${rest#*/} ;;
            *) rest= ;;
        esac
    done
    printf 'chainend\t%s\tok\n' "$path"
}

list() {
    local folder=$1 entry name
    if [ ! -d "$folder" ] || [ ! -r "$folder" ] || [ ! -x "$folder" ]; then
        printf 'listend\t%s\tunreadable\n' "$folder"
        return
    fi
    shopt -s nullglob dotglob
    for entry in "$folder"/*; do
        name=${entry##*/}
        case "$name" in
            *$'\t'* | *$'\n'*) continue ;;
        esac
        printf 'list\t%s\t%s\n' "$folder" "$name"
    done
    shopt -u nullglob dotglob
    printf 'listend\t%s\tok\n' "$folder"
}

link() {
    local path=$1 target
    if target=$(readlink -- "$path" 2> /dev/null) && [ -n "$target" ]; then
        case "$target" in
            *$'\t'* | *$'\n'*) printf 'link\t%s\tunknown\n' "$path" ;;
            *) printf 'link\t%s\t%s\n' "$path" "$target" ;;
        esac
    else
        printf 'link\t%s\tunknown\n' "$path"
    fi
}

while [ $# -ge 2 ]; do
    op=$1 path=$2
    shift 2
    case "$path" in
        /*) ;;
        *) continue ;;
    esac
    case "$path" in
        *$'\t'* | *$'\n'*) continue ;;
    esac
    case "$op" in
        exists | file | sha256 | real | chain | list | link) "$op" "$path" ;;
    esac
done
exit 0
