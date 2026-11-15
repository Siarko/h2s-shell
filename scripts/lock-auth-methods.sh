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
#
# H2S_LOCK_AUTH_METHODS, when set, names an executable that answers instead of this
# script, in the same format. The lock test bed (tests/lock/) uses it to run the real
# shell against PAM stacks of its own rather than the system's. It lives here, in the
# detection step, so that it holds whatever QML asks the question. It grants nothing:
# whoever can set the shell's environment can already run anything as the user.
if [ -n "${H2S_LOCK_AUTH_METHODS:-}" ]; then
    exec "$H2S_LOCK_AUTH_METHODS"
fi

shell_dir=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
# H2S_LOCK_SYSTEM_PAM_DIR: the test bed's seam for where system-wide configs are looked
# for (the shell's password fallback honours it too, singletons/Lockscreen.qml)
system_dir=${H2S_LOCK_SYSTEM_PAM_DIR:-/etc/pam.d}

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
