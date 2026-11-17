#!/usr/bin/env bash
# Checks tests/run-all.sh's own verdict against made-up parts (RUN_ALL_PARTS): that a part
# which failed, could not be set up, was left out or was not reached is named as that and
# never counted as passed, and the exit status; that a SIGTERM ends the part that is
# running at once. Then that every part of the real list names a runner that is there.
# Starts none of the real parts.
#
# Exit status: 0 when every check passed, 1 otherwise.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/run-all-selftest.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$work"' EXIT
failed=0
check() {
    local description=$1
    shift
    if "$@"; then echo "  PASS $description"; else echo "  FAIL $description"; failed=1; fi
}

# part <file name> <status> [<line it prints>]: a stand-in part that notes that it ran
part() {
    printf '#!%s\necho "%s" >> "%s/ran"\n[ -n "%s" ] && echo "%s" >&2\nexit %s\n' \
        "$(type -P bash)" "$1" "$work" "${3:-}" "${3:-}" "$2" > "$work/$1"
    chmod +x "$work/$1"
}
part good 0
part good-too 0
part bad 1
part crashed 139
part no-tool 2 "some-runner.sh: labwc not found on PATH (the headless compositor)"
part bed 0

# run "<name>|<stand-in>"… [-- options…]: OUTPUT, STATUS, and which stand-ins ran
run() {
    : > "$work/ran"
    : > "$work/parts"
    while [ $# -gt 0 ] && [ "$1" != -- ]; do
        echo "${1%%|*}|$work/${1#*|}" >> "$work/parts"
        shift
    done
    [ $# -gt 0 ] && shift
    OUTPUT=$(RUN_ALL_PARTS="$work/parts" "$REPO/tests/run-all.sh" "$@" 2>&1)
    STATUS=$?
}
status_is() { [ "$STATUS" = "$1" ]; }
says() { grep -q -- "$1" <<< "$OUTPUT"; }
silent_on() { ! grep -q -- "$1" <<< "$OUTPUT"; }
ran() { [ "$(tr '\n' ' ' < "$work/ran")" = "$1" ]; }

run "first|good" "second|good-too"
check "all pass: status 0" status_is 0
check "all pass: both named as PASS" test "$(grep -c '^  PASS     ' <<< "$OUTPUT")" = 2
check "all pass: says passed" says "^run-all.sh: passed$"

run "first|good" "second|bad" "third|good-too"
check "a part fails: status 1" status_is 1
check "a part fails: it is named FAIL, with its command" says "^  FAIL     second (status 1, .*) — $work/bad$"
check "a part fails: the parts after it do not run" ran "good bad "
check "a part fails: they are named NOT RUN, with the reason" says "^  NOT RUN  third — not reached: stopped after 'second' failed"
check "a part fails: the one not reached is not a pass" silent_on "PASS     third"
check "a part fails: says FAILED" says "^run-all.sh: FAILED$"

run "first|bad" "second|good" -- --keep-going
check "--keep-going: status 1" status_is 1
check "--keep-going: the parts after the failure run" ran "bad good "
check "--keep-going: the later one is PASS" says "^  PASS     second "

run "first|crashed" "second|good"
check "a part ends with another status (a crash): FAIL, status 1" status_is 1
check "a part ends with another status: named with it" says "^  FAIL     first (status 139, "

run "first|no-tool" "second|good"
check "a part cannot be set up: status 2" status_is 2
check "a part cannot be set up: NOT RUN, with the reason it printed" \
    says "^  NOT RUN  first — it could not be set up: some-runner.sh: labwc not found on PATH (the headless compositor)"
check "a part cannot be set up: it is not a pass" silent_on "PASS     first"
check "a part cannot be set up: the others still run" ran "no-tool good "
check "a part cannot be set up: does not say passed" silent_on "run-all.sh: passed"

run "first|no-tool" "second|bad"
check "one cannot be set up, one fails: status 1" status_is 1

run "first|good" "lock bed|bed"
check "with the lock bed: it runs" ran "good bed "
check "with the lock bed: says passed, nothing left out" says "^run-all.sh: passed$"
run "first|good" "lock bed|bed" -- --quick
check "--quick: status 0" status_is 0
check "--quick: the lock bed does not run" ran "good "
check "--quick: it is named NOT RUN, left out" says "^  NOT RUN  lock bed — left out by --quick"
check "--quick: the verdict says so" says "^run-all.sh: passed, without the lock bed$"

run "first|good" -- --fast
check "a wrong option: status 2" status_is 2
check "a wrong option: nothing runs" ran ""

# Interrupted (SIGTERM) while a part runs: the part and what it started are ended at once,
# not waited for — the stand-in would run for 30 s — and the status is 130
printf '#!%s\necho $$ > "%s/slow.pid"\nsleep 30 &\necho $! > "%s/slow.child"\necho slow >> "%s/ran"\nwait\n' \
    "$(type -P bash)" "$work" "$work" "$work" > "$work/slow"
chmod +x "$work/slow"
: > "$work/ran"
printf '%s\n' "first|$work/slow" "second|$work/good" > "$work/parts"
RUN_ALL_PARTS="$work/parts" "$REPO/tests/run-all.sh" > "$work/interrupted.out" 2>&1 &
runner=$!
# within <seconds> <command…>: true as soon as the command is, false after that long
within() {
    local tries=$(($1 * 20))
    shift
    while ! "$@"; do
        tries=$((tries - 1))
        [ "$tries" -gt 0 ] || return 1
        sleep 0.05
    done
}
gone() { ! kill -0 "$1" 2> /dev/null; }
part_running() { grep -qx slow "$work/ran" && [ -s "$work/slow.child" ]; }
if within 10 part_running; then
    slow_pid=$(cat "$work/slow.pid")
    slow_child=$(cat "$work/slow.child")
    kill -TERM "$runner"
    check "interrupted: the runner ends at once, not when the part would have" within 10 gone "$runner"
    wait "$runner"
    STATUS=$?
    OUTPUT=$(cat "$work/interrupted.out")
    check "interrupted: status 130" status_is 130
    check "interrupted: the part is ended" within 5 gone "$slow_pid"
    check "interrupted: what the part started is ended too" within 5 gone "$slow_child"
    check "interrupted: says so" says "^run-all.sh: interrupted"
    check "interrupted: the next part does not run" ran "slow "
    check "interrupted: nothing is said to have passed" silent_on "PASS"
    # Only what this test started, and only if the runner left it behind
    kill "$slow_child" "$slow_pid" "$runner" 2> /dev/null
else
    check "interrupted: the stand-in part started" false
    kill "$runner" 2> /dev/null
fi

# The real list: each part's runner is there and can be started, and the lock bed is the
# part --quick leaves out
mapfile -t real < <(sed -n '/^parts=($/,/^)$/p' "$REPO/tests/run-all.sh" | sed '1d;$d;s/^ *"//;s/"$//')
check "the real list is read (several parts)" test "${#real[@]}" -ge 8
for entry in "${real[@]}"; do
    command=${entry#*|}
    check "${entry%%|*}: ${command%% *} is there and executable" test -x "$REPO/${command%% *}"
    for word in ${command#* }; do
        [ "$word" = "${command%% *}" ] || check "${entry%%|*}: $word is there" test -e "$REPO/$word"
    done
done
check "the last part is the lock bed (tests/lock/run.sh)" test "${real[-1]}" = "lock bed|tests/lock/run.sh"

echo
if [ "$failed" = 0 ]; then echo "run-all self-test: passed"; else echo "run-all self-test: FAILED"; fi
exit "$failed"
