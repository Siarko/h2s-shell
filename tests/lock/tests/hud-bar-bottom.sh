# The HUD with the bar at the screen's bottom: its window covers the whole screen (it
# ignores exclusive zones), and nothing it shows lands over the bar — the toasts start at the
# top by their gap (no bar there), the shell's own message rests above the bar by its
# clearance, and a toast dropped onto the bar is kept above it (else, a modal over the bar,
# in the window's input mask, would take the bar's clicks). The top bar: toast-modal. A
# stand-in window under the HUD (--window), as there, for the pointer's drag to reach it.

stack_start --session-bus --window --settings '{"bar.edge": "bottom"}'

check_within 10 "the shell's notification server is on the private bus" notification_server_up

hud_origin() {
    hyprctl -j layers | python3 -I -c '
import json, sys
for monitor in json.load(sys.stdin).values():
    for level in monitor["levels"].values():
        for layer in level:
            if layer["namespace"] == "hud":
                print(layer["x"], layer["y"])
                sys.exit(0)
sys.exit(1)'
}
# reserved <index>: the space kept at a screen edge, from the compositor (0 left, 1 top,
# 2 right, 3 bottom)
reserved() {
    hyprctl -j monitors | python3 -I -c '
import json, sys
print(json.load(sys.stdin)[0]["reserved"][int(sys.argv[1])])' "$1"
}
bar_reserves_bottom() { [ "$(reserved 3)" -gt 0 ]; }
# json_field <json> <field>
json_field() {
    python3 -I -c '
import json, sys
value = json.loads(sys.argv[1]).get(sys.argv[2])
print("" if value is None else (str(value).lower() if isinstance(value, bool) else value))' "$1" "$2"
}
toast_field() { json_field "$(shell_ipc toasttest toastRect "$1")" "$2"; }
pill_field() { json_field "$(shell_ipc toasttest shellPillRect)" "$1"; }
toast_rests() { [ "$(toast_field "$1" settled)" = true ]; }
pill_resting() { [ "$(pill_field resting)" = true ]; }
notify() {
    DBUS_SESSION_BUS_ADDRESS=$LOCKTEST_SESSION_BUS gdbus call --session \
        --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.Notify "$1" 0 "" "$2" "" '[]' "$3" "int32 $4" \
        | sed -n 's/^(uint32 \([0-9]*\),)$/\1/p'
}
# pointer_to <x> <y>: the pointer there, kept on the screen
pointer_to() {
    local x=$1 y=$2
    [ "$x" -ge 0 ] || x=0
    [ "$y" -lt "$OUTPUT_HEIGHT" ] || y=$((OUTPUT_HEIGHT - 1))
    send_input "abs $x $y $OUTPUT_WIDTH $OUTPUT_HEIGHT"
}

wait_until 5 hud_origin || abort "the compositor lists no HUD layer"
wait_until 5 bar_reserves_bottom || true
RESERVED_BOTTOM=$(reserved 3)
log "the bar keeps ${RESERVED_BOTTOM} px at the bottom, $(reserved 1) at the top"
check "the bar keeps space at the screen's bottom, none at the top" test "$RESERVED_BOTTOM" -gt 0 -a "$(reserved 1)" -eq 0
check "the HUD's window covers the whole screen" test "$(hud_origin)" = "0 0"

backup=$(notify "Backup" "Backup running" '{}' 0)
check_within "$GUARD" "a staying toast rests" toast_rests "$backup"
check "its top is the gap from the screen's top, no bar there ($(toast_field "$backup" y))" test "$(toast_field "$backup" y)" -eq 16

notify "Shell" "Saved" '{"category": <"x-qs-shell">}' -1 > /dev/null
check_within "$GUARD" "the shell's message shows and rests" pill_resting
pill_bottom=$(( $(pill_field y) + $(pill_field height) ))
log "the shell's message ends at y ${pill_bottom}, the bar's space starts at $((OUTPUT_HEIGHT - RESERVED_BOTTOM))"
screenshot hud-bar-bottom
check "… above the bar by its clearance (40 px)" test "$pill_bottom" -eq $((OUTPUT_HEIGHT - RESERVED_BOTTOM - 40))

# Dragged by its title line down onto the bar: kept above it, whole
start_x=$(toast_field "$backup" x) start_y=$(toast_field "$backup" y)
height=$(toast_field "$backup" height)
pointer_to $((start_x + 60)) $((start_y + 14))
send_input "press left"
for step in 1 2 3 4 5 6 7 8; do
    pointer_to $((start_x + 60 - step * 50)) $((start_y + 14 + step * 130))
done
send_input "release left"
modal_above_bar() {
    [ "$(toast_field "$backup" modal)" = true ] && [ "$(toast_field "$backup" settled)" = true ] \
        && [ "$(toast_field "$backup" y)" -eq $((OUTPUT_HEIGHT - RESERVED_BOTTOM - height)) ]
}
check_within "$GUARD" "dropped onto the bar: a modal kept just above it" modal_above_bar || log "the toast: $(shell_ipc toasttest toastRect "$backup"), ${height} px tall"
check "no protocol errors" no_protocol_errors
