# A sender's progress, through the shell's real notification server on the private session
# bus: a notification with the spec's "value" hint at 10, then the same notification
# replaced (replaces_id) at 60 — the shell holds one entry, at 60, as its card shows it —
# then ended with the shell's "x-qs-progress-state" hint "done": full. (What the card draws
# for each value and state is checked in the unit suites: NotificationRulesTest,
# NotifierTest, LockViewTest.)

stack_start --session-bus --settings '{}'
check_within 10 "the shell's notification server is on the private bus" notification_server_up

# notify_hints <replaces_id> <summary> <hints>: a Notify with these hints (GVariant text),
# printing the id the server gives it
notify_hints() {
    DBUS_SESSION_BUS_ADDRESS=$LOCKTEST_SESSION_BUS gdbus call --session \
        --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.Notify "Transfers" "$1" "" "$2" "photo.jpg" '[]' "$3" "int32 -1" \
        | sed -n 's/^(uint32 \([0-9]*\),)$/\1/p'
}

# notifications_are <json>: the shell's notifications are exactly these (id, summary, and
# the progress's shown / value / state)
notifications_are() {
    shell_ipc shelltest notificationState | python3 -I -c '
import json, sys
held = [[n["id"], n["summary"], n["progress"]["shown"], n["progress"]["value"], n["progress"]["state"]]
        for n in json.load(sys.stdin)]
sys.exit(0 if held == json.loads(sys.argv[1]) else 1)' "$1"
}

id=$(notify_hints 0 "Sending" '{"value": <int32 10>}')
check "the server gave the notification an id" test -n "$id"
check_within 5 "one entry, its bar at 10 %" notifications_are "[[$id, \"Sending\", true, 0.1, \"running\"]]"

replaced=$(notify_hints "$id" "Sending" '{"value": <int32 60>}')
check "the replacement keeps the id" test "$replaced" = "$id"
check_within 5 "still one entry, its bar at 60 %" notifications_are "[[$id, \"Sending\", true, 0.6, \"running\"]]"

notify_hints "$id" "Sent" "{\"value\": <int32 60>, \"x-qs-progress-state\": <'done'>}" > /dev/null
check_within 5 "done: one entry, its bar full" notifications_are "[[$id, \"Sent\", true, 1, \"done\"]]"
