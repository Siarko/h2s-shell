#!/usr/bin/env bash
# Installs h2s-shell: runs the installer of this system's distribution,
# distributions/<id>/install.sh. Only Arch Linux, and systems based on it, has one; on NixOS
# the shell comes with its flake's NixOS module, and on other systems it is set up by hand
# (the README says what it needs). This script says so and changes nothing there.
#
#   curl -fsSL https://raw.githubusercontent.com/Siarko/h2s-shell/master/install.sh | bash
#
# or, from a checkout: ./install.sh [--update] (the arguments are the installer's; Arch's
# says what they do). From a checkout it runs the installer beside it; given to bash on its
# standard input, as curl … | bash does, it fetches that installer from the repository
# first, into a temporary file it removes when done.
#
# Which system: os-release's ID, then each word of its ID_LIKE ("arch": Arch, EndeavourOS,
# and others based on it), read as text, never run.

set -euo pipefail

repository="https://github.com/Siarko/h2s-shell"
raw="https://raw.githubusercontent.com/Siarko/h2s-shell/master"
# The folder os-release is looked for under: "" for the system's (tests/install-test.sh
# runs a copy that names a made-up tree)
os_release_root=""

# os_release_word <text>: the value as os-release writes it, its quotes dropped
os_release_word() {
    local value=$1
    value=${value#[\"\']}
    value=${value%[\"\']}
    printf '%s' "$value"
}

# Sets system ("arch", "nixos", or "" for any other or one that cannot be told) and name
# (os-release's PRETTY_NAME, else its ID; "" when there is none)
detect_system() {
    local file line id="" like="" pretty="" word
    system=""
    name=""
    for file in "$os_release_root/etc/os-release" "$os_release_root/usr/lib/os-release"; do
        [ -e "$file" ] || continue
        [ -r "$file" ] || return 0
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
                ID=*) id=$(os_release_word "${line#ID=}") ;;
                ID_LIKE=*) like=$(os_release_word "${line#ID_LIKE=}") ;;
                PRETTY_NAME=*) pretty=$(os_release_word "${line#PRETTY_NAME=}") ;;
            esac
        done < "$file"
        break
    done
    name=${pretty:-$id}
    case "$id" in
        arch) system=arch; return 0 ;;
        nixos) system=nixos; return 0 ;;
    esac
    for word in $like; do
        if [ "$word" = arch ]; then
            system=arch
            return 0
        fi
    done
}

main() {
    detect_system
    case "$system" in
        arch) ;;
        nixos)
            echo "This installer is not for NixOS: there the shell comes with its flake's NixOS module (programs.h2s-shell.enable). See the README: $repository" >&2
            exit 1
            ;;
        *)
            echo "This installer supports only Arch Linux and systems based on it, not ${name:-this system}." >&2
            echo "The README says what the shell needs, to set it up by hand: $repository" >&2
            exit 1
            ;;
    esac

    # From a checkout: the installer beside this file
    local source=${BASH_SOURCE[0]:-} here=""
    if [ -n "$source" ]; then
        here=.
        [[ "$source" == */* ]] && here=${source%/*}
    fi
    if [ -n "$here" ] && [ -f "$here/distributions/arch/install.sh" ]; then
        bash "$here/distributions/arch/install.sh" "$@" < /dev/null
        return
    fi

    # Given on standard input: the installer fetched from the repository first
    if ! command -v curl > /dev/null; then
        echo "Fetching the Arch installer needs curl, and there is none. Run install.sh from a checkout instead: $repository" >&2
        exit 1
    fi
    fetched=$(mktemp)
    trap 'rm -f "$fetched"' EXIT
    curl -fsSL --proto '=https' -o "$fetched" "$raw/distributions/arch/install.sh"
    bash "$fetched" "$@" < /dev/null
}

# Everything runs from here, once the whole file is read: given to bash on its standard
# input, a cut-off download runs nothing
main "$@"
