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
# the shell is never started again. With glibc's malloc that is one bash process in a few
# hundred; GLIBC_TUNABLES (no thread cache, freed memory filled with 0x7f) makes it most of
# them — which ones depends on what else the heap holds, so the case runs a row of
# supervisors that differ in the length of one environment variable. A bash that does not
# use glibc's malloc cannot be provoked like this: the script says which it found, and the
# case is then only that a killed shell is started again.
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
for name in bash env dirname readlink id date stat mv flock awk sed timeout sleep tr grep head basename cat rm; do
    real=$(type -P "$name") || { echo "launcher-selftest.sh: $name not found on PATH (launch.sh calls it)" >&2; exit 2; }
    ln -s "$real" "$work/bin/$name"
done
# The shell: notes its pid in its supervisor's directory, then does what the file `mode`
# there says — "run" (it sleeps) or "exit <status>"
{
    echo "#!$bash_path"
    echo 'echo $$ >> "$LAUNCHER_SELFTEST_DIR/starts"'
    echo 'read -r what status < "$LAUNCHER_SELFTEST_DIR/mode"'
    echo '[ "$what" = exit ] && exit "$status"'
    echo "exec '$work/bin/sleep' 600"
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

# ---- Can this bash be provoked? `wait -f` on a killed child, with the tunables ---
printf 'set -m\n%s 5 &\nchild=$!\n(%s 0.05; kill -KILL $child) &\nwait -f $child\n' "$work/bin/sleep" "$work/bin/sleep" > "$work/probe.sh"
env -i "GLIBC_TUNABLES=$tunables" "$work/bin/timeout" 1 "$bash_path" "$work/probe.sh" 2>&1 | head -n 5 > "$work/probe.out"
if grep -q 'No record of process' "$work/probe.out"; then
    echo "bash ${BASH_VERSION}: its wait -f never returns after a killed child, with $tunables — the supervisors run with them"
else
    echo "NOTE: bash ${BASH_VERSION}: its wait -f could not be provoked (not glibc's malloc, or a bash without the defect):"
    echo "      the first case is only that a killed shell is started again"
fi

# ---- Supervisors -------------------------------------------------------------------------
# start_launcher <name> [<padding>]: a supervisor with a directory of its own ($work/<name>:
# its runtime dir `run`, its shell's `starts` and `mode`, its output `output`), and what the
# helpers below then speak of. Its output is a file of at most 2 MB: a supervisor that
# prints without end is killed by that limit (SIGXFSZ), not left to fill the disk.
at=""
launcher=""
start_launcher() {
    at=$work/$1
    mkdir -p "$at/run"
    : > "$at/starts"
    echo run > "$at/mode"
    (
        ulimit -f 2048
        exec env -i "PATH=$work/bin" "HOME=$work/home" "XDG_RUNTIME_DIR=$at/run" "XDG_CONFIG_HOME=$work/home/config" \
            "XDG_DATA_HOME=$work/data" "XDG_DATA_DIRS=$work/data" "H2S_SHELL_MODULE_DATA_DIRS=" \
            "WAYLAND_DISPLAY=$socket" "H2S_LAUNCHER_TEST_TIMINGS=first=0.1" "LAUNCHER_SELFTEST=$work" \
            "LAUNCHER_SELFTEST_DIR=$at" "LAUNCHER_SELFTEST_PADDING=${2:-}" "GLIBC_TUNABLES=$tunables" \
            "$bash_path" "$REPO/scripts/launch.sh" > "$at/output" 2>&1 < /dev/null
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
echo "== killed ($layouts supervisors, each with another heap layout)"
for layout in $(seq 1 "$layouts"); do
    start_launcher "layout$layout" "$(printf '%*s' "$layout" '' | tr ' ' x)"
done
for layout in $(seq 1 "$layouts"); do
    at=$work/layout$layout
    up
    signal KILL "$(shell_pid)"
done
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
for layout in $(seq 1 "$layouts"); do
    signal KILL "$(sed -n "${layout}p" "$work/launchers")"
    at=$work/layout$layout
    signal KILL "$(shell_pid)"
done

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

# ---- (3) A shell that quits is not started again ---
echo "== quit"
echo "exit 0" > "$at/mode"
signal KILL "$(shell_pid)"
within 5 "a shell that quits (status 0) ends the supervisor" gone "$launcher"
is "… which said so" said "the shell quit (status 0)"
is "… after starting it that once" test "$(starts)" = 3

# ---- (4) SIGTERM to the supervisor stops the shell ---
echo "== told to stop"
start_launcher told
up
running=$(shell_pid)
signal TERM "$launcher"
within 5 "SIGTERM to the supervisor: the shell is stopped" gone "$running"
within 5 "… and the supervisor ends" gone "$launcher"
is "… without starting another" test "$(starts)" = 1

echo
if [ "$failures" = 0 ]; then
    echo "launch.sh: every check passed"
else
    echo "launch.sh: $failures check(s) FAILED"
    exit 1
fi
