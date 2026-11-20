# A staying toast dragged out by its title line becomes a modal, and the HUD's input mask
# follows: the HUD is one full-screen overlay window per screen, transparent to the pointer
# except where its toasts are (Hud.qml's mask). A modal stands anywhere on the screen, so
# its rectangle is in the mask as it comes, moves and goes. Checked with real pointer events
# through the compositor and a stand-in window beneath (input/ltwindow.py logs each press it
# receives): a click beside a modal reaches the window, a click on it does not; the drag is
# followed while the button is held (one surface: the pointer stays with it); the dropped
# toast frees its slot in the staying queue for the next one.

stack_start --session-bus --window

check_within 10 "the shell's notification server is on the private bus" notification_server_up

# notify_staying <summary>: a notification asking to stay (expire 0), printing its id
notify_staying() {
    DBUS_SESSION_BUS_ADDRESS=$LOCKTEST_SESSION_BUS gdbus call --session \
        --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.Notify "Backup" 0 "" "$1" "Copying files" '[]' '{}' "int32 0" \
        | sed -n 's/^(uint32 \([0-9]*\),)$/\1/p'
}

# toast_at <id> <place> <queue>: where that notification's toast is
toast_at() {
    shell_ipc shelltest notificationState | python3 -I -c '
import json, sys
toast = next((n["toast"] for n in json.load(sys.stdin) if n["id"] == int(sys.argv[1])), None)
sys.exit(0 if toast is not None and toast.get("place") == sys.argv[2] and toast.get("queue") == sys.argv[3] else 1)' "$@"
}

# The HUD's window on the screen, from the compositor: the toasts' coordinates are the
# window's, and it starts below the bar's reserved space (it keeps out of other exclusive
# zones)
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
HUD_X=0 HUD_Y=0
# toast_rect <id> <field>: one field of the toast's rectangle on the first screen — x and y on
# the screen, width, height, modal, movable, settled (not moving); nothing while it has none
toast_rect() {
    shell_ipc toasttest toastRect "$1" | python3 -I -c '
import json, sys
rect = json.load(sys.stdin)
offset = {"x": int(sys.argv[2]), "y": int(sys.argv[3])}
value = rect.get(sys.argv[1])
if value is not None and sys.argv[1] in offset:
    value += offset[sys.argv[1]]
print("" if value is None else (str(value).lower() if isinstance(value, bool) else value))' "$2" "$HUD_X" "$HUD_Y"
}
toast_rect_is() { [ "$(toast_rect "$1" "$2")" = "$3" ]; }
# toast_near <id> <x> <y>: its top left within 2 px of (x, y)
toast_near() {
    local x y
    x=$(toast_rect "$1" x) y=$(toast_rect "$1" y)
    [ -n "$x" ] && [ -n "$y" ] && [ $((x - $2)) -ge -2 ] && [ $((x - $2)) -le 2 ] && [ $((y - $3)) -ge -2 ] && [ $((y - $3)) -le 2 ]
}

# The presses the stand-in window has received, in its own coordinates; WINDOW_DX/DY (from
# the first click, at a known place) turn them into the screen's
window_presses() { grep -c '^press' "$WORK/window.log"; }
window_presses_are() { [ "$(window_presses)" = "$1" ]; }
WINDOW_DX=0 WINDOW_DY=0
# window_pressed_at <x> <y>: the window received a press there (screen coordinates, 1 px)
window_pressed_at() {
    awk -v x="$1" -v y="$2" -v dx="$WINDOW_DX" -v dy="$WINDOW_DY" '
        $1 == "press" { ex = $2 + dx - x; ey = $3 + dy - y; if (ex * ex <= 1 && ey * ey <= 1) found = 1 }
        END { exit !found }' "$WORK/window.log"
}
# clicks_pass_beside <on x> <on y> <beside x> <beside y> <what>: a click on a toast, then one beside
# it; waits for the window to receive the second, and then checks that it did not receive
# the first (input arrives in order: had it come, it came before)
clicks_pass_beside() {
    click_at "$1" "$2"
    click_at "$3" "$4"
    check_within 3 "$5: a click beside it reaches the window beneath" window_pressed_at "$3" "$4"
    check "… a click on it does not (it is the toast's)" not window_pressed_at "$1" "$2"
}
not() { ! "$@"; }

# pointer_to <x> <y>: the pointer there, kept on the screen
pointer_to() {
    local x=$1 y=$2
    [ "$x" -ge 0 ] || x=0
    [ "$y" -ge 0 ] || y=0
    send_input "abs $x $y $OUTPUT_WIDTH $OUTPUT_HEIGHT"
}
# click_at <x> <y>: the pointer there, a left click
click_at() { pointer_to "$1" "$2"; send_input "click left"; }
# drag_held <from x> <from y> <dx> <dy> <steps>: pressed there, moved by (dx, dy) in steps, held
# (released by the caller)
drag_held() {
    local step
    pointer_to "$1" "$2"
    send_input "press left"
    for step in $(seq 1 "$5"); do
        pointer_to $(($1 + $3 * step / $5)) $(($2 + $4 * step / $5))
    done
}

wait_until 5 hud_origin || abort "the compositor lists no HUD layer"
read -r HUD_X HUD_Y < <(hud_origin)
log "the HUD's window on the screen at ($HUD_X, $HUD_Y)"

backup=$(notify_staying "Backup running")
check_within 5 "a staying toast shows" toast_at "$backup" shown staying
next=$(notify_staying "Second backup")
check_within 5 "a second one waits in the staying queue (one at a time)" toast_at "$next" waiting staying
toast_rests_movable() { toast_rect_is "$1" movable true && toast_rect_is "$1" settled true; }
check_within 5 "the toast rests on the first screen, movable (the default)" toast_rests_movable "$backup"

# Before: a click away from the toasts reaches the window beneath
click_at 400 600
check_within 3 "a click away from the toasts reaches the window beneath" window_presses_are 1
read -r _ window_x window_y < <(grep '^press' "$WORK/window.log" | tail -n 1)
WINDOW_DX=$((400 - window_x)) WINDOW_DY=$((600 - window_y))
log "the stand-in window's origin on the screen: ($WINDOW_DX, $WINDOW_DY)"

# Dragged by its title line: pressed there, moved in steps, followed while held, dropped
start_x=$(toast_rect "$backup" x) start_y=$(toast_rect "$backup" y)
log "the toast at ($start_x, $start_y), $(toast_rect "$backup" width)x$(toast_rect "$backup" height)"
grab_x=$((start_x + 60)) grab_y=$((start_y + 14))
drag_held $grab_x $grab_y -500 300 10
check_within 2 "while held, the toast follows the pointer (500 px left, 300 down)" toast_near "$backup" $((start_x - 500)) $((start_y + 300))
for step in 1 2 3 4 5 6; do
    pointer_to $((grab_x - 500 - step * 50)) $((grab_y + 300 + step * 30))
done
check_within 2 "… and on, still held" toast_near "$backup" $((start_x - 800)) $((start_y + 480))
send_input "release left"
check_within 3 "dropped: a modal" toast_at "$backup" moved staying
check "… where it was dropped" toast_near "$backup" $((start_x - 800)) $((start_y + 480))
check_within 3 "its slot in the staying queue went to the next one" toast_at "$next" shown staying
check_within 3 "… which rests in the stack" toast_rect_is "$next" settled true

modal_x=$(toast_rect "$backup" x) modal_y=$(toast_rect "$backup" y)
modal_height=$(toast_rect "$backup" height)
log "the modal at ($modal_x, $modal_y)"

clicks_pass_beside $((modal_x + 120)) $((modal_y + modal_height / 2)) $((modal_x - 40)) $((modal_y + modal_height / 2)) "the modal"
# The stack: the next toast took the place the dragged one left; below it, nothing of the shell
next_x=$(toast_rect "$next" x) next_y=$(toast_rect "$next" y)
clicks_pass_beside $((next_x + 60)) $((next_y + 30)) $((next_x + 60)) 900 "the next toast, in the stack"

# Dragged again, as a modal: it just changes place, and the mask follows it
drag_held $((modal_x + 60)) $((modal_y + 14)) 300 -120 6
send_input "release left"
check_within 3 "a modal dragged again: at its new place" toast_near "$backup" $((modal_x + 300)) $((modal_y - 120))
check "… still a modal" toast_at "$backup" moved staying
clicks_pass_beside $((modal_x + 300 + 120)) $((modal_y - 120 + modal_height / 2)) $((modal_x + 120)) $((modal_y + modal_height / 2)) \
    "the modal at its new place (beside it: its old place)"

# Dropped half off the screen: back inside it, whole
# (the window reaches past the screen's bottom by the bar's reserved space: kept on the screen)
drag_held $((modal_x + 360)) $((modal_y - 106)) -1600 1000 8
send_input "release left"
check_within 3 "dropped past the bottom left corner: inside the screen, whole" \
    toast_near "$backup" "$HUD_X" $((OUTPUT_HEIGHT - modal_height))

# "×" dismisses it: the entry goes, and its place passes clicks again
check "\"×\" on the modal" test -z "$(shell_ipc shelltest toastDismiss "$backup")"
# has_entry <id>: the server still holds that notification (its entry in the centre)
has_entry() {
    shell_ipc shelltest notificationState | python3 -I -c '
import json, sys
sys.exit(0 if any(n["id"] == int(sys.argv[1]) for n in json.load(sys.stdin)) else 1)' "$1"
}
check_within 3 "… the notification is dismissed (its entry gone)" not has_entry "$backup"
check_within 3 "… and off the screen" toast_rect_is "$backup" x ""
corner_y=$((OUTPUT_HEIGHT - modal_height / 2 - 30))
click_at $((HUD_X + 121)) $corner_y
check_within 3 "its place passes clicks to the window again" window_pressed_at $((HUD_X + 121)) $corner_y
check "no protocol errors" no_protocol_errors
