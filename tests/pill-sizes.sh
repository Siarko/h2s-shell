#!/usr/bin/env bash
# What the tree's pills say about their height, for PillSizesTest: every `Pill { … }` in a
# QML file under <tree> (tests/ and components/Pill.qml itself left out).
#
#   tests/pill-sizes.sh <tree>
#
# Prints, one per line:
#   PILL:<file>:<size>      a pill and the size it names ("-" for none: the default)
#   NUMBER:<file>:<line>    a pill that sets its height itself (height, implicitHeight,
#                           minimumHeight), or any other line that names minimumHeight
#   FILES:<count>           the files read
set -uo pipefail

cd "$1" || exit 2
find . -name '*.qml' -not -path './tests/*' -not -path './.git/*' -not -path './components/Pill.qml' | sort | {
    count=0
    while IFS= read -r file; do
        count=$((count + 1))
        awk -v file="${file#./}" '
            function braces(text,   opened, closed) {
                opened = gsub(/\{/, "{", text)
                closed = gsub(/\}/, "}", text)
                return opened - closed
            }
            depth == 0 && /^[ \t]*Pill[ \t]*\{/ { inside = 1; size = "-" }
            inside {
                if ($0 ~ /^[ \t]*(height|implicitHeight|minimumHeight)[ \t]*:/) { print "NUMBER:" file ":" FNR; reported = FNR }
                if (match($0, /^[ \t]*size[ \t]*:[ \t]*"[^"]*"/)) { size = $0; sub(/^[^"]*"/, "", size); sub(/".*$/, "", size) }
                depth += braces($0)
                if (depth <= 0) { print "PILL:" file ":" size; inside = 0; depth = 0 }
                next
            }
            /minimumHeight/ && reported != FNR { print "NUMBER:" file ":" FNR }
        ' "$file"
    done
    echo "FILES:$count"
}
