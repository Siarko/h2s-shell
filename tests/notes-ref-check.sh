#!/usr/bin/env bash
# Code refers to code, and where it truly matters to docs/; never to the working notes,
# which are kept outside the repository. This check fails on a file of the repository
# (tracked, or untracked and not ignored, as tests/affected.sh counts them) that mentions the
# notes' directory, as a path of its own or joined to another, "notes" ending there or
# followed by "/" (not "notes-app", "notes.db"):
#   notes/…, ./notes/…, ../notes             a path of its own (not src/notes/)
#   dir + "/notes/…"                         a string joined to a directory (in QML too, so
#                                            a module named notes is named otherwise)
#   $root/notes, ${root}/notes, "$REPO"/notes   a variable's directory, but not one that is
#                                            not the repository's: $HOME, $XDG_…, $TMPDIR
#   $(git rev-parse --show-toplevel)/notes   a command substitution's directory
#
# Not checked: CHANGELOG.md from its first released section on (released text stays as it
# was released), and this check's own files, which have to name what they look for.
#
# The allowance (tests/notes-ref-allowance.txt) lists files that still mention the notes,
# each with the number of mentions it may keep, one "<count> <path>" per line ("#" starts a
# comment). Their mentions are reported, not failed; a file with more than its count fails,
# and so does a line whose count is higher than the file's mentions (lower it, or remove the
# line once the file has none), so the list only shrinks.
#
#   tests/notes-ref-check.sh [--root <dir>] [--list]
#
# --root checks another git tree (its files and its own allowance), for the check's
# own self-test. --list prints every allowed mention too.
#
# Exit status: 0 when nothing but allowed mentions is found, 1 when something else is,
# 2 for a wrong option, a root that is no git tree, or an allowance line that cannot be read.
set -uo pipefail
export LC_ALL=C

root=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
list=0
while [ $# -gt 0 ]; do
    case "$1" in
        --list) list=1 ;;
        --root)
            [ $# -ge 2 ] || { echo "notes-ref-check.sh: --root needs a directory" >&2; exit 2; }
            root=$(cd "$2" 2> /dev/null && pwd) || { echo "notes-ref-check.sh: no directory $2" >&2; exit 2; }
            shift
            ;;
        *) echo "usage: tests/notes-ref-check.sh [--root <dir>] [--list]" >&2; exit 2 ;;
    esac
    shift
done

allowance_file=tests/notes-ref-allowance.txt
own_files=(tests/notes-ref-check.sh tests/notes-ref-check-selftest.sh "$allowance_file")

# What counts as a mention, as extended regular expressions: the directory's name after a
# prefix (any number of ./ and ../ between), then "/" or the end of the name
directory=notes
up='(\.{1,2}/)*'
end='(/|[^A-Za-z0-9_.-]|$)'
patterns=(
    "(^|[^A-Za-z0-9_./\$-])$up$directory/"                     # notes/… as a path of its own
    "(^|[^A-Za-z0-9_./-])(\.{1,2}/)+$directory$end"            # ../notes
    "[\"'\`]/$up$directory$end"                                # dir + "/notes…"
    "\\\$\\{?[A-Za-z_][A-Za-z0-9_]*\\}?\"?/$up$directory$end"   # $root/notes, "$REPO"/notes
    "\\)\"?/$up$directory$end"                                  # $(…)/notes
)
pattern=$(IFS='|'; echo "${patterns[*]}")
# A variable's directory that is not the repository's (matched against the mention itself)
elsewhere='\$\{?(HOME|XDG_[A-Z_]+|TMPDIR)\}?"?/'

tracked=$(git -C "$root" ls-files --cached --others --exclude-standard 2> /dev/null) ||
    { echo "notes-ref-check.sh: $root is no git tree" >&2; exit 2; }

# The allowance: path -> count
declare -A allowed=()
if [ -f "$root/$allowance_file" ]; then
    number=0
    while IFS= read -r line || [ -n "$line" ]; do
        number=$((number + 1))
        line=${line%%#*}
        read -r count path rest <<< "$line"
        [ -n "${count:-}" ] || continue
        if ! [[ "$count" =~ ^[1-9][0-9]*$ ]] || [ -z "${path:-}" ] || [ -n "${rest:-}" ]; then
            echo "notes-ref-check.sh: $allowance_file:$number: not \"<count> <path>\": $line" >&2
            exit 2
        fi
        allowed[$path]=$count
    done < "$root/$allowance_file"
fi

# Every mention as <file>:<line>:<match>, the exempt ones left out
changelog_released=$(grep -n -m 1 -E '^## \[[0-9]' "$root/CHANGELOG.md" 2> /dev/null | cut -d: -f1)
mentions=$(cd "$root" && grep -v -x -F "$(printf '%s\n' "${own_files[@]}")" <<< "$tracked" | tr '\n' '\0' |
    xargs -0 -r grep -I -s -d skip -D skip -H -n -o -E -- "$pattern" |
    elsewhere=$elsewhere awk -F: -v released="${changelog_released:-0}" '
        { mention = $0; sub(/^[^:]*:[^:]*:/, "", mention) }
        !($1 == "CHANGELOG.md" && released > 0 && $2 >= released) && mention !~ ENVIRON["elsewhere"]')

declare -A found=()
while IFS=: read -r file _; do
    [ -n "$file" ] || continue
    found[$file]=$((${found[$file]:-0} + 1))
done <<< "$mentions"

findings=0
allowed_mentions=0
allowed_files=0
# Mentions in files the allowance does not cover, or more than it allows
while IFS=: read -r file line _; do
    [ -n "$file" ] || continue
    if [ -z "${allowed[$file]:-}" ] || [ "${found[$file]}" -gt "${allowed[$file]}" ]; then
        echo "$file:$line: $(sed -n "${line}p" "$root/$file" | cut -c 1-120)"
        findings=$((findings + 1))
    elif [ "$list" = 1 ]; then
        echo "  allowed $file:$line: $(sed -n "${line}p" "$root/$file" | cut -c 1-120)"
    fi
done <<< "$mentions"
for file in "${!found[@]}"; do
    if [ -n "${allowed[$file]:-}" ] && [ "${found[$file]}" -gt "${allowed[$file]}" ]; then
        echo "$file: ${found[$file]} mentions, the allowance gives it ${allowed[$file]}"
    fi
done
# Allowance lines that give more than the file has
for file in $(printf '%s\n' "${!allowed[@]}" | sort); do
    have=${found[$file]:-0}
    if [ "$have" -lt "${allowed[$file]}" ]; then
        if [ "$have" = 0 ]; then
            echo "$allowance_file: $file has no mention now: remove its line"
        else
            echo "$allowance_file: $file has $have mentions now, not ${allowed[$file]}: lower its count"
        fi
        findings=$((findings + 1))
    elif [ "$have" = "${allowed[$file]}" ]; then
        allowed_mentions=$((allowed_mentions + have))
        allowed_files=$((allowed_files + 1))
    fi
done

[ "$allowed_files" = 0 ] || echo "notes-ref-check: $allowed_mentions allowed mention(s) in $allowed_files file(s), listed in $allowance_file"
if [ "$findings" -gt 0 ]; then
    echo "notes-ref-check: $findings finding(s)"
    exit 1
fi
echo "notes-ref-check: passed"
exit 0
