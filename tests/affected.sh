#!/usr/bin/env bash
# The tests a change needs: the unit suites, module fixture parts, self-tests and lock
# scenarios, printed as the commands that run them, one per line — and run with --run.
#
#   tests/affected.sh                  the branch's change: from the nearest base (the
#                                      fewest commits back) of where it left a segment-*
#                                      branch or master and where it was made, working
#                                      tree and untracked files included
#   tests/affected.sh <range>          what `git diff --name-only <range>` names
#                                      (88991e4^!, master...HEAD, HEAD~3; a single commit
#                                      is that commit against the working tree, as git diff)
#   tests/affected.sh --files <path>…  those files, as if changed
#   tests/affected.sh --run …          run the commands too, through the same runners, one
#                                      after another (the lock bed last); every one runs
#   tests/affected.sh --why …          each changed file and what it selects, instead
#   tests/affected.sh --check          that every tracked file is placed (below) and the map
#                                      is true: tests/affected-selftest.sh runs it
#
# How a file is placed, mechanically (more is selected rather than less):
#   - a unit suite (tests.qml registers it) covers its closure: from tests/<Suite>.qml every
#     type and singleton named (a capitalised word that is <Word>.qml in the file's own
#     directory or a directory it imports — `import qs.a.b`, `import "rel"`), every quoted
#     path naming a file or directory of the tree (relative to the file or to the tree's
#     root: fixtures, scripts, `Qt.resolvedUrl`), transitively; a directory brings every
#     file in it;
#   - a module fixture part of tests/run-all.sh (`tests/run-modules.sh <dir>…`) covers the
#     closure of tests-modules.qml and of every file in its directories;
#   - tests/affected-map.txt places what a closure cannot see — scripts, shell files, the
#     runners, the lock scenarios' subjects — and lists what needs no test (`none`); a
#     line starting with "+" only adds tests (a broad pattern), it places nothing;
#   - a lock scenario covers its own file and what the map gives it, and runs on any
#     change in the lock closure (the map's `@lock-roots` and their closure) unless the
#     map's `@not-lock` names it;
#   - a self-test (tests/*-selftest.sh, tests/install-test.sh, tests/lock/selftest.sh)
#     covers itself;
#   - a component or view mockup (mockups/components/<name>, mockups/views/<name>) covers
#     the closure of every file in its folder, as a unit suite does (its Mockup.qml, its
#     baseline's PNGs and manifest); its command is `tests/run-mockups.sh --by-system
#     <kind>/<name>…` (--compare on Arch, --load-only elsewhere), the map's `mockup:all` runs
#     every one; a plan (mockups/plans/*) is placed with none: it is not
#     tested, and no closure starts from it.
# A changed path the tree no longer has is scanned as present, so that the files still
# naming it select their tests. A changed file none of these places (deleted with nothing
# naming it, or new: --check fails on a tracked one) selects everything — every unit
# suite, module part, mockup and lock scenario — and is named on stderr.
#
# Exit status: 0 (with --run: every command passed); 1 when a command run failed, or
# --check found a file not placed or a map line that is not true; 2 for a wrong option or
# range, or a tree it cannot read.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
MAP=${AFFECTED_MAP:-$REPO/tests/affected-map.txt}
# shellcheck source=count-suites.sh
source "$REPO/tests/count-suites.sh"

usage() {
    echo "usage: tests/affected.sh [--run | --why] [<git range> | --files <path>…]  |  tests/affected.sh --check" >&2
    exit 2
}
mode=print
range=""
files_given=0
given=()
while [ $# -gt 0 ]; do
    case "$1" in
        --run) mode=run ;;
        --why) mode=why ;;
        --check) mode=check ;;
        --files) files_given=1; shift; given=("$@"); break ;;
        -*) usage ;;
        *) [ -z "$range" ] || usage; range=$1 ;;
    esac
    shift
done
[ "$files_given" = 0 ] || [ -z "$range" ] || usage
[ "$mode" != check ] || { [ -z "$range" ] && [ "$files_given" = 0 ]; } || usage

cd "$REPO" || exit 2
git rev-parse --git-dir > /dev/null 2>&1 || { echo "affected.sh: $REPO is not a git checkout" >&2; exit 2; }
[ -r "$MAP" ] || { echo "affected.sh: cannot read $MAP" >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/affected.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT

# ---- The tree: tracked files and untracked ones not ignored -------------------------
{ git ls-files; git ls-files --others --exclude-standard; } | sort -u > "$work/tree"

# ---- The changed files ----------------------------------------------------------------
: > "$work/changed"
if [ "$mode" = check ]; then
    :
elif [ "$files_given" = 1 ]; then
    printf '%s\n' "${given[@]}" > "$work/changed"
elif [ -n "$range" ]; then
    git diff --name-only --no-renames "$range" -- > "$work/changed" 2> "$work/error" ||
        { echo "affected.sh: not a range git diff takes: $range ($(head -n 1 "$work/error"))" >&2; exit 2; }
else
    # The candidates: where HEAD left each segment-* branch and master (a branch that
    # contains HEAD, HEAD merged into it, says nothing), and where the current branch was
    # made (its reflog's first entry: still right after it was merged into its segment).
    # The base is the nearest: the fewest commits from it to HEAD.
    base="" best=""
    head=$(git rev-parse HEAD)
    current=$(git symbolic-ref --quiet --short HEAD || echo "")
    candidates=()
    for branch in $(git for-each-ref --format='%(refname:short)' 'refs/heads/segment-*' refs/heads/master); do
        candidate=$(git merge-base HEAD "$branch" 2> /dev/null) || continue
        [ "$candidate" = "$head" ] || candidates+=("$candidate")
    done
    if [ -n "$current" ] && [ "$current" != master ]; then
        created=$(git reflog show --format=%H "refs/heads/$current" -- 2> /dev/null | tail -n 1)
        if [ -n "$created" ] && git merge-base --is-ancestor "$created" HEAD 2> /dev/null; then
            candidates+=("$created")
        fi
    fi
    for candidate in "${candidates[@]}"; do
        distance=$(git rev-list --count "$candidate..HEAD")
        if [ -z "$best" ] || [ "$distance" -lt "$best" ]; then base=$candidate best=$distance; fi
    done
    [ -n "$base" ] || { echo "affected.sh: no segment-* or master branch to compare with: name a range" >&2; exit 2; }
    { git diff --name-only --no-renames "$base" --; git ls-files --others --exclude-standard; } > "$work/changed"
fi
sed -i '/^$/d' "$work/changed"
sort -u -o "$work/changed" "$work/changed"

# A changed path the tree no longer has (deleted, renamed away) is scanned as present, so
# that the files still naming it reach it
while read -r file; do
    [ -e "$file" ] || echo "$file"
done < "$work/changed" > "$work/gone"
sort -u "$work/tree" "$work/gone" > "$work/scantree"

# ---- The map --------------------------------------------------------------------------
# rules: "<pattern>\t<target>\t<places: 1, or 0 for a + line>" per target
: > "$work/rules"
lock_roots=()
lazy_files=()
not_lock=()
while read -r pattern targets; do
    case "$pattern" in '' | '#'*) continue ;; esac
    if [ "$pattern" = "@lock-roots" ]; then
        read -r -a lock_roots <<< "$targets"
        continue
    fi
    if [ "$pattern" = "@lazy" ]; then
        read -r -a lazy_files <<< "$targets"
        continue
    fi
    if [ "$pattern" = "@not-lock" ]; then
        read -r -a not_lock <<< "$targets"
        continue
    fi
    [ -n "$targets" ] || { echo "affected.sh: map line without a target: $pattern" >&2; exit 2; }
    places=1
    if [ "${pattern#+}" != "$pattern" ]; then pattern=${pattern#+} places=0; fi
    for target in $targets; do printf '%s\t%s\t%s\n' "$pattern" "$target" "$places" >> "$work/rules"; done
done < "$MAP"

# matches <pattern> <path>: a map pattern (`*` matches anything, `/` included)
matches() {
    # shellcheck disable=SC2053  # the pattern is a glob
    [[ $2 == $1 ]]
}

# ---- The roots of the closures --------------------------------------------------------
# "<target>\t<root file>": unit suites, module parts, the lock closure
suites_agree tests.qml || { echo "affected.sh: tests.qml's suites cannot be read reliably" >&2; exit 2; }
registered_suites tests.qml | awk '{ print $1 }' | sort -u > "$work/suites"
: > "$work/roots"
while read -r suite; do
    printf 'unit:%s\ttests/%s.qml\n' "$suite" "$suite" >> "$work/roots"
done < "$work/suites"

# The module fixture parts, as tests/run-all.sh lists them
part_commands=()
while IFS= read -r command; do part_commands+=("$command"); done < <(
    sed -n 's/^[[:space:]]*"[^|"]*|\(tests\/run-modules\.sh [^"]*\)"[[:space:]]*$/\1/p' tests/run-all.sh)
for index in "${!part_commands[@]}"; do
    printf 'modules:%s\ttests-modules.qml\n' "$index" >> "$work/roots"
    for dir in ${part_commands[index]#tests/run-modules.sh }; do
        grep "^$dir/" "$work/tree" | sed "s|^|modules:$index\t|" >> "$work/roots"
    done
done

# The component and view mockups: every file in the mockup's folder
grep -E '^mockups/(components|views)/[a-z0-9-]+/' "$work/scantree" |
    sed -E 's#^(mockups/(components|views)/[a-z0-9-]+)/.*$#mockup:\1\t&#; s#^mockup:mockups/#mockup:#' >> "$work/roots"
# The mockups that are there now (a deleted one selects nothing to run)
grep -E '^mockups/(components|views)/[a-z0-9-]+/Mockup\.qml$' "$work/tree" | while read -r file; do
    [ -f "$file" ] && dirname "${file#mockups/}"
done | LC_ALL=C sort > "$work/mockups"

while read -r file; do
    for pattern in "${lock_roots[@]}"; do
        if matches "$pattern" "$file"; then printf '@lock\t%s\n' "$file" >> "$work/roots"; break; fi
    done
done < "$work/scantree"

# ---- The closures: "<file>\t<target>" for every file each target reaches --------------
sources=()
while read -r file; do [ -f "$file" ] && sources+=("$file"); done < <(grep -E '\.(qml|js)$' "$work/tree")
# One awk over every source, the tree's file list and the roots read first
awk -v treefile="$work/scantree" -v rootsfile="$work/roots" -v lazy=" ${lazy_files[*]} " '
    function norm(path,    parts, count, out, i, n) {
        n = split(path, parts, "/")
        count = 0
        for (i = 1; i <= n; i++) {
            if (parts[i] == "" || parts[i] == ".") continue
            if (parts[i] == "..") { if (count == 0) return "\001"; count--; continue }
            out[++count] = parts[i]
        }
        path = ""
        for (i = 1; i <= count; i++) path = path (i > 1 ? "/" : "") out[i]
        return path
    }
    # The line without its comments (// to the end, /* … */ over lines), strings kept
    function code(line,    out, i, c, quote) {
        out = ""
        quote = ""
        for (i = 1; i <= length(line); i++) {
            c = substr(line, i, 1)
            if (inblock) {
                if (c == "*" && substr(line, i + 1, 1) == "/") { inblock = 0; i++ }
                continue
            }
            if (quote != "") {
                out = out c
                if (c == "\\") { out = out substr(line, i + 1, 1); i++ }
                else if (c == quote) quote = ""
                continue
            }
            if (c == "/" && substr(line, i + 1, 1) == "/") break
            if (c == "/" && substr(line, i + 1, 1) == "*") { inblock = 1; i++; continue }
            if (c == "\"" || c == "\047" || c == "`") quote = c
            out = out c
        }
        return out
    }
    # edge(from, to, kind): kind "type" (a type or singleton named, an import) or "path"
    # (a quoted path)
    function edge(from, to, kind,    i) {
        if (to == "" || to == "\001" || to == from) return
        if (kind == "path") pathdeps[from] = pathdeps[from] SUBSEP to
        else typed[from, to] = 1
        if (to in exists) { deps[from] = deps[from] SUBSEP to; return }
        # (A top-level directory is too broad to be a fixture: "tests/" in a test of a name)
        if ((to in isdir) && index(to, "/") > 0)
            for (i = 1; i <= nfiles; i++)
                if (index(files[i], to "/") == 1 && files[i] != from) {
                    deps[from] = deps[from] SUBSEP files[i]
                    pathdeps[from] = pathdeps[from] SUBSEP files[i]
                }
    }
    BEGIN {
        while ((getline line < treefile) > 0) {
            exists[line] = 1
            files[++nfiles] = line
            path = line
            while (sub(/\/[^\/]*$/, "", path)) isdir[path] = 1
        }
        while ((getline line < rootsfile) > 0) {
            split(line, field, "\t")
            if (field[2] in exists) { roots[field[1]] = roots[field[1]] SUBSEP field[2] }
        }
    }
    FNR == 1 {
        file = FILENAME
        dir = file
        if (!sub(/\/[^\/]*$/, "", dir)) dir = ""
        ndirs = 1
        dirs[1] = dir
        inblock = 0
    }
    {
        line = code($0)
        # Imports name the directories its types come from
        if (match(line, /^[[:space:]]*import[[:space:]]+qs(\.[A-Za-z0-9_]+)*/)) {
            spec = substr(line, RSTART, RLENGTH)
            sub(/^[[:space:]]*import[[:space:]]+qs\.?/, "", spec)
            gsub(/\./, "/", spec)
            dirs[++ndirs] = spec
            next
        }
        if (match(line, /^[[:space:]]*import[[:space:]]+"[^"]*"/)) {
            spec = substr(line, RSTART, RLENGTH)
            sub(/^[^"]*"/, "", spec); sub(/"$/, "", spec)
            target = norm((dir == "" ? "" : dir "/") spec)
            if (target in exists) edge(file, target, "type")
            else if (target != "\001") dirs[++ndirs] = target
            next
        }
        # Quoted paths naming a file or directory of the tree
        rest = line
        while (match(rest, /"[^"]*"|\047[^\047]*\047/)) {
            text = substr(rest, RSTART + 1, RLENGTH - 2)
            rest = substr(rest, RSTART + RLENGTH)
            if (text ~ /[[:space:]]/ || text !~ /[\/.]/ || text ~ /^[.\/]*$/) continue
            sub(/^file:\/\//, "", text)
            sub(/[:\/]+$/, "", text)
            if (text == "" || text ~ /^[.\/]*$/) continue
            edge(file, norm((dir == "" ? "" : dir "/") text), "path")
            edge(file, norm(text), "path")
        }
        # Types and singletons named (outside strings: "Hardware" as a label names nothing)
        rest = line
        gsub(/"[^"]*"|\047[^\047]*\047/, "\"\"", rest)
        while (match(rest, /[A-Z][A-Za-z0-9_]*/)) {
            word = substr(rest, RSTART, RLENGTH)
            rest = substr(rest, RSTART + RLENGTH)
            if ((file SUBSEP word) in done) continue
            done[file, word] = 1
            for (i = 1; i <= ndirs; i++) {
                candidate = (dirs[i] == "" ? "" : dirs[i] "/") word ".qml"
                if (candidate in exists) { edge(file, candidate, "type"); break }
            }
        }
    }
    END {
        for (target in roots) {
            delete seen
            queue = 0
            n = split(substr(roots[target], 2), start, SUBSEP)
            for (i = 1; i <= n; i++) if (!(start[i] in seen)) { seen[start[i]] = 1; depth[start[i]] = 0; todo[++queue] = start[i] }
            for (head = 1; head <= queue; head++) {
                current = todo[head]
                print current "\t" target
                if (!(current in deps)) continue
                # A lazy file (a list of views loaded when shown): the paths it quotes are
                # followed only from a root that names it itself; its types always
                cut = depth[current] > 1 && index(lazy, " " current " ")
                delete quoted
                if (cut && (current in pathdeps)) {
                    m = split(substr(pathdeps[current], 2), next_files, SUBSEP)
                    for (j = 1; j <= m; j++) quoted[next_files[j]] = 1
                }
                m = split(substr(deps[current], 2), next_files, SUBSEP)
                for (j = 1; j <= m; j++)
                    if (cut && (next_files[j] in quoted) && !((current SUBSEP next_files[j]) in typed)) continue
                    else
                    # A file that is not QML (a script, a fixture) counts for a suite and
                    # the files it names: further away it is something a type runs, and
                    # its test is the one of that type. For the lock closure only its
                    # roots: the map places the scripts the lock runs
                    if (!(next_files[j] in seen) && (depth[current] < (target == "@lock" ? 0 : 2) || next_files[j] ~ /\.(qml|js)$/)) { seen[next_files[j]] = 1; depth[next_files[j]] = depth[current] + 1; todo[++queue] = next_files[j] }
            }
        }
    }
' "${sources[@]}" /dev/null > "$work/reach" || { echo "affected.sh: the closure scan failed" >&2; exit 2; }
sort -u -o "$work/reach" "$work/reach"

ls tests/lock/tests/*.sh 2> /dev/null | sed 's|.*/||; s|\.sh$||' | sort > "$work/scenarios"
# The scenarios a change in the lock closure runs: all but the map's @not-lock ones
while read -r scenario; do
    follows=1
    for glob in "${not_lock[@]}"; do
        # shellcheck disable=SC2053
        [[ $scenario == $glob ]] && follows=0
    done
    [ "$follows" = 0 ] || echo "lock:$scenario"
done < "$work/scenarios" > "$work/lock-closure-scenarios"

# place <file> [placing]: "<target>" lines for what the file selects; nothing when not
# placed. With "placing", only what places it: a closure, a line of the map without "+",
# being a scenario or a self-test.
# Targets: unit:<Suite>|unit:all, modules:<index>|modules:all, lock:<glob>|lock:all,
# self:<script>, mockup:<kind>/<name>|mockup:all, none
place() {
    local file=$1 placing=${2:-} pattern target places
    while IFS=$'\t' read -r pattern target places; do
        [ -z "$placing" ] || [ "$places" = 1 ] || continue
        matches "$pattern" "$file" && echo "$target"
    done < "$work/rules"
    awk -F'\t' -v file="$file" '$1 == file { print $2 }' "$work/reach" | while read -r target; do
        if [ "$target" = "@lock" ]; then
            cat "$work/lock-closure-scenarios"
        else
            echo "$target"
        fi
    done
    case "$file" in
        tests/lock/tests/*.sh) echo "lock:$(basename "$file" .sh)" ;;
        tests/*-selftest.sh | tests/install-test.sh | tests/lock/selftest.sh) echo "self:$file" ;;
        mockups/plans/*) echo none ;;
    esac
}

# ---- --check: every tracked file placed (not by a + line alone), the map true ---------------------------------
if [ "$mode" = check ]; then
    problems=0
    while read -r file; do
        if [ -z "$(place "$file" placing)" ]; then
            echo "not placed: $file — give it a line in tests/affected-map.txt (a test, or none; a + line does not place)"
            problems=$((problems + 1))
        fi
    done < <(git ls-files)
    for glob in "${not_lock[@]}"; do
        grep -q "^lock:" < <(while read -r scenario; do
            # shellcheck disable=SC2053
            [[ $scenario == $glob ]] && echo "lock:$scenario"
        done < "$work/scenarios") || { echo "map: @not-lock $glob names no scenario"; problems=$((problems + 1)); }
    done
    while IFS=$'\t' read -r pattern target _; do
        if ! grep -q . < <(while read -r file; do matches "$pattern" "$file" && echo "$file"; done < "$work/tree"); then
            echo "map: '$pattern' matches no file of the tree"
            problems=$((problems + 1))
        fi
        case "$target" in
            none | unit:all | lock:all | modules:all | mockup:all) ;;
            mockup:*)
                grep -qxF "${target#mockup:}" "$work/mockups" || { echo "map: $target is no component or view mockup in mockups/"; problems=$((problems + 1)); } ;;
            unit:*)
                grep -qx "${target#unit:}" "$work/suites" || { echo "map: $target is no suite tests.qml registers"; problems=$((problems + 1)); } ;;
            lock:*)
                glob=${target#lock:}
                found=0
                while read -r scenario; do
                    # shellcheck disable=SC2053
                    [[ $scenario == $glob ]] && { found=1; break; }
                done < "$work/scenarios"
                [ "$found" = 1 ] || { echo "map: $target names no scenario in tests/lock/tests"; problems=$((problems + 1)); } ;;
            self:*)
                [ -x "${target#self:}" ] || { echo "map: $target is not an executable of the tree"; problems=$((problems + 1)); } ;;
            *) echo "map: '$target' is no target"; problems=$((problems + 1)) ;;
        esac
    done < <(sort -u "$work/rules")
    # Every suite reaches its subject, where a file is named after it
    while read -r suite; do
        subject=${suite%Test}
        candidates=$(grep -E "(^|/)(${subject}|${subject}Rules)\.qml$" "$work/tree")
        [ -n "$candidates" ] || continue
        reached=0
        for candidate in $candidates; do
            grep -qxF "$candidate"$'\t'"unit:$suite" "$work/reach" && reached=1
        done
        if [ "$reached" = 0 ]; then
            echo "closure: $suite reaches none of" $candidates
            problems=$((problems + 1))
        fi
    done < "$work/suites"
    for index in "${!part_commands[@]}"; do
        [ -n "$(awk -F'\t' -v target="modules:$index" '$2 == target' "$work/reach")" ] ||
            { echo "closure: the module part '${part_commands[index]}' reaches nothing"; problems=$((problems + 1)); }
    done
    if [ "$problems" -gt 0 ]; then
        echo "affected.sh --check: $problems problem(s)"
        exit 1
    fi
    echo "affected.sh --check: every tracked file placed ($(git ls-files | wc -l) files), the map true"
    exit 0
fi

: > "$work/selected"
while read -r file; do
    targets=$(place "$file" | sort -u)
    # (A deleted QML file nothing names any more: what used it by a name the scan cannot
    # follow is unknown)
    if [ -z "$(place "$file" placing)" ] || { grep -qxF "$file" "$work/gone" &&
        [[ $file =~ \.(qml|js)$ ]] && ! awk -F'\t' -v file="$file" '$1 == file { found = 1 } END { exit !found }' "$work/reach"; }; then
        echo "affected.sh: $file is placed nowhere (tests/affected-map.txt): everything" >&2
        targets=$(printf '%s\nunit:all\nmodules:all\nmockup:all\nlock:all' "$targets" | sed '/^$/d' | sort -u)
    fi
    if [ "$mode" = why ]; then
        printf '%s\t%s\n' "$file" "$(echo "$targets" | tr '\n' ' ' | sed 's/ $//')"
    fi
    echo "$targets" >> "$work/selected"
done < "$work/changed"
[ "$mode" != why ] || exit 0

# ---- The commands -----------------------------------------------------------------------
sort -u -o "$work/selected" "$work/selected"
commands=()
if grep -qx 'unit:all' "$work/selected"; then
    commands+=("tests/run-unit.sh")
else
    units=$(sed -n 's/^unit://p' "$work/selected" | tr '\n' ' ' | sed 's/ $//')
    [ -z "$units" ] || commands+=("tests/run-unit.sh $units")
fi
if grep -qx 'modules:all' "$work/selected"; then
    printf 'modules:%s\n' "${!part_commands[@]}" >> "$work/selected"
fi
for index in $(sed -n 's/^modules:\([0-9]*\)$/\1/p' "$work/selected" | sort -nu); do
    commands+=("${part_commands[index]}")
done
while read -r script; do commands+=("$script"); done < <(sed -n 's/^self://p' "$work/selected")
if [ -s "$work/mockups" ]; then
    if grep -qx 'mockup:all' "$work/selected"; then
        commands+=("tests/run-mockups.sh --by-system")
    else
        mockups=$(sed -n 's/^mockup://p' "$work/selected" | grep -xF -f "$work/mockups" | tr '\n' ' ' | sed 's/ $//')
        [ -z "$mockups" ] || commands+=("tests/run-mockups.sh --by-system $mockups")
    fi
fi
if grep -qx 'lock:all' "$work/selected"; then
    commands+=("tests/lock/run.sh")
else
    scenarios=$(sed -n 's/^lock://p' "$work/selected" | while read -r glob; do
        while read -r scenario; do
            # shellcheck disable=SC2053
            [[ $scenario == $glob ]] && echo "$scenario"
        done < "$work/scenarios"
    done | sort -u | tr '\n' ' ' | sed 's/ $//')
    [ -z "$scenarios" ] || commands+=("tests/lock/run.sh $scenarios")
fi

if [ ${#commands[@]} = 0 ]; then
    echo "affected.sh: nothing to run for $(wc -l < "$work/changed") changed file(s)" >&2
    exit 0
fi
if [ "$mode" = print ]; then
    printf '%s\n' "${commands[@]}"
    exit 0
fi

failed=()
for command in "${commands[@]}"; do
    echo
    echo "==== $command"
    # shellcheck disable=SC2086  # the command's words
    $command || failed+=("$command")
done
echo
if [ ${#failed[@]} -gt 0 ]; then
    echo "affected.sh: FAILED:"
    printf '  %s\n' "${failed[@]}"
    exit 1
fi
echo "affected.sh: passed (${#commands[@]} command(s)); the commit still needs tests/run-all.sh --quick"
exit 0
