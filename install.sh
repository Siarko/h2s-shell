#!/usr/bin/env bash
# Installs h2s-shell on Arch Linux: the packages it needs (pacman asks before installing),
# then a git checkout where Quickshell looks for its default config. Changes nothing
# else: the services and Hyprland's autostart are printed at the end, for you to add.
#
#   curl -fsSL https://raw.githubusercontent.com/Siarko/h2s-shell/master/install.sh | bash
#
# or, from a checkout: ./install.sh
#
# After `git pull` in the checkout, `install.sh --update` copies its built-in modules again
# (no packages, no sudo).
#
# The built-in modules (the checkout's builtin-modules/) are copied to
# ~/.local/share/h2s-shell/builtin, where scripts/launch.sh finds them: a directory the
# shell's install and update write, replaced as a whole each time, never by hand or by
# Settings. Outside the checkout: the built-in root is found from the shell's installation,
# the same place on every Arch install.
#
# On NixOS use the flake instead (see the README).

set -euo pipefail

repository="https://github.com/Siarko/h2s-shell"
target="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/default"
builtin_target="${XDG_DATA_HOME:-$HOME/.local/share}/h2s-shell/builtin"

packages=(
    quickshell
    hyprland
    networkmanager        # nmcli
    bluez bluez-utils     # bluetoothctl
    upower                # battery
    power-profiles-daemon # power profiles
    python                # Google sign-in helper, standard library only
    libnotify             # notify-send
    jq glib2              # icon theme: the setting, the system theme
    cava                  # audio visualiser
    git
    xdg-utils             # opens the browser for the Google sign-in
    libvips               # vipsthumbnail: wallpapers resized to the screen, kept in ~/.cache
    ttf-jetbrains-mono-nerd
)

ours() { git -C "$target" remote get-url origin 2> /dev/null | grep -q "Siarko/h2s-shell"; }

# The checkout's built-in modules into $builtin_target, replacing what was there: copied into
# a new directory beside it first (mktemp: only what this run made is ever deleted), so a copy
# that fails leaves the old one in place. Links are copied as links (a module whose file
# leads out of its directory is refused by the shell's own check).
copy_builtin() {
    local source="$target/builtin-modules"
    echo "==> Built-in modules, in $builtin_target"
    if [ ! -d "$source" ]; then
        echo "This checkout has no built-in modules; leaving $builtin_target as it is."
        return 0
    fi
    if [ -L "$builtin_target" ] || { [ -e "$builtin_target" ] && [ ! -d "$builtin_target" ]; }; then
        echo "$builtin_target is not a directory; leaving it alone. Move it away and run this again." >&2
        exit 1
    fi
    mkdir -p "$(dirname "$builtin_target")"
    local staging old=""
    staging=$(mktemp -d "$builtin_target.new.XXXXXX")
    cp -RP "$source/." "$staging" || { rm -rf "$staging"; exit 1; }
    if [ -d "$builtin_target" ]; then
        old=$(mktemp -d "$builtin_target.old.XXXXXX")
        mv "$builtin_target" "$old/builtin"
    fi
    mv "$staging" "$builtin_target"
    if [ -n "$old" ]; then
        rm -rf "$old"
    fi
}

if [ $# -gt 1 ] || { [ $# = 1 ] && [ "$1" != --update ]; }; then
    echo "usage: install.sh [--update]" >&2
    exit 2
fi

if [ "${1:-}" = --update ]; then
    if [ ! -e "$target/shell.qml" ] || ! ours; then
        echo "h2s-shell is not installed in $target; run this without --update first." >&2
        exit 1
    fi
    copy_builtin
    echo "==> Done. Restart the shell to load the built-in modules again: $target/scripts/launch.sh --restart"
    exit 0
fi

if ! command -v pacman > /dev/null; then
    echo "This script is for Arch Linux (pacman). On NixOS use the flake: see $repository" >&2
    exit 1
fi

echo "==> Packages"
# From the terminal, not stdin: run as `curl ... | bash`, stdin is this script, and
# pacman's question would read its next lines as the answer
sudo pacman -S --needed "${packages[@]}" < /dev/tty

# The icons are Nerd Font glyphs: say so now rather than leave empty boxes to puzzle over
if command -v fc-list > /dev/null && ! fc-list : family | grep -q "Nerd Font"; then
    echo "Warning: no Nerd Font found (fc-list); the shell's icons would show as empty boxes." >&2
    echo "Install one: sudo pacman -S ttf-jetbrains-mono-nerd" >&2
fi

echo "==> The shell, in $target"
if [ -e "$target/shell.qml" ]; then
    if ours; then
        echo "Already installed; update it with: git -C \"$target\" pull && \"$target/install.sh\" --update"
    else
        echo "$target already holds another Quickshell config; leaving it alone." >&2
        echo "Move it away and run this again." >&2
        exit 1
    fi
else
    mkdir -p "$(dirname "$target")"
    git clone "$repository" "$target"
fi

copy_builtin

cat << EOF

==> Done. Left for you:

1. The services the widgets read, if they are not running yet:

     sudo systemctl enable --now NetworkManager bluetooth power-profiles-daemon

2. Start the shell with Hyprland. In hyprland.lua, inside hl.on("hyprland.start", ...):

     hl.exec_cmd("$target/scripts/launch.sh")

   Or start it now, from a terminal in Hyprland, detached and supervised as the
   autostart runs it (a shell that dies is started again, and locks again if the screen
   was locked):

     $target/scripts/launch.sh --restart

   (Not \`launch.sh -d\`: that runs the shell on its own, and nothing would start it
   again after a crash while the screen is locked.)

3. Optional, for the lock screen (the password works as it is):

     fingerprint:   sudo pacman -S fprintd && fprintd-enroll
     security key:  sudo pacman -S pam-u2f && mkdir -p ~/.config/Yubico
                    the first key:   pamu2fcfg > ~/.config/Yubico/u2f_keys
                    another key:     pamu2fcfg -n >> ~/.config/Yubico/u2f_keys
                    (">" replaces the file: on a file with keys it throws them away)

   Accounts not kept in /etc/shadow (systemd-homed, LDAP) need a
   /etc/pam.d/h2s-shell-password — not simply "auth include system-auth", which
   usually brings pam_faillock (wrong passwords at the lock count toward a lockout)
   and often pam_fprintd: see "Lock screen" in the README.
EOF
