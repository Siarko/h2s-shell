#!/usr/bin/env bash
# The lock bed's lint: no fixed sleep in a scenario without its reason. A scenario waits on
# conditions (check_within, wait_until, wait_settled); a fixed `sleep` makes it slower than
# it needs to be on an idle machine and flaky on a loaded one. The few that are right say
# why on their own line, after `# fixed sleep: ` — a negative claim ("nothing happened in
# N s"), a stand-in that never answers, input paced on purpose, a moment that is the
# subject — and that comment is the allow-list.
#
#   tests/lock/lint.sh [file...]     the scenarios given, else every tests/lock/tests/*.sh
#   tests/lock/lint.sh --list        the allowed sleeps, with their reasons
#   tests/lock/lint.sh --selftest    the lint's own cases
#
# A poll loop on one line (`until …; do sleep 0.5; done`, a sampler `( while :; do …;
# sleep 0.1; done ) &`) is a wait on a condition, not a fixed sleep — unless its condition is
# the clock (`date`, `uptime`, `SECONDS`, `EPOCHREALTIME`): that is a fixed wait written as
# a loop, and says why as a sleep does. Exit status: 0 clean,
# 1 a sleep without its reason (each printed as file:line: text).
set -uo pipefail

LINT_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)

# A `sleep` run as a command: at the start of a line or after ; & | ( { do then else
SLEEP_COMMAND='(^|[;&|({]|(^|[[:space:]])(do|then|else))[[:space:]]*sleep[[:space:]]'
ONE_LINE_LOOP='(while|until)[[:space:]]([^;]*);[[:space:]]*do[[:space:]].*done'
# A loop whose condition is the clock
CLOCK='(date|uptime|SECONDS|EPOCHREALTIME|EPOCHSECONDS)'
# The reason: at least a few words
REASON='# fixed sleep: .{10,}'

# lint_files <file...>: prints each offending line, non-zero when there is one
lint_files() {
    local file line number condition found=0
    for file in "$@"; do
        number=0
        while IFS= read -r line || [ -n "$line" ]; do
            number=$((number + 1))
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ "$line" =~ $SLEEP_COMMAND ]] || continue
            if [[ "$line" =~ $ONE_LINE_LOOP ]]; then
                condition=${BASH_REMATCH[2]}
                [[ "$condition" =~ $CLOCK ]] || continue
            fi
            [[ "$line" =~ $REASON ]] && continue
            echo "$file:$number: $line"
            found=1
        done < "$file"
    done
    return $found
}

list_allowed() {
    grep -nE -- "$REASON" "$@" | sed -E 's/^([^:]*):([0-9]+):.*# fixed sleep: /\1:\2: /'
}

selftest() {
    local work failures=0 output
    work=$(mktemp -d "${TMPDIR:-/tmp}/h2s-lint.XXXXXX") || exit 2
    trap 'rm -rf "$work"' RETURN
    expect() {
        local verdict=$1 text=$2 status
        printf '%s\n' "$text" > "$work/case.sh"
        output=$(lint_files "$work/case.sh")
        status=$?
        if { [ "$verdict" = refused ] && [ "$status" = 1 ] && [ -n "$output" ]; } \
            || { [ "$verdict" = passed ] && [ "$status" = 0 ] && [ -z "$output" ]; }; then
            echo "PASS lint: $verdict: $text"
        else
            echo "FAIL lint: should be $verdict: $text"
            failures=$((failures + 1))
        fi
    }
    expect refused 'sleep 1'
    expect refused '    sleep 0.5'
    expect refused 'press_key Tab; sleep 1'
    expect refused 'if true; then sleep 2; fi'
    expect refused 'sleep 1 # the fade'
    expect refused 'sleep 1 # fixed sleep: '
    expect passed 'sleep 1 # fixed sleep: a negative claim: nothing unlocks it'
    expect passed 'until [ -e x ]; do sleep 0.5; done'
    expect refused 'until [ $(($(date +%s) - started)) -ge 12 ]; do sleep 0.5; done'
    expect refused 'until [ "$(uptime_ticks)" -ge 32 ]; do sleep 0.5; done'
    expect passed 'until [ $(($(date +%s) - started)) -ge 12 ]; do sleep 0.5; done # fixed sleep: Quickshell restarts in place only after 10 s'
    expect passed '( while :; do date >> log; sleep 0.1; done ) &'
    expect passed '# sleep 3 in a comment'
    expect passed 'check_within "$GUARD" "the prompt sleeps" state_is prompt_awake false'
    expect passed 'log "waiting out the sleep"'
    [ "$failures" = 0 ]
}

case "${1:-}" in
    --selftest) selftest; exit ;;
    --list)
        shift
        [ $# -gt 0 ] || set -- "$LINT_DIR"/tests/*.sh
        list_allowed "$@"
        exit 0
        ;;
esac
[ $# -gt 0 ] || set -- "$LINT_DIR"/tests/*.sh
lint_files "$@"
