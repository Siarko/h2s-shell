#!/usr/bin/env bash
# What VpnLockdown needs to know before it runs the installed blocking script by itself
# (singletons/network/VpnLockdown.qml), read only, as the user:
#
#   vpn-lockdown-check.sh <owner uid> <shell's script> <installed script> <rule folder> <user> [<nft> ...]
#
#   script <version>     the version of the shell's own copy (scripts/h2s-vpn-lockdown)
#   installed <version>  the installed script is a regular executable file that the owner
#                        (root: 0; a suite's stand-in: the user) owns and nobody else may
#                        change, and every folder above it — as given and with its links
#                        followed — is root's or the owner's and nobody else may change it
#                        (a sticky folder of theirs counts: nobody else may replace what is
#                        in it, such as NixOS's store) — the only one VpnLockdown runs,
#                        through pkexec
#   unsafe <version>     a script is there, but not so: never run
#   folder               a folder at the script's place (an older install's layout): never run
#   rule yes             a polkit rule file in the rule folder names the installed script and
#                        the user
#   nft                  one of the nft places is an executable
#
# Links are followed (NixOS's profile links into its store). Nothing is written, nothing run
# as root.
set -u
export LC_ALL=C
[ $# -ge 5 ] || { echo "vpn-lockdown-check: <owner uid> <script> <installed> <rule folder> <user> [<nft> ...]" >&2; exit 2; }
owner=$1 script=$2 installed=$3 rules=$4 user=$5
shift 5

version() { sed -n 's/^VERSION=\([0-9]*\).*/\1/p' "$1" 2> /dev/null | head -n1; }

# Owned by the owner, writable by nobody else
held() {
    local facts
    facts=$(stat -L -c '%u %a' -- "$1" 2> /dev/null) || return 1
    [ "${facts%% *}" = "$owner" ] || return 1
    [ $((0${facts#* } & 022)) -eq 0 ]
}

# A folder root or the owner holds: nobody else may change it, or only in a sticky folder
held_folder() {
    local facts mode
    facts=$(stat -L -c '%u %a' -- "$1" 2> /dev/null) || return 1
    [ "${facts%% *}" = "$owner" ] || [ "${facts%% *}" = 0 ] || return 1
    mode=$((0${facts#* }))
    [ $((mode & 022)) -eq 0 ] || [ $((mode & 01000)) -ne 0 ]
}

# Every folder above a path held
ancestors_held() {
    local path=$1
    while [ "$path" != / ] && [ -n "$path" ]; do
        path=$(dirname -- "$path")
        held_folder "$path" || return 1
    done
}

echo "script $(version "$script")"
if [ -n "$installed" ] && [ -d "$installed" ]; then
    echo "folder"
elif [ -n "$installed" ] && [ -e "$installed" ]; then
    resolved=$(readlink -f -- "$installed") || resolved=
    if [ -n "$resolved" ] && [ -f "$installed" ] && [ -x "$installed" ] && held "$installed" \
        && ancestors_held "$installed" && ancestors_held "$resolved"; then
        echo "installed $(version "$installed")"
    else
        echo "unsafe $(version "$installed")"
    fi
fi
if [ -n "$installed" ] && [ -n "$rules" ]; then
    for file in "$rules"/*.rules; do
        if grep -qsF -- "\"$installed\"" "$file" && grep -qsF -- "subject.user == \"$user\"" "$file"; then
            echo "rule yes"
            break
        fi
    done
fi
for place in "$@"; do
    if [ -x "$place" ]; then
        echo "nft"
        break
    fi
done
exit 0
