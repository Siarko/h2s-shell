#!/usr/bin/env bash
# The documentation's hard rules, as a lint over README.md and every Markdown file under
# docs/ (CLAUDE.md, "Documentation"):
#
#   outside-link   a relative link that leaves the repository (what is outside it is no
#                  reader's, even where it happens to exist beside a developer's checkout)
#   broken-link    a relative link to a file that is not there
#   environment    a developer's environment: a home path, a checkout folder under ~, a
#                  machine model, "the owner's machine" (the pattern list below)
#   systems        a "NixOS" heading without an "Arch" heading beside it (the same level,
#                  under the same parent), or the other way round
#   english        text that is not English (Polish letters and a few common Polish words)
#
# A lint, not proof: review reads for the rest. Links and headings inside fenced code
# blocks and inline code do not count; the environment and language checks read code too.
#
#   tests/docs-check.sh [--rules] [--root <dir>]
#
# --rules is the only check there is (and the default). --root checks another tree laid out
# like the checkout (its README.md and docs/), for the lint's own self-test.
#
# Exit status: 0 when every file keeps the rules, 1 when one does not (each finding is
# printed as <file>:<line>: <rule>: <text>), 2 for a wrong option or a root without docs.
set -uo pipefail
export LC_ALL=C

root=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
while [ $# -gt 0 ]; do
    case "$1" in
        --rules) ;;
        --root)
            [ $# -ge 2 ] || { echo "docs-check.sh: --root needs a directory" >&2; exit 2; }
            root=$(cd "$2" 2> /dev/null && pwd) || { echo "docs-check.sh: no directory $2" >&2; exit 2; }
            shift
            ;;
        *) echo "usage: tests/docs-check.sh [--rules] [--root <dir>]" >&2; exit 2 ;;
    esac
    shift
done

files=()
[ -f "$root/README.md" ] && files+=("README.md")
if [ -d "$root/docs" ]; then
    while IFS= read -r file; do files+=("${file#"$root"/}"); done \
        < <(find "$root/docs" -type f -name '*.md' | sort)
fi
[ "${#files[@]}" -gt 0 ] || { echo "docs-check.sh: no README.md and no docs/ under $root" >&2; exit 2; }

# What names a developer's environment, as extended regular expressions (case ignored)
environment_patterns=(
    '/home/[A-Za-z0-9_.-]+'
    '~/(src|Projects|wt)/'
    '/Users/[A-Za-z0-9_.-]+'
    '[A-Za-z]:\\Users\\'
    'Framework (Laptop )?1[0-9]'
    'ThinkPad'
    'MacBook'
    'XPS 1[0-9]'
    "owner's (machine|laptop|computer|setup|config)"
    'my (machine|laptop|computer|setup)'
)
# Text that is not English: Polish letters (byte sequences, so LC_ALL=C matches them) and
# common Polish words no English sentence holds
english_pattern='ą|ć|ę|ł|ń|ó|ś|ź|ż|Ą|Ć|Ę|Ł|Ń|Ó|Ś|Ź|Ż|\b(jest|oraz|albo|tylko|dlaczego|trzeba|bardzo|teraz|jeszcze)\b'

findings=0
finding() {
    echo "$1:$2: $3: $4"
    findings=$((findings + 1))
}

# The file with fenced code blocks and inline code blanked, line numbers kept
prose() {
    awk '
        /^[[:space:]]*(```|~~~)/ { fenced = !fenced; print ""; next }
        fenced { print ""; next }
        { gsub(/`[^`]*`/, ""); print }
    ' "$1"
}

for file in "${files[@]}"; do
    path=$root/$file
    directory=$(dirname "$path")

    # Links: inline [text](target "title") and reference definitions [label]: target
    while IFS=$'\t' read -r line target; do
        target=${target%%#*}
        target=${target%%\?*}
        [ -n "$target" ] || continue
        case "$target" in [A-Za-z]*:*) continue ;; esac
        if [ "${target#/}" != "$target" ]; then resolved=$root$target; else resolved=$directory/$target; fi
        resolved=$(realpath -m "$resolved")
        case "$resolved/" in
            "$root/"*) [ -e "$resolved" ] || finding "$file" "$line" broken-link "$target" ;;
            *) finding "$file" "$line" outside-link "$target" ;;
        esac
    done < <(prose "$path" | awk '
        {
            text = $0
            while (match(text, /\]\([^)]*\)/)) {
                target = substr(text, RSTART + 2, RLENGTH - 3)
                sub(/^[[:space:]]*</, "", target); sub(/>.*$/, "", target)
                sub(/^[[:space:]]+/, "", target); sub(/[[:space:]].*$/, "", target)
                print NR "\t" target
                text = substr(text, RSTART + RLENGTH)
            }
            if (match($0, /^[[:space:]]*\[[^]]+\]:[[:space:]]*[^[:space:]]+/)) {
                target = $0
                sub(/^[[:space:]]*\[[^]]+\]:[[:space:]]*/, "", target); sub(/[[:space:]].*$/, "", target)
                print NR "\t" target
            }
        }')

    for pattern in "${environment_patterns[@]}"; do
        while IFS=: read -r line text; do
            finding "$file" "$line" environment "$(cut -c 1-120 <<< "$text")"
        done < <(grep -niE -- "$pattern" "$path")
    done

    while IFS=: read -r line text; do
        finding "$file" "$line" english "$(cut -c 1-120 <<< "$text")"
    done < <(grep -nE -- "$english_pattern" "$path")

    # Headings: each "NixOS" one needs an "Arch" sibling and the other way round. A heading
    # naming both stands for itself. Siblings: the same level, the same parent heading.
    while IFS=$'\t' read -r line text; do
        finding "$file" "$line" systems "$text"
    done < <(prose "$path" | awk '
        function close_level(level,    key) {
            # Report the unpaired headings of every group at this level or deeper
            for (key in nix_line) {
                split(key, part, SUBSEP)
                if (part[2] + 0 >= level) {
                    if (!(key in arch_line)) print nix_line[key] "\t" nix_text[key] " (no Arch heading beside it)"
                    delete nix_line[key]
                }
            }
            for (key in arch_line) {
                split(key, part, SUBSEP)
                if (part[2] + 0 >= level) {
                    if (!(key in seen_nix)) print arch_line[key] "\t" arch_text[key] " (no NixOS heading beside it)"
                    delete arch_line[key]
                }
            }
            for (key in seen_nix) { split(key, part, SUBSEP); if (part[2] + 0 >= level) delete seen_nix[key] }
        }
        /^#{1,6}[[:space:]]/ {
            level = index($0, " ") - 1
            # A new heading at this level ends the groups under the previous one
            close_level(level + 1)
            parent[level] = NR
            for (deeper = level + 1; deeper <= 6; deeper++) delete parent[deeper]
            owner = 0
            for (above = level - 1; above >= 1; above--) if (above in parent) { owner = parent[above]; break }
            key = owner SUBSEP level
            title = $0
            sub(/^#+[[:space:]]+/, "", title)
            nix = (title ~ /(^|[^A-Za-z])NixOS([^A-Za-z]|$)/)
            arch = (title ~ /(^|[^A-Za-z])Arch([^A-Za-z]|$)/)
            if (nix && arch) next
            if (nix) { if (!(key in nix_line)) { nix_line[key] = NR; nix_text[key] = title }; seen_nix[key] = 1 }
            if (arch && !(key in arch_line)) { arch_line[key] = NR; arch_text[key] = title }
        }
        END { close_level(1) }
    ' | sort -n)
done

if [ "$findings" -gt 0 ]; then
    echo "docs-check: $findings finding(s) in ${#files[@]} file(s)"
    exit 1
fi
echo "docs-check: passed (${#files[@]} files)"
exit 0
