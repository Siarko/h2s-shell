#!/usr/bin/env bash
# Runs one suite many times in a row under CPU load, to find a check that depends on timing:
# a flake shows here in minutes instead of once a week.
#
#   tests/soak.sh <suite> <n>                 a unit suite (tests/run-unit.sh <suite>), n runs
#   tests/soak.sh <module dir> <n>            a module's suites (tests/run-modules.sh <dir>)
#   tests/soak.sh --load <k> <suite> <n>      k busy loops (default: one per processor)
#
# The load is busy loops this script starts before the first run and ends after the last
# (or on an interrupt): only the processes it started itself are signalled. Each run's output
# goes to a file of its own; a failed run's file is kept and named, with its FAIL lines, the
# others are removed.
#
# Exit status: 0 when all n runs passed, 1 when any failed, 2 when the arguments are wrong or
# a run could not be set up (the runner's status 2: the soak stops there).
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

usage() { echo "usage: tests/soak.sh [--load <busy loops>] <suite | module dir> <runs>" >&2; exit 2; }
load=$(nproc 2> /dev/null || echo 2)
if [ "${1:-}" = "--load" ]; then
    load=${2:-}
    [[ "$load" =~ ^[0-9]+$ ]] || usage
    shift 2
fi
[ $# -eq 2 ] || usage
subject=$1
runs=$2
[[ "$runs" =~ ^[1-9][0-9]*$ ]] || usage
if [ -d "$subject" ]; then
    [ -f "$subject/module.json" ] || { echo "soak.sh: $subject has no module.json" >&2; exit 2; }
    runner=("$REPO/tests/run-modules.sh" "$subject")
else
    runner=("$REPO/tests/run-unit.sh" "$subject")
fi

logs=$(mktemp -d "${TMPDIR:-/tmp}/h2s-soak.XXXXXX") || { echo "soak.sh: cannot create a temp dir" >&2; exit 2; }
loops=()
stop_load() {
    local pid
    for pid in "${loops[@]}"; do
        kill "$pid" 2> /dev/null
    done
    for pid in "${loops[@]}"; do
        wait "$pid" 2> /dev/null
    done
    loops=()
}
trap stop_load EXIT
trap 'stop_load; exit 130' INT TERM

for (( i = 0; i < load; i++ )); do
    bash -c 'while :; do :; done' &
    loops+=("$!")
done
echo "soak.sh: ${runner[*]#"$REPO/"}, $runs runs, under $load busy loops"

failed=0
started=$SECONDS
for (( run = 1; run <= runs; run++ )); do
    log="$logs/run-$run.log"
    run_started=$SECONDS
    "${runner[@]}" > "$log" 2>&1
    status=$?
    if [ "$status" -eq 0 ]; then
        echo "  run $run: PASS ($(( SECONDS - run_started )) s)"
        rm -f "$log"
    elif [ "$status" -eq 2 ]; then
        echo "  run $run: could not be set up (status 2), stopping; its output: $log"
        tail -n 5 "$log" | sed 's/^/    /'
        exit 2
    else
        failed=$(( failed + 1 ))
        echo "  run $run: FAIL ($(( SECONDS - run_started )) s); its output: $log"
        grep -E 'FAIL|timed out|TypeError|ReferenceError' "$log" | head -n 10 | sed 's/^/    /'
    fi
done
stop_load
echo "soak.sh: $(( runs - failed ))/$runs passed in $(( SECONDS - started )) s"
if [ "$failed" -eq 0 ]; then
    rm -rf "$logs"
    exit 0
fi
exit 1
