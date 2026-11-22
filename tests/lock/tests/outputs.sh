# Outputs come and go while locked (a monitor unplugged, a laptop's screen over a suspend):
# each lock surface is an instance of its own, and the prompt follows them. Two rounds:
#
#   added, then removed: the prompt is on the added output when it goes, and moves, awake,
#   to the one left; the password typed there unlocks.
#   removed, then re-added: the output showing the prompt is removed (the prompt moves to
#   the other one) and an output of that kind is added again; a press on the new one
#   brings the prompt there, and the password typed there unlocks.
#   each monitor its own times: with the two outputs left, a profile turns "Set per monitor"
#   on; one output's own times are the screen-off at 6 s (no screensaver), the other's the
#   screensaver at 12 s (set over the idle IPC, by MonitorRules' ids). Idle: at 6 s the
#   first one's power is cut (dpmsStatus false) while the other still shows the desktop and
#   the session is not reported active; at 12 s the other shows the screensaver and stays
#   on, and now the session is active; input brings both back. An entry for a monitor not
#   connected is kept through it all.
#
# hyprctl talks to the nested Hyprland only (the private runtime dir); the session's
# monitors are never touched.

mkdir -p "$XDG_CONFIG_HOME/h2s_shell"
python3 -I -c '
import json, sys
profiles = [
    {"name": "Full", "enabled": True, "when": {}, "set": {}},
    {"name": "Per monitor", "enabled": True, "when": {"fact": "locktest.perMonitor", "is": True},
     "set": {"lockscreen.perMonitor": True}},
]
json.dump({"profiles": json.dumps(profiles), "widgetPresets": "{}"}, open(sys.argv[1], "w"), indent=2)
' "$XDG_CONFIG_HOME/h2s_shell/config.json" || abort "cannot write the config"

stack_start

headless_output() {
    hyprctl -j monitors | python3 -I -c '
import json, sys
names = [monitor["name"] for monitor in json.load(sys.stdin) if monitor["name"].startswith("HEADLESS")]
print(names[0] if names else "")'
}
# point_at <x> <y> <layout width> <layout height>: an absolute pointer position over the
# whole layout (Hyprland maps the virtual pointer's extent onto it)
point_at() { send_input "abs $1 $2 $3 $4" "move 5 5"; }

# ---- Added, then removed ----
lock_by_ipc
check_within "$GUARD" "round 1: locked" compositor_locked
check_within "$GUARD" "round 1: confirmed" state_is secure true
check "round 1: one surface" state_is surfaces 1

hyprctl output create headless > /dev/null
check_within "$GUARD" "round 1: an added output gets a surface of its own" state_is surfaces 2
added=$(headless_output)
log "added output: $added; surfaces: $(state_field surface_screens)"
woke=0
for attempt in 1 2 3 4 5; do
    point_at $((2800 + attempt * 10)) 500 3840 1080
    wait_until 0.5 state_is prompt_screen "$added" && { woke=1; break; }
done
check "round 1: the pointer on the added output wakes the prompt there" test "$woke" = 1
type_text "half"

hyprctl output remove "$added" > /dev/null
check_within "$GUARD" "round 1: the removed output's surface goes" state_is surfaces 1
check_within "$GUARD" "round 1: the prompt moves, awake, to the output left" state_is prompt_screen WAYLAND-1
check "round 1: and starts with an empty field (a new epoch)" test "$(state_field field_epoch)" -ge 1
check "round 1: still locked" compositor_locked

type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "round 1: the password typed afterwards unlocks" compositor_unlocked
log "password checks: $(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)"
check "round 1: what was half typed on the removed output was not sent with it" \
    test "$(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)" = "right "

# ---- Removed, then re-added ----
hyprctl output create headless > /dev/null
wait_until 5 test -n "$(headless_output)" || abort "no second output for round 2"
lock_by_ipc
check_within "$GUARD" "round 2: locked" compositor_locked
check_within "$GUARD" "round 2: two surfaces" state_is surfaces 2
woke=0
for attempt in 1 2 3 4 5; do
    point_at $((200 + attempt * 10)) 500 3840 1080
    wait_until 0.5 state_is prompt_screen WAYLAND-1 && { woke=1; break; }
done
check "round 2: the prompt wakes on WAYLAND-1" test "$woke" = 1
before=$(state_field prompt_surface)

hyprctl output remove WAYLAND-1 > /dev/null
check_within "$GUARD" "round 2: the prompt's output removed, its surface goes" state_is surfaces 1
check_within "$GUARD" "round 2: the prompt moves to the other output" state_is prompt_screen "$(headless_output)"

hyprctl output create wayland > /dev/null
check_within "$GUARD" "round 2: the re-added output gets a new surface" state_is surfaces 2
readded=$(state_field surface_screens | tr ',' '\n' | grep '^WAYLAND' | head -n 1)
log "re-added output: $readded; surfaces: $(state_field surface_screens)"
# The layout is now the headless output (1920 wide) at 0, the re-added one right of it
# (1280x720): press on it
moved=0
for attempt in 1 2 3 4 5; do
    send_input "abs $((2400 + attempt * 10)) 300 3200 1080" "move 5 5" "click left"
    wait_until 0.5 state_is prompt_screen "$readded" && { moved=1; break; }
done
check "round 2: a press on the re-added output brings the prompt there" test "$moved" = 1
check "round 2: on a new instance, not the removed one's" test "$(state_field prompt_surface)" != "$before"
check "round 2: still locked" compositor_locked

type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "round 2: the password typed on the re-added output unlocks" compositor_unlocked
check "round 2: the shell says unlocked" shell_status_is unlocked

# ---- Each monitor its own times ----
idle_json() { shell_ipc idle state | python3 -I -c "import json, sys; print(json.dumps(eval(sys.argv[1], {}, {'state': json.load(sys.stdin)})))" "$1"; }
power_control() { [ "$(idle_json 'state["config"]["canPowerOff"] and len(state["monitors"]) == 2')" = true ]; }
# monitor_field <index> <id|connector>: the idle state's monitors, in their order
monitor_field() { idle_json "state['monitors'][$1]['$2']" | python3 -I -c 'import json, sys; print(json.load(sys.stdin))'; }
shown_is() { [ "$(idle_json "state['state']['shown'].get('$1', 'on')")" = "\"$2\"" ]; }
# dpms_of <connector> <true|false>
dpms_of() {
    hyprctl -j monitors | python3 -I -c '
import json, sys
found = [monitor for monitor in json.load(sys.stdin) if monitor["name"] == sys.argv[1]]
sys.exit(0 if found and str(found[0].get("dpmsStatus")).lower() == sys.argv[2] else 1)' "$1" "$2"
}
# saver_layer_on <connector>: the screensaver's layer is on that output
saver_layer_on() {
    hyprctl -j layers | python3 -I -c '
import json, sys
monitor = json.load(sys.stdin).get(sys.argv[1], {})
sys.exit(0 if any(surface.get("namespace") == "screensaver"
                  for level in monitor.get("levels", {}).values() for surface in level) else 1)' "$1"
}
entries_value() { shell_ipc profiles status | python3 -I -c 'import json, sys; print(json.dumps(json.load(sys.stdin)["values"].get("lockscreen.monitorIdle"), sort_keys=True))'; }
active_is() { [ "$(idle_json "state['state']['active']")" = "$1" ]; }
off_times='{"screensaverEnabled": false, "screensaverTimeout": 300, "screenOffEnabled": true, "screenOffTimeout": 6}'
saver_times='{"screensaverEnabled": true, "screensaverTimeout": 12, "screenOffEnabled": false, "screenOffTimeout": 600}'

check_within "$GUARD" "round 3: the shell can turn both outputs off (Hyprland)" power_control
off_id=$(monitor_field 0 id); off_output=$(monitor_field 0 connector)
saver_id=$(monitor_field 1 id); saver_output=$(monitor_field 1 connector)
log "round 3: off at 6 s: $off_id ($off_output); screensaver at 12 s: $saver_id ($saver_output)"
check "round 3: the two outputs have distinct ids" test "$off_id" != "$saver_id"
check "round 3: times for a monitor not connected are taken" \
    test "$(shell_ipc idle setMonitorTimes 'Gone|Elsewhere|' "$off_times")" = ok
check "round 3: … the first output's times set" test "$(shell_ipc idle setMonitorTimes "$off_id" "$off_times")" = ok
check "round 3: … the other's set" test "$(shell_ipc idle setMonitorTimes "$saver_id" "$saver_times")" = ok
check "round 3: times not understood are refused" \
    test "$(shell_ipc idle setMonitorTimes "$saver_id" '{"screensaverEnabled": true}')" != ok
check "round 3: … and JSON that is not" test "$(shell_ipc idle setMonitorTimes "$saver_id" '{not json')" != ok
shell_ipc profiles simulate '{"locktest.perMonitor": true}' > /dev/null
move_pointer 700 400
move_pointer 720 410
# One reading between the two times: the first output off, the other on, not active
between_times() {
    [ "$(idle_json "[state['state']['shown'].get('$off_id', 'on'), state['state']['shown'].get('$saver_id', 'on'), state['state']['active']]")" = '["off", "on", false]' ]
}
check_timed 15 "round 3: idle 6 s: the shell has the first output off, the other still on, not active (not every monitor dark)" between_times
check_within "$GUARD" "round 3: … the first output's power is cut" dpms_of "$off_output" false
check_timed 15 "round 3: idle 12 s: the other shows the screensaver" saver_layer_on "$saver_output"
check "round 3: … and is still on" dpms_of "$saver_output" true
check "round 3: … the shell says saver" shown_is "$saver_id" saver
check_within "$GUARD" "round 3: … every monitor dark: active" active_is true
move_pointer 700 400
move_pointer 720 410
check_within "$GUARD" "round 3: input: the first output on again" dpms_of "$off_output" true
check_within "$GUARD" "round 3: … the screensaver gone" shown_is "$saver_id" on
expected=$(python3 -I -c '
import json, sys
off, saver = json.loads(sys.argv[3]), json.loads(sys.argv[4])
print(json.dumps({"Gone|Elsewhere|": off, sys.argv[1]: off, sys.argv[2]: saver}, sort_keys=True))' "$off_id" "$saver_id" "$off_times" "$saver_times")
check "round 3: the monitor not connected keeps its entry" test "$(entries_value)" = "$expected"
check "no protocol error" no_protocol_errors
