# Notifications on the lock screen show the app only by default — not the title, not the
# text (a one-time code in a message is not for whoever stands at the locked screen). The
# shell gets a private session bus here, so its notification server registers and a
# notification can be sent to it. One notification, with a title and a text, is shown by
# the screensaver (whose default is still "in full") and then by the lock screen: the lock
# screen's card is a single line, clearly shorter than the screensaver's. (What each
# detail shows, line by line, is checked in the unit suite: tests/LockViewTest.qml.)
#
# Then the toasts' display time, as each sender asks for it (the spec's expire timeout):
# 0 stays, 2000 ms shows 2 s, -1 the user's time (5 s by default). Read from the shell's
# state over the test tree's locktest.notifications IPC: whether each toast is on screen,
# and for how long. Then the three queues: two critical ones — one shown, one waiting on
# the critical badge — beside the staying toast and an ordinary one.
#
# The screensaver and the lock pause nothing: a toast counts down and goes beneath the
# screensaver, and every toast above counts and queues while the session is locked. Last,
# "×" on a toast dismisses its notification: the entry is gone too.

stack_start --session-bus --settings '{"lockscreen.screensaverEnabled": true, "lockscreen.screensaverTimeout": 3,
    "lockscreen.lockscreenEnabled": false}'

check_within 10 "the shell's notification server is on the private bus" notification_server_up
notify "Messages" "Alice" "Your code is 123456, valid for ten minutes. Do not share it with anyone."

# card_height <name> <top>: the height of the card in the notification column (the right
# 360 px under <top>): from the first to the last row lighter than the black scrim all
# across — text rows inside are not, and neither is the warning Hyprland draws across the
# top of the screen in the test bed (started without start-hyprland), over the card
card_height() {
    python3 -I -c "$_PPM_READER"'
width, height, pixels = read_ppm(sys.argv[1])
top = int(sys.argv[2])
rows = []
for y in range(top - 10, min(height, top + 300)):
    row = y * width * 3
    lit = 0
    for x in range(width - 16 - 360, width - 16):
        offset = row + x * 3
        if max(pixels[offset], pixels[offset + 1], pixels[offset + 2]) > 12:
            lit += 1
    if lit >= 340:
        rows.append(y)
print(rows[-1] - rows[0] + 1 if rows else 0)' "$WORK/$1.ppm" "$2"
}

# notify_for <summary> <expire timeout, ms>: a notification asking for that display time,
# printing the id the server gives it
notify_for() {
    DBUS_SESSION_BUS_ADDRESS=$LOCKTEST_SESSION_BUS gdbus call --session \
        --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.Notify "Timer" 0 "" "$1" "" '[]' '{}' "int32 $2" \
        | sed -n 's/^(uint32 \([0-9]*\),)$/\1/p'
}

# toast_is <id> <shown: true|false> [<duration, ms>]: the shell's state of that
# notification's toast
toast_is() {
    shell_ipc locktest.notifications notificationState | python3 -I -c '
import json, sys
toast = next((n["toast"] for n in json.load(sys.stdin) if n["id"] == int(sys.argv[1])), None)
wanted = {"shown": sys.argv[2] == "true"}
if len(sys.argv) > 3:
    wanted["duration"] = int(sys.argv[3])
sys.exit(0 if toast is not None and all(toast.get(key) == value for key, value in wanted.items()) else 1)' "$@"
}

check_within 8 "the screensaver shows" state_is screensaver true
sleep 1.2 # its fade in (800 ms by default)
screenshot_ppm screensaver
on_screensaver=$(card_height screensaver 30)
log "the notification's card on the screensaver (in full): $on_screensaver px"
check "the screensaver shows the card" test "$on_screensaver" -gt 0

# The screensaver pauses nothing: a toast counts down beneath it and goes (shown again
# after it, it would be stale)
under_screensaver=$(notify_for "Under the screensaver" 2000)
check_within 5 "a 2000 ms toast sent while the screensaver shows is up" toast_is "$under_screensaver" true 2000
check_within 4 "… and gone after its time" toast_is "$under_screensaver" false
check "… the screensaver still showing" state_is screensaver true
# Its entry out of the way: the lock screen's card below is measured alone
check "its entry dismissed" test -z "$(shell_ipc shelltest notificationDismiss "$under_screensaver")"

move_pointer 700 400
move_pointer 710 410
check_within 3 "the screensaver goes" state_is screensaver false

lock_by_ipc
check_within 5 "locked" compositor_locked
sleep 1
check "the prompt sleeps (the notifications show)" state_is prompt_awake false
screenshot_ppm lock
on_lock=$(card_height lock 16)
log "the notification's card on the lock screen (default detail): $on_lock px"
check "the lock screen shows the card" test "$on_lock" -gt 0
check "a single line: shorter than the screensaver's by at least the title and the text" \
    test "$on_lock" -lt "$((on_screensaver - 20))"

staying=$(notify_for "Stays" 0)
check "the server gave the notification an id" test -n "$staying"
check_within 5 "expire 0: its toast is up, with no time (it stays)" toast_is "$staying" true 0
timed=$(notify_for "Two seconds" 2000)
check_within 5 "expire 2000: its toast is up too, for 2000 ms (the one that stays holds no slot)" toast_is "$timed" true 2000
check_within 4 "… and gone after it, well before the user's 5 s" toast_is "$timed" false
usual=$(notify_for "The usual" -1)
check_within 5 "expire -1: its toast is up for the user's time, 5000 ms" toast_is "$usual" true 5000
check_within 8 "… and gone after it" toast_is "$usual" false
check "the one that stays is still up, past the user's time" toast_is "$staying" true 0
check "all of it while locked: the lock pauses no countdown" compositor_locked

# The three queues: critical toasts stay in their own queue, one at a time by default; a
# second waits there, counted on the critical badge, while toasts of the other queues
# still show beside it
notify_critical() {
    DBUS_SESSION_BUS_ADDRESS=$LOCKTEST_SESSION_BUS gdbus call --session \
        --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.Notify "Power" 0 "" "$1" "" '[]' '{"urgency": <byte 2>}' "int32 -1" \
        | sed -n 's/^(uint32 \([0-9]*\),)$/\1/p'
}

# toast_at <id> <place> <queue>: where that notification's toast is
toast_at() {
    shell_ipc locktest.notifications notificationState | python3 -I -c '
import json, sys
toast = next((n["toast"] for n in json.load(sys.stdin) if n["id"] == int(sys.argv[1])), None)
sys.exit(0 if toast is not None and toast.get("place") == sys.argv[2] and toast.get("queue") == sys.argv[3] else 1)' "$@"
}

# badges_are <critical> <staying> <ordinary>: the waiting counts the badges show
badges_are() {
    shell_ipc shelltest toastBadges | python3 -I -c '
import json, sys
badges = json.load(sys.stdin)
sys.exit(0 if [badges.get(queue) for queue in ("critical", "staying", "ordinary")] == [int(arg) for arg in sys.argv[1:4]] else 1)' "$@"
}

first_critical=$(notify_critical "Battery at 4 %")
check_within 5 "urgency critical: its toast shows in the critical queue" toast_at "$first_critical" shown critical
second_critical=$(notify_critical "Battery at 3 %")
check_within 5 "a second critical one waits in the critical queue (one at a time)" toast_at "$second_critical" waiting critical
check "… counted on the critical badge" badges_are 1 0 0
check "the staying toast is still shown beside them" toast_at "$staying" shown staying
beside=$(notify_for "Beside the critical ones" -1)
check_within 5 "an ordinary toast shows beside them, in the ordinary queue" toast_at "$beside" shown ordinary
check_within 8 "… and goes after its time" toast_at "$beside" none ""
check "the critical one still waits, the first still shown" toast_at "$second_critical" waiting critical

# The lock pauses no queue either: of two ordinary toasts (one at a time) the second waits,
# shows when the first has gone and goes after its own time, all while locked
first_of_two=$(notify_for "First of two" 2000)
second_of_two=$(notify_for "Second of two" 2000)
check_within 5 "the first of two shows" toast_at "$first_of_two" shown ordinary
check "… the second waits its turn" toast_at "$second_of_two" waiting ordinary
check_within 4 "the first goes after its time" toast_at "$first_of_two" none ""
check_within 3 "… and the second shows" toast_at "$second_of_two" shown ordinary
check_within 4 "… and goes after its own" toast_at "$second_of_two" none ""
check "still locked" compositor_locked

# has_entry <id> <true|false>: whether the server still holds that notification (its entry
# in the centre)
has_entry() {
    shell_ipc locktest.notifications notificationState | python3 -I -c '
import json, sys
held = any(n["id"] == int(sys.argv[1]) for n in json.load(sys.stdin))
sys.exit(0 if held == (sys.argv[2] == "true") else 1)' "$@"
}

# "×" on a toast dismisses the notification: its entry leaves the centre too
check "the staying toast's entry is in the centre" has_entry "$staying" true
check "\"×\" on its toast" test -z "$(shell_ipc shelltest toastDismiss "$staying")"
check_within 3 "… its entry is gone, its toast too" has_entry "$staying" false
