#!/usr/bin/env bash
# Installs h2s-shell: runs the installer of this system's distribution,
# distributions/<id>/install.sh. Only Arch Linux, and systems based on it, has one; on NixOS
# the shell comes with its flake's NixOS module, and on other systems it is set up by hand
# (the README says what it needs). This script says so and changes nothing there.
#
#   curl -fsSL https://raw.githubusercontent.com/Siarko/h2s-shell/master/install.sh | bash
#
# or, from a checkout: ./install.sh [--update] (the arguments are the installer's; Arch's
# says what they do). From a checkout it runs the installer beside it — `--update` (the
# built-in modules copied again, the helper rebuilt; no packages, no sudo) on any system;
# given to bash on its standard input, as curl … | bash does, it fetches that installer from
# the repository's master branch first, into a temporary file it removes when done. That
# installer may be newer than this script: it is told the version of the hand-over it
# expects (H2S_INSTALL_DISPATCH, below) and refuses one it does not know.
#
# Which system: os-release's ID, then each word of its ID_LIKE ("arch": Arch, EndeavourOS,
# and others based on it), read as text, never run. A system not told to be Arch-based that
# has pacman gets the Arch installer anyway, with a warning, as before there was a choice.

set -euo pipefail

repository="https://github.com/Siarko/h2s-shell"
raw="https://raw.githubusercontent.com/Siarko/h2s-shell/master"
# The hand-over between this script and the installer it runs: raised when what is handed
# over (the arguments, the environment) changes, and the installer's own number with it
dispatch_version=1
# Where this file was read from: "" when bash reads it from its standard input. Read here,
# outside any function: inside one, bash names the caller ("bash" when piped, which would
# make the current folder look like a checkout)
script_source=${BASH_SOURCE[0]:-}

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
    local words=()
    read -r -a words < <(printf '%s\n' "$like") || true
    for word in "${words[@]}"; do
        if [ "$word" = arch ]; then
            system=arch
            return 0
        fi
    done
}

# run_installer <file> <arguments…>: the Arch installer, told the hand-over's version
run_installer() {
    local file=$1
    shift
    H2S_INSTALL_DISPATCH=$dispatch_version bash "$file" "$@" < /dev/null
}

main() {
    # A checkout's installer beside this file, when read from a file
    local here="" beside=""
    if [ -n "$script_source" ]; then
        here=.
        [[ "$script_source" == */* ]] && here=${script_source%/*}
        [ -f "$here/distributions/arch/install.sh" ] && beside=$here/distributions/arch/install.sh
    fi

    # --update installs no package: from a checkout it runs whatever the system is
    if [ "${1:-}" = --update ] && [ -n "$beside" ]; then
        run_installer "$beside" "$@"
        return
    fi

    detect_system
    case "$system" in
        arch) ;;
        nixos)
            echo "This installer is not for NixOS: there the shell comes with its flake's NixOS module (programs.h2s-shell.enable). See the README: $repository" >&2
            exit 1
            ;;
        *)
            if command -v pacman > /dev/null; then
                echo "Warning: ${name:-this system} is not detected as Arch-based (os-release), but it has pacman: continuing with the Arch installer." >&2
            else
                echo "This installer supports only Arch Linux and systems based on it, not ${name:-this system}." >&2
                echo "The README says what the shell needs, to set it up by hand: $repository" >&2
                exit 1
            fi
            ;;
    esac

    if [ -n "$beside" ]; then
        run_installer "$beside" "$@"
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
    run_installer "$fetched" "$@"
}

# Everything runs from here, once the whole file is read: given to bash on its standard
# input, a cut-off download runs nothing
main "$@"
