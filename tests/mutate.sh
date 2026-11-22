#!/usr/bin/env bash
# Mutation testing: whether the suites notice a change to a file's logic. In scratch copies
# of the tree (never the checkout), applies one mechanical mutation at a time to a
# `*Rules.qml` or a singleton, runs unit suites on each mutant, and lists the mutants no
# suite noticed — a check that is missing, or one that cannot fail.
#
#   tests/mutate.sh <file> [<suite>…]   every mutant of <file> (a path in the tree), run
#                                       against the named unit suites (default: the unit
#                                       suites tests/affected.sh selects for the file)
#   tests/mutate.sh --list <file>       the mutants printed, nothing run
#   tests/mutate.sh --max <n> …         at most <n> mutants, picked at random (by --seed)
#   tests/mutate.sh --seed <n> …        the pick of --max (default: a random seed, printed,
#                                       so that a run can be repeated)
#   tests/mutate.sh --judge <log> <status> <file>
#                                       the verdict on one run of the suites — its output
#                                       and status, the subject's path in the tree (for
#                                       tests/mutate-selftest.sh)
#   tests/mutate.sh -j <n> …            at most <n> mutants at once (default: as many as the
#                                       unit runner would run shards: half the processors,
#                                       at most 16, no more than the memory holds at about
#                                       1.1 GB each)
#
# The mutations, on code only (not in comments, strings, regular expressions, import and
# pragma lines; inside `${…}` of a template string they are made): `===`↔`!==`, `==`↔`!=`,
# `<`↔`<=`, `>`↔`>=`, `&&`↔`||`, `true`↔`false`, a `!` dropped, an integer constant + 1, a
# one-line `return <expression>;` negated (`return !(<expression>);`).
#
# Each mutant runs first against the suite named after the file (<File>Test), when it is
# among the suites, then — only when that one passed — against the others, in one run of
# tests/run-unit.sh (-j 1) of the copy. Before any mutant, both runs are made on the copy as
# it is: suites that fail unmutated cannot judge a mutant (status 2). A mutant is
#   survived      every suite passed
#   not run       the runner could not be set up (status 2)
#   not compiled  Quickshell could not load the mutated file: a load error naming it at a
#                 line (a syntax error, "Type … unavailable", in the chain of `caused by`),
#                 whatever the status — a run that hung after it included
#   killed        else: a suite failed (a check, a TypeError or ReferenceError, a crash),
#                 or the run took longer than four times the unmutated run's time (at least
#                 60 s): a hang
# Lock scenarios and module fixture parts are not run: only unit suites.
#
# Tools are taken by tests/run-unit.sh, as always (the pinned ones where there is `nix`, else
# PATH; H2S_TEST_TOOLS says which). Each worker has its own copy of the tree, under this
# run's temp dir, removed by its path when the run ends (an interrupt included).
#
# Exit status: 0 when it ran (whatever survived); 2 for a wrong option or file, suites that
# fail unmutated, or a copy that could not be made; 130 when interrupted.
set -uo pipefail
export LC_ALL=C

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd -P)
usage() { echo "usage: tests/mutate.sh [--list] [--max <n>] [--seed <n>] [-j <n>] <file> [<suite>…]  |  tests/mutate.sh --judge <log> <status> <file>" >&2; exit 2; }
fail() { echo "mutate.sh: $*" >&2; exit 2; }

# verdict <log> <status> <file>: survived, not-run, not-compiled or killed. A load error
# names the file at a line in Quickshell's `caused by` chain; a JavaScript error at run time
# (TypeError, ReferenceError, …) names it too, and is a kill
verdict() {
    local log=$1 status=$2 subject=$3
    case "$status" in
        0) echo survived; return ;;
        2) echo not-run; return ;;
    esac
    if grep -E "caused by @${subject//./\\.}\[[1-9][0-9]*:[0-9]+\]" "$log" 2> /dev/null | grep -q -v -E "(Type|Reference|Range|Syntax|Eval|URI)Error: "; then
        echo not-compiled
    else
        echo killed
    fi
}
if [ "${1:-}" = --judge ]; then
    [ $# = 4 ] && [ -r "$2" ] && [[ "$3" =~ ^[0-9]+$ ]] || usage
    verdict "$2" "$3" "$4"
    exit 0
fi

list_only=0
max=""
seed=""
jobs=""
while [ $# -gt 0 ]; do
    case "$1" in
        --list) list_only=1; shift ;;
        --max) [[ "${2:-}" =~ ^[1-9][0-9]*$ ]] || fail "--max needs a number above 0"; max=$2; shift 2 ;;
        --seed) [[ "${2:-}" =~ ^[0-9]+$ ]] || fail "--seed needs a number"; seed=$2; shift 2 ;;
        -j) [[ "${2:-}" =~ ^[1-9][0-9]*$ ]] || fail "-j needs a number above 0"; jobs=$2; shift 2 ;;
        --) shift; break ;;
        -*) usage ;;
        *) break ;;
    esac
done
[ $# -ge 1 ] || usage
given=$1
shift
suites=("$@")

# The file, as a path in the tree
if [[ "$given" != /* ]] && [ -f "$REPO/$given" ]; then
    absolute=$(readlink -f -- "$REPO/$given")
else
    absolute=$(readlink -f -- "$given")
fi
case "$absolute" in "$REPO"/*) ;; *) fail "$given is not in the tree ($REPO)" ;; esac
file=${absolute#"$REPO"/}
[ -f "$REPO/$file" ] || fail "no file $file in the tree"
case "$file" in *.qml) ;; *) fail "$file is not a QML file" ;; esac
case "$file" in tests/*) fail "$file is a test: mutate what it tests" ;; esac

# ---- The mutants ------------------------------------------------------------------------
# One per line: <line>, <column>, <old text>, <new text>, <kind>, separated by US (\037:
# <new text> may be empty, and a tab would merge empty fields). Columns are in
# bytes (LC_ALL=C), as the awk that applies them counts.
enumerate() {
    awk '
function emit(column, old, new, kind) {
    if (index(old, "\037") || index(new, "\037")) return
    printf "%d\037%d\037%s\037%s\037%s\n", NR, column, old, new, kind
}
BEGIN { mode = "code"; depth = 0; previous = "op" }
{
    line = $0; n = length(line); i = 1
    if (mode == "code" && depth == 0 && line ~ /^[ \t]*(import|pragma)[ \t]/) next
    while (i <= n) {
        ch = substr(line, i, 1)
        if (mode == "block") {
            if (substr(line, i, 2) == "*/") { mode = "code"; i += 2 } else i++
            continue
        }
        if (mode == "template") {
            if (ch == "\\") { i += 2; continue }
            if (ch == "`") { mode = "code"; previous = "value"; i++; continue }
            if (substr(line, i, 2) == "${") { depth++; braces[depth] = 0; mode = "code"; previous = "op"; i += 2; continue }
            i++
            continue
        }
        if (ch == " " || ch == "\t") { i++; continue }
        two = substr(line, i, 2); three = substr(line, i, 3)
        if (two == "//") break
        if (two == "/*") { mode = "block"; i += 2; continue }
        if (ch == "\"" || ch == "\x27") {
            j = i + 1
            while (j <= n && substr(line, j, 1) != ch) { if (substr(line, j, 1) == "\\") j++; j++ }
            i = j + 1; previous = "value"; continue
        }
        if (ch == "`") { mode = "template"; i++; continue }
        if (ch == "/" && previous != "value") {
            j = i + 1; class = 0
            while (j <= n) {
                c = substr(line, j, 1)
                if (c == "\\") { j += 2; continue }
                if (c == "[") class = 1
                else if (c == "]") class = 0
                else if (c == "/" && !class) break
                j++
            }
            j++
            while (j <= n && substr(line, j, 1) ~ /[a-z]/) j++
            i = j; previous = "value"; continue
        }
        if (ch ~ /[A-Za-z_$]/) {
            rest = substr(line, i); match(rest, /^[A-Za-z0-9_$]+/)
            word_length = RLENGTH; word = substr(rest, 1, word_length)
            after_dot = i > 1 && substr(line, i - 1, 1) == "."
            if (!after_dot && word == "true") emit(i, "true", "false", "true->false")
            if (!after_dot && word == "false") emit(i, "false", "true", "false->true")
            if (!after_dot && word == "return") {
                tail = substr(rest, 7)
                if (match(tail, /^[ \t]+/)) {
                    space = substr(tail, 1, RLENGTH); expression = substr(tail, RLENGTH + 1)
                    if (expression ~ /^[^;"\x27`\/]+;[ \t]*(\/\/.*)?$/) {
                        expression = substr(expression, 1, index(expression, ";") - 1)
                        sub(/[ \t]+$/, "", expression)
                        if (expression !~ /^(true|false|null|undefined)$/ && expression != "")
                            emit(i, "return" space expression, "return" space "!(" expression ")", "return negated")
                    }
                }
            }
            if (word ~ /^(return|typeof|case|in|of|delete|void|throw|new|instanceof|else|do)$/) previous = "op"
            else previous = "value"
            i += word_length; continue
        }
        if (ch ~ /[0-9]/) {
            rest = substr(line, i); match(rest, /^[0-9][0-9A-Za-z_.]*/)
            token = substr(rest, 1, RLENGTH)
            if (token ~ /^[0-9]+$/ && token + 0 < 100 && !(i > 1 && substr(line, i - 1, 1) == "."))
                emit(i, token, token + 1, "constant+1")
            i += RLENGTH; previous = "value"; continue
        }
        previous = "op"
        if (three == "===") { emit(i, "===", "!==", "===->!=="); i += 3; continue }
        if (three == "!==") { emit(i, "!==", "===", "!==->==="); i += 3; continue }
        if (three == ">>>" || three == "...") { i += 3; continue }
        if (two == "==") { emit(i, "==", "!=", "==->!="); i += 2; continue }
        if (two == "!=") { emit(i, "!=", "==", "!=->=="); i += 2; continue }
        if (two == "<=") { emit(i, "<=", "<", "<=-><"); i += 2; continue }
        if (two == ">=") { emit(i, ">=", ">", ">=->>"); i += 2; continue }
        if (two == "&&") { emit(i, "&&", "||", "&&->||"); i += 2; continue }
        if (two == "||") { emit(i, "||", "&&", "||->&&"); i += 2; continue }
        if (two ~ /^(=>|<<|>>|\?\?|\?\.|\+\+|--|\+=|-=|\*=|\/=|%=|\*\*)$/) { i += 2; continue }
        if (ch == "<") { emit(i, "<", "<=", "<-><="); i++; continue }
        if (ch == ">") { emit(i, ">", ">=", ">->>="); i++; continue }
        if (ch == "!") { emit(i, "!", "", "dropped !"); i++; continue }
        if (ch == ")" || ch == "]") previous = "value"
        if (ch == "{" && depth > 0) braces[depth]++
        if (ch == "}" && depth > 0) {
            if (braces[depth] == 0) { depth--; mode = "template"; i++; continue }
            braces[depth]--
        }
        i++
    }
}' "$1"
}

# apply <source> <line> <column> <old> <new> > <mutated>: status 3 when the text is not there
apply() {
    MUTATE_OLD=$4 MUTATE_NEW=$5 awk -v target="$2" -v column="$3" '
NR == target {
    old = ENVIRON["MUTATE_OLD"]
    if (substr($0, column, length(old)) != old) { status = 3; exit 3 }
    $0 = substr($0, 1, column - 1) ENVIRON["MUTATE_NEW"] substr($0, column + length(old))
}
{ print }
END { exit status }' "$1"
}

# The run's temp dir, and in it the subject as it is now: what is enumerated, mutated, put
# back and quoted, whatever happens to the file in the tree meanwhile
work=$(mktemp -d "${TMPDIR:-/tmp}/mutate.XXXXXX") || fail "cannot create a temp dir"
workers=()
current_run=""
stop() {
    trap '' INT TERM HUP
    local pid
    for pid in "${workers[@]}"; do kill -TERM "$pid" 2> /dev/null; done
    for pid in "${workers[@]}"; do wait "$pid" 2> /dev/null; done
    # An unmutated run under way (its `timeout` hands the TERM on to the runner)
    if [ -n "$current_run" ]; then
        kill -TERM "$current_run" 2> /dev/null
        wait "$current_run" 2> /dev/null
    fi
    rm -rf "$work"
}
trap stop EXIT
trap 'exit 130' INT TERM HUP
subject=$work/subject.qml
cp "$REPO/$file" "$subject" || fail "cannot copy $file into $work"

mapfile -t all < <(enumerate "$subject")
[ ${#all[@]} -gt 0 ] || { echo "mutate.sh: $file: no mutants"; exit 0; }
total=${#all[@]}

# describe <mutant line>: file:line:column  'old' -> 'new'  | the line as it reads
describe() {
    local line column old new kind source
    IFS=$'\037' read -r line column old new kind <<< "$1"
    source=$(sed -n "${line}p" "$subject" | sed 's/^[[:space:]]*//' | cut -c1-90)
    printf "%s:%s:%s  '%s' -> '%s'  | %s\n" "$file" "$line" "$column" "$old" "$new" "$source"
}

# The pick: with --max, a random one by the seed (bash's own generator: the same seed picks
# the same mutants wherever this bash runs), in file order
picked=("${all[@]}")
if [ -n "$max" ] && [ "$max" -lt "$total" ]; then
    [ -n "$seed" ] || seed=$((RANDOM * 32768 + RANDOM))
    RANDOM=$seed
    keyed=()
    for index in "${!all[@]}"; do keyed+=("$RANDOM$RANDOM $index"); done
    mapfile -t chosen < <(printf '%s\n' "${keyed[@]}" | sort -n | head -n "$max" | awk '{ print $2 }' | sort -n)
    picked=()
    for index in "${chosen[@]}"; do picked+=("${all[$index]}"); done
fi
pick_note="${#picked[@]} of $total mutants"
[ ${#picked[@]} -lt "$total" ] && pick_note="$pick_note (--max $max --seed $seed)"

if [ "$list_only" = 1 ]; then
    echo "mutate.sh: $file, $pick_note"
    for mutant in "${picked[@]}"; do describe "$mutant" | sed 's/^/  /'; done
    exit 0
fi

# ---- The suites -------------------------------------------------------------------------
if [ ${#suites[@]} = 0 ]; then
    # Read whole, then searched: grep -m1 in a pipe ends early, and under pipefail the
    # affected.sh still printing then dies of SIGPIPE and fails the line
    selection=$("$REPO/tests/affected.sh" --files "$file" 2> /dev/null)
    line=$(grep -m1 '^tests/run-unit.sh' <<< "$selection") \
        || fail "tests/affected.sh selects no unit suite for $file: name the suites"
    read -r -a suites <<< "${line#tests/run-unit.sh}"
    [ ${#suites[@]} -gt 0 ] || fail "tests/affected.sh selects every unit suite for $file: name the suites"
fi
base=${file##*/}
own=${base%.qml}Test
first=() rest=()
for suite in "${suites[@]}"; do
    if [ "$suite" = "$own" ]; then first=("$suite"); else rest+=("$suite"); fi
done
if [ ${#first[@]} = 0 ]; then first=("${rest[@]}"); rest=(); fi

if [ -z "$jobs" ]; then
    jobs=$(( $(nproc 2> /dev/null || echo 2) / 2 ))
    [ "$jobs" -ge 1 ] || jobs=1
    [ "$jobs" -le 16 ] || jobs=16
    available_kb=$(awk '$1 == "MemAvailable:" { print $2 }' /proc/meminfo 2> /dev/null)
    if [[ "$available_kb" =~ ^[0-9]+$ ]]; then
        memory_jobs=$((available_kb / 1100000))
        [ "$memory_jobs" -ge 1 ] || memory_jobs=1
        [ "$memory_jobs" -ge "$jobs" ] || jobs=$memory_jobs
    fi
fi
[ "$jobs" -le ${#picked[@]} ] || jobs=${#picked[@]}

# ---- The copies -------------------------------------------------------------------------

# copy_tree <dest>: the tree as it is, without .git and build results
copy_tree() {
    local dest=$1 entry
    mkdir -p "$dest" || return 1
    for entry in "$REPO"/* "$REPO"/.[!.]*; do
        [ -e "$entry" ] || continue
        case "${entry##*/}" in .git | result | result-*) continue ;; esac
        cp -a "$entry" "$dest/" || return 1
    done
}
copy_tree "$work/tree-0" || fail "cannot copy the tree into $work"
cp "$subject" "$work/tree-0/$file"
times_file=${XDG_CACHE_HOME:-${HOME:+$HOME/.cache}}/h2s-shell-tests/unit-times.txt
[ -r "$times_file" ] && cp "$times_file" "$work/times" 2> /dev/null

echo "mutate.sh: $file, $pick_note, $jobs at once"
echo "mutate.sh: first ${first[*]}${rest[*]:+; then, when it passes, ${rest[*]}}"

# run_suites <tree> <log> <limit s> <suite>…: run-unit.sh of that copy; its status (124 for
# the limit). Its times file is the run's own, so that mutants do not write the user's
run_suites() {
    local tree=$1 log=$2 limit=$3 pid status
    shift 3
    H2S_UNIT_TIMES=$work/times-${tree##*/} timeout -k 30 "$limit" "$tree/tests/run-unit.sh" -j 1 "$@" > "$log" 2>&1 < /dev/null &
    pid=$!
    current_run=$pid
    wait "$pid"
    status=$?
    current_run=""
    return "$status"
}

# The unmutated runs: they must pass, and their times set each mutant's limit
cp "$work/times" "$work/times-tree-0" 2> /dev/null
started=$SECONDS
run_suites "$work/tree-0" "$work/baseline-first.log" 900 "${first[@]}" \
    || { tail -n 20 "$work/baseline-first.log" >&2; fail "${first[*]} failed on the unmutated tree: no mutant can be judged"; }
first_limit=$(( (SECONDS - started) * 4 )); [ "$first_limit" -ge 60 ] || first_limit=60
rest_limit=0
if [ ${#rest[@]} -gt 0 ]; then
    started=$SECONDS
    run_suites "$work/tree-0" "$work/baseline-rest.log" 1800 "${rest[@]}" \
        || { tail -n 20 "$work/baseline-rest.log" >&2; fail "${rest[*]} failed on the unmutated tree: no mutant can be judged"; }
    rest_limit=$(( (SECONDS - started) * 4 )); [ "$rest_limit" -ge 60 ] || rest_limit=60
fi
for worker in $(seq 1 $((jobs - 1))); do
    copy_tree "$work/tree-$worker" || fail "cannot copy the tree into $work"
    cp "$subject" "$work/tree-$worker/$file"
    cp "$work/times-tree-0" "$work/times-tree-$worker" 2> /dev/null
done

# A worker: the mutants whose index modulo the workers is its number, in its own copy
work_on() {
    local worker=$1 tree=$work/tree-$1 index mutant line column old new kind outcome status
    current_run=""
    trap '[ -n "$current_run" ] && kill -TERM "$current_run" 2> /dev/null; wait; exit 130' TERM
    for index in "${!picked[@]}"; do
        [ $((index % jobs)) = "$worker" ] || continue
        mutant=${picked[$index]}
        IFS=$'\037' read -r line column old new kind <<< "$mutant"
        if ! apply "$subject" "$line" "$column" "$old" "$new" > "$tree/$file"; then
            outcome=not-run
        else
            run_suites "$tree" "$work/log-$worker" "$first_limit" "${first[@]}"
            status=$?
            outcome=$(verdict "$work/log-$worker" "$status" "$file")
            if [ "$outcome" = survived ] && [ ${#rest[@]} -gt 0 ]; then
                run_suites "$tree" "$work/log-$worker" "$rest_limit" "${rest[@]}"
                status=$?
                outcome=$(verdict "$work/log-$worker" "$status" "$file")
            fi
        fi
        cp "$subject" "$tree/$file"
        printf '%s\037%s\n' "$outcome" "$mutant" >> "$work/results-$worker"
        echo "  [$((index + 1))/${#picked[@]}] $outcome  $(describe "$mutant")"
    done
}

started=$SECONDS
for worker in $(seq 0 $((jobs - 1))); do
    work_on "$worker" &
    workers+=("$!")
done
for pid in "${workers[@]}"; do wait "$pid"; done
workers=()

results=$(cat "$work"/results-* 2> /dev/null | sort -t$'\037' -k2,2n -k3,3n)
count() { printf '%s\n' "$results" | grep -c "^$1"$'\037'; }
killed=$(count killed) survived=$(count survived) not_compiled=$(count not-compiled) not_run=$(count not-run)
section() {
    local outcome=$1 title=$2 entry
    [ "$(count "$outcome")" -gt 0 ] || return 0
    echo
    echo "$title:"
    printf '%s\n' "$results" | grep "^$outcome"$'\037' | while IFS= read -r entry; do
        describe "${entry#*$'\037'}" | sed 's/^/  /'
    done
}
section survived "Surviving mutants (no suite noticed them)"
section not-compiled "Not compiled"
section not-run "Not run (the runner could not be set up, or the text was not found)"
echo
echo "mutate.sh: $file, $((SECONDS - started)) s: killed $killed / survived $survived / not compiled $not_compiled${not_run:+$([ "$not_run" -gt 0 ] && echo " / not run $not_run")}"
exit 0
