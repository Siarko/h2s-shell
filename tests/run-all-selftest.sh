#!/usr/bin/env bash
# Checks tests/run-all.sh's own verdict against made-up parts (RUN_ALL_PARTS): that a part
# which failed, could not be set up, was left out, was not reached or was ended is named as
# that and never counted as passed, and the exit status; that parts run side by side, their
# output printed in the list's order, a failure ending the ones running, and the lock bed
# last and alone; that a SIGTERM ends every part that is running at once. Then that every
# part of the real list names a runner that is there. Starts none of the real parts.
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

# part <file name> <status> [<line it prints>] [<seconds it takes>] [<event it waits for>]: a
# stand-in part that notes that it ran (ran) and when it started and ended (events), prints
# "output of <name>" or the line given, on stderr, and ends after that long, or once the
# event is noted (at most 10 s: run one after another, the part it waits for never comes)
part() {
    {
        printf '#!%s\n' "$(type -P bash)"
        printf 'echo "%s" >> "%s/ran"\necho "start %s" >> "%s/events"\n' "$1" "$work" "$1" "$work"
        if [ -n "${3:-}" ]; then printf 'echo "%s" >&2\n' "$3"; else printf 'echo "output of %s"\n' "$1"; fi
        [ -z "${4:-}" ] || printf 'sleep %s\n' "$4"
        [ -z "${5:-}" ] || printf 'for i in $(seq 200); do grep -qx "%s" "%s/events" && break; sleep 0.05; done\n' "$5" "$work"
        printf 'echo "end %s" >> "%s/events"\nexit %s\n' "$1" "$work" "$2"
    } > "$work/$1"
    chmod +x "$work/$1"
}
part good 0
part good-too 0
part bad 1
part crashed 139
part no-tool 2 "some-runner.sh: labwc not found on PATH (the headless compositor)"
part bed 0
part slow 0 "" "" "end good"
part brief 0 "" 1
part after-bad 0 "" "" "end bad"
part bad-after-good 1 "" "" "end good"
part slower 0 "" 30

# run "<name>|<stand-in>"… [-- options…]: OUTPUT, STATUS, and which stand-ins ran
run() {
    : > "$work/ran"
    : > "$work/events"
    : > "$work/parts"
    while [ $# -gt 0 ] && [ "$1" != -- ]; do
        echo "${1%%|*}|$work/${1#*|}" >> "$work/parts"
        shift
    done
    [ $# -gt 0 ] && shift
    local began=$SECONDS
    OUTPUT=$(RUN_ALL_PARTS="$work/parts" "$REPO/tests/run-all.sh" "$@" 2>&1)
    STATUS=$?
    TOOK=$((SECONDS - began))
}
status_is() { [ "$STATUS" = "$1" ]; }
says() { grep -q -- "$1" <<< "$OUTPUT"; }
silent_on() { ! grep -q -- "$1" <<< "$OUTPUT"; }
ran() { [ "$(tr '\n' ' ' < "$work/ran")" = "$1" ]; }
# ran_set <names…>: these ran, in whatever order
ran_set() { [ "$(sort "$work/ran" | tr '\n' ' ')" = "$(printf '%s\n' "$@" | sort | tr '\n' ' ')" ]; }
# in_order <event>…: each of these events was noted before the next
in_order() {
    local previous=0 line
    while [ $# -gt 0 ]; do
        line=$(grep -nx -m 1 -- "$1" "$work/events" | cut -d: -f1)
        [ -n "$line" ] && [ "$line" -gt "$previous" ] || return 1
        previous=$line
        shift
    done
}
# before <first line> <second line>: the output has both, the first one earlier
before() {
    local first second
    first=$(grep -n -m 1 -- "$1" <<< "$OUTPUT" | cut -d: -f1)
    second=$(grep -n -m 1 -- "$2" <<< "$OUTPUT" | cut -d: -f1)
    [ -n "$first" ] && [ -n "$second" ] && [ "$first" -lt "$second" ]
}

run "first|good" "second|good-too"
check "all pass: status 0" status_is 0
# A memory budget of one cap (a run of its own, not a budget this self-test was started in):
# the parts one after another, and said why
inherited_memory=$(declare -p H2S_TEST_MEMORY_MODE H2S_TEST_SLICE H2S_TEST_MEMORY_BUDGET H2S_TEST_MEMORY_MAX 2> /dev/null)
unset H2S_TEST_MEMORY_MODE H2S_TEST_SLICE H2S_TEST_MEMORY_BUDGET H2S_TEST_MEMORY_MAX
H2S_TEST_MEMORY_MAX=1G H2S_TEST_MEMORY_BUDGET=1G run "first|brief" "second|good"
if says "^memory cap: .* in scopes of the user"; then
    check "a budget of one cap: said the parts go one after another" says "^run-all.sh: the parts one after another: the run's memory budget (1G)"
    check "a budget of one cap: the second started after the first ended" in_order "end brief" "start good"
else
    echo "  SKIP a budget of one cap: no budget without the user's service manager"
fi
eval "$inherited_memory"
check "all pass: both named as PASS" test "$(grep -c '^  PASS     ' <<< "$OUTPUT")" = 2
check "all pass: says passed" says "^run-all.sh: passed$"

run "first|good" "second|bad" "third|good-too" -- -j 1
check "a part fails (-j 1): status 1" status_is 1
check "a part fails: it is named FAIL, with its command" says "^  FAIL     second (status 1, .*) — $work/bad$"
check "a part fails: the parts after it do not run" ran "good bad "
check "a part fails: they are named NOT RUN, with the reason" says "^  NOT RUN  third — not reached: stopped after 'second' failed"
check "a part fails: the one not reached is not a pass" silent_on "PASS     third"
check "a part fails: says FAILED" says "^run-all.sh: FAILED$"

run "first|bad" "second|good" -- --keep-going -j 1
check "--keep-going: status 1" status_is 1
check "--keep-going: the parts after the failure run" ran "bad good "
check "--keep-going: the later one is PASS" says "^  PASS     second "

# Side by side: the second part ends before the first, its output still printed after it
run "first|slow" "second|good"
check "side by side: status 0" status_is 0
side_by_side() { in_order "start good" "end slow" && in_order "end good" "end slow"; }
check "side by side: both started before either ended, the second ended first" side_by_side
check "side by side: the output in the list's order, not the order they ended" \
    before "^==== first: " "^==== second: "
check "side by side: each part's output under its own heading" \
    bash -c 'grep -A1 "^==== first: " <<< "$1" | grep -q "^output of slow$" && grep -A1 "^==== second: " <<< "$1" | grep -q "^output of good$"' _ "$OUTPUT"
check "side by side: the summary in the list's order" before "^  PASS     first " "^  PASS     second "

# A failure while others run: the running one is ended at once (it would take 30 s), the one
# that had no room (-j 2) does not start
run "first|slower" "second|bad" "third|good" -- -j 2
check "a failure beside a running part: status 1" status_is 1
check "… the running part is ended, not waited for ($TOOK s)" test "$TOOK" -lt 15
check "… it is named NOT RUN, ended, with the reason" says "^  NOT RUN  first — ended: stopped after 'second' failed (--keep-going goes on)$"
check "… it is not a pass" silent_on "PASS     first"
check "… the failure is named FAIL" says "^  FAIL     second (status 1, "
check "… the part with no room does not start" bash -c '! grep -qx good "$1"' _ "$work/ran"
check "… it is named NOT RUN, not reached" says "^  NOT RUN  third — not reached: stopped after 'second' failed"
check "… the summary in the list's order" before "^  NOT RUN  first " "^  FAIL     second "

# Two parts end at about the same time, one of them failing: the one that had ended keeps
# its verdict, whichever the runner hears of first
run "first|good" "second|bad-after-good"
check "a failure as another part ends: that one keeps its PASS" says "^  PASS     first "
check "… it is not named ended" silent_on "NOT RUN  first"
check "… the failure is FAIL" says "^  FAIL     second (status 1, "

run "first|bad" "second|after-bad" -- --keep-going
check "--keep-going side by side: the running part is not ended, it passes" says "^  PASS     second "
check "--keep-going side by side: status 1" status_is 1

run "first|crashed" "second|good"
check "a part ends with another status (a crash): FAIL, status 1" status_is 1
check "a part ends with another status: named with it" says "^  FAIL     first (status 139, "

run "first|no-tool" "second|good"
check "a part cannot be set up: status 2" status_is 2
check "a part cannot be set up: NOT RUN, with the reason it printed" \
    says "^  NOT RUN  first — it could not be set up: some-runner.sh: labwc not found on PATH (the headless compositor)"
check "a part cannot be set up: it is not a pass" silent_on "PASS     first"
check "a part cannot be set up: the others still run" ran_set no-tool good
check "a part cannot be set up: does not say passed" silent_on "run-all.sh: passed"

run "first|no-tool" "second|bad"
check "one cannot be set up, one fails: status 1" status_is 1

run "first|slow" "second|good" "lock bed|bed"
bed_alone() { in_order "end good" "start bed" && in_order "end slow" "start bed" "end bed"; }
check "with the lock bed: it runs after the others have ended, alone" bed_alone
check "with the lock bed: says passed, nothing left out" says "^run-all.sh: passed$"
check "with the lock bed: its output after the others'" before "^==== second: " "^==== lock bed: "
run "first|bad" "lock bed|bed"
check "a part fails: the lock bed does not run" ran "bad "
check "… it is named NOT RUN, not reached" says "^  NOT RUN  lock bed — not reached: stopped after 'first' failed"
run "first|good" "lock bed|bed" -- --quick
check "--quick: status 0" status_is 0
check "--quick: the lock bed does not run" ran "good "
check "--quick: it is named NOT RUN, left out" says "^  NOT RUN  lock bed — left out by --quick"
check "--quick: the verdict says so" says "^run-all.sh: passed, without the lock bed$"

run "first|good" -- --fast
check "a wrong option: status 2" status_is 2
check "a wrong option: nothing runs" ran ""
run "first|good" -- -j 0
check "-j 0: status 2" status_is 2
check "-j 0: nothing runs" ran ""

# Interrupted (SIGTERM, or SIGHUP: the terminal closed) while two parts run side by side:
# both, and what they started, are ended at once, not waited for — the stand-ins would run
# for 30 s — and the status is 130
# hanging <name>: a stand-in that notes its pid and its child's, and waits on the child
hanging() {
    printf '#!%s\necho $$ > "%s/%s.pid"\nsleep 30 &\necho $! > "%s/%s.child"\necho %s >> "%s/ran"\nwait\n' \
        "$(type -P bash)" "$work" "$1" "$work" "$1" "$1" "$work" > "$work/$1"
    chmod +x "$work/$1"
}
hanging hang-one
hanging hang-two
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
all_gone() { local pid; for pid in "$@"; do gone "$pid" || return 1; done; }
parts_running() { [ -s "$work/hang-one.child" ] && [ -s "$work/hang-two.child" ]; }
for signal in TERM HUP; do
    : > "$work/ran"
    rm -f "$work"/hang-*.pid "$work"/hang-*.child
    printf '%s\n' "first|$work/hang-one" "second|$work/hang-two" "third|$work/good" > "$work/parts"
    RUN_ALL_PARTS="$work/parts" "$REPO/tests/run-all.sh" -j 2 > "$work/interrupted.out" 2>&1 &
    runner=$!
    if within 10 parts_running; then
        pids=$(cat "$work/hang-one.pid" "$work/hang-two.pid")
        children=$(cat "$work/hang-one.child" "$work/hang-two.child")
        kill -"$signal" "$runner"
        check "SIG$signal: the runner ends at once, not when the parts would have" within 10 gone "$runner"
        wait "$runner"
        STATUS=$?
        OUTPUT=$(cat "$work/interrupted.out")
        check "SIG$signal: status 130" status_is 130
        # shellcheck disable=SC2086  # the pids' words
        check "SIG$signal: both parts are ended" within 5 all_gone $pids
        # shellcheck disable=SC2086
        check "SIG$signal: what the parts started is ended too" within 5 all_gone $children
        check "SIG$signal: says so" says "^run-all.sh: interrupted"
        check "SIG$signal: the part with no room does not run" ran_set hang-one hang-two
        check "SIG$signal: nothing is said to have passed" silent_on "PASS"
        # Only what this test started, and only if the runner left it behind
        # shellcheck disable=SC2086
        kill $children $pids "$runner" 2> /dev/null
    else
        check "SIG$signal: the stand-in parts started" false
        kill "$runner" 2> /dev/null
    fi
done

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
