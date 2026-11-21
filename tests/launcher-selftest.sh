#!/usr/bin/env bash
# Checks the supervisor in scripts/launch.sh — what it does when the shell it started is
# killed, stopped, quits, or when it is signalled itself — against a stand-in `qs` (a script
# that notes its pid and sleeps, or exits as told). The launcher is the real one, run with
# an empty environment, a runtime dir, home and "compositor socket" of this script's own,
# and a PATH that holds only the plain utilities it calls and the stand-in.
#
# The case it is here for: bash's `wait -f` reads the record of a child killed by a signal
# after freeing it (bash 5.3, jobs.c, wait_for_single_pid), and when that memory reads as
# "alive" it never returns — it prints "wait_for: No record of process" without end, and
# the shell is never started again. Whether it does depends on what the heap holds:
# GLIBC_TUNABLES (no thread cache, freed memory filled with 0x7f) makes it likelier with
# glibc's malloc, and the "killed" case runs a row of supervisors that differ in the length
# of one environment variable.
#
# What the run shows, and says: a probe tells whether this bash has the defect at all; a
# row of control supervisors — a copy of launch.sh with `wait -f` put back — tells whether
# the "killed" case can see it on this machine (how many of them spun). Where none did, the
# "killed" case is only that a killed shell is started again, and the "stopped" case is the
# one that fails on `wait -f`: there it spins on every machine.
#
# Last, the module search's built-in root (H2S_SHELL_BUILTIN_MODULES, and its default when
# unset), through `launch.sh --discover-modules`.
#
#   tests/launcher-selftest.sh
#
# Nothing real is started: no compositor, no Quickshell. It needs bash, coreutils, grep,
# sed, awk, util-linux's flock, and a python3 or perl (to make a socket file), so it runs
# the same on NixOS and on Arch. It takes no lock: nothing of it is shared with another run.
#
# Exit status: 0 when every check passed, 1 when one failed, 2 when it could not be set up.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/launcher-self.XXXXXX") || exit 2
bash_path=$(type -P bash)
failures=0
tunables=glibc.malloc.tcache_count=0:glibc.malloc.perturb=127

# A process this script started (the launcher, a stand-in shell): it carries the marker
ours() { [ -r "/proc/$1/environ" ] && tr '\0' '\n' < "/proc/$1/environ" 2> /dev/null | grep -qxF "LAUNCHER_SELFTEST=$work"; }
signal() { ours "$2" && kill -s "$1" "$2" 2> /dev/null; }
clean_up() {
    local pid
    for pid in $(cat "$work/launchers" "$work"/*/starts 2> /dev/null); do
        signal CONT "$pid"
        signal KILL "$pid"
    done
    rm -rf "$work"
}
trap clean_up EXIT

pass() { echo "    PASS $1"; }
failed() { echo "    FAIL $1"; failures=$((failures + 1)); }
is() { local description=$1; shift; if "$@"; then pass "$description"; else failed "$description"; fi; }
wait_until() {
    local deadline=$((SECONDS + $1))
    shift
    until "$@"; do
        [ "$SECONDS" -lt "$deadline" ] || return 1
        sleep 0.05
    done
}
within() { local seconds=$1 description=$2; shift 2; if wait_until "$seconds" "$@"; then pass "$description"; else failed "$description (not within $seconds s)"; fi; }

# ---- The fabricated PATH: the utilities launch.sh calls, the real ones, and the stand-in ---
mkdir -p "$work/bin" "$work/home" "$work/data"
for name in bash env dirname readlink id date stat mv flock awk sed timeout sleep tr grep head basename cat rm find cksum sort; do
    real=$(type -P "$name") || { echo "launcher-selftest.sh: $name not found on PATH (launch.sh calls it)" >&2; exit 2; }
    ln -s "$real" "$work/bin/$name"
done
# The shell: notes its pid in its supervisor's directory (and the notice it was handed,
# H2S_SHELL_LOCK_NOTICE, or "unset", in `notices`), then does what the file `mode`
# there says — "run" (it sleeps), "exit <status>", or "hangup-and-die" (once: it sends its
# supervisor SIGHUP and is killed at the same moment; the next one runs). It sleeps for a
# minute, more than any case takes: one that clean_up missed (its launcher killed before it
# wrote its pid) does not stay for long.
{
    echo "#!$bash_path"
    echo 'echo $$ >> "$LAUNCHER_SELFTEST_DIR/starts"'
    echo 'echo "${H2S_SHELL_LOCK_NOTICE-unset}" >> "$LAUNCHER_SELFTEST_DIR/notices"'
    echo 'read -r what status < "$LAUNCHER_SELFTEST_DIR/mode"'
    echo '[ "$what" = exit ] && exit "$status"'
    echo 'if [ "$what" = hangup-and-die ]; then'
    echo '    echo run > "$LAUNCHER_SELFTEST_DIR/mode"'
    echo '    kill -HUP "$PPID"'
    echo '    kill -KILL $$'
    echo 'fi'
    echo "exec '$work/bin/sleep' 60"
} > "$work/bin/qs"
chmod +x "$work/bin/qs"

# The "compositor": a socket file (the launcher only looks at it)
socket=$work/wayland-selftest
if type -P python3 > /dev/null; then
    python3 -I -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$socket"
elif type -P perl > /dev/null; then
    perl -MIO::Socket::UNIX -e 'IO::Socket::UNIX->new(Local => $ARGV[0], Listen => 1) or exit 1' "$socket"
fi
[ -S "$socket" ] || { echo "launcher-selftest.sh: cannot make a socket file (python3 or perl makes it)" >&2; exit 2; }

# ---- Has this bash the defect? `wait -f` on a killed child, with the tunables ---
printf 'set -m\n%s 5 &\nchild=$!\n(%s 0.05; kill -KILL $child) &\nwait -f $child\n' "$work/bin/sleep" "$work/bin/sleep" > "$work/probe.sh"
env -i "GLIBC_TUNABLES=$tunables" "$work/bin/timeout" 1 "$bash_path" "$work/probe.sh" 2>&1 | head -n 5 > "$work/probe.out"
if grep -q 'No record of process' "$work/probe.out"; then
    echo "bash ${BASH_VERSION}: a probe's wait -f did not return after a killed child (with $tunables)"
else
    echo "bash ${BASH_VERSION}: a probe's wait -f returned after a killed child (with $tunables):"
    echo "    not glibc's malloc, a bash without the defect, or a heap that hid it"
fi

# ---- The launcher under test: a copy of scripts/launch.sh beside the test bed's seams.sh
# (tests/lock/seams/), as in the lock bed's test tree: the checkout's own seams.sh is
# constants, and the cases need the first pause shortened (H2S_LAUNCHER_TEST_TIMINGS)
mkdir -p "$work/tree/scripts"
cp "$REPO/scripts/launch.sh" "$work/tree/scripts/launch.sh" \
    && cp "$REPO/tests/lock/seams/seams.sh" "$work/tree/scripts/seams.sh" \
    || { echo "launcher-selftest.sh: cannot copy the launcher and the test seams.sh" >&2; exit 2; }
launch_script=$work/tree/scripts/launch.sh

# ---- The control: launch.sh with `wait -f` put back, to see what the "killed" case can catch
mkdir -p "$work/control/scripts"
cp "$REPO/tests/lock/seams/seams.sh" "$work/control/scripts/seams.sh" \
    || { echo "launcher-selftest.sh: cannot copy the test seams.sh" >&2; exit 2; }
control_script=$work/control/scripts/launch.sh
sed 's/^        wait "\$child"$/        wait -f "$child"/' "$REPO/scripts/launch.sh" > "$control_script"
if [ "$(grep -c '^        wait -f "\$child"$' "$control_script")" != 1 ] \
    || [ "$(diff "$REPO/scripts/launch.sh" "$control_script" | grep -c '^[<>]')" != 2 ]; then
    # (Counted as a failure, and the cases still run: they say what the launcher does)
    failed "the control supervisor cannot be made: the line \`wait \"\$child\"\` of wait_for_shell is not in scripts/launch.sh once"
    control_script=""
fi

# ---- Supervisors -------------------------------------------------------------------------
# start_launcher <name> [<padding>] [<script>]: a supervisor with a directory of its own ($work/<name>:
# its runtime dir `run`, its shell's `starts` and `mode`, its output `output`), and what the
# helpers below then speak of. Its output is a file of at most 2 MB: a supervisor that
# prints without end is killed by that limit (SIGXFSZ), not left to fill the disk.
at=""
launcher=""
start_launcher() {
    at=$work/$1
    mkdir -p "$at/run"
    : > "$at/starts"
    : > "$at/notices"
    echo run > "$at/mode"
    (
        ulimit -f 2048
        # SIGHUP reset: a run started with it ignored (nohup, a detached ssh) would hand that on,
        # and bash cannot trap a signal ignored at its start
        exec env --default-signal=HUP -i "PATH=$work/bin" "HOME=$work/home" "XDG_RUNTIME_DIR=$at/run" "XDG_CONFIG_HOME=$work/home/config" \
            "XDG_DATA_HOME=$work/data" "XDG_DATA_DIRS=$work/data" "H2S_SHELL_MODULE_DATA_DIRS=" \
            "WAYLAND_DISPLAY=$socket" "H2S_LAUNCHER_TEST_TIMINGS=first=0.1" "LAUNCHER_SELFTEST=$work" \
            "LAUNCHER_SELFTEST_DIR=$at" "LAUNCHER_SELFTEST_PADDING=${2:-}" "GLIBC_TUNABLES=$tunables" \
            "$bash_path" "${3:-$launch_script}" > "$at/output" 2>&1 < /dev/null
    ) &
    launcher=$!
    # (Not a job of this script's: bash would report each one killed below)
    disown "$launcher"
    echo "$launcher" >> "$work/launchers"
}
starts() { grep -c . "$at/starts"; }
started() { [ "$(starts)" -ge "$1" ]; }
shell_pid() { tail -n 1 "$at/starts"; }
said() { grep -qF -- "$1" "$at/output"; }
said_times() { grep -cF -- "$1" "$at/output"; }
gone() { [ ! -e "/proc/$1" ]; }
state_of() { local stat; stat=$(cat "/proc/$1/stat" 2> /dev/null) || return 1; stat=${stat##*) }; echo "${stat%% *}"; }
# Processor time the process itself has used (not its children), in clock ticks
ticks_of() { local stat; stat=$(cat "/proc/$1/stat" 2> /dev/null) || { echo 0; return; }; stat=${stat##*) }; set -- $stat; echo $((${12} + ${13})); }
up() { wait_until 10 started 1 || { echo "launcher-selftest.sh: the launcher did not start the stand-in shell:" >&2; cat "$at/output" >&2; exit 2; }; }

# ---- (1) A killed shell is started again, and the launcher says little ---
layouts=16
# start_row <name> [<script>]: $layouts supervisors, $work/<name>1 …, each with another
# heap layout, and each one's shell killed once it runs
start_row() {
    local layout
    for layout in $(seq 1 "$layouts"); do
        start_launcher "$1$layout" "$(printf '%*s' "$layout" '' | tr ' ' x)" "${2:-}"
        echo "$launcher" >> "$work/$1.launchers"
    done
    for layout in $(seq 1 "$layouts"); do
        at=$work/$1$layout
        up
        signal KILL "$(shell_pid)"
    done
}
# end_row <name>: its supervisors and their shells, killed
end_row() {
    local layout
    for layout in $(seq 1 "$layouts"); do
        signal KILL "$(sed -n "${layout}p" "$work/$1.launchers")"
        at=$work/$1$layout
        signal KILL "$(shell_pid)"
    done
}
echo "== killed ($layouts supervisors, each with another heap layout)"
start_row layout
restarted=0 lost=0 lines=0
for layout in $(seq 1 "$layouts"); do
    at=$work/layout$layout
    wait_until 5 started 2 && said "the shell exited (status 137): starting it again" && restarted=$((restarted + 1))
    said "No record of process" && lost=$((lost + 1))
    count=$(grep -c . "$at/output")
    [ "$count" -le "$lines" ] || lines=$count
done
is "a killed shell is started again, its status known ($restarted of $layouts)" test "$restarted" = "$layouts"
is "bash never lost the child (\"No record of process\": $lost of $layouts)" test "$lost" = 0
is "the launcher's output stayed small (at most $lines lines)" test "$lines" -le 20
end_row layout

# The control row (names as long as the row's above: the same environment, but for the
# script's path): which of them spin is what the checks above could have caught
[ -z "$control_script" ] || start_row contrl "$control_script"
settled() { started 2 || said "No record of process"; }
spun=0 unsettled=0
deadline=$((SECONDS + 5))
for layout in $([ -z "$control_script" ] || seq 1 "$layouts"); do
    at=$work/contrl$layout
    remaining=$((deadline - SECONDS))
    wait_until "$((remaining > 0 ? remaining : 0))" settled
    if said "No record of process"; then
        spun=$((spun + 1))
    elif ! started 2; then
        unsettled=$((unsettled + 1))
    fi
done
[ -z "$control_script" ] || end_row contrl
if [ -z "$control_script" ]; then
    echo "    NOTE control: none was run: what the checks above can catch on this machine is not known"
elif [ "$spun" -gt 0 ]; then
    echo "    control: with wait -f put back, $spun of $layouts supervisors spun (\"No record of process\"):"
    echo "             the checks above catch bash's defect on this machine"
else
    echo "    NOTE control: with wait -f put back, none of $layouts supervisors spun ($unsettled did not restart in time):"
    echo "             the checks above could NOT detect bash's defect on this machine — they show only"
    echo "             that a killed shell is started again. The \"stopped\" case below stands for it:"
    echo "             it fails on wait -f on every machine"
fi

# ---- (2) A stopped shell is left alone, without the supervisor spinning ---
echo "== stopped"
start_launcher stopped
up
stopped=$(shell_pid)
ticks_before=$(ticks_of "$launcher")
signal STOP "$stopped"
sleep 3
ticks=$(($(ticks_of "$launcher") - ticks_before))
is "a stopped shell is left alone" test "$(state_of "$stopped")" = T
is "… no other was started" test "$(shell_pid)" = "$stopped"
is "… the supervisor did not spin meanwhile ($ticks of some $((3 * $(getconf CLK_TCK))) clock ticks)" test "$ticks" -le $((3 * $(getconf CLK_TCK) / 5))
is "… it said so, once" test "$(said_times 'is stopped: left alone')" = 1
signal CONT "$stopped"
signal HUP "$launcher"
within 3 "SIGHUP to the supervisor: it says so" said "SIGHUP (the terminal it was started from closed?)"
is "… and the shell runs on" test "$(state_of "$stopped")" = S -a "$(shell_pid)" = "$stopped"
signal KILL "$stopped"
within 5 "killed after it ran on: started again" started 2
within 3 "… with its status known" said "the shell exited (status 137)"

# ---- (3) SIGHUP that interrupts the wait just as the shell is killed: the shell's status counts
echo "== hangup as the shell dies"
before=$(starts)
echo hangup-and-die > "$at/mode"
signal KILL "$(shell_pid)"
within 5 "the shell after the one that hung up and died is started" started $((before + 2))
is "… the supervisor took the killed shell's status, not the signal's" test "$(said_times 'the shell exited (status 137)')" = 3
is "… and did not take it for stopped on purpose" test "$(said_times 'the shell was stopped')" = 0

# ---- (4) A shell that quits is not started again ---
echo "== quit"
echo "exit 0" > "$at/mode"
signal KILL "$(shell_pid)"
within 5 "a shell that quits (status 0) ends the supervisor" gone "$launcher"
is "… which said so" said "the shell quit (status 0)"
is "… after starting it that once" test "$(starts)" = 5

# ---- (5) SIGTERM to the supervisor stops the shell ---
echo "== told to stop"
start_launcher told
up
running=$(shell_pid)
signal TERM "$launcher"
within 5 "SIGTERM to the supervisor: the shell is stopped" gone "$running"
within 5 "… and the supervisor ends" gone "$launcher"
is "… without starting another" test "$(starts)" = 1

# ---- (6) Died while locked: at most 3 restarts while the session stays locked ---
# The lock marker says locked (the stand-in shell never writes it); the record of restarts
# while locked is the launcher's, overwritten by the shell at an unlock — here emptied by this script
echo "== died while locked"
start_launcher locked
up
marker=$at/run/h2s-shell-lock
record=$at/run/h2s-shell-lock-restarts
echo "locked selftest-key" > "$marker"
record_is() { [ "$(cat "$record" 2> /dev/null)" = "$1" ]; }
kill_and_restart() { local before; before=$(starts); signal KILL "$(shell_pid)"; wait_until 10 started $((before + 1)); }
kill_and_restart
is "killed while locked: started again" test "$(starts)" = 2
is "… the first restart while locked, said so" said "while the screen was locked: starting it again in 0.1 s (restart 1 of 3 while locked)"
within 3 "… and recorded" record_is 1
kill_and_restart
is "the second, recorded" record_is 2
: > "$record"

echo "    (the record emptied: an unlock, as the shell overwrites it)"
kill_and_restart
is "after an unlock the count starts afresh" test "$(said_times "(restart 1 of 3 while locked)")" = 2
is "… recorded" record_is 1
echo garbage > "$record"
kill_and_restart
is "a record that is not the launcher's count counts as an unlock" test "$(said_times "(restart 1 of 3 while locked)")" = 3
kill_and_restart
kill_and_restart
is "the third restart since the last unlock" said "(restart 3 of 3 while locked)"
is "… recorded" record_is 3
last=$(shell_pid)
signal KILL "$last"
within 10 "the fourth death while locked: not started again, the supervisor ends" gone "$launcher"
is "… which said so" said "after 3 restarts since the last unlock: not starting it again. The session stays locked."
is "… after 7 starts in all" test "$(starts)" = 7
is "… it left the notice for the next launcher" test "$(cat "$at/run/h2s-shell-lock-notice" 2> /dev/null)" = 3
is "… and removed its record" test ! -e "$record"
is "… and never touched the marker" test "$(cat "$marker")" = "locked selftest-key"
is "no notice was handed to any of those shells" test "$(grep -cx unset "$at/notices")" = 7

# The next launcher, started by hand: its first shell is handed the notice, the next not
start_launcher locked
up
is "the next launcher hands its first shell the notice" test "$(head -n 1 "$at/notices")" = 3
is "… and removed it" test ! -e "$at/run/h2s-shell-lock-notice"
is "… and said so" said "the last launcher gave up on a shell that died while the screen was locked"
kill_and_restart
is "its next shell is not handed it" test "$(sed -n 2p "$at/notices")" = unset
is "a new launcher starts a fresh count" said "(restart 1 of 3 while locked)"
echo unlocked > "$marker"
echo "exit 0" > "$at/mode"
signal KILL "$(shell_pid)"
within 5 "unlocked, a shell that quits ends the supervisor as before" gone "$launcher"

# ---- (7) Deaths under the lock are not counted as deaths outside it ---
# Three deaths while locked, an unlock, then three outside the lock within 2 minutes: six
# deaths in all, but only three outside the lock — not the crash loop that ends the launcher
echo "== deaths under the lock, then outside it"
start_launcher mixed
up
marker=$at/run/h2s-shell-lock
record=$at/run/h2s-shell-lock-restarts
echo "locked selftest-key" > "$marker"
kill_and_restart
kill_and_restart
kill_and_restart
is "three restarts while locked" said "(restart 3 of 3 while locked)"
echo unlocked > "$marker"
echo "unlocked 1" > "$record"
echo "    (unlocked: the marker says so, the record overwritten as the shell does)"
kill_and_restart
kill_and_restart
kill_and_restart
is "three deaths outside the lock after it: each started again" test "$(starts)" = 7
is "… the launcher did not give up" test "$(said_times "not starting it again")" = 0
is "… and still runs" test -e "/proc/$launcher"
running=$(shell_pid)
signal TERM "$launcher"
within 5 "stopped" gone "$running"

# ---- (8) The built-in root of the module search ---
# Unset, it is the data home's h2s-shell/builtin (where install.sh puts it on Arch); one that
# holds only builtin.json — what the package and install.sh bring while no module ships —
# finds what no built-in root finds; set, the one given; set and empty, none.
echo "== the built-in root of the module search"
discovery=$work/discovery
mkdir -p "$discovery/run" "$discovery/data/h2s-shell/modules/alpha" "$discovery/data/h2s-shell/builtin" "$discovery/package/gamma"
echo '{ "id": "alpha" }' > "$discovery/data/h2s-shell/modules/alpha/module.json"
echo '{ "off": [] }' > "$discovery/data/h2s-shell/builtin/builtin.json"
echo '{ "id": "gamma" }' > "$discovery/package/gamma/module.json"
discover() {
    env -i "PATH=$work/bin" "HOME=$work/home" "XDG_RUNTIME_DIR=$discovery/run" "XDG_DATA_HOME=$discovery/data" \
        "H2S_SHELL_MODULE_DATA_DIRS=" "$@" "$bash_path" "$launch_script" --discover-modules 2> /dev/null
}
canonical() { (cd -P "$1" && pwd); }
alpha=$(canonical "$discovery/data/h2s-shell/modules/alpha")
is "unset, with only builtin.json there: the user's module alone" test "$(discover)" = "$alpha"
is "… the same as with no built-in root" test "$(discover H2S_SHELL_BUILTIN_MODULES=)" = "$alpha"
mkdir -p "$discovery/data/h2s-shell/builtin/beta"
echo '{ "id": "beta" }' > "$discovery/data/h2s-shell/builtin/beta/module.json"
beta=$(canonical "$discovery/data/h2s-shell/builtin/beta")
is "unset: a module in the data home's h2s-shell/builtin is found, after the user's" test "$(discover)" = "$alpha:$beta"
is "set and empty: none" test "$(discover H2S_SHELL_BUILTIN_MODULES=)" = "$alpha"
is "set: the one given, not the data home's" \
    test "$(discover "H2S_SHELL_BUILTIN_MODULES=$discovery/package")" = "$alpha:$(canonical "$discovery/package/gamma")"
is "set to a relative path: none" test "$(discover H2S_SHELL_BUILTIN_MODULES=package)" = "$alpha"

echo "== the built-in copy against the checkout's builtin-modules/"
# Said once per change of the outcome, in the launcher's log; only for the data home's copy
copy_log=$discovery/run/h2s-shell-launcher.log
copy_lines() { grep -c "built-in modules: " "$copy_log" 2> /dev/null || true; }
copy_said() { grep -q "built-in modules: $discovery/data/h2s-shell/builtin $1" "$copy_log" 2> /dev/null; }
discover > /dev/null
is "without builtin-modules/ in the checkout: nothing said" test "$(copy_lines)" = 0
mkdir -p "$work/tree/builtin-modules"
cp -R "$discovery/data/h2s-shell/builtin/." "$work/tree/builtin-modules/"
discover > /dev/null
is "the copy as the checkout's: nothing said" test "$(copy_lines)" = 0
echo '{ "id": "beta", "name": "Beta" }' > "$discovery/data/h2s-shell/builtin/beta/module.json"
discover > /dev/null
discover > /dev/null
is "a file changed in the copy: said once that it differs, over two searches" test "$(copy_lines)" = 1
is "… naming the copy and install.sh --update" copy_said "differs from this checkout's builtin-modules/ (install.sh --update copies it again)"
discover "H2S_SHELL_BUILTIN_MODULES=$discovery/package" > /dev/null
is "another built-in root (the package's): not compared" test "$(copy_lines)" = 1
cp "$work/tree/builtin-modules/beta/module.json" "$discovery/data/h2s-shell/builtin/beta/module.json"
discover > /dev/null
is "the same again: said once" test "$(copy_lines)" = 2
is "… that it matches again" copy_said "matches this checkout's builtin-modules/ again"
mv "$discovery/data/h2s-shell/builtin" "$discovery/builtin-away"
discover > /dev/null
is "the copy missing: said" copy_said "is missing"
rm -r "$work/tree/builtin-modules"

echo
if [ "$failures" = 0 ]; then
    echo "launch.sh: every check passed"
else
    echo "launch.sh: $failures check(s) FAILED"
    exit 1
fi
