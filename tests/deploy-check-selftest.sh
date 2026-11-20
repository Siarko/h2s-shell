#!/usr/bin/env bash
# Checks tests/device/deploy-check.sh — the read-only check run after a deploy — on stand-in
# input: an `h2s-shell` that answers canned `modules list` / `tailscale state` JSON, a `qs`
# that lists canned instances and prints a canned log, and a `tailscale` that only notes it
# was called. For each case: the verdicts, the exit status, and that only the two read calls
# went over the IPC and no `tailscale` command ran at all.
#
#   tests/deploy-check-selftest.sh
#
# Nothing real is reached: the PATH holds only the plain utilities the check calls and the
# stand-ins. It needs bash, coreutils, grep, sed, awk and python3, so it runs the same on
# NixOS and on Arch. It takes no lock: nothing of it is shared with another run.
#
# Exit status: 0 when every check passed, 1 when one failed, 2 when it could not be set up.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
SCRIPT=$REPO/tests/device/deploy-check.sh
work=$(mktemp -d "${TMPDIR:-/tmp}/deploy-check-self.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
bash_path=$(type -P bash)
failures=0

check() {
    local description=$1
    shift
    if "$@"; then echo "  PASS $description"; else echo "  FAIL $description"; failures=$((failures + 1)); fi
}

# ---- The PATH: real plain utilities, and the stand-ins ---------------------------------------
mkdir -p "$work/bin" "$work/standins" "$work/run"
for name in bash env timeout awk date mktemp rm readlink dirname sort grep cut head tr sed id cat; do
    real=$(type -P "$name") || { echo "deploy-check-selftest.sh: $name not found on PATH (the check calls it)" >&2; exit 2; }
    ln -s "$real" "$work/bin/$name"
done
# The interpreter itself, not a version manager's shim (which needs its own environment)
python=$(python3 -I -c 'import sys; print(sys.executable)' 2> /dev/null) && [ -x "$python" ] \
    || { echo "deploy-check-selftest.sh: python3 not found (the check reads the IPC's JSON with it)" >&2; exit 2; }
ln -s "$python" "$work/bin/python3"

stand_in() {
    local file=$work/standins/$1
    shift
    { echo "#!$bash_path"; printf '%s\n' "$@"; } > "$file"
    chmod +x "$file"
}
# h2s-shell: notes its arguments, answers from the case's directory (<target>.json, and
# <target>.status for its exit status)
stand_in h2s-shell \
    'echo "$*" >> "$CASE/calls"' \
    '[ "$1 $2" = "ipc call" ] || exit 64' \
    'cat "$CASE/$3.json" 2> /dev/null' \
    'exit "$(cat "$CASE/$3.status" 2> /dev/null || echo 0)"'
# qs: `list` prints the case's instances, `log <file>` the case's log for that instance
stand_in qs \
    'echo "$*" >> "$CASE/qs-calls"' \
    'case "$1" in' \
    '    list) cat "$CASE/instances" ;;' \
    '    log) id=$(basename "$(dirname "$2")"); cat "$CASE/log-$id" 2> /dev/null || { echo "no log $2" >&2; exit 1; } ;;' \
    '    *) exit 64 ;;' \
    'esac'
stand_in tailscale 'echo "$*" >> "$CASE/tailscale-calls"' 'exit 0'
ln -s "$(type -P basename)" "$work/bin/basename"
# A launch.sh for H2S_SHELL_DIR without an h2s-shell command: the same answers
mkdir -p "$work/checkout/scripts" "$work/other/scripts"
cp "$work/standins/h2s-shell" "$work/checkout/scripts/launch.sh"
cp "$work/standins/h2s-shell" "$work/other/scripts/launch.sh"
touch "$work/checkout/shell.qml" "$work/other/shell.qml"

# ---- Canned answers ---------------------------------------------------------------------------
good_modules='{"api":"1.35","safeMode":false,"safeModeReason":"","hostError":"","testMode":false,"modules":[{"id":"tailscale","name":"Tailscale","version":"0.6.0","directory":"/m/tailscale","state":"loaded","enabled":true,"errors":[],"warnings":["a warning"],"deprecations":[]}]}'
good_state='{"phase":"running","state":"activated","backendState":"Running","cli":"present","daemon":"running","ready":true,"stale":false,"failure":"","busy":false,"operation":"","testMode":false,"devices":7,"exitNodes":2,"warnings":0,"streamUp":true,"reads":3}'
stamp() { date -d "-$1 sec" '+%F %T.000'; }

# new_case <name>: a case directory with the good answers and a quiet log, one instance
new_case() {
    CASE=$work/cases/$1
    mkdir -p "$CASE"
    printf '%s\n' "$good_modules" > "$CASE/modules.json"
    printf '%s\n' "$good_state" > "$CASE/tailscale.json"
    printf 'Instance abc123:\n  Process ID: 1\n  Config path: %s/checkout/shell.qml\n' "$work" > "$CASE/instances"
    {
        echo "$(stamp 60)  INFO: Configuration Loaded"
        echo "  a continuation line without a timestamp"
        echo "  a continuation line without a timestamp"
    } > "$CASE/log-abc123"
}

# run [VAR=value…] [-- options…]: OUTPUT and STATUS of the check, with the stand-ins first
run() {
    local -a assignments=()
    while [ $# -gt 0 ] && [ "$1" != -- ]; do assignments+=("$1"); shift; done
    [ "${1:-}" = -- ] && shift
    OUTPUT=$(env -i HOME="$work" XDG_RUNTIME_DIR="$work/run" CASE="$CASE" PATH="$work/standins:$work/bin" \
        "${assignments[@]}" "$bash_path" "$SCRIPT" "$@" 2>&1)
    STATUS=$?
}
says() { grep -qF -- "$1" <<< "$OUTPUT"; }
says_not() { ! says "$1"; }
calls_were() { [ "$(cat "$CASE/calls" 2> /dev/null)" = "$1" ]; }
no_tailscale() { [ ! -e "$CASE/tailscale-calls" ]; }
status_is() { [ "$STATUS" = "$1" ]; }
reads_only=$'ipc call modules list\nipc call tailscale state'

echo "== Everything fine"
new_case fine
for i in 1 2 3 4 5; do echo "$(stamp $((100 + i)))  WARN qml: [X] five times is the limit"; done >> "$CASE/log-abc123"
run
check "exit 0" status_is 0
check "the host passes" says "PASS  modules: the host answers"
check "the module passes" says "PASS  modules: tailscale loaded and enabled, no errors (0.6.0, /m/tailscale)"
check "its warning is noted" says "NOTE  modules: tailscale warning: a warning"
check "the state passes" says "PASS  tailscale: the daemon running and read"
check "the counts are printed" says "devices 7, exitNodes 2, warnings 0, streamUp true"
check "a line as often as the limit passes; continuation lines are left out" says "PASS  log: instance abc123: no line more than 5 times in the last 10 minutes (6 lines)"
check "only the two reads went over the IPC" calls_were "$reads_only"
check "no tailscale command ran" no_tailscale
check "qs listed the running instances and read that instance's log" \
    test "$(cat "$CASE/qs-calls")" = "list --all --no-color"$'\n'"log $work/run/quickshell/by-id/abc123/log.qslog --log-times --no-color"

echo "== A line repeated"
new_case repeated
for i in 1 2 3 4 5 6; do echo "$(stamp $((30 + i)))  WARN qml: [NetworkEvents] nmcli monitor exited, restarting"; done >> "$CASE/log-abc123"
for i in 1 2 3 4 5 6 7 8 9; do echo "$(stamp $((1200 + i)))  WARN qml: [Old] long ago"; done >> "$CASE/log-abc123"
run
check "exit 1" status_is 1
check "the line and its count are named, timestamps aside" says "FAIL  log: instance abc123: 6× in the last 10 minutes: WARN qml: [NetworkEvents] nmcli monitor exited, restarting"
check "lines older than the window do not count" says_not "[Old]"
run -- --minutes 30
check "… within a wider window they do" says "9× in the last 30 minutes: WARN qml: [Old] long ago"
run -- --repeats 6
check "… and --repeats moves the limit" status_is 0

echo "== The module not loaded, the host in safe mode"
new_case failed
printf '%s\n' '{"safeMode":true,"safeModeReason":"died twice","hostError":"","testMode":false,"modules":[{"id":"tailscale","version":"0.6.0","directory":"/m","state":"failed","enabled":true,"errors":["boom"]}]}' > "$CASE/modules.json"
run
check "exit 1" status_is 1
check "safe mode fails, with its reason" says "FAIL  modules: the host: safe mode: died twice"
check "the module's state and error are named" says "FAIL  modules: tailscale (0.6.0, /m): state failed; error: boom"
new_case missing
printf '%s\n' '{"safeMode":false,"hostError":"","testMode":false,"modules":[]}' > "$CASE/modules.json"
run
check "no tailscale module listed fails" says "FAIL  modules: no module \"tailscale\" listed"

echo "== The daemon not right"
new_case daemon
printf '%s\n' '{"cli":"present","daemon":"not-running","ready":true,"stale":true,"backendState":"","failure":"could not connect","busy":true,"operation":"connect","testMode":true}' > "$CASE/tailscale.json"
run
check "exit 1" status_is 1
check "each problem is named" says "FAIL  tailscale: the module is in test mode; the daemon: not-running; the last read timed out (stale); no backend state; a failed action: could not connect; an operation under way: connect"
check "still only reads" calls_were "$reads_only"
check "still no tailscale command" no_tailscale

echo "== A call that fails, an answer that is not JSON"
new_case broken
echo 1 > "$CASE/tailscale.status"
echo "No running instances" > "$CASE/tailscale.json"
printf 'not json \033[31m<b>red</b>\n' > "$CASE/modules.json"
run
check "exit 1" status_is 1
check "the failed call is named" says "FAIL  tailscale: \`tailscale state\` the call failed (status 1): No running instances"
check "the answer that is not JSON is shown as plain text" says "FAIL  modules: \`modules list\` not JSON: not json  [31m<b>red</b>"
check "… without its control characters" test "$(printf '%s' "$OUTPUT" | tr -d -c '\033' | wc -c)" = 0

echo "== Which shell"
new_case dir
printf 'Instance abc123:\n  Config path: %s/other/shell.qml\nInstance def456:\n  Config path: %s/checkout/shell.qml\nInstance ghi789:\n  Config path: /nowhere/shell.qml\n' "$work" "$work" > "$CASE/instances"
cp "$CASE/log-abc123" "$CASE/log-def456"
mv "$work/standins/h2s-shell" "$work/h2s-shell.away"
run H2S_SHELL_DIR="$work/checkout"
check "without h2s-shell, H2S_SHELL_DIR's launch.sh takes the calls" says "via $work/checkout/scripts/launch.sh"
check "… only the reads" calls_were "$reads_only"
check "only the log of the instance from H2S_SHELL_DIR is read" \
    test "$(grep '^log' "$CASE/qs-calls")" = "log $work/run/quickshell/by-id/def456/log.qslog --log-times --no-color"
run
check "neither h2s-shell nor H2S_SHELL_DIR: exit 2" status_is 2
check "… saying why" says "no h2s-shell command on PATH and no H2S_SHELL_DIR"
mv "$work/h2s-shell.away" "$work/standins/h2s-shell"
new_case none
printf 'Instance zzz:\n  Config path: /nowhere/shell.qml\n' > "$CASE/instances"
run
check "no running h2s-shell instance: exit 1" status_is 1
check "… named" says "FAIL  log: no running h2s-shell instance found"
run -- --frobnicate
check "a wrong option: exit 2" status_is 2
run -- --minutes 0
check "--minutes 0: exit 2" status_is 2

echo
if [ "$failures" = 0 ]; then
    echo "deploy-check-selftest.sh: every check passed"
    exit 0
fi
echo "deploy-check-selftest.sh: $failures failed"
exit 1
