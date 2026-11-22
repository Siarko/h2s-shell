#!/usr/bin/env bash
# `h2s-helper screensaver` on a private bus — part of tests/run-helper.sh, which builds the
# helper and the test client (helper/tests/client.cpp) and hands them here:
#
#   tests/helper/screensaver.sh <h2s-helper> <h2s-helper-test-client>
#
# A dbus-daemon of the run's own (tests/helper/session.conf, its socket in the run's
# directory; never the session's bus), then:
#   1. the helper driven as the shell drives it, apps played by the test client and gdbus:
#      ready and the name owned; Inhibit → its holder with its caller (markup comes through
#      as text, the app's name cut at 64 characters, a 10 kB reason at 128); another
#      caller's cookie cannot be removed; UnInhibit; a caller leaving the bus drops its
#      cookies (also a gdbus call that leaves at once); a client flooding Inhibit/UnInhibit
#      makes a few reports; 16 cookies a caller, also over two connections of one process;
#      SimulateUserActivity forwarded, on both paths; SetActive(true) answered with the
#      shell's answer (false unanswered), SetActive(false) false and not asked; GetActive /
#      GetActiveTime / ActiveChanged follow the shell's state (one signal per change, on each
#      path); GetSessionIdleTime answered by the shell per call (a late answer answers no
#      newer call), or an error when it does not answer; holders of a helper before taken
#      over where their caller is on the bus; the name asked for only after the shell's
#      {"own":true}, released with the apps' cookies at {"own":false} (another program can
#      then own it; queued, it leaves the queue) and taken back at {"own":true};
#      its standard input closed → it ends and the
#      name is free; the
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
holder() { printf '{"app":"%s","caller":"%s","cookie":%s,"reason":"%s"}' "$1" "$2" "$3" "$4"; }
cookie_of() { sed -n 's/^cookie \([0-9][0-9]*\)$/\1/p' <<< "$1"; }

echo "the helper on a private bus"
protocol=$(sed -n 's/.*readonly property int protocol: \([0-9]*\).*/\1/p' "$REPO/singletons/HelperRules.qml" | head -n 1)
start helper "$helper" screensaver
check "it says it is ready, with its protocol" test "$(next helper)" = "{\"event\":\"ready\",\"protocol\":$protocol}"
check "… and leaves the name alone until the shell says" name_free
tell helper '{"own":true}'
check "the shell's own: true → it owns org.freedesktop.ScreenSaver" test "$(next helper)" = '{"event":"name","owned":true}'

start first "$client"
start second "$client"
start watcher "$client"
check "the apps are on the bus" test "$(next first)$(next second)$(next watcher)" = readyreadyready
tell watcher watch
check "one watches ActiveChanged on both paths" test "$(next watcher)" = watching

tell first unique
first_name=$(next first | sed -n 's/^unique //p')
tell second unique
second_name=$(next second | sed -n 's/^unique //p')
long=$(head -c 10240 /dev/zero | tr '\0' r)
tell first "$(printf 'inhibit\t<b>Player</b> & co %s\t%s' "$long" "$long")"
reply=$(next first)
first_cookie=$(cookie_of "$reply")
check "Inhibit: a cookie" test -n "$first_cookie"
check "… the holder reported with its caller: markup as text, the app's name cut at 64 characters, the 10 kB reason at 128" \
    test "$(next helper)" = "$(holders "$(holder "<b>Player</b> & co ${long:0:45}" "$first_name" "$first_cookie" "${long:0:128}")")"
tell second "path	/ScreenSaver"
next second > /dev/null
tell second "$(printf 'inhibit\tmpv\tvideo playing')"
second_cookie=$(cookie_of "$(next second)")
check "Inhibit on /ScreenSaver: both holders, by cookie" \
    grep -q "$(holder mpv "$second_name" "$second_cookie" "video playing")" <<< "$(next helper)"
check "… two cookies apart" test -n "$second_cookie" -a "$second_cookie" != "$first_cookie"
tell first "uninhibit	$second_cookie"
check "UnInhibit of another caller's cookie: answered" test "$(next first)" = ok
tell first "uninhibit	$first_cookie"
next first > /dev/null
check "… left it (the next report, after the caller's own UnInhibit, still holds it)" \
    test "$(next helper)" = "$(holders "$(holder mpv "$second_name" "$second_cookie" "video playing")")"
tell second "$(printf 'inhibit\tmpv\tsecond one')"
next second > /dev/null
next helper > /dev/null
close_input second
check "a caller leaving the bus holding two cookies: both dropped, in one report" test "$(next helper)" = "$(holders "")"
gdbus_cookie=$(call /org/freedesktop/ScreenSaver Inhibit gdbus "one call" | sed -n 's/^(uint32 \([0-9]*\),)$/\1/p')
report=$(next helper)
[ "$report" = "$(holders "")" ] || report=$(next helper)
check "a gdbus Inhibit (its connection ends at once): handed a cookie, then dropped as it leaves" \
    test -n "$gdbus_cookie" -a "$report" = "$(holders "")"

tell first "flood	200"
check "a client inhibiting and releasing 200 times in a row: done" test "$(next first)" = flooded
# Quiet for longer than the helper gathers changes (75 ms): every report has gone
sleep 0.3
reports=$(($(wc -l < "$dir/helper.out") - $(cat "$dir/helper.read")))
check "… a few reports, not 400 ($reports)" test "$reports" -ge 1 -a "$reports" -le 40
until [ "$reports" -le 0 ]; do last=$(next helper); reports=$((reports - 1)); done
check "… the last one empty" test "$last" = "$(holders "")"

for i in $(seq 1 16); do tell first "$(printf 'inhibit\tmany\t%s' "$i")"; done
for i in $(seq 1 16); do next first > /dev/null; done
tell first "$(printf 'inhibit\tmany\t17')"
check "a 17th cookie for one caller: refused (LimitsExceeded)" test "$(next first)" = "error org.freedesktop.DBus.Error.LimitsExceeded"
tell first "$(printf 'inhibit2\tmany\t17')"
check "… also through a second connection of the same process" test "$(next first)" = "error org.freedesktop.DBus.Error.LimitsExceeded"
sixteen() { [ "$(tail -n 1 "$dir/helper.out" | grep -o '"cookie"' | wc -l)" = 16 ]; }
tries=0
until sixteen || [ "$tries" -ge 100 ]; do sleep 0.05; tries=$((tries + 1)); done
check "… the 16 reported" sixteen
wc -l < "$dir/helper.out" > "$dir/helper.read"
tell first exit
check "… the caller gone, its 16 dropped" test "$(next helper)" = "$(holders "")"

call /ScreenSaver SimulateUserActivity > /dev/null
check "SimulateUserActivity (on /ScreenSaver): forwarded" test "$(next helper)" = '{"event":"activity"}'
call /org/freedesktop/ScreenSaver SimulateUserActivity > /dev/null
check "… and on /org/freedesktop/ScreenSaver" test "$(next helper)" = '{"event":"activity"}'
call /ScreenSaver SetActive true > "$dir/set.answer" &
set_call=$!
asked=$(next helper)
set_id=$(sed -n 's/^{"event":"setActive","id":\([0-9]*\)}$/\1/p' <<< "$asked")
check "SetActive(true): the shell asked, with an id" test -n "$set_id"
tell helper "{\"answer\":$set_id,\"taken\":true}"
wait "$set_call"
check "… taken: true to the app" test "$(cat "$dir/set.answer")" = "(true,)"
call /ScreenSaver SetActive true > "$dir/set.answer" &
set_call=$!
set_id=$(next helper | sed -n 's/^{"event":"setActive","id":\([0-9]*\)}$/\1/p')
tell helper "{\"answer\":$set_id,\"taken\":false}"
wait "$set_call"
check "SetActive(true) not taken (the shell locked): false to the app" test "$(cat "$dir/set.answer")" = "(false,)"
started_at=$SECONDS
check "SetActive(true) unanswered: false after 2 s" test "$(call /ScreenSaver SetActive true)" = "(false,)"
check "… (within a few seconds)" test $((SECONDS - started_at)) -le 4
next helper > /dev/null
check "SetActive(false): false, and the shell not asked" test "$(call /ScreenSaver SetActive false)" = "(false,)"

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
check "the same state again (then a line it does not know: an error; SetActive(false) asked nothing before it)" \
    test "$(next helper)" = '{"event":"error","message":"unknown message"}'
tell watcher active
check "… no second ActiveChanged" test "$(next watcher)" = "active true"
tell helper '{"active":false}'
check "inactive: ActiveChanged(false)" test "$(next watcher)" = "ActiveChanged /org/freedesktop/ScreenSaver false"
next watcher > /dev/null
check "… GetActive false" test "$(call /ScreenSaver GetActive)" = "(false,)"

call /ScreenSaver GetSessionIdleTime > "$dir/idle.answer" &
idle_call=$!
idle_id=$(next helper | sed -n 's/^{"event":"askIdle","id":\([0-9]*\)}$/\1/p')
check "GetSessionIdleTime: the shell asked, with an id" test -n "$idle_id"
call /ScreenSaver GetSessionIdleTime > "$dir/idle2.answer" &
idle_call2=$!
idle_id2=$(next helper | sed -n 's/^{"event":"askIdle","id":\([0-9]*\)}$/\1/p')
check "… a second call: an id of its own" test -n "$idle_id2" -a "$idle_id2" != "$idle_id"
tell helper "{\"answer\":$idle_id2,\"idleSeconds\":9}"
tell helper "{\"answer\":$idle_id,\"idleSeconds\":7}"
wait "$idle_call" "$idle_call2"
check "… each call gets its own answer" test "$(cat "$dir/idle.answer") $(cat "$dir/idle2.answer")" = "(uint32 7,) (uint32 9,)"
started_at=$SECONDS
idle_unanswered=$(call /ScreenSaver GetSessionIdleTime)
check "… unanswered: an error after 2 s" grep -q "org.freedesktop.DBus.Error.Failed" <<< "$idle_unanswered"
check "… (within a few seconds)" test $((SECONDS - started_at)) -le 4
late_id=$(next helper | sed -n 's/^{"event":"askIdle","id":\([0-9]*\)}$/\1/p')
call /ScreenSaver GetSessionIdleTime > "$dir/idle3.answer" &
idle_call3=$!
newer_id=$(next helper | sed -n 's/^{"event":"askIdle","id":\([0-9]*\)}$/\1/p')
tell helper "{\"answer\":$late_id,\"idleSeconds\":1}"
tell helper "{\"answer\":$newer_id,\"idleSeconds\":3}"
wait "$idle_call3"
check "… its late answer does not answer a newer call" test "$(cat "$dir/idle3.answer")" = "(uint32 3,)"

# A helper that ended: the next takes over its holders whose callers are still on the bus
start adopter "$client"
next adopter > /dev/null
tell adopter unique
adopter_name=$(next adopter | sed -n 's/^unique //p')
tell helper "{\"adopt\":[{\"caller\":\"$adopter_name\",\"app\":\"kept\",\"reason\":\"still here\",\"cookie\":4242},{\"caller\":\":1.9999\",\"app\":\"gone\",\"reason\":\"\",\"cookie\":4243},{\"caller\":\"not-unique\",\"app\":\"odd\",\"reason\":\"\",\"cookie\":4244}]}"
check "adopt: the holder whose caller is on the bus taken over, the others not" \
    test "$(next helper)" = "$(holders "$(holder kept "$adopter_name" 4242 "still here")")"
tell adopter "uninhibit	4242"
next adopter > /dev/null
check "… and its caller can give it back" test "$(next helper)" = "$(holders "")"
tell adopter exit

# Idle turned off in the shell: the name left free for another program, and taken back
start app "$client"
next app > /dev/null
tell app "$(printf 'inhibit\tmpv\tvideo')"
next app > /dev/null
next helper > /dev/null
tell helper '{"own":false}'
check "the shell's own: false → released" test "$(next helper)" = '{"event":"name","released":true}'
check "… the apps' cookies dropped" test "$(next helper)" = "$(holders "")"
check "… and the name is free" name_free
tell helper '{"own":false}'
tell helper '{"what":1}'
check "… own: false again says nothing more" test "$(next helper)" = '{"event":"error","message":"unknown message"}'
start other "$client"
next other > /dev/null
tell other own
check "… so another program can own it" test "$(next other)" = owned
other_name=$(head -c 15 "/proc/${pid_of[other]}/comm" | tr -d '\n')
tell helper '{"own":true}'
check "own: true while another holds it: queued, and said who ($other_name)" \
    test "$(next helper)" = "{\"event\":\"name\",\"owned\":false,\"owner\":\"$other_name\"}"
tell helper '{"own":false}'
check "own: false while queued: released" test "$(next helper)" = '{"event":"name","released":true}'
tell other exit
wait_gone other
check "… it left the queue: the other program gone, the name stays free" name_free
tell helper '{"own":true}'
check "own: true again: the name taken back" test "$(next helper)" = '{"event":"name","owned":true}'
check "… and answers" test "$(call /ScreenSaver GetActive)" = "(false,)"
tell app exit

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
tell queued '{"own":true}'
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
