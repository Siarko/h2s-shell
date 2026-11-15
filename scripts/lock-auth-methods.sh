#!/usr/bin/env bash
# The ways the lock screen can check who is there, one per line:
#
#   <method> TAB <PAM config directory> TAB <PAM config name>
#
# Each method is a PAM conversation of its own, so that a fingerprint reader waiting for
# a finger never holds up a typed password. A system-wide /etc/pam.d/h2s-shell-<method>
# wins (the NixOS module writes them; elsewhere the administrator may), else the config
# shipped in pam/ is used.
#
#   password     always
#   fingerprint  when fprintd has a finger enrolled for the user
#   u2f          when the system has a config for it, or the user has registered keys

shell_dir=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
system_dir=/etc/pam.d

method() {
    if [ -r "$system_dir/h2s-shell-$1" ]; then
        printf '%s\t%s\t%s\n' "$1" "$system_dir" "h2s-shell-$1"
    else
        printf '%s\t%s\t%s\n' "$1" "$shell_dir/pam" "$1"
    fi
}

# NixOS keeps PAM modules in the store, each package its own: the shipped configs, which
# name modules without a path, do not work there (pam_unix is found, but cannot reach
# its password helper). Its module writes the system-wide ones; without them the
# password goes through "login", which works but waits for a fingerprint reader first.
if [ -e /etc/NIXOS ] && [ ! -r "$system_dir/h2s-shell-password" ]; then
    printf 'password\t%s\tlogin\n' "$system_dir"
else
    method password
fi

if command -v fprintd-list > /dev/null \
    && fprintd-list "$(id -un)" 2> /dev/null | grep -q '^ *- #'; then
    method fingerprint
fi

if [ -r "$system_dir/h2s-shell-u2f" ] \
    || [ -s "${XDG_CONFIG_HOME:-$HOME/.config}/Yubico/u2f_keys" ]; then
    method u2f
fi
