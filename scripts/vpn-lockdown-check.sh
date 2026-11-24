#!/usr/bin/env bash
# What VpnLockdown needs to know before it runs the installed blocking script by itself
# (singletons/network/VpnLockdown.qml), read only, as the user:
#
#   vpn-lockdown-check.sh <owner uid> <shell's script> <installed script> <rule folder> <user> [<nft> ...]
#
#   script <version>     the version of the shell's own copy (scripts/h2s-vpn-lockdown)
#   installed <version>  the installed script is a regular executable file that the owner
#                        (root: 0; a suite's stand-in: the user) owns and nobody else may
#                        change, in a folder the same holds for — the only one VpnLockdown
#                        runs, through pkexec
#   unsafe <version>     a script is there, but not so: never run
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

echo "script $(version "$script")"
if [ -n "$installed" ] && [ -e "$installed" ]; then
    if [ -f "$installed" ] && [ -x "$installed" ] && held "$installed" && held "$(dirname -- "$(readlink -f -- "$installed")")"; then
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
