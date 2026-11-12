#!/usr/bin/env bash
# Installs h2s-shell on Arch Linux: the packages it needs (pacman asks before installing),
# then a git checkout where Quickshell looks for its default config. Changes nothing
# else: the services and Hyprland's autostart are printed at the end, for you to add.
#
#   curl -fsSL https://raw.githubusercontent.com/Siarko/h2s-shell/master/install.sh | bash
#
# or, from a checkout: ./install.sh
#
# On NixOS use the flake instead (see the README).

set -euo pipefail

repository="https://github.com/Siarko/h2s-shell"
target="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/default"

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
    if git -C "$target" remote get-url origin 2> /dev/null | grep -q "Siarko/h2s-shell"; then
        echo "Already installed; update it with: git -C \"$target\" pull"
    else
        echo "$target already holds another Quickshell config; leaving it alone." >&2
        echo "Move it away and run this again." >&2
        exit 1
    fi
else
    mkdir -p "$(dirname "$target")"
    git clone "$repository" "$target"
fi

cat << EOF

==> Done. Left for you:

1. The services the widgets read, if they are not running yet:

     sudo systemctl enable --now NetworkManager bluetooth power-profiles-daemon

2. Start the shell with Hyprland. In hyprland.lua, inside hl.on("hyprland.start", ...):

     hl.exec_cmd("$target/scripts/launch.sh")

   Or start it now, from a terminal in Hyprland:

     $target/scripts/launch.sh -d
EOF
