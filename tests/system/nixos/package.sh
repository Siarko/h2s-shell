# shellcheck shell=bash
# The flake's package (nix/package.nix): it builds, holds the shell without the parts left
# out and its built-in modules beside it, and its h2s-shell command runs the checkout
# H2S_SHELL_DIR names with every program the shell calls on PATH, the package's built-in
# modules' directory and its helper's (H2S_SHELL_LIBEXEC, holding h2s-helper, built from
# helper/ and answering --version with the shell's version). Builds into the store, links nothing, writes no lock file.
need nix "builds the flake's package"
need diff "compares the package's built-in modules with the checkout's"

work=$(mktemp -d "${TMPDIR:-/tmp}/system-package.XXXXXX") || cannot_run "cannot create a temp dir"
trap 'rm -rf "$work"' EXIT
out=$(cd "$REPO" && nix --extra-experimental-features "nix-command flakes" build --no-link \
    --no-write-lock-file --print-out-paths "path:$REPO#h2s-shell" 2> "$work/nix.log" | tail -n 1)
if [ -z "$out" ]; then
    tail -n 20 "$work/nix.log"
fi
check "the package builds" test -n "$out" -a -d "$out"
[ -n "$out" ] || return 0

number=$(sed -n 's/.*readonly property string number: "\([^"]*\)".*/\1/p' "$REPO/singletons/Version.qml")
check "its version is singletons/Version.qml's ($number)" test -n "$number" -a "${out#*-h2s-shell-}" = "$number"
check "it holds the shell" test -f "$out/share/h2s-shell/shell.qml"
for left_out in tests/lock docs helper mockups mockup.qml tests/mockup.sh tests/mockup-selftest.sh tests/run-mockups.sh tests/fixtures/mockups; do
    check "$left_out is not in it" test ! -e "$out/share/h2s-shell/$left_out"
done
check "it has the h2s-shell command" test -x "$out/bin/h2s-shell"
check "its built-in modules are beside the shell, in share/h2s-shell-builtin, as builtin-modules/ holds them" \
    diff -r "$REPO/builtin-modules" "$out/share/h2s-shell-builtin"
check "… and not inside the shell's tree" test ! -e "$out/share/h2s-shell/builtin-modules"

# The launcher, asked with nothing of this session: a stand-in launch.sh in the checkout it
# is pointed at says which arguments and which programs reached it. PATH is empty, so a
# program found is one the package brings.
programs=(qs nmcli bluetoothctl python3 notify-send jq gsettings gdbus cava git xdg-open vipsthumbnail flock setsid timeout)
mkdir -p "$work/checkout/scripts" "$work/home"
{
    echo '#!/bin/sh'
    echo 'echo "arguments: $*"'
    echo 'echo "built-in modules: ${H2S_SHELL_BUILTIN_MODULES-unset}"'
    echo 'echo "libexec: ${H2S_SHELL_LIBEXEC-unset}"'
    for program in "${programs[@]}"; do
        echo "command -v $program > /dev/null && echo 'found: $program'"
    done
    echo 'exit 0'
} > "$work/checkout/scripts/launch.sh"
chmod +x "$work/checkout/scripts/launch.sh"
answer=$(timeout 20 env -i PATH="" HOME="$work/home" H2S_SHELL_DIR="$work/checkout" H2S_SHELL_BUILTIN_MODULES="$work/home" \
    "$out/bin/h2s-shell" one two 2>&1)
answered() { grep -qxF -- "$1" <<< "$answer"; }
check "the launcher runs the checkout H2S_SHELL_DIR names, with its arguments" answered "arguments: one two"
check "… handing it the package's built-in modules (whatever the caller had set)" answered "built-in modules: $out/share/h2s-shell-builtin"
for program in "${programs[@]}"; do
    check "$program is on the launcher's PATH" answered "found: $program"
done

# The helper: the launcher names its directory, and the program there answers
libexec=$(sed -n 's/^libexec: //p' <<< "$answer")
check "the launcher hands the shell the helper's directory (H2S_SHELL_LIBEXEC), in the store" \
    test -n "$libexec" -a "${libexec#/nix/store/}" != "$libexec"
check "… holding h2s-helper, a program" test -x "$libexec/h2s-helper"
protocol=$(sed -n 's/.*readonly property int protocol: \([0-9]*\).*/\1/p' "$REPO/singletons/HelperRules.qml")
helper_answer=$(timeout 10 env -i "$libexec/h2s-helper" --version 2> /dev/null)
check "… which answers --version with the shell's version ($number) and the protocol HelperRules speaks ($protocol)" \
    test "$helper_answer" = "{\"protocol\":$protocol,\"version\":\"$number\"}"
