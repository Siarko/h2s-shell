#!/usr/bin/env bash
# `h2s-helper screensaver` on a private bus — part of tests/run-helper.sh, which builds the
# helper and the test client (helper/tests/client.cpp) and hands them here:
#
#   tests/helper/screensaver.sh <h2s-helper> <h2s-helper-test-client>
#
# A dbus-daemon of the run's own (tests/helper/session.conf, its socket in the run's
# directory; never the session's bus), then:
#   1. the helper driven as the shell drives it, apps played by the test client and gdbus:
#      ready and the name owned; Inhibit → its holder (markup and a 10 kB reason come
#      through as text, cut at 1000 characters); another caller's cookie cannot be removed;
#      UnInhibit; a caller leaving the bus drops its cookies (also a gdbus call that leaves
#      at once); 16 cookies a caller; SimulateUserActivity and SetActive forwarded, on both
#      paths; GetActive / GetActiveTime / ActiveChanged follow the shell's state (one signal
#      per change, on each path); GetSessionIdleTime answered by the shell, or an error when
#      it does not answer; its standard input closed → it ends and the name is free; the
#      name held by another connection → said with that program's name, and taken when it
#      leaves; no bus → an error line, exit 1;
#   2. the shell's side (singletons/helper/ScreenSaverClient.qml) against the same helper on
#      that bus: tests-helper.qml in a headless compositor (tests/headless.sh), the suites
#      in tests/helper/.
#
# The tools, as every runner takes them (tests/lock/resolve.sh, through tests/headless.sh):
# dbus-daemon and gdbus from the pinned tests/lock/tools.nix where there is `nix`, else from
# PATH; Quickshell and labwc for part 2. Exit status: 0 passed, 1 a check failed, 2 it could
# not be set up.
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
helper=${1:-}
client=${2:-}
[ -x "$helper" ] && [ -x "$client" ] || { echo "usage: tests/helper/screensaver.sh <h2s-helper> <h2s-helper-test-client>" >&2; exit 2; }

# shellcheck disable=SC2034  # read by tests/headless.sh
HEADLESS_NAME=run-helper.sh
# shellcheck source=../headless.sh
source "$REPO/tests/headless.sh"
headless_setup
PATH="${LOCKTEST_TOOLS:+$LOCKTEST_TOOLS/bin:}$PATH"
for tool in dbus-daemon gdbus mkfifo; do
    type -P "$tool" > /dev/null || setup_error "$tool not found (the private bus and its calls)"
done

dir=$work/bus
mkdir -p "$dir"
bus=unix:path=$dir/socket
started=()
stop_all() {
    local pid
    for pid in "${started[@]}"; do kill "$pid" 2> /dev/null; done
}
trap 'stop_all; headless_cleanup' EXIT

dbus-daemon --nofork --nopidfile --config-file="$REPO/tests/helper/session.conf" --address="$bus" > "$dir/daemon.log" 2>&1 &
started+=($!)
for _ in $(seq 1 100); do [ -S "$dir/socket" ] && break; sleep 0.05; done
[ -S "$dir/socket" ] || { cat "$dir/daemon.log" >&2; setup_error "the private bus did not start"; }
export DBUS_SESSION_BUS_ADDRESS=$bus

failed=0
check() {
    local description=$1
    shift
    if "$@"; then echo "  PASS $description"; else echo "  FAIL $description"; failed=1; fi
}

# A process talked to in lines: its input a fifo held open here, its output a file read
# line by line (a coprocess allows one at a time); how many lines were read is kept in a
# file, as `next` runs in a command substitution
declare -A to_fd=() pid_of=()
start() {
    local name=$1
    shift
    mkfifo "$dir/$name.in"
    # Without the inputs of the others held open (each would never see its end)
    (
        for fd in "${to_fd[@]}"; do eval "exec $fd>&-"; done
        exec "$@"
    ) < "$dir/$name.in" > "$dir/$name.out" 2> "$dir/$name.err" &
    pid_of[$name]=$!
    started+=($!)
    exec {fd}> "$dir/$name.in"
    to_fd[$name]=$fd
    echo 0 > "$dir/$name.read"
}
tell() { printf '%s\n' "$2" >&"${to_fd[$1]}"; }
# The next line it said (waited for, 5 s at most); "" when none came
next() {
    local name=$1 want tries=0
    want=$(($(cat "$dir/$name.read") + 1))
    until [ "$(wc -l < "$dir/$name.out")" -ge "$want" ] || [ "$tries" -ge 100 ]; do sleep 0.05; tries=$((tries + 1)); done
    echo "$want" > "$dir/$name.read"
    sed -n "${want}p" "$dir/$name.out"
}
close_input() { local fd=${to_fd[$1]}; exec {fd}>&-; }
gone() { ! kill -0 "${pid_of[$1]}" 2> /dev/null; }
wait_gone() { local tries=0; until gone "$1" || [ "$tries" -ge 100 ]; do sleep 0.05; tries=$((tries + 1)); done; gone "$1"; }
call() { gdbus call --session --dest org.freedesktop.ScreenSaver --object-path "$1" --method "org.freedesktop.ScreenSaver.$2" "${@:3}" 2>&1; }
name_free() { [ "$(gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.NameHasOwner org.freedesktop.ScreenSaver)" = "(false,)" ]; }
holders() { printf '{"event":"inhibitors","list":[%s]}' "$1"; }
holder() { printf '{"app":"%s","cookie":%s,"reason":"%s"}' "$1" "$2" "$3"; }
cookie_of() { sed -n 's/^cookie \([0-9][0-9]*\)$/\1/p' <<< "$1"; }

echo "the helper on a private bus"
protocol=$(sed -n 's/.*readonly property int protocol: \([0-9]*\).*/\1/p' "$REPO/singletons/HelperRules.qml" | head -n 1)
start helper "$helper" screensaver
check "it says it is ready, with its protocol" test "$(next helper)" = "{\"event\":\"ready\",\"protocol\":$protocol}"
check "… and that it owns org.freedesktop.ScreenSaver" test "$(next helper)" = '{"event":"name","owned":true}'

start first "$client"
start second "$client"
start watcher "$client"
check "the apps are on the bus" test "$(next first)$(next second)$(next watcher)" = readyreadyready
tell watcher watch
check "one watches ActiveChanged on both paths" test "$(next watcher)" = watching

long=$(head -c 10240 /dev/zero | tr '\0' r)
tell first "$(printf 'inhibit\t<b>Player</b> & co\t%s' "$long")"
reply=$(next first)
first_cookie=$(cookie_of "$reply")
check "Inhibit: a cookie" test -n "$first_cookie"
check "… the holder reported: the app's name as it was sent, the 10 kB reason cut at 1000 characters" \
    test "$(next helper)" = "$(holders "$(holder '<b>Player</b> & co' "$first_cookie" "${long:0:1000}")")"
tell second "path	/ScreenSaver"
next second > /dev/null
tell second "$(printf 'inhibit\tmpv\tvideo playing')"
second_cookie=$(cookie_of "$(next second)")
check "Inhibit on /ScreenSaver: both holders, by cookie" \
    grep -q "\"cookie\":$second_cookie,\"reason\":\"video playing\"" <<< "$(next helper)"
check "… two cookies apart" test -n "$second_cookie" -a "$second_cookie" != "$first_cookie"
tell first "uninhibit	$second_cookie"
check "UnInhibit of another caller's cookie: answered" test "$(next first)" = ok
tell first "uninhibit	$first_cookie"
next first > /dev/null
check "… left it (the next report, after the caller's own UnInhibit, still holds it)" \
    test "$(next helper)" = "$(holders "$(holder mpv "$second_cookie" "video playing")")"
tell second "$(printf 'inhibit\tmpv\tsecond one')"
next second > /dev/null
next helper > /dev/null
close_input second
check "a caller leaving the bus holding two cookies: both dropped, in one report" test "$(next helper)" = "$(holders "")"
gdbus_cookie=$(call /org/freedesktop/ScreenSaver Inhibit gdbus "one call" | sed -n 's/^(uint32 \([0-9]*\),)$/\1/p')
check "a gdbus Inhibit (its connection ends at once): reported" test "$(next helper)" = "$(holders "$(holder gdbus "$gdbus_cookie" "one call")")"
check "… and dropped as it leaves" test "$(next helper)" = "$(holders "")"

for i in $(seq 1 16); do tell first "$(printf 'inhibit\tmany\t%s' "$i")"; done
for i in $(seq 1 16); do next first > /dev/null; next helper > /dev/null; done
tell first "$(printf 'inhibit\tmany\t17')"
check "a 17th cookie for one caller: refused (LimitsExceeded)" test "$(next first)" = "error org.freedesktop.DBus.Error.LimitsExceeded"
tell first exit
check "… the caller gone, its 16 dropped" test "$(next helper)" = "$(holders "")"

call /ScreenSaver SimulateUserActivity > /dev/null
check "SimulateUserActivity (on /ScreenSaver): forwarded" test "$(next helper)" = '{"event":"activity"}'
call /org/freedesktop/ScreenSaver SimulateUserActivity > /dev/null
check "… and on /org/freedesktop/ScreenSaver" test "$(next helper)" = '{"event":"activity"}'
check "SetActive(true): forwarded, answered true" test "$(call /ScreenSaver SetActive true)" = "(true,)"
check "… the shell told" test "$(next helper)" = '{"active":true,"event":"setActive"}'

check "GetActive before the shell said anything: false" test "$(call /org/freedesktop/ScreenSaver GetActive)" = "(false,)"
check "GetActiveTime then: 0" test "$(call /org/freedesktop/ScreenSaver GetActiveTime)" = "(uint32 0,)"
tell helper "{\"active\":true,\"since\":$(($(date +%s) - 30))}"
check "the shell's screensaver active: ActiveChanged(true) on /org/freedesktop/ScreenSaver" \
    test "$(next watcher)" = "ActiveChanged /org/freedesktop/ScreenSaver true"
check "… and on /ScreenSaver" test "$(next watcher)" = "ActiveChanged /ScreenSaver true"
check "GetActive: true, on both paths" test "$(call /org/freedesktop/ScreenSaver GetActive)$(call /ScreenSaver GetActive)" = "(true,)(true,)"
active_time=$(call /ScreenSaver GetActiveTime | sed -n 's/^(uint32 \([0-9]*\),)$/\1/p')
check "GetActiveTime: from the shell's time ($active_time s)" test "${active_time:-0}" -ge 30 -a "${active_time:-0}" -le 40
tell helper '{"active":true,"since":1}'
tell helper '{"what":1}'
check "the same state again (then a line it does not know: an error)" test "$(next helper)" = '{"event":"error","message":"unknown message"}'
tell watcher active
check "… no second ActiveChanged" test "$(next watcher)" = "active true"
tell helper '{"active":false}'
check "inactive: ActiveChanged(false)" test "$(next watcher)" = "ActiveChanged /org/freedesktop/ScreenSaver false"
next watcher > /dev/null
check "… GetActive false" test "$(call /ScreenSaver GetActive)" = "(false,)"

call /ScreenSaver GetSessionIdleTime > "$dir/idle.answer" &
idle_call=$!
check "GetSessionIdleTime: the shell asked" test "$(next helper)" = '{"event":"askIdle"}'
tell helper '{"idleSeconds":7}'
wait "$idle_call"
check "… its answer is the reply" test "$(cat "$dir/idle.answer")" = "(uint32 7,)"
started_at=$SECONDS
idle_unanswered=$(call /ScreenSaver GetSessionIdleTime)
check "… unanswered: an error after 2 s" grep -q "org.freedesktop.DBus.Error.Failed" <<< "$idle_unanswered"
check "… (within a few seconds)" test $((SECONDS - started_at)) -le 4
next helper > /dev/null

close_input helper
check "its standard input closed (the shell gone): it ends" wait_gone helper
wait "${pid_of[helper]}"
check "… with status 0" test $? = 0
check "… and the name is free at once" name_free
check "… having said nothing on standard error" test ! -s "$dir/helper.err"

start holder "$client"
next holder > /dev/null
tell holder own
check "another program takes the name" test "$(next holder)" = owned
start queued "$helper" screensaver
next queued > /dev/null
holder_name=$(head -c 15 "/proc/${pid_of[holder]}/comm" | tr -d '\n')
check "a helper started then: the name held, by that program's name ($holder_name)" \
    test "$(next queued)" = "{\"event\":\"name\",\"owned\":false,\"owner\":\"$holder_name\"}"
check "… apps reach the other program, not the helper" test "$(call /ScreenSaver GetActive | head -c 6)" = "Error:"
tell holder exit
check "that program gone: the helper takes the name" test "$(next queued)" = '{"event":"name","owned":true}'
check "… and answers" test "$(call /ScreenSaver GetActive)" = "(false,)"
close_input queued
wait_gone queued

DBUS_SESSION_BUS_ADDRESS=unix:path=$dir/nothing-here "$helper" screensaver < /dev/null > "$dir/nobus.out" 2> /dev/null
check "no bus: exit 1" test $? = 1
check "… after an error line saying so" grep -q '^{"event":"error","message":"no session bus' "$dir/nobus.out"

echo
echo "the shell's side, against the helper on that bus"
headless_run "$REPO/tests-helper.qml" "" PATH="${LOCKTEST_TOOLS:+$LOCKTEST_TOOLS/bin:}$PATH" \
    DBUS_SESSION_BUS_ADDRESS="$bus" H2S_TEST_HELPER="$helper" H2S_TEST_CLIENT="$client" > /dev/null
headless_verdict "Helper suites" 1 "in tests-helper.qml" exactly ScreenSaverClient || failed=1
[ "$failed" = 0 ] || grep -E "FAIL|the app said" "$HEADLESS_LOG" | head -n 20
exit "$failed"
