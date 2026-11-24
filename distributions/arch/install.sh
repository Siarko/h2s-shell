#!/usr/bin/env bash
# Installs h2s-shell on Arch Linux: the packages it needs (pacman asks before installing),
# then a git checkout where Quickshell looks for its default config. Changes nothing
# else: the services and Hyprland's autostart are printed at the end, for you to add.
#
# Run by the checkout's top-level install.sh on Arch (and systems based on it), which is
# what the README names:
#
#   curl -fsSL https://raw.githubusercontent.com/Siarko/h2s-shell/master/install.sh | bash
#
# or, from a checkout: ./install.sh. This file does not depend on where it is: everything
# it reads or runs is in the target checkout.
#
# After `git pull` in the checkout, `install.sh --update` copies its built-in modules again
# and builds the helper again (no packages, no sudo).
#
# The built-in modules (the checkout's builtin-modules/) are copied to
# ~/.local/share/h2s-shell/builtin, where scripts/launch.sh finds them: a directory the
# shell's install and update write, replaced as a whole each time, never by hand or by
# Settings. Outside the checkout: the built-in root is found from the shell's installation,
# the same place on every Arch install.
#
# The helper (the checkout's helper/, a small C++/Qt program for what the shell cannot do
# from QML) is built by scripts/build-helper.sh, as you, into ~/.cache/h2s-shell/helper —
# with cmake, a C++ compiler (base-devel) and Qt 6's development files (qt6-base). The
# shell's launcher rebuilds it in the background when an update changed its source; a
# build that fails leaves the shell running without it.
#
# On NixOS use the flake instead (see the README).

set -euo pipefail

# The top-level install.sh's hand-over this installer understands (its dispatch_version):
# one fetched from the repository may be newer or older than the script that fetched it.
# Run directly, without the top-level script, nothing is handed over.
dispatch_known=1
# pacman's settings: with pacman itself, what tells an Arch-based system from one that has
# another program of that name (tests/install-test.sh runs a copy naming a made-up file)
pacman_conf=/etc/pacman.conf
if [ -n "${H2S_INSTALL_DISPATCH:-}" ] && [ "$H2S_INSTALL_DISPATCH" != "$dispatch_known" ]; then
    echo "This Arch installer does not match the install.sh that ran it (hand-over $H2S_INSTALL_DISPATCH, it knows $dispatch_known). Fetch install.sh again and run that." >&2
    exit 1
fi

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
    cmake base-devel qt6-base # the helper: cmake, a C++ compiler, Qt's headers
    ttf-jetbrains-mono-nerd
)

# Where the checkout in $target comes from (empty when git cannot say)
origin() { git -C "$target" remote get-url origin 2> /dev/null || true; }

# address_of <url>: "<host>/<path>", lowercased (GitHub's names ignore case), from an address
# as git keeps it — with a scheme (http, https, ssh, git) or in scp's form (user@host:path) —
# without the user, password, port, a leading www., a trailing / or .git; nothing (status 1)
# for a local path
address_of() {
    local url=${1,,} rest host path
    case $url in
        http://* | https://* | ssh://* | git://*)
            rest=${url#*://}
            host=${rest%%/*}
            path=${rest#"$host"}
            host=${host##*@}
            host=${host%%:*}
            ;;
        *:*)
            host=${url%%:*}
            path=${url#*:}
            case $host in */*) return 1 ;; esac
            host=${host##*@}
            ;;
        *) return 1 ;;
    esac
    path=${path#/}
    path=${path%/}
    path=${path%.git}
    printf '%s/%s\n' "${host#www.}" "$path"
}

# ours <origin>: this repository, however git spells its address; nothing else, so a fork, or
# another repository whose address merely contains this one's name, is somebody else's config,
# left alone. A host alias of the user's SSH config is not followed: it could name any server.
ours() {
    [ "$(address_of "$1")" = github.com/siarko/h2s-shell ]
}

# shown <url>: the address without a user and password, which may hold a token
shown() {
    local url=$1 rest authority
    case $url in
        *://*)
            rest=${url#*://}
            authority=${rest%%/*}
            printf '%s://%s%s\n' "${url%%://*}" "${authority##*@}" "${rest#"$authority"}"
            ;;
        *) printf '%s\n' "${url#*@}" ;;
    esac
}

# Somebody else's config in $target: said, and the script ends
leave_other() {
    local address
    echo "$target already holds another Quickshell config; leaving it alone." >&2
    if [ -n "$1" ]; then
        echo "It comes from $(shown "$1"), not from $repository." >&2
        address=$(address_of "$1") || address=""
        if [ "${address#*/}" = siarko/h2s-shell ]; then
            echo "If it is this repository under another name for GitHub (a host of your SSH config), give it GitHub's own address and run this again:" >&2
            echo "  git -C \"$target\" remote set-url origin git@github.com:Siarko/h2s-shell.git" >&2
            exit 1
        fi
    fi
    echo "Move it away and run this again." >&2
    exit 1
}

# What is in $target, checked before anything is installed: somebody else's config, a file, a
# folder that cannot be read or that holds something else is left alone (git clones only into
# an empty folder or none)
check_target() {
    local from has_entries
    if [ -L "$target/shell.qml" ] && [ ! -e "$target/shell.qml" ]; then
        echo "$target/shell.qml is a link that leads nowhere; leaving $target alone. Move it away and run this again." >&2
        exit 1
    elif [ -e "$target/shell.qml" ]; then
        from=$(origin)
        ours "$from" || leave_other "$from"
    elif { [ -e "$target" ] || [ -L "$target" ]; } && [ ! -d "$target" ]; then
        echo "$target is not a folder; leaving it alone. Move it away and run this again." >&2
        exit 1
    elif [ -d "$target" ] && { [ ! -r "$target" ] || [ ! -x "$target" ]; }; then
        echo "$target cannot be read; leaving it alone. Move it away and run this again." >&2
        exit 1
    elif [ -d "$target" ]; then
        has_entries=$(shopt -s nullglob dotglob; for entry in "$target"/*; do echo yes; break; done)
        if [ -n "$has_entries" ]; then
            echo "$target holds no Quickshell config (no shell.qml), but it is not empty; leaving it alone." >&2
            echo "Move it away, or empty it, and run this again." >&2
            exit 1
        fi
    fi
}

# pacman or sudo failed, or the answer was no
packages_failed() {
    echo "The packages were not installed (above); nothing else was done." >&2
    exit 1
}

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

# The helper, built from the checkout as this user (never through sudo). A failed build is
# not the install's failure: the shell runs without the helper, and says so.
build_helper() {
    echo "==> The helper"
    if [ ! -f "$target/scripts/build-helper.sh" ]; then
        echo "This checkout has no helper to build."
        return 0
    fi
    if ! bash "$target/scripts/build-helper.sh" > /dev/null; then
        echo "Warning: the helper did not build (above); the shell runs without it." >&2
        echo "Build it again with: $target/scripts/build-helper.sh" >&2
    fi
}

if [ $# -gt 1 ] || { [ $# = 1 ] && [ "$1" != --update ]; }; then
    echo "usage: install.sh [--update]" >&2
    exit 2
fi

if [ "${1:-}" = --update ]; then
    if [ ! -e "$target/shell.qml" ]; then
        echo "h2s-shell is not installed in $target; run this without --update first." >&2
        exit 1
    fi
    from=$(origin)
    ours "$from" || leave_other "$from"
    copy_builtin
    build_helper
    echo "==> Done. Restart the shell to load the built-in modules and the helper again: $target/scripts/launch.sh --restart"
    exit 0
fi

if ! command -v pacman > /dev/null || [ ! -e "$pacman_conf" ]; then
    echo "This script is for Arch Linux (pacman). On NixOS use the flake: see $repository" >&2
    exit 1
fi

check_target

# What the packages step needs, checked first so that the script, not bash, says what is
# missing (as root pacman runs as it is, without sudo)
if [ "$EUID" != 0 ] && ! command -v sudo > /dev/null; then
    echo "Installing the packages needs sudo (the package sudo), to run pacman as root, and there is none." >&2
    echo "Install it as root, or install the packages listed in this script by hand, then run this again." >&2
    exit 1
fi
if ! { : < /dev/tty; } 2> /dev/null; then
    echo "Installing the packages needs a terminal, for pacman's questions and sudo's password, and there is none." >&2
    echo "Run this from a terminal." >&2
    exit 1
fi

echo "==> Packages"
# From the terminal, not stdin: run as `curl ... | bash`, stdin is this script, and
# pacman's question would read its next lines as the answer
if [ "$EUID" = 0 ]; then
    pacman -S --needed "${packages[@]}" < /dev/tty || packages_failed
else
    sudo pacman -S --needed "${packages[@]}" < /dev/tty || packages_failed
fi

# The icons are Nerd Font glyphs: say so now rather than leave empty boxes to puzzle over
# (the list read whole, not piped into grep -q: grep ends at the first match, and under
# pipefail the fc-list still writing then would fail the test and warn wrongly). Without
# fc-list, or when it fails, nothing is said: it cannot tell.
if command -v fc-list > /dev/null && fonts=$(fc-list : family 2> /dev/null) && [[ "$fonts" != *"Nerd Font"* ]]; then
    echo "Warning: no Nerd Font found (fc-list); the shell's icons would show as empty boxes." >&2
    echo "Install one: sudo pacman -S ttf-jetbrains-mono-nerd" >&2
fi

echo "==> The shell, in $target"
if [ -e "$target/shell.qml" ]; then
    echo "Already installed; update it with: git -C \"$target\" pull && \"$target/install.sh\" --update"
else
    mkdir -p "$(dirname "$target")"
    git clone "$repository" "$target"
fi

copy_builtin
build_helper

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
