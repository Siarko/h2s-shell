# The shell's own sender's progress notification, on its real path: a handle (Notifier's,
# io/NotificationHandle.qml) driven over the bed's `locktest progress` IPC sends with the
# real gdbus to the shell's own notification server on the private session bus, and learns
# a click and a dismissal from that server in-process. Checked from the shell's state
# (`shelltest notificationState`) and the handle's (`locktest progress state`):
#
# - a summary and a body of quotes, backslashes, line breaks and an emoji arrive exactly as
#   sent (the GVariant text gdbus parses: NotificationRules.gvariantString);
# - "whileRunning": the toast stays past the user's time (an ordinary toast sent beside it
#   comes and goes);
# - ten updates in a burst: a few gdbus calls, the last value shown;
# - an action pressed after an update reaches its callback once, the entry stays;
# - done: the toast takes the user's time and goes, the entry stays, full;
# - dismissed: onDismissed, the entry gone, a later update sends nothing;
# - close(): gone, no onDismissed;
# - a reload: the running notification of the run before is dismissed as an orphan, an
#   ended one stays;
# - no gdbus process left over.

stack_start --session-bus --reload-seam --settings '{"notifications.toastDuration": 2}'
check_within 10 "the shell's notification server is on the private bus" notification_server_up

progress() { shell_ipc locktest progress "$1" "${2:-}"; }

# handle_is <python expression over the handle's state `h`>
handle_is() {
    progress state | python3 -I -c '
import json, sys
h = json.load(sys.stdin)
sys.exit(0 if eval(sys.argv[1]) else 1)' "$1"
}

# entry_is <id> <python expression over the entry `n`, None when it is not there>
entry_is() {
    shell_ipc shelltest notificationState | python3 -I -c '
import json, sys
n = next((n for n in json.load(sys.stdin) if n["id"] == int(sys.argv[1])), None)
sys.exit(0 if eval(sys.argv[2]) else 1)' "$1" "$2"
}

handle_field() { progress state | python3 -I -c 'import json, sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"; }

# The texts, as Python: quotes, backslashes, line breaks, an emoji, a leading-dash word, a %s
texts_py='q = chr(39); summary = "It" + q + "s \"quoted\" \\ back\\slash 😀 -x"; body = "line one\nline " + q + "two" + q + " \\ \"three\"\n😀 ü %s"'
show_json=$(python3 -I -c "$texts_py"'
import json; print(json.dumps({"summary": summary, "body": body, "progress": 0, "toast": "whileRunning", "actions": ["cancel"]}))')
log "sent: $show_json"

# texts_are <id>: the entry's summary and body are exactly what show_json sent
texts_are() {
    shell_ipc shelltest notificationState | python3 -I -c '
import json, sys
sent = json.loads(sys.argv[2])
n = next((n for n in json.load(sys.stdin) if n["id"] == int(sys.argv[1])), None)
sys.exit(0 if n is not None and n["summary"] == sent["summary"] and n["body"] == sent["body"] else 1)' "$1" "$show_json"
}

progress send "$show_json" > /dev/null
check_within 5 "shown: the handle has an id and runs" handle_is 'h["id"] > 0 and h["state"] == "running" and h["open"]'
id=$(handle_field id)
check "the summary and the body arrived exactly as sent" texts_are "$id"
check "one entry, its bar at 0" entry_is "$id" 'n["progress"]["shown"] and n["progress"]["value"] == 0 and n["progress"]["state"] == "running"'
check_within 5 "whileRunning: its toast is up and stays (no time)" entry_is "$id" 'n["toast"] == {"shown": True, "duration": 0}'

usual=$(DBUS_SESSION_BUS_ADDRESS=$LOCKTEST_SESSION_BUS gdbus call --session \
    --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.Notify "Messages" 0 "" "Beside" "" '[]' '{}' "int32 -1" \
    | sed -n 's/^(uint32 \([0-9]*\),)$/\1/p')
check_within 5 "an ordinary toast beside it counts the user's 2 s" entry_is "$usual" 'n["toast"]["shown"] and n["toast"]["duration"] == 2000'
check_within 6 "… and goes" entry_is "$usual" 'not n["toast"]["shown"]'
check "the progress toast is still up, past the user's time" entry_is "$id" 'n["toast"] == {"shown": True, "duration": 0}'

calls_before=$(handle_field calls)
for value in 10 20 30 40 50 60 70 80 90 95; do
    progress update "{\"progress\": $value}" > /dev/null
done
check_within 5 "ten updates in a burst: the last value shown" entry_is "$id" 'n["progress"]["value"] == 0.95'
calls_after=$(handle_field calls)
log "gdbus calls for the ten updates: $((calls_after - calls_before))"
check "… in at most four gdbus calls (coalesced)" test "$((calls_after - calls_before))" -le 4
check "… still one entry with that id" entry_is "$id" 'n is not None and n["toast"]["shown"]'

check "an action pressed on it" test -z "$(shell_ipc shelltest notificationAction "$id" cancel)"
check_within 5 "the action reached its callback" handle_is 'h["events"] == ["action:cancel"]'
check "… once, the handle open" handle_is 'h["events"] == ["action:cancel"] and h["open"]'
check "… and the entry stays (resident)" entry_is "$id" 'n is not None'

progress update '{"state": "done", "progress": 100, "summary": "Sent"}' > /dev/null
check_within 5 "done: the bar full, the summary changed" entry_is "$id" 'n["summary"] == "Sent" and n["progress"]["value"] == 1 and n["progress"]["state"] == "done"'
check_within 5 "done: the toast takes the user's 2 s" entry_is "$id" 'n["toast"] == {"shown": True, "duration": 2000}'
check_within 6 "… and goes" entry_is "$id" 'not n["toast"]["shown"]'
check "the entry stays in the centre" entry_is "$id" 'n is not None and n["progress"]["state"] == "done"'
check "after done no update is taken" handle_is 'h["state"] == "done"'
done_id=$id

# Dismissed by the user (as the centre dismisses it)
progress send '{"summary": "Second", "progress": 10}' > /dev/null
check_within 5 "a second handle shown" handle_is 'h["id"] > 0 and h["state"] == "running"'
id=$(handle_field id)
check "dismissed in the centre" test -z "$(shell_ipc shelltest notificationDismiss "$id")"
check_within 5 "dismissed: onDismissed, the handle closed" handle_is 'h["events"] == ["dismissed"] and h["state"] == "closed" and not h["open"]'
check "… the entry gone" entry_is "$id" 'n is None'
calls_before=$(handle_field calls)
progress update '{"progress": 50, "summary": "Back?"}' > /dev/null
check "a later update sends nothing" test "$(handle_field calls)" = "$calls_before"
check "… and brings nothing back" entry_is "$id" 'n is None'

# close()
progress send '{"summary": "Third", "progress": 10, "actions": ["cancel"]}' > /dev/null
check_within 5 "a third handle shown" handle_is 'h["id"] > 0 and h["state"] == "running"'
id=$(handle_field id)
check_within 5 "its entry is there" entry_is "$id" 'n is not None'
progress close > /dev/null
check_within 5 "close(): the entry gone" entry_is "$id" 'n is None'
check "close(): no onDismissed, closed" handle_is 'h["events"] == [] and h["state"] == "closed"'

# A reload: the running notification of the run before is an orphan
progress send '{"summary": "Orphan", "progress": 30, "toast": "whileRunning"}' > /dev/null
check_within 5 "a fourth handle shown" handle_is 'h["id"] > 0 and h["state"] == "running"'
orphan=$(handle_field id)
reloads_before=$(shell_log_count "Reloading configuration")
shell_ipc locktest reload false > /dev/null
check_within 10 "the shell reloaded" lines_more_than "$reloads_before" "Reloading configuration" "$WORK/shell.log"
check_within 10 "the reloaded shell dismissed the orphan" entry_is "$orphan" 'n is None'
check "the ended one stays" entry_is "$done_id" 'n is not None and n["progress"]["state"] == "done"'

no_gdbus_left() { ! test_pgrep -f "org.freedesktop.Notifications" > /dev/null; }
check_within 5 "no gdbus process left over" no_gdbus_left
