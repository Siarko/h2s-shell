#!/usr/bin/env bash
# Checks tests/lock/resolve.sh — where the tests' tools and Quickshell are taken from —
# against fabricated PATHs of stand-in executables: a `nix` that prints a made-up store
# path, a labwc, a launcher, a qs that only answer --version. For each case: the source
# taken, the lines printed, what the caller is handed, and for a missing tool exit 2 with a
# line naming each one. And what the programs resolve.sh starts get of the caller's session
# (the launcher it asks, a program asked for its version): nothing. For the lock need with
# the system's tools also the set it makes (links, bindings, keymaps: the commands run, by
# stand-ins of python3, pkg-config and xkbcli), and the launcher taken when there is no
# h2s-shell command — the test bed's launcher.sh, the real one, checked on its own too.
# With nix, the store path remembered from an earlier run: taken without asking nix while
# the tree's inputs are unchanged and the path still holds what is needed, not otherwise.
# And the lock tests/lock/run.sh takes for the machine (on a lock file of this script's own,
# in a run that ends at its first set-up check): it waits for another run and says so, does
# not wait for a caller that holds the lock for it, and ends at once when interrupted.
#
#   tests/resolve-selftest.sh
#
# Nothing real is started: no compositor, no Quickshell, no nix. It needs bash, coreutils,
# findutils, grep, sed and util-linux's setsid and flock only, so it runs the same on NixOS
# and on Arch. It takes no lock: nothing of it is shared with another run.
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
link_real base env mktemp tail head grep wc cat rm mkdir chmod sleep ln touch cp bash sha256sum uname mv find sort
link_real session setsid timeout
# What tests/lock/run.sh calls before its first set-up check
mkdir -p "$work/bed"
link_real bed flock id dirname readlink nproc

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
# answers <file> <text>: a program that only answers --version, and leaves the environment
# it was asked in beside itself (<file>.env)
answers() { stand_in "$1" "[ \"\${1:-}\" = --version ] && { env > '$work/$1.env'; echo '$2'; }" "exit 0"; }
# A setpriv that writes down its first argument and runs the command it is given after it
setpriv_stand_in() {
    stand_in "$1" "if [ \"\${1:-}\" = --version ]; then echo 'setpriv from util-linux $2'; exit 0; fi" \
        "echo \"\$1\" >> '$work/setpriv.calls'" 'shift' 'exec "$@"'
}

# The system's tools
answers system/labwc "labwc 7.8.9 (+xwayland +nls) wlroots-0.19.0"
setpriv_stand_in system/setpriv 6.5.4
answers hyprland/Hyprland "Hyprland 0.50.0 built from branch v0.50.0"
answers hyprland-same/Hyprland "Hyprland 0.57.1 built from branch v0.57.1"
stand_in hyprland-silent/Hyprland "exit 3"
answers hyprland-commit/Hyprland "Hyprland 0.57.1 built from another commit"

# The lock bed's set on a system: the programs it only needs to find (lockset, wlr-randr),
# and the three it makes the generated parts with. python3 answers the import question and
# "runs" pywayland's scanner (a file in the directory after -o); pkg-config names the two
# data directories; xkbcli prints a keymap that says how it was asked. Each leaves how it
# was called (<name>.calls) and its environment (<name>.env).
mkdir -p "$work/lockset"
for name in hyprctl grim dbus-daemon gdbus wl-copy wl-paste; do stand_in "lockset/$name" "exit 0"; done
stand_in wlr-randr/wlr-randr "exit 0"
python_stand_in() {
    stand_in "$1/python3" "echo \"\$*\" >> '$work/python.calls'" "'$work/base/env' > '$work/python.env'" \
        'case "$*" in' \
        "    '-I -c import pywayland.client, pywayland.scanner') exit $2 ;;" \
        "    '-I -B -m pywayland.scanner -o '*) $3 ;;" \
        'esac' 'exit 1'
}
python_stand_in python 0 "'$work/base/mkdir' -p \"\$6\" && echo generated > \"\$6/wayland.py\"; exit 0"
python_stand_in python-bare 1 "exit 1"
python_stand_in python-no-scanner 0 "echo 'the stand-in scanner failed' >&2; exit 1"
stand_in pkg-config/pkg-config 'case "$*" in' \
    "    '--variable=pkgdatadir wayland-scanner') echo '$work/pkgdata/wayland' ;;" \
    "    '--variable=pkgdatadir wayland-protocols') echo '$work/pkgdata/wayland-protocols' ;;" \
    '    *) exit 1 ;;' 'esac'
stand_in pkg-config-empty/pkg-config "echo '$work/pkgdata/empty'"
mkdir -p "$work/pkgdata/wayland" "$work/pkgdata/wayland-protocols/stable/xdg-shell" "$work/pkgdata/empty"
touch "$work/pkgdata/wayland/wayland.xml" "$work/pkgdata/wayland-protocols/stable/xdg-shell/xdg-shell.xml"
stand_in xkbcli/xkbcli "echo \"\$*\" >> '$work/xkbcli.calls'" "'$work/base/env' > '$work/xkbcli.env'" 'echo "keymap for: $*"'
stand_in xkbcli-failing/xkbcli "echo 'the stand-in xkbcli failed' >&2" "exit 1"
stand_in xkbcli-silent/xkbcli "exit 0"

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
# with its own qs first on PATH, one that says nothing, one that never answers. The first
# leaves what it was started with: its environment, and its session (the sixth field of
# /proc/<pid>/stat)
answers qs/qs "Quickshell 0.0.1 (revision , distributed by a stand-in)"
answers quickshell/quickshell "Quickshell 0.0.2 (revision , distributed by a stand-in)"
answers given/qs "Quickshell 0.0.3"
answers launcher-qs/qs "Quickshell 0.0.4"
answers qs-mute/qs "a program that names no version"
stand_in launcher/h2s-shell "echo called >> '$work/launcher.calls'" "env > '$work/launcher.env'" \
    'read -r _ _ _ _ _ session _ < /proc/$$/stat' "echo \"\$session\" > '$work/launcher.session'" \
    "PATH=$work/launcher-qs:\$PATH" 'exec "$H2S_SHELL_DIR/scripts/launch.sh"'
stand_in launcher-given/h2s-shell "PATH=$work/given:\$PATH" 'exec "$H2S_SHELL_DIR/scripts/launch.sh"'
stand_in launcher-mute/h2s-shell "echo called >> '$work/launcher.calls'" "exit 0"
stand_in launcher-hangs/h2s-shell "echo called >> '$work/launcher.calls'" "exec sleep 60"
touch "$work/not-executable"

# What a runner does: defines what resolve.sh asks of its caller, sources it, and here
# prints what it was handed
cat > "$work/driver.sh" << 'DRIVER'
# As strict as the runners are
set -uo pipefail
setup_error() {
    echo "driver: $*" >&2
    [ -n "$probe" ] && rm -rf "$probe"
    exit 2
}
LOCKTEST_DIR=$1
LOCKTEST_NEED=$2
temp_base=$3
PROBE_TIMEOUT=1
probe=""
source "$LOCKTEST_DIR/resolve.sh"
read -r _ _ _ _ _ session _ < /proc/$$/stat
echo "session=$session"
echo "source=$LOCKTEST_TOOL_SOURCE"
echo "tools=$LOCKTEST_TOOLS"
echo "labwc=$LOCKTEST_LABWC"
echo "setpriv=$SETPRIV"
echo "launcher=$LOCKTEST_LAUNCHER"
echo "launcher_from=$LOCKTEST_LAUNCHER_FROM"
echo "qs=$LOCKTEST_QS"
# The lock bed's set from the system's tools, as run.sh has it made (MAKE_ANYWAY: a caller
# that asks for it where it is not for)
if { [ "$LOCKTEST_NEED" = lock ] && [ "$LOCKTEST_TOOL_SOURCE" = system ]; } || [ -n "${MAKE_ANYWAY:-}" ]; then
    make_system_tools "$4"
    echo "made=$4"
fi
DRIVER

# ---- The checks -----------------------------------------------------------------------
# resolve <case> <need> <PATH's parts, by name> [VAR=value…]: runs the driver with that
# PATH and those variables and nothing else; its output in <case>.out, its errors in
# <case>.err, its status in $status
lock_directory=$REPO/tests/lock
resolve() {
    local name=$1 need=$2 part path=""
    case_name=$name
    for part in $3; do path+="${path:+:}$work/$part"; done
    shift 3
    rm -f "$work/nix.calls" "$work/launcher.calls" "$work/setpriv.calls" "$work/launcher.env" "$work/launcher.session" \
        "$work/python.calls" "$work/xkbcli.calls"
    find "$work" -name '*.env' -delete
    made=$work/made/$name
    env -i PATH="$path" "$@" "$bash_path" "$work/driver.sh" "$lock_directory" "$need" "$work/temp" "$made" \
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
# has_line <file, in $work> <line>, lacks_variable <file> <name>: of what a stand-in left.
# A file that is not there fails both: the stand-in was not started
has_line() {
    if grep -q -x -F -- "$2" "$work/$1" 2> /dev/null; then pass "$1 has: $2"; else failed "$1 lacks: $2 ($(tr '\n' ' ' < "$work/$1" 2>&1))"; fi
}
lacks_variable() {
    if [ -e "$work/$1" ] && ! grep -q -- "^$2=" "$work/$1"; then pass "$1 has no $2"; else failed "$1 has $2, or is not there"; fi
}
# The session the tests' author sits in, as the driver's environment
hostile=(WAYLAND_DISPLAY=wayland-1 DISPLAY=:0 HOME=/hostile/home XDG_RUNTIME_DIR=/hostile/run
    DBUS_SESSION_BUS_ADDRESS=unix:path=/hostile/run/bus HYPRLAND_INSTANCE_SIGNATURE=hostile)
called() { if [ -e "$work/$1.calls" ]; then pass "$1 was called"; else failed "$1 was not called"; fi; }
not_called() { if [ -e "$work/$1.calls" ]; then failed "$1 was called"; else pass "$1 was not called"; fi; }

missing_header_system="driver: nothing was run, the tests' tools are not all there (tools from: system):"
missing_header_nix="driver: nothing was run, the tests' tools are not all there (tools from: nix):"
missing_labwc="  labwc not found on PATH (the headless compositor the suites' windows open in)"
missing_setpriv="  setpriv not found on PATH (starts every test process with no new privileges)"
missing_setsid="  setsid not found on PATH (puts the compositor in a process group of its own, to be stopped whole)"
missing_timeout="  timeout not found on PATH (ends a compositor or a Quickshell that hangs)"
missing_quickshell="  Quickshell (qs or quickshell) not found on PATH (it runs the suites; LOCKTEST_QS names one, LOCKTEST_LAUNCHER a launcher to ask)"
stand_in_launcher=$REPO/tests/lock/launcher.sh
stand_in_launcher_line="launcher: $stand_in_launcher (the test bed's stand-in: no LOCKTEST_LAUNCHER, no h2s-shell on PATH)"
# is <description> <command…>: a check of what a case left
is() {
    local description=$1
    shift
    if "$@" > /dev/null 2>&1; then pass "$description"; else failed "$description"; fi
}
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

# What the launcher is started with, when the caller sits in a session: nothing of it. A
# launcher that ignored H2S_SHELL_DIR would start a real shell, so it gets a private HOME
# and runtime dir (the probe's, gone afterwards), no display, D-Bus addresses that lead
# nowhere, no new privileges, a session of its own
resolve launcher-isolated unit "base session system launcher qs" "${hostile[@]}"
exits 0
prints out "qs=$work/launcher-qs/qs"
probe_dir=$(sed -n 's/^H2S_SHELL_DIR=//p' "$work/launcher.env" 2> /dev/null)
case "$probe_dir" in
    "$work"/temp/locktest-probe.*) pass "the launcher was pointed at the probe's dir" ;;
    *) failed "the launcher was pointed at '$probe_dir', not at a probe dir in $work/temp" ;;
esac
has_line launcher.env "HOME=$probe_dir/home"
has_line launcher.env "XDG_RUNTIME_DIR=$probe_dir/run"
has_line launcher.env "DBUS_SESSION_BUS_ADDRESS=unix:path=$probe_dir/run/no-session-bus"
has_line launcher.env "DBUS_SYSTEM_BUS_ADDRESS=unix:path=$probe_dir/run/no-system-bus"
has_line launcher.env "LIBSEAT_BACKEND=disabled-for-test"
lacks_variable launcher.env WAYLAND_DISPLAY
lacks_variable launcher.env DISPLAY
lacks_variable launcher.env HYPRLAND_INSTANCE_SIGNATURE
has_line setpriv.calls "--no-new-privs"
launcher_session=$(cat "$work/launcher.session" 2> /dev/null)
driver_session=$(sed -n 's/^session=//p' "$work/$case_name.out")
if [ -n "$launcher_session" ] && [ -n "$driver_session" ] && [ "$launcher_session" != "$driver_session" ]; then
    pass "the launcher ran in a session of its own"
else
    failed "the launcher ran in session '$launcher_session', the caller's is '$driver_session'"
fi
# … and so does a program asked for its version: an empty environment
for asked in system/labwc launcher-qs/qs; do
    for variable in WAYLAND_DISPLAY DISPLAY HOME XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS HYPRLAND_INSTANCE_SIGNATURE; do
        lacks_variable "$asked.env" "$variable"
    done
done

# A launcher that never answers is stopped, and said to be one
hang_started=$SECONDS
resolve launcher-hangs unit "base session system launcher-hangs qs" "${hostile[@]}"
exits 2
# The driver's PROBE_TIMEOUT is 1 s (and 2 s more before the kill); the launcher sleeps 60
if [ $((SECONDS - hang_started)) -le 10 ]; then pass "stopped within the probe's time"; else failed "took $((SECONDS - hang_started)) s"; fi
prints err "driver: the launcher ($work/launcher-hangs/h2s-shell) did not answer within 1 s when asked which qs it runs — does it honour H2S_SHELL_DIR? (or set LOCKTEST_QS)"
silent_on out "qs="
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
prints out "launcher_from="
silent_on out "launcher:"
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
prints out "NOTE: the pinned Hyprland (Hyprland 0.57.1 built from branch v0.57.1) is not the system's (Hyprland 0.50.0 built from branch v0.50.0): move the pin in tools.nix"

# The whole line counts: the same number from another commit is another Hyprland
resolve hyprland-commit unit "base session nix hyprland-commit qs"
exits 0
prints out "NOTE: the pinned Hyprland (Hyprland 0.57.1 built from branch v0.57.1) is not the system's (Hyprland 0.57.1 built from another commit): move the pin in tools.nix"

resolve hyprland-same unit "base session nix hyprland-same qs"
exits 0
silent_on out "NOTE"

# One that prints a line without a number is still compared; one that prints nothing cannot be
resolve hyprland-no-number unit "base session nix-mute-hyprland hyprland qs"
exits 0
prints out "NOTE: the pinned Hyprland (no number here) is not the system's (Hyprland 0.50.0 built from branch v0.50.0): move the pin in tools.nix"

resolve hyprland-unreadable unit "base session nix hyprland-silent qs"
exits 0
prints out "NOTE: cannot compare the pinned Hyprland (Hyprland 0.57.1 built from branch v0.57.1) with the system's (version unknown)"

resolve hyprland-system unit "base session system hyprland qs"
exits 0
silent_on out "NOTE"

# ---- The lock need ---
resolve lock-nix lock "base session nix launcher"
exits 0
prints out "$nix_tools_line, Hyprland 0.57.1"
prints out "launcher: $work/launcher/h2s-shell (h2s-shell on PATH)"
prints out "launcher=$work/launcher/h2s-shell"
prints out "launcher_from=path"
prints out "qs=$work/launcher-qs/qs"
silent_on out "made="

# The whole pinned set is asked for
resolve lock-partial lock "base session nix-partial qs" LOCKTEST_QS="$work/given/qs"
exits 2
prints err "$missing_header_nix"
prints err "  the pinned tool set ($work/store/bbbbbbbb-h2s-locktest-tools) lacks bin/grim (screenshots of the lock screen)"
prints err "  the pinned tool set ($work/store/bbbbbbbb-h2s-locktest-tools) lacks share/keymaps (the layouts the virtual keyboard sends)"
hands_over_nothing

# ---- The lock need, with the system's tools ---
system_lock="base session system hyprland lockset wlr-randr python xkbcli pkg-config"
system_lock_line="$system_tools_line, Hyprland 0.50.0"
protocols=$REPO/tests/lock/protocols

# Chosen although nix is there: every program from PATH, and the set made for the run —
# links to those programs, the bindings by pywayland's scanner from the four protocol files
# (the two kept here among them), the three keymaps by the options tools.nix gives xkbcli
resolve lock-system lock "$system_lock nix launcher" H2S_TEST_TOOLS=system "${hostile[@]}"
exits 0
prints out "$system_lock_line"
prints out "source=system"
prints out "made=$made"
not_called nix
for name in labwc setpriv; do is "bin/$name is the system's" test "$(readlink "$made/bin/$name")" = "$work/system/$name"; done
is "bin/Hyprland is the system's" test "$(readlink "$made/bin/Hyprland")" = "$work/hyprland/Hyprland"
for name in hyprctl grim dbus-daemon gdbus wl-copy wl-paste; do
    is "bin/$name is the system's" test "$(readlink "$made/bin/$name")" = "$work/lockset/$name"
done
is "bin/wlr-randr is the system's" test "$(readlink "$made/bin/wlr-randr")" = "$work/wlr-randr/wlr-randr"
is "bin/python3 is the system's" test "$(readlink "$made/bin/python3")" = "$work/python/python3"
is "bin/xkbcli is the system's" test "$(readlink "$made/bin/xkbcli")" = "$work/xkbcli/xkbcli"
is "bin/ holds the twelve programs of tools.nix, no more" test "$(ls "$made/bin" | wc -l)" = 12
has_line python.calls "-I -c import pywayland.client, pywayland.scanner"
has_line python.calls "-I -B -m pywayland.scanner -o $made/share/ltproto -i $work/pkgdata/wayland/wayland.xml $protocols/virtual-keyboard-unstable-v1.xml $protocols/wlr-virtual-pointer-unstable-v1.xml $work/pkgdata/wayland-protocols/stable/xdg-shell/xdg-shell.xml"
is "the two protocol files kept here are there" test -s "$protocols/virtual-keyboard-unstable-v1.xml" -a -s "$protocols/wlr-virtual-pointer-unstable-v1.xml"
is "share/ltproto holds what the scanner wrote" test -f "$made/share/ltproto/wayland.py"
is "share/ltproto is a Python package" test -f "$made/share/ltproto/__init__.py"
has_line xkbcli.calls "compile-keymap --rules evdev --model pc105 --layout us"
has_line xkbcli.calls "compile-keymap --rules evdev --model pc105 --layout us --variant intl"
has_line xkbcli.calls "compile-keymap --rules evdev --model pc105 --layout us --options compose:ralt"
is "share/keymaps/us.xkb is the plain layout" test "$(cat "$made/share/keymaps/us.xkb")" = "keymap for: compile-keymap --rules evdev --model pc105 --layout us"
is "share/keymaps/us-intl.xkb is the international one" test "$(cat "$made/share/keymaps/us-intl.xkb")" = "keymap for: compile-keymap --rules evdev --model pc105 --layout us --variant intl"
is "share/keymaps/us-compose.xkb has the Compose key" test "$(cat "$made/share/keymaps/us-compose.xkb")" = "keymap for: compile-keymap --rules evdev --model pc105 --layout us --options compose:ralt"
is "share/us.xkb is the plain layout too" cmp "$made/share/us.xkb" "$made/share/keymaps/us.xkb"
is "the set holds bin and share only" test "$(ls -A "$made" | tr '\n' ' ')" = "bin share "
# What makes the set gets nothing of the session, and no home of the user's (an XKB config
# there would change the keymaps)
for asked in python xkbcli; do
    for variable in WAYLAND_DISPLAY DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS HYPRLAND_INSTANCE_SIGNATURE; do
        lacks_variable "$asked.env" "$variable"
    done
    has_line "$asked.env" "HOME=$made/home"
done
lacks_variable python.env PKG_CONFIG_PATH

# Where the caller keeps pkg-config's files elsewhere (PKG_CONFIG_PATH), the scanner is told
# too: it asks pkg-config for the core protocol
resolve lock-system-pkg-config-path lock "$system_lock launcher" PKG_CONFIG_PATH="$work/pkgconfig-elsewhere"
exits 0
prints out "made=$made"
has_line python.env "PKG_CONFIG_PATH=$work/pkgconfig-elsewhere"
lacks_variable xkbcli.env PKG_CONFIG_PATH

# Found, there being no nix
resolve lock-no-nix lock "$system_lock launcher"
exits 0
prints out "$system_lock_line"
prints out "source=system"
prints out "made=$made"

# What is missing, all at once: a program; pywayland for the python3 that is there; the
# protocol files where pkg-config says they are. Nothing is made
resolve lock-system-partial lock "base session system hyprland lockset python-bare xkbcli pkg-config-empty launcher"
exits 2
prints err "$missing_header_system"
prints err "  wlr-randr not found on PATH (sets the headless output's size)"
prints err "  pywayland cannot be imported by $work/python-bare/python3 (the Python module the virtual keyboard and pointer speak Wayland with, and its scanner)"
prints err "  wayland.xml not found where pkg-config says wayland-scanner keeps it (a protocol file the input bindings are generated from)"
prints err "  xdg-shell.xml not found where pkg-config says wayland-protocols keeps it (a protocol file the input bindings are generated from)"
silent_on err "labwc"
hands_over_nothing
silent_on out "made="
is "nothing was made" test ! -e "$made"

# Nothing of the lock bed's there: each program named, and nothing asked of those missing
resolve lock-system-bare lock "base session system qs"
exits 2
prints err "$missing_header_system"
prints err "  Hyprland not found on PATH (the compositor the lock screen is tested in)"
prints err "  hyprctl not found on PATH (the compositor the lock screen is tested in)"
prints err "  grim not found on PATH (screenshots of the lock screen)"
prints err "  python3 not found on PATH (the virtual keyboard and pointer)"
prints err "  xkbcli not found on PATH (tells the virtual keyboard which keys type a character)"
prints err "  dbus-daemon not found on PATH (a private session bus for the notification tests)"
prints err "  gdbus not found on PATH (a private session bus for the notification tests)"
prints err "  wl-copy not found on PATH (the primary selection of the paste test)"
prints err "  wl-paste not found on PATH (the primary selection of the paste test)"
prints err "  wlr-randr not found on PATH (sets the headless output's size)"
prints err "  pkg-config not found on PATH (finds the Wayland protocol files the input bindings are generated from)"
silent_on err "pywayland"
silent_on err ".xml"
silent_on err "labwc"
hands_over_nothing

# A set that cannot be made is a set-up error, with what the tool said
resolve lock-scanner-fails lock "base session system hyprland lockset wlr-randr python-no-scanner xkbcli pkg-config launcher"
exits 2
prints err "the stand-in scanner failed"
prints err "driver: pywayland's scanner could not generate the input protocol bindings (output above)"
silent_on out "made="

resolve lock-keymap-fails lock "base session system hyprland lockset wlr-randr python xkbcli-failing pkg-config launcher"
exits 2
prints err "the stand-in xkbcli failed"
prints err "driver: xkbcli could not compile the us keymap (output above)"
silent_on out "made="

# … and so is a keymap that came out empty
resolve lock-keymap-empty lock "base session system hyprland lockset wlr-randr python xkbcli-silent pkg-config launcher"
exits 2
prints err "driver: xkbcli could not compile the us keymap (output above)"
silent_on out "made="

# The set is made for the lock need with the system's tools only: asked for with the unit
# need, or with the pinned tools, it is refused and nothing is made
resolve make-for-unit unit "base session system qs" MAKE_ANYWAY=1
exits 2
prints err "driver: make_system_tools is for the lock need with the system's tools"
silent_on out "made="
is "nothing was made" test ! -e "$made"

resolve make-with-nix lock "base session nix launcher" MAKE_ANYWAY=1
exits 2
prints err "driver: make_system_tools is for the lock need with the system's tools"
silent_on out "made="
is "nothing was made" test ! -e "$made"

# ---- The launcher of the lock need ---
# The one named, before the h2s-shell on PATH
resolve lock-launcher-given lock "$system_lock launcher" LOCKTEST_LAUNCHER="$work/launcher-given/h2s-shell"
exits 0
prints out "launcher: $work/launcher-given/h2s-shell (LOCKTEST_LAUNCHER)"
prints out "launcher=$work/launcher-given/h2s-shell"
prints out "launcher_from=given"
prints out "qs=$work/given/qs"
not_called launcher

# No h2s-shell command: the test bed's own launcher (the real one is run here), said to be
# a stand-in, and asked like any other which qs it runs — the one on PATH
resolve lock-launcher-stand-in lock "$system_lock quickshell qs"
exits 0
prints out "$stand_in_launcher_line"
prints out "launcher=$stand_in_launcher"
prints out "launcher_from=stand-in"
prints out "quickshell: $work/qs/qs 0.0.1 (asked of the launcher $stand_in_launcher)"
prints out "qs=$work/qs/qs"

# … with the pinned tools too: the launcher does not follow the tools' source
resolve lock-nix-launcher-stand-in lock "base session nix qs"
exits 0
prints out "source=nix"
prints out "$stand_in_launcher_line"
prints out "launcher_from=stand-in"
prints out "qs=$work/qs/qs"

# … and a Quickshell that is given does not do away with it: the shell is started through one
resolve lock-given-qs lock "$system_lock qs" LOCKTEST_QS="$work/given/qs"
exits 0
prints out "$stand_in_launcher_line"
prints out "quickshell: $work/given/qs 0.0.3 (LOCKTEST_QS)"

# The stand-in has no Quickshell of its own: none on PATH is an error
resolve lock-launcher-stand-in-no-qs lock "$system_lock"
exits 2
prints err "driver: the launcher ($stand_in_launcher) did not name an executable qs (status 1, said: ''); set LOCKTEST_QS"
silent_on out "qs="

# ---- The test bed's launcher itself ---
# What the packaged launcher does with H2S_SHELL_DIR set: that checkout's launch.sh, with
# the arguments as given and its exit status; without H2S_SHELL_DIR nothing is started
case_name=launcher-sh
mkdir -p "$work/checkout/scripts"
stand_in checkout/scripts/launch.sh "printf '%s\n' \"\$@\" > '$work/launch.arguments'" "exit 7"
env -i PATH="$work/base" H2S_SHELL_DIR="$work/checkout" "$stand_in_launcher" ipc call "two words" \
    > "$work/$case_name.out" 2> "$work/$case_name.err" < /dev/null
status=$?
exits 7
is "launch.sh got the arguments as given" test "$(cat "$work/launch.arguments")" = $'ipc\ncall\ntwo words'
rm -f "$work/launch.arguments"
env -i PATH="$work/base" "$stand_in_launcher" > "$work/$case_name.out" 2> "$work/$case_name.err" < /dev/null
status=$?
exits 2
prints err "launcher.sh: H2S_SHELL_DIR is not set: this launcher only runs the checkout it is pointed at"
is "nothing was started" test ! -e "$work/launch.arguments"

# The unit need does not look at the lock bed's parts
resolve unit-partial unit "base session nix-partial qs"
exits 0
prints out "source=nix"

# ---- The pinned set's path, remembered ---
# Against a copy of tests/lock, so that its inputs can be changed. Each group of cases has a
# cache directory of its own
lock_directory=$work/lock-copy
mkdir -p "$lock_directory" && cp -a "$REPO/tests/lock/resolve.sh" "$REPO/tests/lock/tools.nix" "$REPO/tests/lock/protocols" \
    "$REPO/tests/lock/launcher.sh" "$lock_directory/" || { echo "resolve-selftest.sh: cannot copy tests/lock" >&2; exit 2; }
nix_path="base session nix system qs"
remembered_line="tools: nix (tests/lock/tools.nix, pinned: $store, remembered from an earlier run) — labwc 1.2.3, setpriv 4.5.6"
# remembered <cache directory>: the paths remembered there, one per file
remembered() { cat "$1"/h2s-shell-tests/tools-nix-* 2> /dev/null; }

# Nothing remembered: nix is asked, and its answer written down — one file, no other left
resolve cache-first unit "$nix_path" XDG_CACHE_HOME="$work/cache"
exits 0
called nix
prints out "resolving tools (tools.nix)…"
prints out "$nix_tools_line"
is "the path is remembered" test "$(remembered "$work/cache")" = "$store"
is "one file in the cache directory, no other" test "$(ls -A "$work/cache/h2s-shell-tests" | wc -l)" = 1

# Remembered: nix is not asked, and the run says where the path came from
resolve cache-hit unit "$nix_path" XDG_CACHE_HOME="$work/cache"
exits 0
not_called nix
silent_on out "resolving tools"
prints out "$remembered_line"
prints out "tools=$store"
prints out "labwc=$store/bin/labwc"

# … for the lock need too, whose whole set the path holds
resolve cache-hit-lock lock "base session nix launcher" XDG_CACHE_HOME="$work/cache"
exits 0
not_called nix
prints out "$remembered_line, Hyprland 0.57.1"

# Asked to, nix is asked whatever is remembered
resolve cache-bypassed unit "$nix_path" XDG_CACHE_HOME="$work/cache" H2S_TEST_TOOLS_CACHE=0
exits 0
called nix
prints out "$nix_tools_line"

# Without XDG_CACHE_HOME the file is under the home directory's .cache
resolve cache-home unit "$nix_path" HOME="$work/cache-home"
exits 0
called nix
is "the path is remembered under HOME" test "$(remembered "$work/cache-home/.cache")" = "$store"
resolve cache-home-hit unit "$nix_path" HOME="$work/cache-home"
exits 0
not_called nix

# A file tools.nix names has changed: another build, nix is asked
echo "<!-- changed -->" >> "$lock_directory/protocols/virtual-keyboard-unstable-v1.xml"
resolve cache-input-changed unit "$nix_path" XDG_CACHE_HOME="$work/cache"
exits 0
called nix
prints out "$nix_tools_line"
resolve cache-input-changed-hit unit "$nix_path" XDG_CACHE_HOME="$work/cache"
exits 0
not_called nix
# … and so when tools.nix itself has
echo "# changed" >> "$lock_directory/tools.nix"
resolve cache-tools-nix-changed unit "$nix_path" XDG_CACHE_HOME="$work/cache"
exits 0
called nix
# … and a file it names that is not there: nothing is remembered at all
echo "# ./protocols/not-there.xml" >> "$lock_directory/tools.nix"
resolve cache-input-missing unit "$nix_path" XDG_CACHE_HOME="$work/cache-missing"
exits 0
called nix
is "nothing is remembered" test ! -e "$work/cache-missing"
cp "$REPO/tests/lock/tools.nix" "$lock_directory/tools.nix"

# The remembered path is gone (the store was cleaned): nix is asked, its answer remembered
cp -a "$store" "$work/store/eeeeeeee-h2s-locktest-tools"
nix_stand_in nix-other "$work/store/eeeeeeee-h2s-locktest-tools"
resolve cache-other unit "base session nix-other system qs" XDG_CACHE_HOME="$work/cache-gone"
exits 0
is "the path is remembered" test "$(remembered "$work/cache-gone")" = "$work/store/eeeeeeee-h2s-locktest-tools"
rm -r "$work/store/eeeeeeee-h2s-locktest-tools"
resolve cache-path-gone unit "$nix_path" XDG_CACHE_HOME="$work/cache-gone"
exits 0
called nix
prints out "$nix_tools_line"
prints out "tools=$store"
is "the new path is remembered" test "$(remembered "$work/cache-gone")" = "$store"

# The remembered path lacks what this caller needs (remembered by the unit need, which a
# set without grim and the keymaps serves; asked for by the lock need): nix is asked
resolve cache-partial unit "base session nix-partial system qs" XDG_CACHE_HOME="$work/cache-partial"
exits 0
is "the partial set is remembered" test "$(remembered "$work/cache-partial")" = "$work/store/bbbbbbbb-h2s-locktest-tools"
resolve cache-partial-unit unit "$nix_path" XDG_CACHE_HOME="$work/cache-partial"
exits 0
not_called nix
prints out "tools=$work/store/bbbbbbbb-h2s-locktest-tools"
resolve cache-partial-lock lock "base session nix launcher" XDG_CACHE_HOME="$work/cache-partial"
exits 0
called nix
prints out "$nix_tools_line, Hyprland 0.57.1"
is "the whole set is remembered" test "$(remembered "$work/cache-partial")" = "$store"

# A set that lacks what the caller needs is not remembered
resolve cache-lacking lock "base session nix-partial qs" XDG_CACHE_HOME="$work/cache-lacking" LOCKTEST_QS="$work/given/qs"
exits 2
is "nothing is remembered" test -z "$(remembered "$work/cache-lacking")"

# What is remembered is not a path: nix is asked
mkdir -p "$work/cache-junk/h2s-shell-tests"
for file in "$work/cache"/h2s-shell-tests/tools-nix-*; do echo "not a path" > "$work/cache-junk/h2s-shell-tests/$(basename "$file")"; done
resolve cache-junk unit "$nix_path" XDG_CACHE_HOME="$work/cache-junk"
exits 0
called nix
prints out "tools=$store"

# The system's tools: nothing is remembered, nothing remembered is read
resolve cache-system unit "$nix_path" XDG_CACHE_HOME="$work/cache-system" H2S_TEST_TOOLS=system
exits 0
prints out "$system_tools_line"
is "nothing is remembered" test ! -e "$work/cache-system"
lock_directory=$REPO/tests/lock

# ---- The lock bed's lock for the machine (tests/lock/run.sh) ---
# The real run.sh, on a lock file of this script's own, with a TMPDIR it refuses: that is
# its first check after the lock, so the run ends there, having started nothing (status 2).
bed_lock=$work/bed.flock
refusal="run.sh: TMPDIR (/tmp/not a plain path) must be an absolute path of letters, digits and ._/+- only"
# bed <case> [wrapper…]: run.sh in the background, as $bed_pid
bed() {
    case_name=$1
    shift
    "$@" env -i PATH="$work/base:$work/session:$work/bed" LOCKTEST_LOCK_FILE="$bed_lock" TMPDIR="/tmp/not a plain path" \
        "$REPO/tests/lock/run.sh" -j 1 > "$work/$case_name.out" 2> "$work/$case_name.err" < /dev/null &
    bed_pid=$!
}
# bed_ends: waits for it (the wrappers below end a run that hangs), its status in $status
bed_ends() { wait "$bed_pid"; status=$?; }
# holder: a process of another "run" holding the lock, as $holder_pid (one process: the lock
# goes when it is killed); back when it has it
holder() {
    (flock 9 && exec sleep 60) 9< "$bed_lock" &
    holder_pid=$!
    for _ in $(seq 1 100); do flock -n "$bed_lock" true 2> /dev/null || return 0; sleep 0.05; done
    echo "resolve-selftest.sh: the stand-in run did not take $bed_lock" >&2
    exit 2
}
# waiting_said: the run has printed that it waits (within 10 s)
waiting_line="run.sh: waiting for another run of the lock test bed to end ($bed_lock)…"
waiting_said() {
    for _ in $(seq 1 200); do grep -q -x -F -- "$waiting_line" "$work/$case_name.out" 2> /dev/null && return 0; sleep 0.05; done
    return 1
}
# still_running: it has not ended a moment later
still_running() { sleep 0.3; kill -0 "$bed_pid" 2> /dev/null; }

# Nobody has the lock: taken without a word
bed bed-lock-free timeout 20
bed_ends
exits 2
prints err "$refusal"
silent_on out "waiting"

# Another run has it: this one says so, once, and waits; it goes on when the other ends
holder
bed bed-lock-held timeout 20
is "says that it waits for another run" waiting_said
is "waits" still_running
silent_on err "TMPDIR"
kill "$holder_pid" 2> /dev/null
wait "$holder_pid" 2> /dev/null
bed_ends
exits 2
prints err "$refusal"
is "said so once" test "$(grep -c -F -- "waiting" "$work/$case_name.out")" = 1

# The caller wrapped the run in flock on the same file: the run does not wait for its caller
bed bed-lock-wrapped timeout 20 flock "$bed_lock"
bed_ends
exits 2
prints err "$refusal"
silent_on out "waiting"

# Interrupted while it waits: ends at once, and the lock is the other run's to give up.
# (Signalled itself, not through `timeout`, which would signal the flock it waits in too; a
# run that does not end is ended by the stand-in run's own end, a minute later)
holder
bed bed-lock-interrupted
is "says that it waits for another run" waiting_said
kill -TERM "$bed_pid" 2> /dev/null
interrupted_at=$SECONDS
bed_ends
exits 130
if [ $((SECONDS - interrupted_at)) -le 5 ]; then pass "ended at once"; else failed "took $((SECONDS - interrupted_at)) s to end"; fi
kill "$holder_pid" 2> /dev/null
wait "$holder_pid" 2> /dev/null
is "the lock is free again" flock -n "$bed_lock" true

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
