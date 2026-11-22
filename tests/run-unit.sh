#!/usr/bin/env bash
# Runs the unit suites (tests.qml) in parallel shards, each a Quickshell process in a private,
# headless compositor of its own, so that nothing shows on the screen (several suites open a
# small window, FileChooserTest a file dialog) and no suite shares a process with one it
# would disturb.
#
#   tests/run-unit.sh                            every suite tests.qml registers
#   tests/run-unit.sh FormatTest LockRulesTest   only the named ones (a suite is named by its
#                                                type, the file in tests/ without ".qml")
#   tests/run-unit.sh --log <file> [<suite>…]    the suites' output also saved to <file>
#   tests/run-unit.sh -j <n> [<suite>…]          at most <n> shards at once (default: half
#                                                the processors, at most 16, and no more
#                                                than the memory available holds, at about
#                                                1.1 GB a shard; at least 1)
#
# The shards are computed, never kept by hand (plan_shards, tests/count-suites.sh): a suite
# whose file says `ownProcess: true` runs alone; the others are packed by the time each took
# last (${XDG_CACHE_HOME:-~/.cache}/h2s-shell-tests/unit-times.txt, rewritten after each run
# with the times of the suites that passed; H2S_UNIT_TIMES names another file), into as many
# shards as it takes for none to run longer than the longest suite. Each shard is this
# runner again, with its suites named, its output printed when it ends; one shard is run
# here directly. A named suite brings the suites tests.qml gives it, in its shard. The names
# reach tests/TestCase.qml as H2S_TEST_SUITES; every suite is still built, the others do not
# run. A suite is found there by its suiteName followed by "Test", so that is what its file
# is called.
#
# The isolation (a headless labwc in a private runtime dir, D-Bus addresses that lead
# nowhere, a private HOME and XDG directories, no new privileges) and each shard's verdict
# are tests/headless.sh's, shared with tests/run-modules.sh. On PATH first: stand-ins for
# nmcli and notify-send (tests/fixtures/unit-path), for the suites that build the real
# settings window. Each shard's Quickshell runs under a memory cap (H2S_TEST_MEMORY_MAX,
# 1536M by default, 0 for none; tests/memory-cap.sh, said in the first lines): a shard
# stopped there fails, its verdict naming the suites it was running and the cap.
#
# Needs Quickshell, labwc, setpriv, setsid and timeout. labwc and setpriv are the pinned
# ones of tests/lock/tools.nix where there is a `nix` command, else those on PATH
# (H2S_TEST_TOOLS=nix or =system says which); Quickshell is LOCKTEST_QS, else the one the
# h2s-shell launcher runs, else qs or quickshell on PATH (tests/lock/resolve.sh). The first
# lines printed say what was taken.
#
# Exit status: 0 when every suite passed, 1 when a check FAILed, a suite timed out, checked
# nothing (0/0) or checked after it had reported, a TypeError / ReferenceError was printed,
# a shard's Quickshell exited non-zero (a crash after a partial summary included) or was
# stopped at the memory cap, or the
# suites that reported are not exactly those run — all of tests.qml's, or the named ones
# and those they bring —, 2 when the runner or a shard could not be set up (a missing tool
# is named, with its use), a name is empty or not a suite of tests.qml, or the suites of
# tests.qml cannot be read reliably (nothing runs then).
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
# shellcheck disable=SC2034  # read by tests/headless.sh
HEADLESS_NAME=run-unit.sh
# shellcheck source=count-suites.sh
source "$REPO/tests/count-suites.sh"

usage() { echo "usage: tests/run-unit.sh [--log <file>] [-j <shards at once>] [<suite>…]" >&2; exit 2; }
output_copy=""
jobs=""
while [ $# -gt 0 ]; do
    case "$1" in
        --log)
            output_copy=${2:-}
            [ -n "$output_copy" ] || { echo "run-unit.sh: --log needs a file" >&2; exit 2; }
            shift 2
            ;;
        -j)
            jobs=${2:-}
            [[ "$jobs" =~ ^[1-9][0-9]*$ ]] || { echo "run-unit.sh: -j needs a number of shards above 0" >&2; exit 2; }
            shift 2
            ;;
        -*) usage ;;
        *) break ;;
    esac
done
# What one shard takes, measured: Quickshell with every suite built about 0.8 GB resident,
# its labwc about 0.3 GB
shard_memory_kb=1100000
jobs_note=""
if [ -z "$jobs" ]; then
    jobs=$(( $(nproc 2> /dev/null || echo 2) / 2 ))
    [ "$jobs" -ge 1 ] || jobs=1
    [ "$jobs" -le 16 ] || jobs=16
    available_kb=$(awk '$1 == "MemAvailable:" { print $2 }' /proc/meminfo 2> /dev/null)
    if [[ "$available_kb" =~ ^[0-9]+$ ]]; then
        memory_jobs=$((available_kb / shard_memory_kb))
        [ "$memory_jobs" -ge 1 ] || memory_jobs=1
        if [ "$memory_jobs" -lt "$jobs" ]; then
            jobs_note=" (fewer than the processors allow: $((available_kb / 1024)) MB of memory available, about $((shard_memory_kb / 1024)) MB a shard)"
            jobs=$memory_jobs
        fi
    fi
fi

# The expected count and the selection both come from tests.qml's registration lines: when
# the two ways of reading them disagree, neither can be trusted
suites_agree "$REPO/tests.qml" \
    || { echo "run-unit.sh: cannot read the suites of tests.qml: $(count_suites "$REPO/tests.qml") registration lines, $(registered_suites "$REPO/tests.qml" | grep -c .) suites read from them (a brace in a string or comment of a suite's arguments?); nothing was run" >&2; exit 2; }

# Before anything is started: a name tests.qml does not register must not end as a pass
selected=()
for name in "$@"; do
    [ -n "$name" ] || { echo "run-unit.sh: an empty suite name; nothing was run" >&2; exit 2; }
done
if [ $# -gt 0 ]; then
    unknown=$(suites_with_needed "$REPO/tests.qml" "$@" 2>&1 > /dev/null) || {
        echo "run-unit.sh: no suite named '$unknown' in tests.qml (a suite is named by its type: FormatTest); nothing was run" >&2
        exit 2
    }
    mapfile -t selected < <(suites_with_needed "$REPO/tests.qml" "$@")
fi

times_file=${H2S_UNIT_TIMES:-${XDG_CACHE_HOME:-${HOME:+$HOME/.cache}}/h2s-shell-tests/unit-times.txt}
# shellcheck source=headless.sh
source "$REPO/tests/headless.sh"

# run_here: the suites in one Quickshell process, here, and its verdict. Stand-ins for nmcli
# and notify-send first on PATH: suites that build the real settings window start the
# shell's network readers and may notify, and must reach no real daemon
run_here() {
    local unit_path
    headless_setup
    unit_path=PATH="$REPO/tests/fixtures/unit-path:${LOCKTEST_TOOLS:+$LOCKTEST_TOOLS/bin:}$PATH"
    if [ ${#selected[@]} -gt 0 ]; then
        headless_run "$REPO/tests.qml" "$output_copy" "$unit_path" H2S_TEST_SUITES="$(IFS=:; echo "${selected[*]}")"
        # Exactly the selected suites must report, under the names TestCase gives them
        headless_verdict "Unit suites" ${#selected[@]} "selected" exactly "${selected[@]%Test}"
    else
        headless_run "$REPO/tests.qml" "$output_copy" "$unit_path"
        # Every suite tests.qml registers (`property var _name: SomethingTest {…}`) must report
        headless_verdict "Unit suites" "$(count_suites "$REPO/tests.qml")" "in tests.qml"
    fi
}

# record_times <log>…: the time each suite that passed took, merged into the times file
# (written beside it and moved into place). Not being able to is not an error: the next
# plan takes the defaults
record_times() {
    local directory=${times_file%/*} new
    [ -n "$times_file" ] && mkdir -p "$directory" 2> /dev/null || return 0
    new=$(mktemp "$directory/.unit-times.XXXXXX" 2> /dev/null) || return 0
    {
        sed -n 's/^.*--- \([A-Za-z0-9]*\): \([0-9][0-9]*\)\/\2 passed (\([0-9][0-9]*\) ms) ---.*$/\1Test \3/p' "$@" 2> /dev/null
        [ ! -r "$times_file" ] || awk 'NF == 2' "$times_file"
    } | awk '!seen[$1]++' | LC_ALL=C sort > "$new" 2> /dev/null \
        && mv -f "$new" "$times_file" 2> /dev/null || rm -f "$new"
}

# A shard: its suites, here (started by the runner below, which printed the tools). Only
# when this runner's parent is the runner that started it (H2S_UNIT_SHARD is "<its pid>:<n>"):
# a variable inherited from elsewhere does not turn a whole run into one shard
shard_mark=${H2S_UNIT_SHARD:-}
if [ -n "$shard_mark" ] && [ "${shard_mark%%:*}" = "$PPID" ]; then
    run_here
    exit $?
fi

if [ ${#selected[@]} -gt 0 ]; then
    run=("${selected[@]}")
else
    mapfile -t run < <(registered_suites "$REPO/tests.qml" | awk '{ print $1 }')
fi
mapfile -t shards < <(plan_shards "$REPO/tests.qml" "$times_file" "${run[@]}")
[ ${#shards[@]} -gt 0 ] || setup_error "no shard could be planned for: ${run[*]}"
[ ${#selected[@]} -gt 0 ] && echo "run-unit.sh: running ${selected[*]}"

# One shard: run here, as a shard would
if [ ${#shards[@]} = 1 ]; then
    run_here
    status=$?
    record_times "$HEADLESS_LOG"
    exit $status
fi

# Shards are waited for as each ends (wait -n -p: bash 5.1)
if [ "${BASH_VERSINFO[0]}" -lt 5 ] || { [ "${BASH_VERSINFO[0]}" = 5 ] && [ "${BASH_VERSINFO[1]}" -lt 1 ]; }; then
    setup_error "running shards side by side needs bash 5.1 or later (wait -n -p); this is bash $BASH_VERSION"
fi
headless_resolve
# Short, as headless_setup's: the shards' outputs, removed with the rest (headless_cleanup)
work=$(mktemp -d /tmp/ut.XXXXXX) || setup_error "cannot create a temp dir"
chmod 700 "$work"
started=$SECONDS
echo "run-unit.sh: ${#run[@]} suites in ${#shards[@]} shards, at most $jobs at once$jobs_note"

declare -A shard_of=()
shard_status=()
running=()
# stop_shards: every shard still running asked to end (each stops its Quickshell and its
# compositor, tests/headless.sh) and waited for; then what headless_cleanup removes
stop_shards() {
    trap '' INT TERM HUP
    local pid
    for pid in "${running[@]}"; do kill -TERM "$pid" 2> /dev/null; done
    for pid in "${running[@]}"; do wait "$pid" 2> /dev/null; done
    running=()
    headless_cleanup
}
trap stop_shards EXIT
trap 'exit 130' INT TERM HUP

# start_shard <index>: this runner on the shard's suites, in the background; its output in
# the work dir. TERM (stop_shards) ends it: a command started in the background ignores INT
start_shard() {
    local index=$1
    local -a suites
    read -r -a suites <<< "${shards[$index]}"
    H2S_UNIT_SHARD=$$:$((index + 1)) HEADLESS_QUIET_RESOLVE=1 LOCKTEST_QS=$LOCKTEST_QS H2S_TEST_TOOLS=$LOCKTEST_TOOL_SOURCE \
        H2S_UNIT_TIMES=$times_file "$REPO/tests/run-unit.sh" --log "$work/shard-$index.log" "${suites[@]}" \
        > "$work/shard-$index.out" 2>&1 < /dev/null &
    shard_of[$!]=$index
    running+=("$!")
}

# print_shard <index>: its output, under a line naming it
print_shard() {
    local index=$1
    echo
    echo "=== shard $((index + 1)) of ${#shards[@]}: ${shards[$index]} (status ${shard_status[$index]}) ==="
    cat "$work/shard-$index.out"
}

# shard_reasons <index>: why the shard failed, as its verdict said (the lines of its last
# verdict block that are not a suite's summary), so that the end of the output says it
shard_reasons() {
    local reasons="" output
    output=$(cat "$work/shard-$1.out" 2> /dev/null)
    # No verdict block (a shard ended by a signal or a bash error): its output is not one,
    # Quickshell's indented log lines would pass for reasons
    if grep -q '^Unit suites (' <<< "$output"; then
        reasons=$(sed -n '/^Unit suites (/h; /^Unit suites (/!H; ${x;p}' <<< "$output" \
            | grep -E -- '^  [^ ]' | grep -v -E -- '^  --- ')
    fi
    [ -n "$reasons" ] || reasons="  (no verdict: its output is above)"
    printf '%s\n' "$reasons" | sed 's/^/  /'
}

next=0
while [ "$next" -lt ${#shards[@]} ] || [ ${#running[@]} -gt 0 ]; do
    while [ "$next" -lt ${#shards[@]} ] && [ ${#running[@]} -lt "$jobs" ]; do
        start_shard "$next"
        next=$((next + 1))
    done
    finished=""
    wait -n -p finished "${running[@]}"
    status=$?
    # Not one of ours ended: none is left to wait for (127), which cannot be while some are
    # listed as running — said, not waited for again and again
    [ -n "$finished" ] || setup_error "lost track of the shards (wait said $status, ${#running[@]} listed as running)"
    index=${shard_of[$finished]}
    shard_status[index]=$status
    remaining=()
    for pid in "${running[@]}"; do [ "$pid" = "$finished" ] || remaining+=("$pid"); done
    running=("${remaining[@]}")
    print_shard "$index"
done

logs=()
for index in "${!shards[@]}"; do logs+=("$work/shard-$index.log"); done
[ -n "$output_copy" ] && cat "${logs[@]}" > "$output_copy" 2> /dev/null
record_times "${logs[@]}"

# The verdict over all shards: each shard's own (above) passed, and the suites that reported
# are exactly those that were run, each once
failed=0
set_up=0
summary=$(cat "${logs[@]}" 2> /dev/null | grep -E -- '^.*--- .*: [0-9]+/[0-9]+ passed' | sed 's/^.*--- /--- /')
echo
echo "Unit suites ($((SECONDS - started)) s, ${#shards[@]} shards, at most $jobs at once):"
[ -n "$summary" ] && echo "$summary" | sed 's/^/  /'
for index in "${!shards[@]}"; do
    case "${shard_status[$index]}" in
        0) ;;
        2) echo "  shard $((index + 1)) (${shards[$index]}) could not be set up"; set_up=1 ;;
        *)
            echo "  shard $((index + 1)) (${shards[$index]}) failed (status ${shard_status[$index]}):"
            shard_reasons "$index"
            failed=1
            ;;
    esac
done
reported=$(printf '%s\n' "$summary" | grep -c -- '^--- ')
if [ ${#selected[@]} -gt 0 ]; then where="selected"; else where="in tests.qml"; fi
[ "$reported" != ${#run[@]} ] && { echo "  $reported suites reported, ${#run[@]} were $where"; failed=1; }
for name in "${run[@]}"; do
    times_reported=$(printf '%s\n' "$summary" | grep -c -F -- "--- ${name%Test}: ")
    [ "$times_reported" = 1 ] || { echo "  ${name%Test} reported $times_reported times"; failed=1; }
done
# A failure is a failure even when another shard could not be set up: never "not run"
[ "$failed" = 1 ] && exit 1
[ "$set_up" = 1 ] && exit 2
exit 0
