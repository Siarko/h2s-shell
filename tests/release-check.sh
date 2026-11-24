#!/usr/bin/env bash
# Every check due before a minor or major release, in one command, with one summary.
#
#   tests/release-check.sh [--remote <dest>] [--module <dir>]… [--since <ref>]
#                          [--soak-runs <n>] [--dry-run]
#
#   --remote <dest>   the other machine's ssh destination, in place of H2S_REMOTE (it is
#                     never written to a file; see tests/remote-run.sh)
#   --module <dir>    a module directory whose suites run against this tree; once per
#                     module, added to those in H2S_MODULE_DIRS (directories separated by ":")
#   --since <ref>     the release the Rules files changed since (default: the last tag,
#                     `git describe --tags --abbrev=0`; no tag: every Rules file)
#   --soak-runs <n>   runs per soak (default 20)
#   --dry-run         print the plan, run nothing
#
# The parts, each a runner of its own (run as written here, from the tree's top):
#   the full set here         tests/run-all.sh --keep-going
#   the full set there        tests/remote-run.sh --host <dest>  (HEAD, which must be
#                             committed; the remote runs tests/run-all.sh --keep-going)
#   mutants of <file>         tests/mutate.sh <file>, for each *Rules.qml changed since the
#                             release (outside tests/, still in the tree)
#   soak of <suite>           tests/soak.sh <suite> <n>, for each suite in tests/flaky-suites.txt
#   soak of module <dir>      tests/soak.sh <dir> <n>, for each module whose own
#                             tests/flaky-suites.txt names a suite
#   module <dir>              tests/run-modules.sh <dir>, for each module directory given
#
# What runs side by side: the full set there runs on the other machine, so it starts first
# and goes on beside everything here; the parts here run one after another — the lock bed
# needs the machine to itself, a soak loads every processor, and run-all.sh and mutate.sh
# each size their work to the machine's whole memory budget (tests/memory-cap.sh). Each
# part's output is shown as it goes (the remote's once it has ended) and kept in a log.
#
# Every part runs, whatever another's verdict. The summary names each PASS, FAIL or NOT RUN
# with the reason: a part with nothing to run on (no destination, no module directory), or
# one that could not be set up (its status 2, the last lines it printed). A mutation run
# with survivors is a FAIL: each survivor needs a check, or a reason it cannot be told apart.
#
# Exit status: 0 when every part ran and passed; 1 when any failed; 2 when none failed but
# one did not run, or for a wrong option or flaky list; 130 when interrupted.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd -P)
usage() {
    echo "usage: tests/release-check.sh [--remote <dest>] [--module <dir>]… [--since <ref>] [--soak-runs <n>] [--dry-run]" >&2
    exit 2
}
fail() { echo "release-check.sh: $*" >&2; exit 2; }

host=${H2S_REMOTE:-}
modules=()
if [ -n "${H2S_MODULE_DIRS:-}" ]; then
    IFS=: read -r -a modules <<< "$H2S_MODULE_DIRS"
fi
since=""
soak_runs=20
dry_run=0
while [ $# -gt 0 ]; do
    case "$1" in
        --remote) [ $# -ge 2 ] || usage; host=$2; shift 2 ;;
        --module) [ $# -ge 2 ] || usage; modules+=("$2"); shift 2 ;;
        --since) [ $# -ge 2 ] || usage; since=$2; shift 2 ;;
        --soak-runs) [[ "${2:-}" =~ ^[1-9][0-9]*$ ]] || usage; soak_runs=$2; shift 2 ;;
        --dry-run) dry_run=1; shift ;;
        *) usage ;;
    esac
done

# The module directories, canonical; an empty entry (a stray ":") is dropped
module_dirs=()
for dir in "${modules[@]}"; do
    [ -n "$dir" ] || continue
    [ -f "$dir/module.json" ] || fail "$dir is no module directory (no module.json)"
    module_dirs+=("$(cd "$dir" && pwd -P)")
done

# read_list <file>: the names in a flaky list, comments and blank lines left out
read_list() {
    sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' "$1" | grep -v '^$'
}

# ---- The plan: name | command (the words of a runner in tests/, from the tree's top) ---
names=() commands=() skipped=()
add() { names+=("$1"); commands+=("$2"); skipped+=("${3:-}"); }

remote_part=""
if [ -n "$host" ]; then
    remote_part=0
    add "the full set on $host" "tests/remote-run.sh --host $host"
else
    add "the full set on the other machine" "tests/remote-run.sh" \
        "no destination: set H2S_REMOTE or pass --remote"
fi
add "the full set here" "tests/run-all.sh --keep-going"

if [ -z "$since" ]; then
    since=$(git -C "$REPO" describe --tags --abbrev=0 2> /dev/null) || since=""
fi
if [ -n "$since" ]; then
    git -C "$REPO" rev-parse --verify --quiet "$since^{commit}" > /dev/null || fail "--since: '$since' is no commit"
    # Changed since the release, the working tree included; deleted ones are not there to mutate
    mapfile -t rules < <(git -C "$REPO" diff --name-only --diff-filter=d "$since" -- '*Rules.qml' ':!tests/*' | sort)
    rules_note="changed since $since"
else
    mapfile -t rules < <(git -C "$REPO" ls-files -- '*Rules.qml' ':!tests/*' | sort)
    rules_note="every one: no tag to compare with"
fi
for file in "${rules[@]}"; do
    [ -n "$file" ] && add "mutants of $file" "tests/mutate.sh $file"
done

if [ -f "$REPO/tests/flaky-suites.txt" ]; then
    while read -r suite; do
        [[ "$suite" =~ ^[A-Za-z0-9_]+$ ]] && [ -f "$REPO/tests/$suite.qml" ] \
            || fail "tests/flaky-suites.txt: '$suite' is no unit suite (tests/<name>.qml)"
        add "soak of $suite" "tests/soak.sh $suite $soak_runs"
    done < <(read_list "$REPO/tests/flaky-suites.txt")
fi
for dir in "${module_dirs[@]}"; do
    [ -f "$dir/tests/flaky-suites.txt" ] || continue
    listed=()
    while read -r suite; do
        [[ "$suite" =~ ^[A-Za-z0-9_]+$ ]] && [ -f "$dir/tests/$suite.qml" ] \
            || fail "$dir/tests/flaky-suites.txt: '$suite' is no suite of the module"
        listed+=("$suite")
    done < <(read_list "$dir/tests/flaky-suites.txt")
    [ ${#listed[@]} = 0 ] || add "soak of module $dir (flaky: ${listed[*]})" "tests/soak.sh $dir $soak_runs"
done

if [ ${#module_dirs[@]} = 0 ]; then
    add "the modules' suites" "tests/run-modules.sh" \
        "no module directory: set H2S_MODULE_DIRS or pass --module"
fi
for dir in "${module_dirs[@]}"; do
    add "module $dir" "tests/run-modules.sh $dir"
done

if [ "$dry_run" = 1 ]; then
    echo "release-check.sh: the plan for $REPO (Rules files: $rules_note; ${#rules[@]} of them)"
    for index in "${!names[@]}"; do
        if [ -n "${skipped[index]}" ]; then
            printf '  NOT RUN  %s — %s\n' "${names[index]}" "${skipped[index]}"
        else
            printf '  %-8s %s: %s\n' "$([ "$index" = "$remote_part" ] && echo beside || echo then)" "${names[index]}" "${commands[index]}"
        fi
    done
    exit 0
fi

# ---- Running it --------------------------------------------------------------------------
logs=$(mktemp -d "${TMPDIR:-/tmp}/release-check.XXXXXX") || fail "cannot create a temp dir"
summary=() started_at=()
current="" remote_pid=""
started=$SECONDS

# start <index> <shown>: the part in the background, in a process group of its own (so that
# an interrupt ends all of it), its output in its log, and on the terminal when shown
start() {
    local index=$1 command=${commands[$1]}
    started_at[index]=$SECONDS
    set -m
    if [ "$2" = shown ]; then
        # shellcheck disable=SC2086  # the command's words
        ( (cd "$REPO" && exec $command) 2>&1 < /dev/null | tee "$logs/$index"; exit "${PIPESTATUS[0]}") &
    else
        # shellcheck disable=SC2086
        (cd "$REPO" && exec $command) > "$logs/$index" 2>&1 < /dev/null &
    fi
    set +m
}

# record <index> <status>
record() {
    local index=$1 status=$2 name=${names[$1]} took reason survived
    took="$((SECONDS - started_at[index])) s"
    case "$status" in
        0)
            survived=$(sed -n 's|^mutate\.sh: .* / survived \([0-9][0-9]*\).*|\1|p' "$logs/$index" | tail -n 1)
            if [ -n "$survived" ] && [ "$survived" -gt 0 ]; then
                summary[index]="  FAIL     $name ($survived survived, $took) — each needs a check or a reason; ${commands[index]}"
            else
                summary[index]="  PASS     $name ($took)"
            fi
            ;;
        2)
            reason=$(grep -v '^[[:space:]]*$' "$logs/$index" | tail -n 3 | tr '\n' ' ' | cut -c 1-400)
            summary[index]="  NOT RUN  $name — it could not be set up: ${reason:-status 2, no output}"
            ;;
        130) summary[index]="  NOT RUN  $name — interrupted" ;;
        *) summary[index]="  FAIL     $name (status $status, $took) — ${commands[index]}" ;;
    esac
}

print_summary() {
    local index
    for index in "${!names[@]}"; do
        [ -z "${summary[index]:-}" ] || printf '%s\n' "${summary[index]}"
    done
}

# end_group <pid>: SIGTERM to its group so that the runner cleans up after itself, SIGKILL
# for what has not gone in 10 s
end_group() {
    local pid=$1 tries=0
    kill -TERM -- "-$pid" 2> /dev/null
    while kill -0 -- "-$pid" 2> /dev/null && [ "$tries" -lt 100 ]; do
        sleep 0.1
        tries=$((tries + 1))
    done
    kill -KILL -- "-$pid" 2> /dev/null
    wait "$pid" 2> /dev/null
}
interrupted() {
    local index
    trap '' INT TERM HUP
    [ -z "$current" ] || end_group "$current"
    [ -z "$remote_pid" ] || end_group "$remote_pid"
    for index in "${!names[@]}"; do
        [ -n "${summary[index]:-}" ] || summary[index]="  NOT RUN  ${names[index]} — interrupted"
    done
    echo
    echo "release-check.sh: interrupted; the parts:"
    print_summary
    [ -z "$remote_pid" ] || echo "release-check.sh: the remote run goes on; its id is in $logs/$remote_part"
    exit 130
}
trap interrupted INT TERM HUP

for index in "${!names[@]}"; do
    [ -z "${skipped[index]}" ] || summary[index]="  NOT RUN  ${names[index]} — ${skipped[index]}"
done
if [ -n "$remote_part" ]; then
    echo "==== ${names[remote_part]}: ${commands[remote_part]} (beside the parts here; its output at the end)"
    start "$remote_part" quiet
    remote_pid=$!
fi
for index in "${!names[@]}"; do
    [ -z "${summary[index]:-}" ] && [ "$index" != "$remote_part" ] || continue
    echo
    echo "==== ${names[index]}: ${commands[index]}"
    start "$index" shown
    current=$!
    wait "$current"
    status=$?
    current=""
    record "$index" "$status"
done
if [ -n "$remote_pid" ]; then
    echo
    echo "==== ${names[remote_part]}: waiting for it"
    wait "$remote_pid"
    status=$?
    remote_pid=""
    cat "$logs/$remote_part"
    record "$remote_part" "$status"
fi
trap - INT TERM HUP
rm -rf "$logs"

echo
echo "Release check ($((SECONDS - started)) s; Rules files: $rules_note):"
print_summary
if grep -q '^  FAIL ' < <(print_summary); then
    echo "release-check.sh: FAILED"
    exit 1
fi
if grep -q '^  NOT RUN ' < <(print_summary); then
    echo "release-check.sh: not everything ran (above)"
    exit 2
fi
echo "release-check.sh: passed"
exit 0
