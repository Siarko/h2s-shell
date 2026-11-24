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
#   sha256 TAB <path> TAB <hex>       the sha256 of exactly the bytes read and shown
#   file TAB <path> TAB absent | unreadable   as pam-files.sh's (larger than 64 KiB: unreadable)
#   real TAB <path> TAB <real path> | unknown the path with every link resolved (unknown also
#                                     when it holds a tab or a line break)
#   uid TAB <n>                       this user's id (the path is not read)
#   chain TAB <path> TAB <part> TAB <uid> TAB <mode>
#                                     each folder of the real path from / down to it, its
#                                     owner and octal mode (stat); <uid> "unknown" when it
#                                     cannot be read
#                                     — first those of each folder that holds a link met
#                                     on the way (whoever may write one may point the path
#                                     elsewhere), the real path's own last — then
#   chainend TAB <path> TAB ok | unknown      unknown: the real path could not be found, holds
#                                     a tab or a line break, or takes more than 40 links
#   gitdir <path>                     as real and chain, for a .git's own place: the folder,
#                                     or the folder a .git file names (gitdir: …)
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
    local path=$1 text sum
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
    # Hashed from the text read, so that it names exactly what is shown (a second read
    # could see the file changed between the two)
    sum=$(printf '%s' "$text" | sha256sum) || sum=
    printf 'file\t%s\ttext\n' "$path"
    printf '%s' "$text" | while IFS= read -r line || [ -n "$line" ]; do
        printf '|%s\n' "$line"
    done
    printf 'end\t%s\n' "$path"
    [ -z "$sum" ] || printf 'sha256\t%s\t%s\n' "$path" "${sum%% *}"
}

# resolve <path>: the real path on stdout; fails when it cannot be found or would not stay
# one field of one record
resolve() {
    local resolved
    resolved=$(readlink -e -- "$1" 2> /dev/null) && [ -n "$resolved" ] || return 1
    case "$resolved" in
        *$'\t'* | *$'\n'*) return 1 ;;
    esac
    printf '%s' "$resolved"
}

real() {
    local path=$1 resolved
    if resolved=$(resolve "$path"); then
        printf 'real\t%s\t%s\n' "$path" "$resolved"
    else
        printf 'real\t%s\tunknown\n' "$path"
    fi
}

# parts <key> <real path>: a chain record for each folder of the path, / down to it
parts() {
    local key=$1 part=/ rest=${2#/} owner
    while :; do
        if owner=$(stat -c '%u %a' -- "$part" 2> /dev/null); then
            printf 'chain\t%s\t%s\t%s\t%s\n' "$key" "$part" "${owner% *}" "${owner#* }"
        else
            printf 'chain\t%s\t%s\tunknown\tunknown\n' "$key" "$part"
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
}

# walk <path>: resolves the path one part at a time, following at most 40 links; sets
# walk_final (the real path) and walk_holders (the real folders that hold a link passed on
# the way: whoever may write one of them may point the path elsewhere). Fails when a part is
# missing, a link cannot be read or there are too many.
walk() {
    local rest=${1#/} prefix= part target hops=0
    walk_holders=()
    while [ -n "$rest" ]; do
        part=${rest%%/*}
        case "$rest" in
            */*) rest=${rest#*/} ;;
            *) rest= ;;
        esac
        case "$part" in
            "" | .) continue ;;
            ..) prefix=${prefix%/*}; continue ;;
        esac
        if [ -L "$prefix/$part" ]; then
            hops=$((hops + 1))
            [ "$hops" -le 40 ] || return 1
            target=$(readlink -- "$prefix/$part") && [ -n "$target" ] || return 1
            walk_holders+=("${prefix:-/}")
            case "$target" in
                /*) prefix=; rest=${target#/}${rest:+/$rest} ;;
                *) rest=$target${rest:+/$rest} ;;
            esac
        elif [ -e "$prefix/$part" ]; then
            prefix=$prefix/$part
        else
            return 1
        fi
    done
    walk_final=${prefix:-/}
}

# chain_of <key> <path>: the chains of every folder holding a link on the way, then the real
# path's own, all under <key>; the real path's last, so its last part is the real path
chain_of() {
    local key=$1 path=$2 resolved holder
    if ! resolved=$(resolve "$path") || ! walk "$path" || [ "$walk_final" != "$resolved" ]; then
        printf 'chainend\t%s\tunknown\n' "$key"
        return
    fi
    for holder in "${walk_holders[@]}"; do
        case "$holder" in
            *$'\t'* | *$'\n'*) printf 'chainend\t%s\tunknown\n' "$key"; return ;;
        esac
    done
    for holder in "${walk_holders[@]}"; do
        parts "$key" "$holder"
    done
    parts "$key" "$resolved"
    printf 'chainend\t%s\tok\n' "$key"
}

chain() {
    chain_of "$1" "$1"
}

# gitdir <path>: a .git's own place — the folder itself, or the folder a .git file names
# ("gitdir: <path>", relative to the file's folder) — its real path and chain under <path>
gitdir() {
    local path=$1 line target resolved
    target=$path
    if [ -f "$path" ]; then
        IFS= read -r line < "$path" 2> /dev/null || line=
        case "$line" in
            "gitdir: "/*) target=${line#gitdir: } ;;
            "gitdir: "?*) target=$(dirname "$path")/${line#gitdir: } ;;
            *) printf 'real\t%s\tunknown\n' "$path"; printf 'chainend\t%s\tunknown\n' "$path"; return ;;
        esac
    fi
    if resolved=$(resolve "$target"); then
        printf 'real\t%s\t%s\n' "$path" "$resolved"
    else
        printf 'real\t%s\tunknown\n' "$path"
    fi
    chain_of "$path" "$target"
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
        exists | file | real | chain | gitdir | list | link) "$op" "$path" ;;
        uid) printf 'uid\t%s\n' "$(id -u)" ;;
    esac
done
exit 0
