#!/usr/bin/env bash
# Checks tests/lock/resolve.sh — where the tests' tools and Quickshell are taken from —
# against fabricated PATHs of stand-in executables: a `nix` that prints a made-up store
# path, a labwc, a launcher, a qs that only answer --version. For each case: the source
# taken, the lines printed, what the caller is handed, and for a missing tool exit 2 with a
# line naming each one.
#
#   tests/resolve-selftest.sh
#
# Nothing real is started: no compositor, no Quickshell, no nix. It needs bash, coreutils,
# grep, sed and util-linux's setsid only, so it runs the same on NixOS and on Arch.
#
# Exit status: 0 when every check passed, 1 when one failed, 2 when it could not be set up.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/resolve-self.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
bash_path=$(type -P bash)
failures=0

# ---- The fabricated PATH's parts ------------------------------------------------------
# base: the plain utilities resolve.sh itself calls, the real ones. session: setsid and
# timeout, real too (the launcher probe runs through them), apart so a case can leave them
# out. Everything else is a stand-in.
mkdir -p "$work/base" "$work/session" "$work/temp"
link_real() {
    local directory=$1 name real
    shift
    for name in "$@"; do
        real=$(type -P "$name") || { echo "resolve-selftest.sh: $name not found on PATH (resolve.sh calls it)" >&2; exit 2; }
        ln -s "$real" "$work/$directory/$name"
    done
}
link_real base env mktemp tail head grep wc cat rm mkdir chmod
link_real session setsid timeout

# stand_in <file> <line>…: an executable made of those lines
stand_in() {
    local file=$work/$1
    shift
    mkdir -p "$(dirname "$file")"
    {
        echo "#!$bash_path"
        printf '%s\n' "$@"
    } > "$file"
    chmod +x "$file"
}
# answers <file> <text>: a program that only answers --version
answers() { stand_in "$1" "[ \"\${1:-}\" = --version ] && echo '$2'" "exit 0"; }
# A setpriv that runs the command it is given (after --no-new-privs)
setpriv_stand_in() {
    stand_in "$1" "if [ \"\${1:-}\" = --version ]; then echo 'setpriv from util-linux $2'; exit 0; fi" 'shift' 'exec "$@"'
}

# The system's tools
answers system/labwc "labwc 7.8.9 (+xwayland +nls) wlroots-0.19.0"
setpriv_stand_in system/setpriv 6.5.4
answers hyprland/Hyprland "Hyprland 0.50.0 built from branch v0.50.0"
answers hyprland-same/Hyprland "Hyprland 0.57.1 built from another branch"

# What a nix build of tools.nix would print: a store path, made up, holding the whole set
store=$work/store/aaaaaaaa-h2s-locktest-tools
answers "${store#"$work/"}/bin/labwc" "labwc 1.2.3 (+xwayland) wlroots-0.20.2"
setpriv_stand_in "${store#"$work/"}/bin/setpriv" 4.5.6
answers "${store#"$work/"}/bin/Hyprland" "Hyprland 0.57.1 built from branch v0.57.1"
mkdir -p "$store/share/ltproto" "$store/share/keymaps"
touch "$store/share/us.xkb" "$store/bin/hyprctl" "$store/bin/grim" "$store/bin/python3" "$store/bin/xkbcli" \
    "$store/bin/dbus-daemon" "$store/bin/gdbus" "$store/bin/wl-copy" "$store/bin/wl-paste" "$store/bin/wlr-randr"
# The same set with two parts gone, and one whose Hyprland does not say its version
cp -a "$store" "$work/store/bbbbbbbb-h2s-locktest-tools"
rm -r "$work/store/bbbbbbbb-h2s-locktest-tools/bin/grim" "$work/store/bbbbbbbb-h2s-locktest-tools/share/keymaps"
cp -a "$store" "$work/store/cccccccc-h2s-locktest-tools"
answers store/cccccccc-h2s-locktest-tools/bin/Hyprland "no number here"
cp -a "$store" "$work/store/dddddddd-h2s-locktest-tools"
rm "$work/store/dddddddd-h2s-locktest-tools/bin/labwc"

# nix: writes down how it was called, prints the store path
nix_stand_in() { stand_in "$1/nix" "echo \"\$*\" >> '$work/nix.calls'" "echo '$2'"; }
nix_stand_in nix "$store"
nix_stand_in nix-partial "$work/store/bbbbbbbb-h2s-locktest-tools"
nix_stand_in nix-mute-hyprland "$work/store/cccccccc-h2s-locktest-tools"
nix_stand_in nix-no-labwc "$work/store/dddddddd-h2s-locktest-tools"
stand_in nix-failing/nix "echo 'error: the stand-in build failed' >&2" "exit 1"

# Quickshells, and launchers: one that runs the launch.sh it is pointed at (H2S_SHELL_DIR)
# with its own qs first on PATH, one that says nothing
answers qs/qs "Quickshell 0.0.1 (revision , distributed by a stand-in)"
answers quickshell/quickshell "Quickshell 0.0.2 (revision , distributed by a stand-in)"
answers given/qs "Quickshell 0.0.3"
answers launcher-qs/qs "Quickshell 0.0.4"
answers qs-mute/qs "a program that names no version"
stand_in launcher/h2s-shell "echo called >> '$work/launcher.calls'" "PATH=$work/launcher-qs:\$PATH" 'exec "$H2S_SHELL_DIR/scripts/launch.sh"'
stand_in launcher-mute/h2s-shell "echo called >> '$work/launcher.calls'" "exit 0"
touch "$work/not-executable"

# What a runner does: defines what resolve.sh asks of its caller, sources it, and here
# prints what it was handed
cat > "$work/driver.sh" << 'DRIVER'
setup_error() {
    echo "driver: $*" >&2
    [ -n "$probe" ] && rm -rf "$probe"
    exit 2
}
LOCKTEST_DIR=$1
LOCKTEST_NEED=$2
temp_base=$3
PROBE_TIMEOUT=2
probe=""
source "$LOCKTEST_DIR/resolve.sh"
echo "source=$LOCKTEST_TOOL_SOURCE"
echo "tools=$LOCKTEST_TOOLS"
echo "labwc=$LOCKTEST_LABWC"
echo "setpriv=$SETPRIV"
echo "launcher=$LOCKTEST_LAUNCHER"
echo "qs=$LOCKTEST_QS"
DRIVER

# ---- The checks -----------------------------------------------------------------------
# resolve <case> <need> <PATH's parts, by name> [VAR=value…]: runs the driver with that
# PATH and those variables and nothing else; its output in <case>.out, its errors in
# <case>.err, its status in $status
resolve() {
    local name=$1 need=$2 part path=""
    case_name=$name
    for part in $3; do path+="${path:+:}$work/$part"; done
    shift 3
    rm -f "$work/nix.calls" "$work/launcher.calls"
    env -i PATH="$path" "$@" "$bash_path" "$work/driver.sh" "$REPO/tests/lock" "$need" "$work/temp" \
        > "$work/$name.out" 2> "$work/$name.err" < /dev/null
    status=$?
}
pass() { echo "PASS $case_name: $1"; }
failed() {
    echo "FAIL $case_name: $1"
    sed 's/^/    out: /' "$work/$case_name.out"
    sed 's/^/    err: /' "$work/$case_name.err"
    failures=$((failures + 1))
}
exits() { if [ "$status" = "$1" ]; then pass "exit $1"; else failed "exit $status, expected $1"; fi; }
# prints <out|err> <line>: that exact line is there
prints() {
    if grep -q -x -F -- "$2" "$work/$case_name.$1"; then pass "$1 has: $2"; else failed "$1 lacks: $2"; fi
}
# silent_on <out|err> <text>: no line holds that text
silent_on() {
    if grep -q -F -- "$2" "$work/$case_name.$1"; then failed "$1 has '$2'"; else pass "$1 has no '$2'"; fi
}
# hands_over_nothing: resolve.sh ended the run; the caller got no tools
hands_over_nothing() { silent_on out "source="; silent_on out "tools:"; silent_on out "quickshell:"; }
called() { if [ -e "$work/$1.calls" ]; then pass "$1 was called"; else failed "$1 was not called"; fi; }
not_called() { if [ -e "$work/$1.calls" ]; then failed "$1 was called"; else pass "$1 was not called"; fi; }

missing_header_system="driver: nothing was run, the tests' tools are not all there (tools from: system):"
missing_header_nix="driver: nothing was run, the tests' tools are not all there (tools from: nix):"
missing_labwc="  labwc not found on PATH (the headless compositor the suites' windows open in)"
missing_setpriv="  setpriv not found on PATH (starts every test process with no new privileges)"
missing_setsid="  setsid not found on PATH (puts the compositor in a process group of its own, to be stopped whole)"
missing_timeout="  timeout not found on PATH (ends a compositor or a Quickshell that hangs)"
missing_quickshell="  Quickshell (qs or quickshell) not found on PATH (it runs the suites; LOCKTEST_QS names one, LOCKTEST_LAUNCHER a launcher to ask)"
missing_launcher="  h2s-shell not found on PATH (the launcher the shell under test is started through; LOCKTEST_LAUNCHER names another)"
not_from_system="driver: the lock test bed cannot take its tools from the system yet (its protocol bindings and keymaps are built by tests/lock/tools.nix only): it needs nix. The unit and module suites run without."
nix_tools_line="tools: nix (tests/lock/tools.nix, pinned: $store) — labwc 1.2.3, setpriv 4.5.6"
system_tools_line="tools: system (PATH, not pinned) — labwc 7.8.9, setpriv 6.5.4"

# ---- The source ---
# A nix command: the pinned build, also when the system has the tools
resolve nix unit "base session nix system qs"
exits 0
prints out "resolving tools (tools.nix)…"
prints out "$nix_tools_line"
prints out "source=nix"
prints out "tools=$store"
prints out "labwc=$store/bin/labwc"
prints out "setpriv=$store/bin/setpriv"
if grep -q -x -F -- "build --no-link --print-out-paths --impure -f $REPO/tests/lock/tools.nix" "$work/nix.calls" 2> /dev/null; then
    pass "nix was asked to build tools.nix"
else
    failed "nix was not asked to build tools.nix"
fi

# No nix command: the system's
resolve system unit "base session system qs"
exits 0
prints out "$system_tools_line"
prints out "source=system"
prints out "tools="
prints out "labwc=$work/system/labwc"
prints out "setpriv=$work/system/setpriv"
silent_on out "resolving tools"

# The choice, said: system although nix is there
resolve forced-system unit "base session nix system qs" H2S_TEST_TOOLS=system
exits 0
prints out "$system_tools_line"
prints out "source=system"
not_called nix

# … nix although the system has the tools
resolve forced-nix unit "base session nix system qs" H2S_TEST_TOOLS=nix
exits 0
prints out "source=nix"
called nix

# … nix where there is none: an error, not the system's tools
resolve forced-nix-absent unit "base session system qs" H2S_TEST_TOOLS=nix
exits 2
prints err "driver: H2S_TEST_TOOLS=nix, but there is no nix command on PATH"
hands_over_nothing

resolve unknown-source unit "base session nix system qs" H2S_TEST_TOOLS=pinned
exits 2
prints err "driver: H2S_TEST_TOOLS must be nix or system, not 'pinned'"
hands_over_nothing
not_called nix

# ---- A missing tool ---
resolve no-labwc unit "base session qs" H2S_TEST_TOOLS=system
exits 2
prints err "$missing_header_system"
prints err "$missing_labwc"
prints err "$missing_setpriv"
silent_on err "setsid"
hands_over_nothing

# Every missing one in the one run, Quickshell too
resolve nothing unit "base"
exits 2
prints err "$missing_header_system"
prints err "$missing_labwc"
prints err "$missing_setpriv"
prints err "$missing_setsid"
prints err "$missing_timeout"
prints err "$missing_quickshell"
hands_over_nothing

# The pinned set does not hold setsid and timeout: wanted on PATH with nix too
resolve nix-no-session unit "base nix qs"
exits 2
prints err "$missing_header_nix"
prints err "$missing_setsid"
prints err "$missing_timeout"
silent_on err "labwc"
hands_over_nothing

# A build that fails is not a reason to take the system's tools
resolve nix-fails unit "base session nix-failing system qs"
exits 2
prints err "error: the stand-in build failed"
prints err "driver: nix could not build tests/lock/tools.nix (output above)"
hands_over_nothing

resolve nix-lacks-labwc unit "base session nix-no-labwc system qs"
exits 2
prints err "$missing_header_nix"
prints err "  the pinned tool set ($work/store/dddddddd-h2s-locktest-tools) lacks bin/labwc (the headless compositor the suites' windows open in)"
hands_over_nothing

# ---- Quickshell ---
# LOCKTEST_QS before the launcher and PATH; the launcher is not asked
resolve given-qs unit "base session system launcher qs" LOCKTEST_QS="$work/given/qs"
exits 0
prints out "quickshell: $work/given/qs 0.0.3 (LOCKTEST_QS)"
prints out "qs=$work/given/qs"
not_called launcher

resolve given-qs-broken unit "base session system qs" LOCKTEST_QS="$work/not-executable"
exits 2
prints err "driver: LOCKTEST_QS ($work/not-executable) is not an executable file"
hands_over_nothing

# The launcher before PATH: its qs, not the one on PATH
resolve launcher unit "base session system launcher qs"
exits 0
prints out "quickshell: $work/launcher-qs/qs 0.0.4 (asked of the launcher $work/launcher/h2s-shell)"
prints out "launcher=$work/launcher/h2s-shell"
prints out "qs=$work/launcher-qs/qs"
called launcher

# A launcher that does not say (here: the one LOCKTEST_LAUNCHER names, before the h2s-shell
# on PATH): an error, although PATH has a qs
resolve launcher-mute unit "base session system launcher qs" LOCKTEST_LAUNCHER="$work/launcher-mute/h2s-shell"
exits 2
prints err "driver: the launcher ($work/launcher-mute/h2s-shell) did not name an executable qs (status 0, said: ''); set LOCKTEST_QS"
silent_on out "quickshell:"
silent_on out "qs="
called launcher

resolve launcher-broken unit "base session system qs" LOCKTEST_LAUNCHER="$work/not-executable"
exits 2
prints err "driver: LOCKTEST_LAUNCHER ($work/not-executable) is not an executable file"
silent_on out "qs="

# No launcher: qs on PATH, before quickshell
resolve path-qs unit "base session system quickshell qs"
exits 0
prints out "quickshell: $work/qs/qs 0.0.1 (PATH)"
prints out "launcher="
prints out "qs=$work/qs/qs"

resolve path-quickshell unit "base session system quickshell"
exits 0
prints out "quickshell: $work/quickshell/quickshell 0.0.2 (PATH)"
prints out "qs=$work/quickshell/quickshell"

resolve no-quickshell unit "base session system"
exits 2
prints err "$missing_header_system"
prints err "$missing_quickshell"
silent_on err "labwc"
hands_over_nothing

# A version that cannot be read is said to be unknown
resolve version-unknown unit "base session system qs-mute"
exits 0
prints out "quickshell: $work/qs-mute/qs version unknown (PATH)"

# ---- The pinned Hyprland against the system's (nix only) ---
resolve hyprland-differs unit "base session nix hyprland qs"
exits 0
prints out "NOTE: the pinned Hyprland (0.57.1) is not the system's (0.50.0): move the pin in tools.nix"

resolve hyprland-same unit "base session nix hyprland-same qs"
exits 0
silent_on out "NOTE"

resolve hyprland-unreadable unit "base session nix-mute-hyprland hyprland qs"
exits 0
prints out "NOTE: cannot compare the pinned Hyprland (version unknown) with the system's (0.50.0)"

resolve hyprland-system unit "base session system hyprland qs"
exits 0
silent_on out "NOTE"

# ---- The lock need ---
resolve lock-nix lock "base session nix launcher"
exits 0
prints out "$nix_tools_line, Hyprland 0.57.1"
prints out "launcher=$work/launcher/h2s-shell"
prints out "qs=$work/launcher-qs/qs"

# Not from the system: said, whether chosen or found
resolve lock-system lock "base session nix system launcher" H2S_TEST_TOOLS=system
exits 2
prints err "$not_from_system"
hands_over_nothing
not_called nix

resolve lock-no-nix lock "base session system launcher"
exits 2
prints err "$not_from_system"
hands_over_nothing

# The whole set is asked for, and a launcher even with a Quickshell given
resolve lock-partial lock "base session nix-partial qs" LOCKTEST_QS="$work/given/qs"
exits 2
prints err "$missing_header_nix"
prints err "  the pinned tool set ($work/store/bbbbbbbb-h2s-locktest-tools) lacks bin/grim (screenshots of the lock screen)"
prints err "  the pinned tool set ($work/store/bbbbbbbb-h2s-locktest-tools) lacks share/keymaps (the layouts the virtual keyboard sends)"
prints err "$missing_launcher"
hands_over_nothing

# The unit need does not look at the lock bed's parts
resolve unit-partial unit "base session nix-partial qs"
exits 0
prints out "source=nix"

# ---- A caller that does not say what it needs ---
resolve no-need "" "base session system qs"
exits 2
prints err "driver: resolve.sh: LOCKTEST_NEED must be unit or lock, not ''"
hands_over_nothing

# ---- Nothing left behind (the nix log, the launcher probe's dir) ---
case_name=temp
if [ -z "$(ls -A "$work/temp")" ]; then pass "the temp dir is empty"; else failed "left in the temp dir: $(ls -A "$work/temp" | tr '\n' ' ')"; fi

echo
if [ "$failures" = 0 ]; then
    echo "resolve.sh: every check passed"
else
    echo "resolve.sh: $failures check(s) FAILED"
    exit 1
fi
