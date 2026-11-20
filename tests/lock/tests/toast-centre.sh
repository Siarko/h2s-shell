# The toasts beside the open notification centre, and a queue's badge opening it. The HUD's
# overlay is above the centre's popup, so the toasts that stay while the centre is open
# (critical, staying) would be drawn over its cards: while it is open on their screen the
# column — toasts and badges — stands left of it, and slides back when it closes. A click on
# a badge opens the centre on the badge's own screen and closes it there when it is open
# already, as the bell does — with a second output too, where each bar used to answer the
# click and the last one to open won.

stack_start --session-bus

check_within 10 "the shell's notification server is on the private bus" notification_server_up

# notify_staying <summary>: a notification asking to stay (expire 0), printing its id
notify_staying() {
    DBUS_SESSION_BUS_ADDRESS=$LOCKTEST_SESSION_BUS gdbus call --session \
        --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.Notify "Updates" 0 "" "$1" "Ready to install" '[]' '{}' "int32 0" \
        | sed -n 's/^(uint32 \([0-9]*\),)$/\1/p'
}

# json_field <field>: one field of the JSON on stdin, booleans lower case, nothing if absent
json_field() {
    python3 -I -c '
import json, sys
value = json.load(sys.stdin).get(sys.argv[1])
print("" if value is None else (str(value).lower() if isinstance(value, bool) else value))' "$1"
}
# The first screen's HUD covers the whole screen at (0, 0) (toast-modal checks it): its
# coordinates are the screen's
toast_field() { shell_ipc toasttest toastRect "$1" | json_field "$2"; }
badge_field() { shell_ipc toasttest badgeRect staying | json_field "$1"; }
centre_field() { shell_ipc toasttest centreArea | json_field "$1"; }
popup_field() { shell_ipc shelltest popupState | json_field "$1"; }

toast_settled() { [ "$(toast_field "$1" settled)" = true ]; }
badge_settled() { [ "$(badge_field settled)" = true ]; }
toast_right() { echo $(($(toast_field "$1" x) + $(toast_field "$1" width))); }
badge_right() { echo $(($(badge_field x) + $(badge_field width))); }
centre_open_on() { [ "$(popup_field open)" = true ] && [ "$(popup_field content)" = notifications ] && [ "$(centre_field screen)" = "$1" ]; }
centre_closed() { [ "$(popup_field open)" = false ] && [ -z "$(centre_field screen)" ]; }
not() { ! "$@"; }

# Left of the open centre, settled: the toast's and the badge's right edges by its left edge
# less the gap (the theme's osdToast.screenGap, 16)
column_left_of_centre() {
    local left
    left=$(centre_field x)
    [ -n "$left" ] && toast_settled "$1" && badge_settled \
        && [ "$(toast_right "$1")" -le $((left - 16)) ] && [ "$(badge_right)" -le $((left - 16)) ]
}
# toast_back <id> <right>: settled with its right edge where it was
toast_back() { toast_settled "$1" && [ "$(toast_right "$1")" = "$2" ]; }
# The badge settled with its right edge where it was before the centre opened
badge_back() { badge_settled && [ "$(badge_right)" = "$badge_before" ]; }

EXTENT_WIDTH=$OUTPUT_WIDTH EXTENT_HEIGHT=$OUTPUT_HEIGHT
# click_badge: a left click in the middle of the staying badge, where it stands now
click_badge() {
    local x y
    x=$(($(badge_field x) + $(badge_field width) / 2)) y=$(($(badge_field y) + $(badge_field height) / 2))
    send_input "abs $x $y $EXTENT_WIDTH $EXTENT_HEIGHT" "click left"
}

updates=$(notify_staying "Updates ready")
notify_staying "More updates" > /dev/null
check_within 5 "a staying toast rests on the first screen" toast_settled "$updates"
check_within 5 "the next waits: the staying badge shows beside it, at rest" badge_settled
right_before=$(toast_right "$updates")
badge_before=$(badge_right)
log "the toast's right edge at $right_before, the badge's at $badge_before"

# ---- The badge opens the centre on its screen; the column stands left of it ----
click_badge
centre_open() { [ "$(popup_field open)" = true ] && [ "$(popup_field content)" = notifications ]; }
check_within 3 "a click on the badge opens the centre" centre_open
centre_placed() { [ -n "$(centre_field screen)" ]; }
check_within 3 "… its place told to the toasts" centre_placed
screen_a=$(centre_field screen)
log "the centre open on $screen_a at x $(centre_field x), $(centre_field width) px wide"
check "… on the badge's screen (the first)" test "$screen_a" = WAYLAND-1
check "the centre reaches into the toasts' column (else the next checks prove nothing)" \
    test "$(centre_field x)" -lt "$badge_before"
check_within 3 "the toast and its badge move left of the centre, by the gap" column_left_of_centre "$updates"
check "the column stands free of the screen's edge" test "$(centre_field free)" = true
screenshot toast-beside-centre
check "the toast still shows (staying), the next still waits (its badge)" test -n "$(toast_field "$updates" x)" -a -n "$(badge_field x)"

# ---- The badge again: the centre closes, the column slides back ----
click_badge
check_within 3 "a click on the badge with the centre open closes it" centre_closed
check_within 3 "the toast slides back to its place" toast_back "$updates" "$right_before"
check_within 3 "… and the badge to the screen's edge" badge_back

# ---- Two outputs: the badge's own screen, never the other one ----
hyprctl output create headless > /dev/null
second() {
    hyprctl -j monitors | python3 -I -c '
import json, sys
names = [monitor["name"] for monitor in json.load(sys.stdin) if monitor["name"].startswith("HEADLESS")]
print(names[0] if names else "")'
}
wait_until 5 test -n "$(second)" || abort "no second output"
B=$(second)
read -r EXTENT_WIDTH EXTENT_HEIGHT <<< "$(hyprctl -j monitors | python3 -I -c '
import json, sys
monitors = json.load(sys.stdin)
print(max(m["x"] + m["width"] for m in monitors), max(m["y"] + m["height"] for m in monitors))')"
log "a second output, $B: the pointer's extent ${EXTENT_WIDTH}x${EXTENT_HEIGHT}"
two_bars() { [ "$(hyprctl -j layers | python3 -I -c '
import json, sys
print(sum(1 for monitor in json.load(sys.stdin).values() for level in monitor["levels"].values() for layer in level if layer["namespace"] == "hud"))')" = 2 ]; }
check_within 5 "a HUD on each output" two_bars
check_within 3 "the badge still shows on the first screen" badge_settled

for round in 1 2; do
    check_within 3 "round $round: the badge at rest by the screen's edge" badge_back
    click_badge
    check_within 3 "round $round: the badge opens the centre on its own screen ($screen_a), not $B" centre_open_on "$screen_a"
    check_within 3 "… the column left of it" column_left_of_centre "$updates"
    click_badge
    check_within 3 "… the badge again closes it, rather than moving it to $B" centre_closed
done
check "no protocol errors" no_protocol_errors
