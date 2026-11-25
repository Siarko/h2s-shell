#!/usr/bin/env bash
# Everything to run before committing, in one command: the general set (the same on every
# system) and the set of the system this machine runs.
#
#   tests/run-all.sh               all of it; most of the time is the lock bed
#   tests/run-all.sh --quick       without the lock bed
#   tests/run-all.sh --keep-going  go on after a part failed (the default stops there)
#   tests/run-all.sh -j <n>        at most n parts at once (default: one per processor;
#                                  -j 1 runs them one after another)
#
# The parts (each can be run alone, as written). All but the lock bed run side by side:
# each is isolated already — its own temp dirs, compositor, runtime dir and home; none takes
# a fixed path, port or lock (the tools' cache is written by rename) —, each in a process
# group of its own, its output kept in a log of its own and printed, in this order, once it
# and the parts before it have ended. The lock bed runs last and alone, its output shown as
# it goes: its scenarios time the shell, and it takes the machine-wide lock itself.
# The parts share one memory budget (tests/memory-cap.sh, H2S_TEST_MEMORY_BUDGET), made here
# and handed on in the environment: whatever they start side by side, together they never
# take more than it; it ends with this runner. A budget that holds fewer than two processes
# at the memory cap runs the parts one after another (unless -j says otherwise).
#
#   tests/run-all-selftest.sh                           this runner's own verdict
#   tests/run-system-selftest.sh                        the system runner's own verdict
#   tests/distribution-selftest.sh                      the distributions' facts as the scripts
#                                                       read them, and their detection
#   tests/install-test.sh                               install.sh under stand-ins
#   tests/run-helper.sh                                 the helper (helper/), built and run;
#                                                       its build and launch.sh's look-up
#   tests/run-unit.sh                                   the unit suites
#   tests/run-modules.sh tests/fixtures/modules/good tests/fixtures/modules/legacy-elevate
#                                                       modules' suites, on the fixtures
#   tests/run-modules.sh tests/fixtures/modules/privileged tests/fixtures/modules/privileged-undeclared
#                                                       runs as administrator, on a fixture
#                                                       (a run of its own: its suite times
#                                                       the shell's one queue)
#   tests/run-modules.sh tests/fixtures/modules/nixos-apply
#                                                       the shell's NixOS root step, on a
#                                                       fixture's stand-in pkexec (a run of
#                                                       its own: it locks the session)
#   tests/run-modules.sh tests/fixtures/modules/nixos-build
#                                                       the shell's NixOS build, on a stand-in
#                                                       nix and the fixture's stand-in pkexec
#   tests/run-modules.sh tests/fixtures/modules/nixos-rebuild
#                                                       the shell's NixOS rebuild run, with the
#                                                       build and root step on stand-ins (a run
#                                                       of its own: it locks the session)
#   tests/resolve-selftest.sh                           where the runners take their tools
#   tests/launcher-selftest.sh                          the supervisor in scripts/launch.sh
#   tests/deploy-check-selftest.sh                      the deploy check, on canned answers
#   tests/docs-check-selftest.sh                        the documentation's rules lint, on
#                                                       stand-ins and on README.md and docs/
#   tests/notes-ref-check-selftest.sh                   no file of the repository mentions the
#                                                       working notes (beyond its allowance), on
#                                                       stand-ins and on this checkout
#   tests/run-unit-selftest.sh                          the unit runner's own verdict
#   tests/remote-run-selftest.sh                        the remote runner, on a stand-in ssh
#   tests/affected-selftest.sh                          the tests a change needs: every file
#                                                       placed, on made-up repositories
#   tests/mutate-selftest.sh                            the mutation runner, on a fixture
#                                                       (tests/mutate.sh itself is run by hand)
#   tests/release-check-selftest.sh                     the release check, on stand-in runners
#                                                       (tests/release-check.sh is run by hand)
#   tests/lock/selftest.sh                              the lock bed's runner: its lint, FLAKY reruns
#   tests/mockup-selftest.sh                            the mockups' screen tool, on stand-ins
#   tests/run-mockups.sh --by-system                    the component and view mockups:
#                                                       compared with their baselines on
#                                                       Arch, every state reached elsewhere
#   tests/run-system.sh                                 this system's set (NixOS or Arch)
#   tests/lock/run.sh                                   the lock screen, end to end
#
# Each part finds its own tools and says what it took; nothing here needs the caller to
# prepare the environment, and nothing shows on the screen.
#
# The summary names every part, in this order: PASS, FAIL, or NOT RUN with the reason — a
# part that could not be set up (its status 2: a missing tool is named with its use, a
# system without a set), one left out by --quick, one not reached after a failure, one
# ended because another failed. A part that did not run to its end is never counted as
# passed. The log of a part that failed or could not be set up is kept, named on its line,
# under ${XDG_CACHE_HOME:-~/.cache}/h2s-shell-tests/run-all/<date-time>-<pid>/ (UTC; the
# newest 20 runs' kept, and any younger than a day); the others go with the run.
# Without --keep-going a failure starts nothing more and ends the parts still running (they are named NOT RUN, ended); the lock bed then does not run.
#
# Exit status: 0 when every part ran and passed (with --quick: every part but the lock
# bed); 1 when a part failed; 2 when none failed but one could not be set up, or for a
# wrong option; 130 when interrupted.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
usage() { echo "usage: tests/run-all.sh [--quick] [--keep-going] [-j <parts at once>]" >&2; exit 2; }
quick=0
keep_going=0
jobs=""
while [ $# -gt 0 ]; do
    case "$1" in
        --quick) quick=1 ;;
        --keep-going) keep_going=1 ;;
        -j) [ $# -ge 2 ] || usage; jobs=$2; shift ;;
        -j*) jobs=${1#-j} ;;
        *) usage ;;
    esac
    shift
done
jobs_given=$jobs
if [ -n "$jobs" ]; then
    [[ "$jobs" =~ ^[1-9][0-9]{0,2}$ ]] || usage
else
    jobs=$(nproc 2> /dev/null || getconf _NPROCESSORS_ONLN 2> /dev/null)
    [[ "$jobs" =~ ^[1-9][0-9]*$ ]] || jobs=1
fi
# (wait -n -p: bash 5.1)
if [ "${BASH_VERSINFO[0]}" -lt 5 ] || { [ "${BASH_VERSINFO[0]}" = 5 ] && [ "${BASH_VERSINFO[1]}" -lt 1 ]; }; then
    echo "run-all.sh: needs bash 5.1 or later (this is $BASH_VERSION)" >&2
    exit 2
fi

# name | command (relative to the checkout), in the order they start and are reported.
# RUN_ALL_PARTS names another list, in the same form: for a test of this runner's own verdict.
parts=(
    "this runner's self-test|tests/run-all-selftest.sh"
    "system runner self-test|tests/run-system-selftest.sh"
    "distribution facts self-test|tests/distribution-selftest.sh"
    "install.sh under stand-ins|tests/install-test.sh"
    "helper|tests/run-helper.sh"
    "unit suites|tests/run-unit.sh"
    "module fixture suites|tests/run-modules.sh tests/fixtures/modules/good tests/fixtures/modules/legacy-elevate"
    "privileged runs fixture|tests/run-modules.sh tests/fixtures/modules/privileged tests/fixtures/modules/privileged-undeclared"
    "NixOS root step fixture|tests/run-modules.sh tests/fixtures/modules/nixos-apply"
    "NixOS build fixture|tests/run-modules.sh tests/fixtures/modules/nixos-build"
    "NixOS rebuild fixture|tests/run-modules.sh tests/fixtures/modules/nixos-rebuild"
    "tool lookup self-test|tests/resolve-selftest.sh"
    "supervisor self-test|tests/launcher-selftest.sh"
    "deploy check self-test|tests/deploy-check-selftest.sh"
    "docs rules lint|tests/docs-check-selftest.sh"
    "notes references guard|tests/notes-ref-check-selftest.sh"
    "unit runner self-test|tests/run-unit-selftest.sh"
    "remote run self-test|tests/remote-run-selftest.sh"
    "affected tests self-test|tests/affected-selftest.sh"
    "mutation runner self-test|tests/mutate-selftest.sh"
    "release check self-test|tests/release-check-selftest.sh"
    "lock bed self-test|tests/lock/selftest.sh"
    "mockup screen tool self-test|tests/mockup-selftest.sh"
    "mockups|tests/run-mockups.sh --by-system"
    "system set|tests/run-system.sh"
    "lock bed|tests/lock/run.sh"
)
if [ -n "${RUN_ALL_PARTS:-}" ]; then
    mapfile -t parts < "$RUN_ALL_PARTS" || { echo "run-all.sh: cannot read $RUN_ALL_PARTS" >&2; exit 2; }
fi

logs=$(mktemp -d "${TMPDIR:-/tmp}/run-all.XXXXXX") || { echo "run-all.sh: cannot create a temp dir" >&2; exit 2; }
# shellcheck source=memory-cap.sh
source "$REPO/tests/memory-cap.sh"
trap 'rm -rf "$logs"; memory_cap_finish' EXIT
memory_cap_init
# A budget that holds fewer than two processes at their cap (a small machine, or little
# memory free now): parts side by side would stop each other at it, so they go one at a time
if [ -z "$jobs_given" ] && memory_cap_budget_small; then
    jobs=1
    echo "run-all.sh: the parts one after another: the run's memory budget ($MEMORY_CAP_BUDGET_LABEL) holds fewer than two processes at the memory cap ($MEMORY_CAP_LABEL)"
fi

count=${#parts[@]}
names=() commands=()
for part in "${parts[@]}"; do
    names+=("${part%%|*}")
    commands+=("${part#*|}")
done
# Per part, by its index: its summary line once it has one, whether its output has been
# printed, when it started. And the parts running: pid -> index
summary=() printed=() started_at=()
declare -A running=()
any_failed=0
any_not_run=0
stopped_by=""
started=$SECONDS

# The lock bed runs alone, after every part before it, its output shown as it goes
alone() { [ "${names[$1]}" = "lock bed" ]; }

# start_part <index>: in the background, in a process group of its own (job control only
# for that), its output in its log — and on the terminal too for a part that runs alone
start_part() {
    local index=$1 command=${commands[$1]} pid
    started_at[index]=$SECONDS
    # (Until it is registered: a signal's trap registers it from $!)
    starting=$index
    set -m
    if alone "$index"; then
        echo
        echo "==== ${names[index]}: $command"
        printed[index]=1
        # shellcheck disable=SC2086  # the command's words
        ( (cd "$REPO" && exec $command) 2>&1 < /dev/null | tee "$logs/$index"; exit "${PIPESTATUS[0]}") &
    else
        # shellcheck disable=SC2086  # the command's words
        (cd "$REPO" && exec $command) > "$logs/$index" 2>&1 < /dev/null &
    fi
    pid=$!
    set +m
    running[$pid]=$index
    starting=""
}

# end_running <why>: every part still running is ended — its whole group, SIGTERM so that
# it cleans up after itself, SIGKILL for what has not gone in 10 s — and, given a reason,
# named NOT RUN with it. A part that had already ended keeps its own verdict (what it left
# behind in its group is ended all the same).
ending=""
starting=""
end_running() {
    local pid tries=0 alive status finished=()
    ending=1
    if [ -n "$starting" ] && [ -n "${!:-}" ] && [ -z "${running[$!]:-}" ]; then
        running[$!]=$starting
        starting=""
    fi
    [ ${#running[@]} -gt 0 ] || { ending=""; return 0; }
    for pid in "${!running[@]}"; do
        exited "$pid" && finished+=("$pid")
    done
    for pid in "${!running[@]}"; do kill -TERM -- "-$pid" 2> /dev/null; done
    while [ "$tries" -lt 100 ]; do
        alive=0
        for pid in "${!running[@]}"; do kill -0 -- "-$pid" 2> /dev/null && alive=1; done
        [ "$alive" = 1 ] || break
        sleep 0.1
        tries=$((tries + 1))
    done
    for pid in "${!running[@]}"; do
        kill -KILL -- "-$pid" 2> /dev/null
        wait "$pid" 2> /dev/null
        status=$?
        if [[ " ${finished[*]} " == *" $pid "* ]]; then
            record "${running[$pid]}" "$status"
        elif [ -n "${1:-}" ]; then
            summary[${running[$pid]}]="  NOT RUN  ${names[${running[$pid]}]} — $1"
        fi
        unset "running[$pid]"
    done
    ending=""
}

# exited <pid>: the part itself has ended (a zombie not yet waited for, or gone)
exited() {
    local stat
    stat=$(cat "/proc/$1/stat" 2> /dev/null) || return 0
    stat=${stat##*) }
    [ "${stat%% *}" = Z ]
}

# print_ready: the output of each part, in the list's order, as far as the parts have ended
next_printed=0
print_ready() {
    while [ "$next_printed" -lt "$count" ] && [ -n "${summary[next_printed]:-}" ]; do
        if [ -z "${printed[next_printed]:-}" ] && [ -f "$logs/$next_printed" ]; then
            echo
            echo "==== ${names[next_printed]}: ${commands[next_printed]}"
            cat "$logs/$next_printed"
        fi
        printed[next_printed]=1
        next_printed=$((next_printed + 1))
    done
}

print_summary() {
    local index
    for index in "${!names[@]}"; do
        [ -z "${summary[index]:-}" ] || printf '%s\n' "${summary[index]}"
    done
}

trap 'end_running; print_ready; echo; echo "run-all.sh: interrupted; the parts so far:"; print_summary; exit 130' INT TERM HUP

# keep_log <index>: the part's log copied where it outlives the run (a one-off failure can be
# read afterwards); kept_note "; log: <path>", or empty when it cannot be kept
kept="" kept_note=""
keep_log() {
    local base=${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/h2s-shell-tests/run-all copy old
    kept_note=""
    [ -f "$logs/$1" ] || return 0
    if [ -z "$kept" ]; then
        kept=$base/$(date -u +%Y%m%d-%H%M%S)-$$
        mkdir -p "$kept" 2> /dev/null || { kept=""; return 0; }
        # The newest 20 runs' logs stay (names sort by their time), and any younger than a day
        for old in $(find "$base" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r | tail -n +21); do
            [ -z "$(find "$base/$old" -maxdepth 0 -mmin +1440)" ] || rm -rf -- "${base:?}/$old"
        done
    fi
    copy=$kept/$(printf '%02d' "$1").log
    cp "$logs/$1" "$copy" 2> /dev/null && kept_note="; log: $copy"
}

# record <index> <status>: its summary line, and what its end means for the rest
record() {
    local index=$1 status=$2 name=${names[$1]} took reason
    took="$((SECONDS - started_at[index])) s"
    case "$status" in
        0) summary[index]="  PASS     $name ($took)" ;;
        2)
            # A set-up error ends with its reason: the last lines the part printed
            reason=$(grep -v '^[[:space:]]*$' "$logs/$index" | tail -n 3 | tr '\n' ' ' | cut -c 1-400)
            keep_log "$index"
            summary[index]="  NOT RUN  $name — it could not be set up: ${reason:-status 2, no output}$kept_note"
            any_not_run=1
            ;;
        130)
            [ -n "$ending" ] || kill -INT $$
            summary[index]="  NOT RUN  $name — interrupted"
            ;;
        *)
            keep_log "$index"
            summary[index]="  FAIL     $name (status $status, $took) — ${commands[index]}$kept_note"
            any_failed=1
            if [ "$keep_going" != 1 ] && [ -z "$stopped_by" ] && [ -z "$ending" ]; then
                stopped_by=$name
                end_running "ended: stopped after '$stopped_by' failed (--keep-going goes on)"
            fi
            ;;
    esac
}

next=0
while :; do
    # Start what may start: up to $jobs at once; a part that runs alone waits for the
    # others to end, and nothing starts beside it
    while [ -z "$stopped_by" ] && [ "$next" -lt "$count" ] && [ ${#running[@]} -lt "$jobs" ]; do
        if [ "$quick" = 1 ] && [ "${names[next]}" = "lock bed" ]; then
            summary[next]="  NOT RUN  ${names[next]} — left out by --quick (${commands[next]} runs it)"
            next=$((next + 1))
            continue
        fi
        if alone "$next"; then
            [ ${#running[@]} = 0 ] || break
            print_ready
            start_part "$next"
            next=$((next + 1))
            break
        fi
        start_part "$next"
        next=$((next + 1))
        [ ${#running[@]} -lt "$jobs" ] || break
    done
    [ ${#running[@]} -gt 0 ] || break
    # Running alone: nothing else starts until it has ended
    ended_pid=""
    wait -n -p ended_pid "${!running[@]}"
    status=$?
    [ -n "$ended_pid" ] || continue
    index=${running[$ended_pid]}
    unset "running[$ended_pid]"
    record "$index" "$status"
    print_ready
done
for ((index = next; index < count; index++)); do
    if [ "$quick" = 1 ] && [ "${names[index]}" = "lock bed" ]; then
        summary[index]="  NOT RUN  ${names[index]} — left out by --quick (${commands[index]} runs it)"
    else
        summary[index]="  NOT RUN  ${names[index]} — not reached: stopped after '$stopped_by' failed (--keep-going goes on)"
    fi
done
print_ready

echo
echo "All ($((SECONDS - started)) s):"
print_summary
if [ "$any_failed" = 1 ]; then
    echo "run-all.sh: FAILED"
    exit 1
fi
if [ "$any_not_run" = 1 ]; then
    echo "run-all.sh: not everything could be run (above)"
    exit 2
fi
if [ "$quick" = 1 ]; then
    echo "run-all.sh: passed, without the lock bed"
else
    echo "run-all.sh: passed"
fi
exit 0
