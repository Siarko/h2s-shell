# shellcheck shell=bash
# The suites a root file registers, read from the file itself — the one list of suites —
# and shared by tests/run-unit.sh and tests/run-unit-selftest.sh. Sourced.
#
#   registered_suites <root.qml>   one line per `property var _name: SomethingTest {…}`:
#                                  the suite's type, then the types of the suites it is
#                                  given (`SomethingTest { after: _other }` prints
#                                  "SomethingTest OtherTest"), whether its arguments are on
#                                  that line or on the ones after it
#   count_suites <root.qml>        how many it registers; a suite written with arguments
#                                  counts as well
#   suites_with_needed <root.qml> <suite>…
#                                  those suites and every suite they are given, each once,
#                                  one per line; returns 1 and prints the name on stderr for
#                                  a name the file does not register

registered_suites() {
    awk '
        # Every `_name` a text refers to (`after: _modules`), as " _name" words
        function references(text,    found, word) {
            found = ""
            while (match(text, /(^|[^A-Za-z0-9_.])_[A-Za-z0-9]+/)) {
                word = substr(text, RSTART, RLENGTH)
                sub(/^[^_]/, "", word)
                found = found " " word
                text = substr(text, RSTART + RLENGTH)
            }
            return found
        }
        # The braces a text opens, less the ones it closes
        function opened(text,    opening, closing) {
            opening = gsub(/\{/, "{", text)
            closing = gsub(/\}/, "}", text)
            return opening - closing
        }
        depth == 0 && /^[[:space:]]*property var _[A-Za-z0-9]+: [A-Za-z0-9]+Test[[:space:]]*\{/ {
            property = $0
            sub(/^[[:space:]]*property var /, "", property)
            sub(/:.*$/, "", property)
            type = $0
            sub(/^[^:]*: /, "", type)
            sub(/[[:space:]]*\{.*$/, "", type)
            arguments = $0
            sub(/^[^{]*/, "", arguments)
            count++
            order[count] = property
            typeOf[property] = type
            given[property] = references(arguments)
            depth = opened(arguments)
            next
        }
        depth > 0 {
            given[order[count]] = given[order[count]] references($0)
            depth += opened($0)
        }
        END {
            for (i = 1; i <= count; i++) {
                line = typeOf[order[i]]
                total = split(given[order[i]], words, " ")
                # Only what the file registers is a suite: other names are not
                for (j = 1; j <= total; j++)
                    if (words[j] in typeOf)
                        line = line " " typeOf[words[j]]
                print line
            }
        }
    ' "$1"
}

count_suites() {
    registered_suites "$1" | grep -c .
}

suites_with_needed() {
    local root=$1 table name known
    shift
    table=$(registered_suites "$root")
    local -a queue=("$@") result=() line
    local -A seen=()
    while [ ${#queue[@]} -gt 0 ]; do
        name=${queue[0]}
        queue=("${queue[@]:1}")
        [ -n "$name" ] || continue
        [ -n "${seen[$name]:-}" ] && continue
        known=0
        while read -r -a line; do
            [ "${line[0]:-}" = "$name" ] || continue
            known=1
            queue+=("${line[@]:1}")
        done <<< "$table"
        [ "$known" = 1 ] || { echo "$name" >&2; return 1; }
        seen[$name]=1
        result+=("$name")
    done
    printf '%s\n' "${result[@]}"
}
