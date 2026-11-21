#!/usr/bin/env bash
# Everything to run before committing, in one command: the general set (the same on every
# system) and the set of the system this machine runs, the quick parts first.
#
#   tests/run-all.sh               all of it; about four minutes, most of it the lock bed
#   tests/run-all.sh --quick       without the lock bed (under a minute)
#   tests/run-all.sh --keep-going  go on after a part failed (the default stops there)
#
# The parts, in the order they run (each can be run alone, as written):
#
#   tests/run-all-selftest.sh                           this runner's own verdict
#   tests/run-system-selftest.sh                        the system runner's own verdict
#   tests/install-test.sh                               install.sh under stand-ins
#   tests/run-unit.sh                                   the unit suites
#   tests/run-modules.sh tests/fixtures/modules/good tests/fixtures/modules/legacy-elevate
#                                                       modules' suites, on the fixtures
#   tests/run-modules.sh tests/fixtures/modules/privileged tests/fixtures/modules/privileged-undeclared
#                                                       runs as administrator, on a fixture
#                                                       (alone: its suite times the shell's
#                                                       one queue)
#   tests/resolve-selftest.sh                           where the runners take their tools
#   tests/launcher-selftest.sh                          the supervisor in scripts/launch.sh
#   tests/deploy-check-selftest.sh                      the deploy check, on canned answers
#   tests/docs-check-selftest.sh                        the documentation's rules lint, on
#                                                       stand-ins and on README.md and docs/
#   tests/run-unit-selftest.sh                          the unit runner's own verdict
#   tests/run-system.sh                                 this system's set (NixOS or Arch)
#   tests/lock/run.sh                                   the lock screen, end to end
#
# Each part finds its own tools and says what it took; nothing here needs the caller to
# prepare the environment, and nothing shows on the screen. The lock bed takes the
# machine-wide lock itself and waits for another run of it.
#
# The summary names every part: PASS, FAIL, or NOT RUN with the reason — a part that could
# not be set up (its status 2: a missing tool is named with its use, a system without a
# set), one left out by --quick, one not reached after a failure. A part that did not run
# is never counted as passed.
#
# Exit status: 0 when every part ran and passed (with --quick: every part but the lock
# bed); 1 when a part failed; 2 when none failed but one could not be set up, or for a
# wrong option; 130 when interrupted.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
quick=0
keep_going=0
for option in "$@"; do
    case "$option" in
        --quick) quick=1 ;;
        --keep-going) keep_going=1 ;;
        *) echo "usage: tests/run-all.sh [--quick] [--keep-going]" >&2; exit 2 ;;
    esac
done

# name | command (relative to the checkout), in the order they run. RUN_ALL_PARTS names
# another list, in the same form: for a test of this runner's own verdict.
parts=(
    "this runner's self-test|tests/run-all-selftest.sh"
    "system runner self-test|tests/run-system-selftest.sh"
    "install.sh under stand-ins|tests/install-test.sh"
    "unit suites|tests/run-unit.sh"
    "module fixture suites|tests/run-modules.sh tests/fixtures/modules/good tests/fixtures/modules/legacy-elevate"
    "privileged runs fixture|tests/run-modules.sh tests/fixtures/modules/privileged tests/fixtures/modules/privileged-undeclared"
    "tool lookup self-test|tests/resolve-selftest.sh"
    "supervisor self-test|tests/launcher-selftest.sh"
    "deploy check self-test|tests/deploy-check-selftest.sh"
    "docs rules lint|tests/docs-check-selftest.sh"
    "unit runner self-test|tests/run-unit-selftest.sh"
    "system set|tests/run-system.sh"
    "lock bed|tests/lock/run.sh"
)
if [ -n "${RUN_ALL_PARTS:-}" ]; then
    mapfile -t parts < "$RUN_ALL_PARTS" || { echo "run-all.sh: cannot read $RUN_ALL_PARTS" >&2; exit 2; }
fi

log=$(mktemp "${TMPDIR:-/tmp}/run-all.XXXXXX") || { echo "run-all.sh: cannot create a temp file" >&2; exit 2; }
trap 'rm -f "$log"' EXIT
# A part runs in the background, in a process group of its own, and is waited for: bash
# runs a trap only once the foreground command has ended, which for a part running in the
# foreground meant minutes after a SIGTERM. Interrupted, the part's whole group is ended
# first (SIGTERM, so that it cleans up after itself; SIGKILL if it has not gone in 10 s).
part_pid=""
end_part() {
    [ -n "$part_pid" ] || return 0
    kill -TERM -- "-$part_pid" 2> /dev/null
    local tries=0
    while kill -0 -- "-$part_pid" 2> /dev/null && [ "$tries" -lt 100 ]; do
        sleep 0.1
        tries=$((tries + 1))
    done
    kill -KILL -- "-$part_pid" 2> /dev/null
    part_pid=""
}
trap 'end_part; echo; echo "run-all.sh: interrupted; the parts so far:"; printf "%s\n" "${summary[@]}"; exit 130' INT TERM

summary=()
any_failed=0
any_not_run=0
stopped_by=""
started=$SECONDS
for part in "${parts[@]}"; do
    name=${part%%|*}
    command=${part#*|}
    if [ "$quick" = 1 ] && [ "$name" = "lock bed" ]; then
        summary+=("  NOT RUN  $name — left out by --quick ($command runs it)")
        continue
    fi
    if [ -n "$stopped_by" ]; then
        summary+=("  NOT RUN  $name — not reached: stopped after '$stopped_by' failed (--keep-going goes on)")
        continue
    fi
    echo
    echo "==== $name: $command"
    part_started=$SECONDS
    # Job control only to give the part its group; the subshell hands on the part's status
    set -m
    # shellcheck disable=SC2086  # the command's words
    ( (cd "$REPO" && exec $command) 2>&1 < /dev/null | tee "$log"; exit "${PIPESTATUS[0]}") &
    part_pid=$!
    set +m
    wait "$part_pid"
    status=$?
    part_pid=""
    took="$((SECONDS - part_started)) s"
    case "$status" in
        0) summary+=("  PASS     $name ($took)") ;;
        2)
            # A set-up error ends with its reason: the last lines the part printed
            reason=$(grep -v '^[[:space:]]*$' "$log" | tail -n 3 | tr '\n' ' ' | cut -c 1-400)
            summary+=("  NOT RUN  $name — it could not be set up: ${reason:-status 2, no output}")
            any_not_run=1
            ;;
        130) kill -INT $$ ;;
        *)
            summary+=("  FAIL     $name (status $status, $took) — $command")
            any_failed=1
            [ "$keep_going" = 1 ] || stopped_by=$name
            ;;
    esac
done

echo
echo "All ($((SECONDS - started)) s):"
printf '%s\n' "${summary[@]}"
if [ "$any_failed" = 1 ]; then
    echo "run-all.sh: FAILED"
    exit 1
fi
if [ "$any_not_run" = 1 ]; then
    echo "run-all.sh: not everything could be run (above)"
    exit 2
fi
if [ "$quick" = 1 ]; then
    echo "run-all.sh: passed, without the lock bed"
else
    echo "run-all.sh: passed"
fi
exit 0
