#!/usr/bin/env bash
# Every check due before a minor or major release, in one command, with one summary.
#
#   tests/release-check.sh [--remote <dest>] [--module <dir>]… [--since <ref>]
#                          [--soak-runs <n>] [--dry-run]
#
#   --remote <dest>   the other machine's ssh destination, in place of H2S_REMOTE (handed to
#                     tests/remote-run.sh in its environment; never written to a file)
#   --module <dir>    a module directory whose suites run against this tree; once per
#                     module, added to those in H2S_MODULE_DIRS (directories separated by ":")
#   --since <ref>     the release the Rules files changed since (default: the last minor or
#                     major release before HEAD, `git describe --tags --abbrev=0 --match
#                     'v[0-9]*.[0-9]*.0' HEAD^`; none: every Rules file)
#   --soak-runs <n>   runs per soak (default 20)
#   --dry-run         print the plan, run nothing
#
# What is checked is HEAD, here and there alike: the tree must have no uncommitted change to
# a tracked file and no untracked Rules file (status 2 otherwise, --dry-run too).
#
# The parts, each a runner of its own (run as written here, from the tree's top):
#   the full set on the other machine
#                             tests/remote-run.sh (it runs tests/run-all.sh --keep-going there)
#   the full set here         tests/run-all.sh --keep-going
#   mutants of <file>         tests/mutate.sh <file>, for each *Rules.qml outside tests/
#                             changed between the release and HEAD
#   soak of <suite>           tests/soak.sh <suite> <n>, for each suite in tests/flaky-suites.txt
#   soak of module <dir>      tests/soak.sh <dir> <n>, for each module whose own
#                             tests/flaky-suites.txt names a suite (of its manifest's)
#   module <dir>              tests/run-modules.sh <dir>, for each module directory given
#
# What runs side by side: the full set on the other machine runs there, so it starts first
# and goes on beside everything here; the parts here run one after another — the lock bed
# needs the machine to itself, a soak loads every processor, and run-all.sh and mutate.sh
# each size their work to the machine's whole memory budget (tests/memory-cap.sh). Each
# part's output is shown as it goes (the remote's once it has ended) and kept, with the
# summary, in ${XDG_CACHE_HOME:-~/.cache}/h2s-shell-tests/release-check/<date-time>/.
#
# Every part runs, whatever another's verdict. The summary names each PASS, FAIL or NOT RUN
# with the reason, a part not passed with its log: NOT RUN for a part with nothing to run on
# (no destination, no module directory) or one that could not be set up (its status 2, the
# last lines it printed). A mutation run fails on a survivor not in tests/mutants-accepted.txt
# or a stale entry there, and is not run when a mutant was not run or it gave no summary.
#
# Exit status: 0 when every part ran and passed; 1 when any failed; 2 when none failed but
# one did not run (a --dry-run whose plan has such a part too), for a wrong option or list,
# or a tree with uncommitted changes; 130 when interrupted.
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
        --remote) [ -n "${2:-}" ] || usage; host=$2; shift 2 ;;
        --module) [ $# -ge 2 ] || usage; modules+=("$2"); shift 2 ;;
        --since) [ -n "${2:-}" ] || usage; since=$2; shift 2 ;;
        --soak-runs) [[ "${2:-}" =~ ^[1-9][0-9]*$ ]] || usage; soak_runs=$2; shift 2 ;;
        --dry-run) dry_run=1; shift ;;
        *) usage ;;
    esac
done

# ---- The tree: HEAD, as the other machine gets it ----------------------------------------
changes=$(git -C "$REPO" status --porcelain --untracked-files=no) || fail "cannot read the tree's status (git)"
[ -z "$changes" ] || fail "uncommitted changes to tracked files: commit them first (the other machine checks HEAD)"
untracked=$(git -C "$REPO" ls-files --others --exclude-standard -- '*Rules.qml' ':!tests/*') || fail "cannot list untracked files (git)"
[ -z "$untracked" ] || fail "untracked Rules files ($(echo $untracked)): commit them first"

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

# ---- The plan ------------------------------------------------------------------------------
# Per part: its name, its kind, its command (shell-quoted words of a runner in tests/, from
# the tree's top), and why it does not run, if it does not
names=() kinds=() commands=() skipped=()
add() {
    local name=$1 kind=$2 reason=$3 command
    shift 3
    printf -v command '%q ' "$@"
    names+=("$name") kinds+=("$kind") commands+=("${command% }") skipped+=("$reason")
}

remote_part=""
if [ -n "$host" ]; then
    remote_part=0
    add "the full set on the other machine" remote "" tests/remote-run.sh
else
    add "the full set on the other machine" remote "no destination: set H2S_REMOTE or pass --remote" tests/remote-run.sh
fi
add "the full set here" full "" tests/run-all.sh --keep-going

if [ -z "$since" ] && git -C "$REPO" rev-parse --verify --quiet 'HEAD^' > /dev/null; then
    since=$(git -C "$REPO" describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.0' 'HEAD^' 2> /dev/null) || since=""
fi
if [ -n "$since" ]; then
    git -C "$REPO" rev-parse --verify --quiet "$since^{commit}" > /dev/null || fail "--since: '$since' is no commit"
    listing=$(git -C "$REPO" diff --name-only --diff-filter=d "$since" HEAD -- '*Rules.qml' ':!tests/*') \
        || fail "cannot list the Rules files changed since $since (git)"
    rules_note="changed since $since"
else
    listing=$(git -C "$REPO" ls-files -- '*Rules.qml' ':!tests/*') || fail "cannot list the Rules files (git)"
    rules_note="every one: no minor or major release tag before HEAD"
fi
mapfile -t rules < <(printf '%s\n' "$listing" | grep -v '^$' | sort)
for file in "${rules[@]}"; do
    add "mutants of $file" mutate "" tests/mutate.sh "$file"
done

if [ -f "$REPO/tests/flaky-suites.txt" ]; then
    while read -r suite; do
        [[ "$suite" =~ ^[A-Za-z0-9_]+$ ]] && [ -f "$REPO/tests/$suite.qml" ] \
            || fail "tests/flaky-suites.txt: '$suite' is no unit suite (tests/<name>.qml)"
        add "soak of $suite" soak "" tests/soak.sh "$suite" "$soak_runs"
    done < <(read_list "$REPO/tests/flaky-suites.txt")
fi
for dir in "${module_dirs[@]}"; do
    [ -f "$dir/tests/flaky-suites.txt" ] || continue
    listed=()
    while read -r suite; do
        [[ "$suite" =~ ^[A-Za-z0-9_]+$ ]] && grep -q -F "\"tests/$suite.qml\"" "$dir/module.json" \
            || fail "$dir/tests/flaky-suites.txt: '$suite' is no suite in the module's manifest"
        listed+=("$suite")
    done < <(read_list "$dir/tests/flaky-suites.txt")
    [ ${#listed[@]} = 0 ] || add "soak of module $dir (flaky: ${listed[*]})" soak "" tests/soak.sh "$dir" "$soak_runs"
done

if [ ${#module_dirs[@]} = 0 ]; then
    add "the modules' suites" modules "no module directory: set H2S_MODULE_DIRS or pass --module" tests/run-modules.sh
fi
for dir in "${module_dirs[@]}"; do
    add "module $dir" modules "" tests/run-modules.sh "$dir"
done

any_skipped=0
for index in "${!names[@]}"; do [ -z "${skipped[index]}" ] || any_skipped=1; done

if [ "$dry_run" = 1 ]; then
    echo "release-check.sh: the plan for HEAD of $REPO (Rules files: $rules_note; ${#rules[@]} of them)"
    for index in "${!names[@]}"; do
        if [ -n "${skipped[index]}" ]; then
            printf '  NOT RUN  %s — %s\n' "${names[index]}" "${skipped[index]}"
        else
            printf '  %-8s %s: %s\n' "$([ "$index" = "$remote_part" ] && echo beside || echo then)" "${names[index]}" "${commands[index]}"
        fi
    done
    [ "$any_skipped" = 0 ] || { echo "release-check.sh: not everything would run (above)"; exit 2; }
    exit 0
fi

# ---- Running it --------------------------------------------------------------------------
logs=${XDG_CACHE_HOME:-$HOME/.cache}/h2s-shell-tests/release-check/$(date +%Y%m%d-%H%M%S)
[ ! -e "$logs" ] || logs=$logs-$$
mkdir -p "$logs" || fail "cannot create $logs"
echo "release-check.sh: the logs in $logs"
summary=() started_at=()
current="" remote_pid=""
started=$SECONDS
log_of() { printf '%s/%02d.log' "$logs" "$1"; }

# start <index> <shown>: the part in the background, in a process group of its own (so that
# an interrupt ends all of it), its output in its log, and on the terminal when shown
start() {
    local index=$1 command=${commands[$1]} log
    log=$(log_of "$1")
    started_at[index]=$SECONDS
    set -m
    if [ "$2" = shown ]; then
        ( (cd "$REPO" && eval "exec $command") 2>&1 < /dev/null | tee "$log"; exit "${PIPESTATUS[0]}") &
    else
        (cd "$REPO" && export H2S_REMOTE="$host" && eval "exec $command") > "$log" 2>&1 < /dev/null &
    fi
    set +m
}

# mutate_verdict <log>: FAIL <why>, NOT RUN <why> or PASS, from mutate.sh's summary line
mutate_verdict() {
    local line survived accepted stale not_run
    if grep -q '^mutate\.sh: .*: no mutants$' "$1"; then echo PASS; return; fi
    line=$(grep -E '^mutate\.sh: .*, [0-9]+ s: killed ' "$1" | tail -n 1)
    [[ "$line" =~ " / survived "([0-9]+)" (accepted "([0-9]+)") / stale "([0-9]+)" / " ]] \
        || { echo "NOT RUN it gave no summary line"; return; }
    survived=${BASH_REMATCH[1]} accepted=${BASH_REMATCH[2]} stale=${BASH_REMATCH[3]}
    not_run=0
    [[ "$line" =~ " / not run "([0-9]+) ]] && not_run=${BASH_REMATCH[1]}
    if [ $((survived - accepted)) -gt 0 ] || [ "$stale" -gt 0 ]; then
        echo "FAIL $((survived - accepted)) survived not accepted, $stale stale accepted entries"
    elif [ "$not_run" -gt 0 ]; then
        echo "NOT RUN $not_run mutants not run"
    else
        echo PASS
    fi
}

# record <index> <status>
record() {
    local index=$1 status=$2 name=${names[$1]} took reason verdict log
    log=$(log_of "$1")
    took="$((SECONDS - started_at[index])) s"
    case "$status" in
        0)
            verdict=PASS
            [ "${kinds[index]}" != mutate ] || verdict=$(mutate_verdict "$log")
            case "$verdict" in
                PASS) summary[index]="  PASS     $name ($took)" ;;
                FAIL*) summary[index]="  FAIL     $name (${verdict#FAIL }, $took) — each needs a check or an entry with its reason in tests/mutants-accepted.txt; log: $log" ;;
                *) summary[index]="  NOT RUN  $name — ${verdict#NOT RUN }; log: $log" ;;
            esac
            ;;
        2)
            reason=$(grep -v '^[[:space:]]*$' "$log" | tail -n 3 | tr '\n' ' ' | cut -c 1-400)
            summary[index]="  NOT RUN  $name — it could not be set up: ${reason:-status 2, no output}; log: $log"
            ;;
        130) summary[index]="  NOT RUN  $name — interrupted" ;;
        *) summary[index]="  FAIL     $name (status $status, $took) — ${commands[index]}; log: $log" ;;
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
    print_summary | tee "$logs/summary.txt"
    [ -z "$remote_pid" ] || echo "release-check.sh: the remote run goes on; its id is in $(log_of "$remote_part")"
    echo "release-check.sh: the logs in $logs"
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
    cat "$(log_of "$remote_part")"
    record "$remote_part" "$status"
fi
trap - INT TERM HUP

echo
echo "Release check of $(git -C "$REPO" rev-parse --short HEAD) ($((SECONDS - started)) s; Rules files: $rules_note):"
print_summary | tee "$logs/summary.txt"
echo "release-check.sh: the logs in $logs"
if grep -q '^  FAIL ' "$logs/summary.txt"; then
    echo "release-check.sh: FAILED"
    exit 1
fi
if grep -q '^  NOT RUN ' "$logs/summary.txt"; then
    echo "release-check.sh: not everything ran (above)"
    exit 2
fi
echo "release-check.sh: passed"
exit 0
