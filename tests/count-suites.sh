# shellcheck shell=bash
# The suites a root file registers, read from the file itself — the one list of suites —
# and shared by tests/run-unit.sh and tests/run-unit-selftest.sh. Sourced.
#
#   registered_suites <root.qml>   one line per `property var _name: SomethingTest {…}`:
#                                  the suite's type, then the types of the suites it is
#                                  given (`SomethingTest { after: _other }` prints
#                                  "SomethingTest OtherTest"), whether its arguments are on
#                                  that line or on the ones after it
#   count_suites <root.qml>        how many it registers: its registration lines, counted
#                                  without reading what follows them; a suite written with
#                                  arguments counts as well
#   suites_agree <root.qml>        whether registered_suites found as many: it follows the
#                                  braces of a suite written over several lines, and a brace
#                                  in a string or a comment there can hide the suites after
#                                  it. The runner does not start on a list it cannot trust
#   suites_with_needed <root.qml> <suite>…
#                                  those suites and every suite they are given, each once,
#                                  one per line; returns 1 and prints the name on stderr for
#                                  a name the file does not register

registered_suites() {
    awk '
        # Every `_name` a text refers to (`after: _modules`, `after: root._modules`), as
        # " _name" words
        function references(text,    found, word) {
            found = ""
            while (match(text, /(^|[^A-Za-z0-9_])_[A-Za-z0-9]+/)) {
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
    grep -c -E '^[[:space:]]*property var _[A-Za-z0-9]+: [A-Za-z0-9]+Test[[:space:]]*\{' "$1"
}

suites_agree() {
    [ "$(registered_suites "$1" | grep -c .)" = "$(count_suites "$1")" ]
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
    # Nothing asked for, nothing printed: printf would print one empty line
    [ ${#result[@]} -eq 0 ] || printf '%s\n' "${result[@]}"
}

# plan_shards <root.qml> <times file> <suite>…
#                                  the shards those suites run in, one line each (the suites
#                                  of a shard, space-separated), the longest first. A suite
#                                  whose file (tests/<type>.qml beside the root file) says
#                                  `ownProcess: true` has a shard of its own; a suite and the
#                                  suites it is given share one. The others are packed,
#                                  longest first, each into the shard with the least time so
#                                  far, into as many shards as it takes for none to hold more
#                                  than the longest suite takes alone (5 s at least). A
#                                  suite's time is the one last measured (the times file:
#                                  lines "<type> <ms>"), else 5 s for an asynchronous suite
#                                  (its file says `asynchronous: true`), 0.1 s for another.
plan_shards() {
    local root=$1 times=$2 table name file own weight given
    shift 2
    table=$(registered_suites "$root")
    for name in "$@"; do
        file=$(dirname "$root")/tests/$name.qml
        own=0
        grep -q -E '^[[:space:]]*ownProcess: true[[:space:]]*$' "$file" 2> /dev/null && own=1
        weight=""
        [ -n "$times" ] && [ -r "$times" ] && weight=$(awk -v name="$name" '$1 == name && $2 ~ /^[0-9]+$/ { found = $2 } END { print found }' "$times")
        if [ -z "$weight" ]; then
            if grep -q -E '^[[:space:]]*asynchronous: true[[:space:]]*$' "$file" 2> /dev/null; then weight=5000; else weight=100; fi
        fi
        given=$(awk -v name="$name" '$1 == name { $1 = ""; print }' <<< "$table")
        echo "$name $own $weight $given"
    done | awk '
        function find(x) { while (parent[x] != x) x = parent[x]; return x }
        {
            count++
            order[count] = $1
            own[$1] = $2
            weight[$1] = $3 + 0
            parent[$1] = $1
            givenTo[$1] = ""
            for (i = 4; i <= NF; i++) givenTo[$1] = givenTo[$1] " " $i
        }
        END {
            # A suite and what it is given: one unit, in one shard
            for (i = 1; i <= count; i++) {
                total = split(givenTo[order[i]], words, " ")
                for (j = 1; j <= total; j++)
                    if (words[j] in parent && find(words[j]) != find(order[i]))
                        parent[find(words[j])] = find(order[i])
            }
            units = 0
            longest = 0
            for (i = 1; i <= count; i++) {
                root = find(order[i])
                if (!(root in unitOf)) {
                    units++
                    unitOf[root] = units
                    members[units] = ""
                    load[units] = 0
                    alone[units] = 0
                }
                unit = unitOf[root]
                members[unit] = members[unit] (members[unit] == "" ? "" : " ") order[i]
                load[unit] += weight[order[i]]
                if (own[order[i]]) alone[unit] = 1
            }
            for (unit = 1; unit <= units; unit++)
                if (load[unit] > longest) longest = load[unit]
            # A shard costs its own start (a compositor, Quickshell, every suite built: about
            # a second): short suites fill one up to 5 s, at least
            if (longest < 5000) longest = 5000
            # The units to pack, longest first (ties: in the order registered)
            packed = 0
            packedLoad = 0
            for (unit = 1; unit <= units; unit++) {
                if (alone[unit]) continue
                packed++
                sorted[packed] = unit
                packedLoad += load[unit]
                for (k = packed; k > 1 && load[sorted[k]] > load[sorted[k - 1]]; k--) {
                    swap = sorted[k]; sorted[k] = sorted[k - 1]; sorted[k - 1] = swap
                }
            }
            shards = 0
            for (unit = 1; unit <= units; unit++)
                if (alone[unit]) { shards++; shardMembers[shards] = members[unit]; shardLoad[shards] = load[unit] }
            if (packed > 0) {
                bins = longest > 0 ? int((packedLoad + longest - 1) / longest) : 1
                if (bins < 1) bins = 1
                if (bins > packed) bins = packed
                first = shards + 1
                for (b = 0; b < bins; b++) { shardMembers[first + b] = ""; shardLoad[first + b] = 0 }
                for (k = 1; k <= packed; k++) {
                    unit = sorted[k]
                    best = first
                    for (b = first + 1; b < first + bins; b++)
                        if (shardLoad[b] < shardLoad[best]) best = b
                    shardMembers[best] = shardMembers[best] (shardMembers[best] == "" ? "" : " ") members[unit]
                    shardLoad[best] += load[unit]
                }
                shards += bins
            }
            # The longest first: they start first
            for (s = 1; s <= shards; s++) {
                byLoad[s] = s
                for (k = s; k > 1 && shardLoad[byLoad[k]] > shardLoad[byLoad[k - 1]]; k--) {
                    swap = byLoad[k]; byLoad[k] = byLoad[k - 1]; byLoad[k - 1] = swap
                }
            }
            for (s = 1; s <= shards; s++) print shardMembers[byLoad[s]]
        }
    '
}
