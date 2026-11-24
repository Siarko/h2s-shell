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
#   tests/mutate.sh --accepted <list> …
#                                       the accepted survivors (default:
#                                       tests/mutants-accepted.txt, when there is one)
#   tests/mutate.sh --only <list> …     only the mutants whose keys <list> names (entries
#                                       in the accepted list's form; `#` lines and blank
#                                       ones skipped): tests/release-check.sh's quiet second
#                                       look at accepted entries that came out stale
#   tests/mutate.sh -j <n> …            at most <n> mutants at once (default: as many as the
#                                       unit runner would run shards: half the processors,
#                                       at most 16, no more than the run's memory budget
#                                       holds at one memory cap each)
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
#   killed        a check failed (a `FAIL:` line) or a JavaScript error (TypeError,
#                 ReferenceError, …) names the mutated file; or the run took longer than
#                 four times the unmutated run's time (at least 60 s): a hang, shown as
#                 "killed (time limit)"; or Quickshell was stopped at the memory cap or the
#                 run's budget (the runner says "killed at the memory cap"): a mutant that
#                 runs away, shown as "killed (memory cap)"; or the run failed with neither
#                 (an error naming another file, a crash, the runner's own time-out of a
#                 suite): shown as "killed (unclear failure)". The last three are listed
#                 apart, and the mutant is run once more when every other mutant is done —
#                 alone, against limits measured again on the unmutated copy (the larger of
#                 the two); the second run's outcome is the mutant's: under load, from other
#                 mutants or anything else, a slow survivor reaches the time limit, a
#                 neighbour's memory the budget, and a suite can fail on its own (a late
#                 answer reaching a suite already torn down). An accepted survivor that a
#                 suite killed is run once more the same way. A measurement that fails is
#                 made once more; failing again, the first limits stay, with a warning
# Lock scenarios and module fixture parts are not run: only unit suites.
#
# Accepted survivors: a mutant no check can tell apart (an equivalent mutant) is listed in
# tests/mutants-accepted.txt, one line per mutant, its fields separated by tabs —
#   <file>  <old> -> <new>  #<n>  <the line it mutates, without its leading and trailing blanks>
# where #<n> counts the mutants with the same old and new text on lines that read the same
# (1 for the first in the file): a key that holds while lines move and breaks when the line
# is edited. Each entry, or block of entries, has a `# reason: <why>` line above it (a blank
# line ends a block); an entry without one is a list error. Such a survivor is shown apart,
# as accepted; an entry that matches no mutant any more, or one a suite now kills, is stale
# (the latter also printed as `stale-killed<TAB><entry>`, for tests/release-check.sh's
# second look).
# Every surviving mutant not accepted is printed once more as a line for the list:
# `survivor-key<TAB><entry>`. The summary: `survived <n> (accepted <m>) / stale <k>`.
#
# Each mutant's Quickshell runs under the unit runner's memory cap (tests/memory-cap.sh,
# H2S_TEST_MEMORY_MAX, 1536M by default), all of them within one memory budget for the run
# (H2S_TEST_MEMORY_BUDGET: by default the memory available less a reserve), made here: a
# mutant that runs away is stopped at its cap, and mutants that run away together at the
# budget, either way counted as killed. Tools are taken by tests/run-unit.sh, as always (the pinned ones where
# there is `nix`, else PATH; H2S_TEST_TOOLS says which). Each worker has its own copy of the tree, under this
# run's temp dir, removed by its path when the run ends (an interrupt included).
#
# Exit status: 0 when it ran (whatever survived); 2 for a wrong option, file or accepted list, suites that
# fail unmutated, or a copy that could not be made; 130 when interrupted.
set -uo pipefail
export LC_ALL=C

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd -P)
usage() { echo "usage: tests/mutate.sh [--list] [--max <n>] [--seed <n>] [--accepted <list>] [--only <list>] [-j <n>] <file> [<suite>…]  |  tests/mutate.sh --judge <log> <status> <file>" >&2; exit 2; }
fail() { echo "mutate.sh: $*" >&2; exit 2; }

# verdict <log> <status> <file>: survived, not-run, not-compiled, capped (killed at the
# memory cap), timed-out (stopped at the time limit: 124 from `timeout`, 137 from its -k),
# killed (a check's FAIL line, or an error naming the file) or unclear (a failure with
# neither: an error in another file, a crash, a suite the runner timed out). A load error names the file at a line in Quickshell's `caused by`
# chain; a JavaScript error at run time (TypeError, ReferenceError, …) names it too, and is
# a kill
verdict() {
    local log=$1 status=$2 subject=$3
    case "$status" in
        0) echo survived; return ;;
        2) echo not-run; return ;;
    esac
    if grep -E "caused by @${subject//./\\.}\[[1-9][0-9]*:[0-9]+\]" "$log" 2> /dev/null | grep -q -v -E "(Type|Reference|Range|Syntax|Eval|URI)Error: "; then
        echo not-compiled
    elif grep -q -E "killed at the (memory cap|run's memory budget)" "$log" 2> /dev/null; then
        echo capped
    elif [ "$status" = 124 ] || [ "$status" = 137 ]; then
        echo timed-out
    elif grep -q -E "  FAIL: " "$log" 2> /dev/null \
        || grep -E "${subject//./\\.}[^A-Za-z0-9_/]" "$log" 2> /dev/null | grep -q -E "(Type|Reference|Range|Syntax|Eval|URI)Error"; then
        echo killed
    else
        echo unclear
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
accepted_list=""
only_list=""
while [ $# -gt 0 ]; do
    case "$1" in
        --list) list_only=1; shift ;;
        --accepted) [ -n "${2:-}" ] || usage; [ -f "$2" ] || fail "--accepted: no file $2"; accepted_list=$2; shift 2 ;;
        --only) [ -n "${2:-}" ] || usage; [ -f "$2" ] || fail "--only: no file $2"; only_list=$2; shift 2 ;;
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

# ---- The accepted survivors -------------------------------------------------------------
[ -n "$accepted_list" ] || accepted_list=$REPO/tests/mutants-accepted.txt
declare -A accepted=()
accepted_entries=()
if [ -f "$accepted_list" ]; then
    number=0 reason=""
    while IFS= read -r raw || [ -n "$raw" ]; do
        number=$((number + 1))
        raw=${raw%$'\r'}
        if [[ "$raw" =~ ^[[:space:]]*$ ]]; then reason=""; continue; fi
        if [[ "$raw" == '#'* ]]; then
            [[ "$raw" =~ ^#\ reason:[[:space:]]*[^[:space:]] ]] && reason=1
            continue
        fi
        [ -n "$reason" ] || fail "$accepted_list:$number: an entry without a '# reason: …' line above it"
        IFS=$'\t' read -r -a fields <<< "$raw"
        { [ ${#fields[@]} = 4 ] && [[ "${fields[1]}" == *" -> "* ]] && [[ "${fields[2]}" =~ ^#[1-9][0-9]*$ ]]; } \
            || fail "$accepted_list:$number: not '<file><TAB><old> -> <new><TAB>#<n><TAB><line>'"
        [ "${fields[0]}" = "$file" ] || continue
        accepted[$raw]=1
        accepted_entries+=("$raw")
    done < "$accepted_list"
fi

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
    ! declare -F memory_cap_finish > /dev/null || memory_cap_finish
    rm -rf "$work"
}
trap stop EXIT
trap 'exit 130' INT TERM HUP
subject=$work/subject.qml
cp "$REPO/$file" "$subject" || fail "cannot copy $file into $work"

mapfile -t all < <(enumerate "$subject")
if [ ${#all[@]} = 0 ]; then
    if [ ${#accepted_entries[@]} -gt 0 ]; then
        echo "mutate.sh: $file, 0 s: killed 0 / survived 0 (accepted 0) / stale ${#accepted_entries[@]} / not compiled 0"
    else
        echo "mutate.sh: $file: no mutants"
    fi
    exit 0
fi
total=${#all[@]}

# Each mutant's key, as an entry of the accepted list names it
trim() { local text=${1//$'\t'/ }; text=${text#"${text%%[![:space:]]*}"}; printf '%s' "${text%"${text##*[![:space:]]}"}"; }
mapfile -t source_lines < "$subject"
declare -A occurrences=() key_of=() all_keys=()
for mutant in "${all[@]}"; do
    IFS=$'\037' read -r line column old new kind <<< "$mutant"
    old=${old//$'\t'/ } new=${new//$'\t'/ }
    text=$(trim "${source_lines[line - 1]}")
    id=$old$'\037'$new$'\037'$text
    occurrences[$id]=$(( ${occurrences[$id]:-0} + 1 ))
    printf -v key '%s\t%s -> %s\t#%d\t%s' "$file" "$old" "$new" "${occurrences[$id]}" "$text"
    key_of[$mutant]=$key
    all_keys[$key]=1
done

# describe <mutant line>: file:line:column  'old' -> 'new'  | the line as it reads
describe() {
    local line column old new kind source
    IFS=$'\037' read -r line column old new kind <<< "$1"
    source=$(sed -n "${line}p" "$subject" | sed 's/^[[:space:]]*//' | cut -c1-90)
    printf "%s:%s:%s  '%s' -> '%s'  | %s\n" "$file" "$line" "$column" "$old" "$new" "$source"
}

# With --only, the mutants it names, nothing else
if [ -n "$only_list" ]; then
    declare -A only=()
    while IFS= read -r raw || [ -n "$raw" ]; do
        raw=${raw%$'\r'}
        [[ "$raw" =~ ^[[:space:]]*$ ]] || [[ "$raw" == '#'* ]] || only[$raw]=1
    done < "$only_list"
    named=()
    for mutant in "${all[@]}"; do [ -z "${only[${key_of[$mutant]}]:-}" ] || named+=("$mutant"); done
    [ ${#named[@]} -gt 0 ] || fail "--only: $only_list names no mutant of $file"
    all=("${named[@]}")
fi

# The pick: with --max, a random one by the seed (bash's own generator: the same seed picks
# the same mutants wherever this bash runs), in file order
picked=("${all[@]}")
if [ -n "$max" ] && [ "$max" -lt ${#all[@]} ]; then
    [ -n "$seed" ] || seed=$((RANDOM * 32768 + RANDOM))
    RANDOM=$seed
    keyed=()
    for index in "${!all[@]}"; do keyed+=("$RANDOM$RANDOM $index"); done
    mapfile -t chosen < <(printf '%s\n' "${keyed[@]}" | sort -n | head -n "$max" | awk '{ print $2 }' | sort -n)
    picked=()
    for index in "${chosen[@]}"; do picked+=("${all[$index]}"); done
fi
pick_note="${#picked[@]} of $total mutants"
[ -z "$only_list" ] || pick_note="$pick_note (--only $only_list)"
[ -n "$max" ] && [ ${#picked[@]} -lt ${#all[@]} ] && pick_note="$pick_note (--max $max --seed $seed)"

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

# The memory budget of the whole run, every mutant's runner inside it (they take it over
# from the environment); said here, ended by stop
# shellcheck source=memory-cap.sh
source "$REPO/tests/memory-cap.sh"
memory_cap_init
if [ -z "$jobs" ]; then
    jobs=$(( $(nproc 2> /dev/null || echo 2) / 2 ))
    [ "$jobs" -ge 1 ] || jobs=1
    [ "$jobs" -le 16 ] || jobs=16
    memory_jobs=$(memory_cap_jobs 1100000)
    [ "$memory_jobs" -ge "$jobs" ] || jobs=$memory_jobs
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

# The unmutated runs: they must pass, and their times set each mutant's limit (at least
# H2S_MUTATE_MIN_LIMIT seconds, 60 by default: tests/mutate-selftest.sh makes it short)
min_limit=${H2S_MUTATE_MIN_LIMIT:-60}
[[ "$min_limit" =~ ^[1-9][0-9]*$ ]] || fail "H2S_MUTATE_MIN_LIMIT needs a number above 0"
cp "$work/times" "$work/times-tree-0" 2> /dev/null
started=$SECONDS
run_suites "$work/tree-0" "$work/baseline-first.log" 900 "${first[@]}" \
    || { tail -n 20 "$work/baseline-first.log" >&2; fail "${first[*]} failed on the unmutated tree: no mutant can be judged"; }
first_limit=$(( (SECONDS - started) * 4 )); [ "$first_limit" -ge "$min_limit" ] || first_limit=$min_limit
rest_limit=0
if [ ${#rest[@]} -gt 0 ]; then
    started=$SECONDS
    run_suites "$work/tree-0" "$work/baseline-rest.log" 1800 "${rest[@]}" \
        || { tail -n 20 "$work/baseline-rest.log" >&2; fail "${rest[*]} failed on the unmutated tree: no mutant can be judged"; }
    rest_limit=$(( (SECONDS - started) * 4 )); [ "$rest_limit" -ge "$min_limit" ] || rest_limit=$min_limit
fi
for worker in $(seq 1 $((jobs - 1))); do
    copy_tree "$work/tree-$worker" || fail "cannot copy the tree into $work"
    cp "$subject" "$work/tree-$worker/$file"
    cp "$work/times-tree-0" "$work/times-tree-$worker" 2> /dev/null
done

# judge <tree> <log> <first limit> <rest limit> <mutant>: OUTCOME, the mutant applied in that
# copy and its suites run (the others only when the first passed); the copy put back
judge() {
    local tree=$1 log=$2 limit_first=$3 limit_rest=$4 line column old new kind status
    IFS=$'\037' read -r line column old new kind <<< "$5"
    if ! apply "$subject" "$line" "$column" "$old" "$new" > "$tree/$file"; then
        OUTCOME=not-run
    else
        run_suites "$tree" "$log" "$limit_first" "${first[@]}"
        status=$?
        OUTCOME=$(verdict "$log" "$status" "$file")
        if [ "$OUTCOME" = survived ] && [ ${#rest[@]} -gt 0 ]; then
            run_suites "$tree" "$log" "$limit_rest" "${rest[@]}"
            status=$?
            OUTCOME=$(verdict "$log" "$status" "$file")
        fi
    fi
    cp "$subject" "$tree/$file"
}
shown_as() {
    case "$1" in
        capped) echo "killed (memory cap)" ;;
        timed-out) echo "killed (time limit)" ;;
        unclear) echo "killed (unclear failure)" ;;
        *) echo "$1" ;;
    esac
}

# A worker: the mutants whose index modulo the workers is its number, in its own copy
work_on() {
    local worker=$1 index mutant OUTCOME
    current_run=""
    trap '[ -n "$current_run" ] && kill -TERM "$current_run" 2> /dev/null; wait; exit 130' TERM
    for index in "${!picked[@]}"; do
        [ $((index % jobs)) = "$worker" ] || continue
        mutant=${picked[$index]}
        judge "$work/tree-$worker" "$work/log-$worker" "$first_limit" "$rest_limit" "$mutant"
        printf '%s\037%s\n' "$OUTCOME" "$mutant" >> "$work/results-$worker"
        echo "  [$((index + 1))/${#picked[@]}] $(shown_as "$OUTCOME")  $(describe "$mutant")"
    done
}

started=$SECONDS
for worker in $(seq 0 $((jobs - 1))); do
    work_on "$worker" &
    workers+=("$!")
done
for pid in "${workers[@]}"; do wait "$pid"; done
workers=()

# Once more, alone: a mutant stopped at the time limit or at a memory limit was judged while
# the run's other mutants, and whatever else the machine ran, took their share of it — a slow
# survivor or a neighbour's memory is not a kill. So was an accepted survivor that a suite
# killed: under load a suite can fail on its own (a late answer reaching a suite already torn
# down), and the entry would come out stale. Each runs again in the first copy, one at a
# time, against limits measured again on the unmutated copy as the machine is now (the larger
# of then and now); the second outcome is the mutant's.
again=()
while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    outcome=${entry%%$'\037'*} mutant=${entry#*$'\037'}
    case "$outcome" in
        timed-out | capped | unclear) again+=("$mutant") ;;
        killed) [ -z "${accepted[${key_of[$mutant]}]:-}" ] || again+=("$mutant") ;;
    esac
done < <(cat "$work"/results-* 2> /dev/null | sort -t$'\037' -k2,2n -k3,3n)
if [ ${#again[@]} -gt 0 ]; then
    echo "mutate.sh: ${#again[@]} stopped at a limit, failed unclearly, or accepted but killed: each once more, alone"
    # measure_again <limit now> <log> <cap s> <suite>…: MEASURED, the larger of the limit now
    # and four times an unmutated run as the machine is now; a run that fails is made once
    # more, and failing again leaves the limit as it was, with a warning (the results so far
    # stand). Not in a subshell: stop must see the run under way
    measure_again() {
        local limit=$1 log=$2 cap=$3 try measured
        shift 3
        for try in 1 2; do
            measured=$SECONDS
            if run_suites "$work/tree-0" "$log" "$cap" "$@"; then
                [ $(( (SECONDS - measured) * 4 )) -le "$limit" ] || limit=$(( (SECONDS - measured) * 4 ))
                MEASURED=$limit
                return
            fi
        done
        echo "mutate.sh: warning: $* failed twice on the unmutated tree, measured again: the first limit ($limit s) stays" >&2
        tail -n 20 "$log" >&2
        MEASURED=$limit
    }
    measure_again "$first_limit" "$work/again-first.log" 900 "${first[@]}"
    again_first=$MEASURED again_rest=$rest_limit
    if [ ${#rest[@]} -gt 0 ]; then
        measure_again "$rest_limit" "$work/again-rest.log" 1800 "${rest[@]}"
        again_rest=$MEASURED
    fi
    for index in "${!again[@]}"; do
        mutant=${again[$index]}
        judge "$work/tree-0" "$work/log-again" "$again_first" "$again_rest" "$mutant"
        printf '%s\037%s\n' "$OUTCOME" "$mutant" >> "$work/again"
        echo "  [again $((index + 1))/${#again[@]}] $(shown_as "$OUTCOME")  $(describe "$mutant")"
    done
fi

# The outcomes, a second look's in place of the first
results=$(cat "$work"/results-* "$work"/again 2> /dev/null | awk -F'\037' '
    { mutant = substr($0, index($0, "\037") + 1); if (!(mutant in outcome)) order[++n] = mutant; outcome[mutant] = $1 }
    END { for (i = 1; i <= n; i++) printf "%s\037%s\n", outcome[order[i]], order[i] }' | sort -t$'\037' -k2,2n -k3,3n)
# An accepted survivor is shown apart; an entry no survivor matches is stale
declare -A outcome_of=()
relabelled=""
while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    outcome=${entry%%$'\037'*} mutant=${entry#*$'\037'}
    outcome_of[${key_of[$mutant]}]=$outcome
    [ "$outcome" = survived ] && [ -n "${accepted[${key_of[$mutant]}]:-}" ] && outcome=accepted
    relabelled+=$outcome$'\037'$mutant$'\n'
done <<< "$results"
results=${relabelled%$'\n'}
stale_entries=()
for entry in "${accepted_entries[@]}"; do
    if [ -z "${all_keys[$entry]:-}" ]; then
        stale_entries+=("$entry")
    else
        case "${outcome_of[$entry]:-}" in "" | survived | not-run) ;; *) stale_entries+=("$entry") ;; esac
    fi
done
count() { printf '%s\n' "$results" | grep -c "^$1"$'\037'; }
capped=$(count capped) timed_out=$(count timed-out) unclear=$(count unclear)
killed=$(( $(count killed) + capped + timed_out + unclear )) accepted_count=$(count accepted) not_compiled=$(count not-compiled) not_run=$(count not-run)
survived=$(( $(count survived) + accepted_count ))
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
section accepted "Accepted survivors (in $accepted_list)"
section capped "Killed at the memory cap or the run's budget, alone too (Quickshell ran away: counted as killed)"
section timed-out "Killed at the time limit, alone too (a hang: counted as killed)"
section unclear "Killed by a failure that names neither a check nor the file, alone too (counted as killed)"
section not-compiled "Not compiled"
section not-run "Not run (the runner could not be set up, or the text was not found)"
if [ ${#stale_entries[@]} -gt 0 ]; then
    echo
    echo "Stale accepted entries (no such survivor now: remove them from $accepted_list):"
    printf '  %s\n' "${stale_entries[@]}"
    # Those a suite killed now, as lines for a second look (tests/release-check.sh reruns them
    # alone with --only): a busy machine can make a survivor look killed; a key that matches
    # no mutant any more needs none
    for entry in "${stale_entries[@]}"; do
        [ -z "${all_keys[$entry]:-}" ] || printf 'stale-killed\t%s\n' "$entry"
    done
fi
if [ "$(count survived)" -gt 0 ]; then
    echo
    echo "The survivors' keys (an entry of the accepted list, under a '# reason: …' line, for one that cannot be told apart):"
    printf '%s\n' "$results" | grep "^survived"$'\037' | while IFS= read -r entry; do
        printf 'survivor-key\t%s\n' "${key_of[${entry#*$'\037'}]}"
    done
fi
echo
echo "mutate.sh: $file, $((SECONDS - started)) s: killed $killed$(limits=(); [ "$capped" -gt 0 ] && limits+=("$capped at the memory cap"); [ "$timed_out" -gt 0 ] && limits+=("$timed_out at the time limit"); [ "$unclear" -gt 0 ] && limits+=("$unclear by unclear failures"); [ ${#limits[@]} = 0 ] || printf ' (%s)' "$(IFS=,; echo "${limits[*]}" | sed 's/,/, /g')") / survived $survived (accepted $accepted_count) / stale ${#stale_entries[@]} / not compiled $not_compiled${not_run:+$([ "$not_run" -gt 0 ] && echo " / not run $not_run")}"
exit 0
