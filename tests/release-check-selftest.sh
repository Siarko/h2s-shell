#!/usr/bin/env bash
# Checks tests/release-check.sh on stand-ins: a copy of it in a made-up repository whose
# runners (run-all.sh, remote-run.sh, mutate.sh, soak.sh, run-modules.sh) only note how they
# were called and end with the status they are given. That the plan holds every part (the
# Rules files changed since the tag and nothing else, the flaky lists, the modules, the
# destination from the environment or an argument); that every part runs whatever another's
# verdict, the remote one beside the others; that the summary and the exit status say FAIL,
# NOT RUN and survivors as they are; that a TERM ends the part running at once. Then that
# the real tree's plan is made (--dry-run): its flaky list names suites that are there.
# Starts none of the real runners.
#
# Exit status: 0 when every check passed, 1 otherwise.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/release-check-selftest.XXXXXX") || { echo "cannot create a temp dir" >&2; exit 2; }
trap 'rm -rf "$work"' EXIT
failed=0
check() {
    local description=$1
    shift
    if "$@"; then echo "  PASS $description"; else echo "  FAIL $description"; failed=1; fi
}

# ---- The made-up repository ---------------------------------------------------------------
tree=$work/tree
mkdir -p "$tree/tests" "$tree/singletons" "$work/status"
cp "$REPO/tests/release-check.sh" "$tree/tests/"
# standin <runner>: notes "<runner> <arguments>" in calls and "start/end <runner>" in events,
# prints a line (mutate.sh: its summary line, with the survivors given in survive/<file>),
# waits for the event in wait/<runner> when there is one (at most 10 s), sleeps sleep/<runner>
# seconds, and ends with the status in status/<runner> (default 0)
standin() {
    cat > "$tree/tests/$1" << EOF
#!$(type -P bash)
w=$work
echo "$1 \$*" >> "\$w/calls"
echo "start $1" >> "\$w/events"
echo "output of $1 \$*"
if [ "$1" = mutate.sh ]; then
    echo "mutate.sh: \$1, 1 s: killed 3 / survived \$(cat "\$w/survive/\$(basename "\$1")" 2> /dev/null || echo 0) / not compiled 0"
fi
if [ -f "\$w/wait/$1" ]; then
    for i in \$(seq 200); do grep -qx "\$(cat "\$w/wait/$1")" "\$w/events" && break; sleep 0.05; done
fi
[ ! -f "\$w/sleep/$1" ] || sleep "\$(cat "\$w/sleep/$1")"
echo "end $1" >> "\$w/events"
exit \$(cat "\$w/status/$1" 2> /dev/null || echo 0)
EOF
    chmod +x "$tree/tests/$1"
}
for runner in run-all.sh remote-run.sh mutate.sh soak.sh run-modules.sh; do standin "$runner"; done
touch "$tree/tests/FlakyTest.qml" "$tree/tests/OtherTest.qml"
printf '# a comment\n\nFlakyTest   # why\n' > "$tree/tests/flaky-suites.txt"
for file in SameRules ChangedRules GoneRules; do echo "// $file" > "$tree/singletons/$file.qml"; done
echo "// a suite's own" > "$tree/tests/SuiteRules.qml"
# Modules: one with a flaky list, one without
mkdir -p "$work/mod-a/tests" "$work/mod-b"
echo '{"id": "a"}' > "$work/mod-a/module.json"
echo '{"id": "b"}' > "$work/mod-b/module.json"
touch "$work/mod-a/tests/LiveTest.qml"
echo LiveTest > "$work/mod-a/tests/flaky-suites.txt"
git -C "$tree" init -q
git -C "$tree" -c user.name=t -c user.email=t@t add -A
git -C "$tree" -c user.name=t -c user.email=t@t commit -q -m one
git -C "$tree" tag v1.0.0
echo "// changed" >> "$tree/singletons/ChangedRules.qml"
echo "// changed" >> "$tree/tests/SuiteRules.qml"
git -C "$tree" rm -q singletons/GoneRules.qml
git -C "$tree" -c user.name=t -c user.email=t@t commit -q -am two
echo "// uncommitted" > "$tree/singletons/NewRules.qml"
git -C "$tree" add singletons/NewRules.qml

# run [options…]: OUTPUT, STATUS, TOOK; the calls and events start empty
run() {
    : > "$work/calls"
    : > "$work/events"
    local began=$SECONDS
    OUTPUT=$(env -u H2S_REMOTE -u H2S_MODULE_DIRS ${ENVIRONMENT:-} "$tree/tests/release-check.sh" "$@" 2>&1)
    STATUS=$?
    TOOK=$((SECONDS - began))
}
reset() { rm -rf "$work/status" "$work/survive" "$work/wait" "$work/sleep"; mkdir -p "$work/status" "$work/survive" "$work/wait" "$work/sleep"; }
status_is() { [ "$STATUS" = "$1" ]; }
says() { grep -q -- "$1" <<< "$OUTPUT"; }
silent_on() { ! grep -q -- "$1" <<< "$OUTPUT"; }
called() { grep -qx -- "$1" "$work/calls"; }
not_called() { ! grep -q -- "$1" "$work/calls"; }
nothing_called() { [ ! -s "$work/calls" ]; }
in_order() {
    local previous=0 line
    while [ $# -gt 0 ]; do
        line=$(grep -nx -m 1 -- "$1" "$work/events" | cut -d: -f1)
        [ -n "$line" ] && [ "$line" -gt "$previous" ] || return 1
        previous=$line
        shift
    done
}

# ---- The plan -------------------------------------------------------------------------------
reset
ENVIRONMENT="H2S_REMOTE=box H2S_MODULE_DIRS=$work/mod-a" run --module "$work/mod-b" --dry-run
check "--dry-run: status 0" status_is 0
check "--dry-run: nothing runs" nothing_called
check "--dry-run: the remote from H2S_REMOTE, beside the rest" says "^  beside   the full set on box: tests/remote-run.sh --host box$"
check "--dry-run: the full set here, kept going" says "^  then     the full set here: tests/run-all.sh --keep-going$"
check "--dry-run: a Rules file changed since the tag" says "mutate.sh singletons/ChangedRules.qml$"
check "--dry-run: a Rules file added, not yet committed" says "mutate.sh singletons/NewRules.qml$"
check "--dry-run: not one unchanged since the tag" silent_on "SameRules"
check "--dry-run: not one deleted" silent_on "GoneRules"
check "--dry-run: not one under tests/" silent_on "SuiteRules"
check "--dry-run: says what they changed since" says "Rules files: changed since v1.0.0; 2 of them"
check "--dry-run: a soak of the listed suite, 20 runs" says "tests/soak.sh FlakyTest 20$"
check "--dry-run: not of a suite left unlisted" silent_on "soak.sh OtherTest"
check "--dry-run: a soak of the module with a flaky list" says "soak of module $work/mod-a (flaky: LiveTest): tests/soak.sh $work/mod-a 20$"
check "--dry-run: none of the module without one" silent_on "soak.sh $work/mod-b"
check "--dry-run: each module's suites, from the environment and the argument" \
    bash -c 'grep -q "tests/run-modules.sh $2\$" <<< "$1" && grep -q "tests/run-modules.sh $3\$" <<< "$1"' _ "$OUTPUT" "$work/mod-a" "$work/mod-b"

run --remote other --since HEAD --soak-runs 3 --dry-run
check "--remote names the destination" says "tests/remote-run.sh --host other$"
check "--since: nothing committed since HEAD but the staged file" bash -c '[ "$(grep -c "mutate.sh " <<< "$1")" = 1 ]' _ "$OUTPUT"
check "--soak-runs: the runs per soak" says "tests/soak.sh FlakyTest 3$"
check "no module directory: NOT RUN, with the reason" says "^  NOT RUN  the modules' suites — no module directory: set H2S_MODULE_DIRS or pass --module$"

run --dry-run
check "no destination: NOT RUN, with the reason" says "^  NOT RUN  the full set on the other machine — no destination: set H2S_REMOTE or pass --remote$"

run --since nonesuch --dry-run
check "--since a ref that is not there: status 2" status_is 2
run --module "$work" --dry-run
check "a module directory without module.json: status 2" status_is 2
cp "$tree/tests/flaky-suites.txt" "$work/flaky.saved"
echo NoSuchTest >> "$tree/tests/flaky-suites.txt"
run --remote box --module "$work/mod-b"
check "a flaky list naming no suite: status 2" status_is 2
check "… named" says "'NoSuchTest' is no unit suite"
check "… and nothing runs" nothing_called
cp "$work/flaky.saved" "$tree/tests/flaky-suites.txt"

# ---- Running it -----------------------------------------------------------------------------
reset
echo "end run-all.sh" > "$work/wait/remote-run.sh"
run --remote box --module "$work/mod-a" --module "$work/mod-b"
check "all pass: status 0" status_is 0
check "all pass: says passed" says "^release-check.sh: passed$"
check "all pass: run-all.sh, kept going" called "run-all.sh --keep-going"
check "all pass: remote-run.sh, to the destination" called "remote-run.sh --host box"
check "all pass: mutate.sh on each changed Rules file" \
    bash -c 'grep -qx "mutate.sh singletons/ChangedRules.qml" "$1" && grep -qx "mutate.sh singletons/NewRules.qml" "$1"' _ "$work/calls"
check "all pass: soak.sh on the flaky suite and the module" \
    bash -c 'grep -qx "soak.sh FlakyTest 20" "$1" && grep -qx "soak.sh $2 20" "$1"' _ "$work/calls" "$work/mod-a"
check "all pass: run-modules.sh on each module" \
    bash -c 'grep -qx "run-modules.sh $2" "$1" && grep -qx "run-modules.sh $3" "$1"' _ "$work/calls" "$work/mod-a" "$work/mod-b"
check "the remote run went on beside the full set here" in_order "start remote-run.sh" "end run-all.sh" "end remote-run.sh"
local_one_at_a_time() {
    # Without the remote one's lines, each part here ends before the next starts
    grep -v remote-run "$work/events" | awk '/^start/ { if (open) exit 1; open = 1 } /^end/ { open = 0 } END { exit 0 }'
}
check "the parts here run one after another" local_one_at_a_time
check "each part's output is shown" says "^output of soak.sh FlakyTest 20$"
check "the summary names every part PASS" bash -c '[ "$(grep -c "^  PASS     " <<< "$1")" = 8 ]' _ "$OUTPUT"

reset
echo 1 > "$work/status/run-all.sh"
echo 2 > "$work/status/run-modules.sh"
run --remote box --module "$work/mod-b"
check "a part fails: status 1" status_is 1
check "a part fails: it is named FAIL, with its command" says "^  FAIL     the full set here (status 1, .*) — tests/run-all.sh --keep-going$"
check "a part fails: the parts after it run all the same" called "soak.sh FlakyTest 20"
check "a part that could not be set up: NOT RUN, with its last lines" says "^  NOT RUN  module $work/mod-b — it could not be set up: output of run-modules.sh"
check "a part fails: says FAILED" says "^release-check.sh: FAILED$"

reset
echo 2 > "$work/survive/ChangedRules.qml"
run --remote box --module "$work/mod-b"
check "survivors: status 1" status_is 1
check "survivors: the mutation part is FAIL, with their number" says "^  FAIL     mutants of singletons/ChangedRules.qml (2 survived, "
check "survivors: a file without any is PASS" says "^  PASS     mutants of singletons/NewRules.qml "

reset
run --module "$work/mod-b"
check "no destination, all else passing: status 2" status_is 2
check "… named NOT RUN" says "^  NOT RUN  the full set on the other machine — no destination"
check "… says not everything ran" says "^release-check.sh: not everything ran"
check "… remote-run.sh not started" not_called "remote-run.sh"

reset
echo 1 > "$work/status/remote-run.sh"
run --remote box --module "$work/mod-b"
check "the remote run fails: status 1, named FAIL" \
    bash -c '[ "$1" = 1 ] && grep -q "^  FAIL     the full set on box (status 1" <<< "$2"' _ "$STATUS" "$OUTPUT"

# A TERM while a part runs: it is ended at once (it would take 30 s), the rest NOT RUN
reset
echo 30 > "$work/sleep/run-all.sh"
: > "$work/calls"
: > "$work/events"
began=$SECONDS
env -u H2S_REMOTE -u H2S_MODULE_DIRS "$tree/tests/release-check.sh" --module "$work/mod-b" > "$work/term.out" 2>&1 &
checker=$!
for i in $(seq 200); do grep -qx "start run-all.sh" "$work/events" && break; sleep 0.05; done
kill -TERM "$checker"
wait "$checker"
STATUS=$?
TOOK=$((SECONDS - began))
OUTPUT=$(cat "$work/term.out")
check "a TERM: status 130" status_is 130
check "… the running part is ended, not waited for ($TOOK s)" test "$TOOK" -lt 15
check "… its stand-in did not run to its end" bash -c '! grep -qx "end run-all.sh" "$1"' _ "$work/events"
check "… the parts not run are named so" says "^  NOT RUN  soak of FlakyTest — interrupted$"

# ---- The real tree -----------------------------------------------------------------------
OUTPUT=$(env -u H2S_REMOTE -u H2S_MODULE_DIRS "$REPO/tests/release-check.sh" --dry-run 2>&1)
STATUS=$?
check "the real tree: its plan is made (the flaky list names suites that are there)" status_is 0
check "the real tree: the full set here is in it" says "tests/run-all.sh --keep-going$"

[ "$failed" = 0 ] && echo "release-check-selftest.sh: all passed" || echo "release-check-selftest.sh: FAILED"
exit "$failed"
