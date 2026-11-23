#!/usr/bin/env bash
# Runs the checks of the system this machine runs: what holds on NixOS only, or on Arch
# only — the flake's package, install.sh's package names, the files a system keeps where.
# What does not depend on the system is in the other runners.
#
#   tests/run-system.sh              every check of this system's set
#   tests/run-system.sh <check>…     only the named ones (a check is named by its file in
#                                    tests/system/<system>/ without ".sh")
#
# The system is the distribution the shell's scripts detect (scripts/distribution.sh: a
# marker such as /etc/NIXOS, else os-release's ID, else its ID_LIKE): a set per
# distribution, none for the generic one. H2S_DISTRIBUTION_ROOT is put before the paths it
# reads (tests/run-system-selftest.sh's made-up trees).
#
# A check file is sourced in a shell of its own with REPO (the checkout) and:
#
#   check <description> <command…>   PASS or FAIL by the command's status
#   need <program> <use>             cannot run without it: the check ends, NOT RUN
#   cannot_run <reason>              the same, for another reason
#
# The checks change nothing on the machine: they read, ask `pacman -Si`, build with nix.
#
# Exit status: 0 when every check passed; 1 when one FAILed; 2 when nothing could be run
# (an unknown system, a name that is no check of this system — also when it is the other
# system's —, an empty set) or a check could not run (the reason is printed) and none
# failed. A set that did not run is never printed as a pass.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
SYSTEMS=(nixos arch)
setup_error() { echo "run-system.sh: $*" >&2; exit 2; }

case "${1:-}" in -*) echo "usage: tests/run-system.sh [<check>…]" >&2; exit 2 ;; esac
# The distribution as the shell's scripts tell it (scripts/distribution.sh)
source "$REPO/scripts/distribution.sh" || setup_error "cannot read scripts/distribution.sh; nothing was run"
if ! distribution_detect "$REPO" "" "${H2S_DISTRIBUTION_ROOT:-}"; then
    setup_error "which distribution this is cannot be told: $distribution_problem; nothing was run"
fi
system=$distribution_id
case "$system" in
    nixos | arch) ;;
    *) setup_error "no set for this system: $system (${distribution_os_id:+ID=$distribution_os_id, }${distribution_how}); the sets are: ${SYSTEMS[*]}. Nothing was run" ;;
esac
set_dir=$REPO/tests/system/$system

names=()
if [ $# -gt 0 ]; then
    for name in "$@"; do
        [ -n "$name" ] || setup_error "an empty check name; nothing was run"
        if [ ! -f "$set_dir/$name.sh" ] || [[ "$name" == */* ]]; then
            for other in "${SYSTEMS[@]}"; do
                [ "$other" != "$system" ] && [ -f "$REPO/tests/system/$other/$name.sh" ] && [[ "$name" != */* ]] \
                    && setup_error "'$name' is a check of the $other set, and this system is $system; nothing was run"
            done
            setup_error "no check named '$name' in tests/system/$system (this system is $system); nothing was run"
        fi
        names+=("$name")
    done
else
    for file in "$set_dir"/*.sh; do
        [ -f "$file" ] && names+=("$(basename "$file" .sh)")
    done
    [ ${#names[@]} -gt 0 ] || setup_error "the $system set (tests/system/$system) holds no check; nothing was run"
fi

echo "system: $system — ${#names[@]} check(s): ${names[*]}"

# One check file, in a shell of its own: status 0 passed, 1 a FAIL, 2 could not run
run_check() (
    failed=0
    checked=0
    check() {
        local description=$1
        shift
        checked=$((checked + 1))
        if "$@"; then
            echo "    PASS $description"
        else
            echo "    FAIL $description"
            failed=1
        fi
    }
    cannot_run() { echo "    cannot run: $*"; echo "$*" > "$reason_file"; exit 2; }
    need() { type -P "$1" > /dev/null || cannot_run "$1 not found on PATH ($2)"; }
    # shellcheck disable=SC1090
    source "$1"
    # A file that checked nothing has not passed
    [ "$checked" -gt 0 ] || cannot_run "it made no check"
    exit "$failed"
)

reason_file=$(mktemp "${TMPDIR:-/tmp}/run-system.XXXXXX") || setup_error "cannot create a temp file"
trap 'rm -f "$reason_file"' EXIT
summary=()
any_failed=0
any_not_run=0
for name in "${names[@]}"; do
    echo "== $name"
    : > "$reason_file"
    run_check "$set_dir/$name.sh"
    case $? in
        0) summary+=("  PASS     $name") ;;
        2) summary+=("  NOT RUN  $name — $(head -n 1 "$reason_file" | cut -c 1-300)"); any_not_run=1 ;;
        *) summary+=("  FAIL     $name"); any_failed=1 ;;
    esac
done

echo
echo "System set ($system):"
printf '%s\n' "${summary[@]}"
[ "$any_failed" = 0 ] || exit 1
[ "$any_not_run" = 0 ] || exit 2
exit 0
