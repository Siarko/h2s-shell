# shellcheck shell=bash
# Where NixOS keeps what the shell's code reads there. Read only.
check "/etc/NIXOS is there (how the shell tells NixOS)" test -e /etc/NIXOS
check "/etc/pam.d/login can be read (the lock's password config without the module's)" test -r /etc/pam.d/login
check "/run/current-system/sw/bin is a directory (where a module's commands are)" test -d /run/current-system/sw/bin
check "/etc/static/polkit-1/rules.d is a directory (where the module's polkit rules are)" test -d /etc/static/polkit-1/rules.d
