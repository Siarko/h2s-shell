# The lock screen's screen-off without power control (the shell started without Hyprland's
# instance: no backend can cut a monitor's power): after its time the lock surface goes plain
# black instead — its notifications gone — and input brings the lock screen back. The
# output itself stays on.

stack_start --no-hyprland-ipc --session-bus --settings '{"lockscreen.lockedScreenOffTimeout": 5}'

check_within 10 "the shell's notification server is on the private bus" notification_server_up
notify "Messages" "Alice" "See you at five."

# card_rows: rows of the notification column (the right 360 px, below the top margin)
# lighter than the black scrim all across, in a fresh screenshot
card_rows() {
    screenshot_ppm lock > /dev/null
    python3 -I -c "$_PPM_READER"'
width, height, pixels = read_ppm(sys.argv[1])
rows = 0
for y in range(6, min(height, 320)):
    row = y * width * 3
    lit = sum(1 for x in range(width - 16 - 360, width - 16)
              if max(pixels[row + x * 3], pixels[row + x * 3 + 1], pixels[row + x * 3 + 2]) > 12)
    if lit >= 340:
        rows += 1
print(rows)' "$WORK/lock.ppm"
}
card_shown() { [ "$(card_rows)" -gt 0 ]; }
card_gone() { [ "$(card_rows)" = 0 ]; }

# idle_is <section> <field> <value>: the shell's `idle state` says so
idle_is() {
    [ "$(shell_ipc idle state | python3 -I -c 'import json, sys; print(json.dumps(json.load(sys.stdin)[sys.argv[1]][sys.argv[2]]))' "$1" "$2")" = "$3" ]
}
lock_black_is() { idle_is state lockBlack "$1"; }

check_within "$GUARD" "no power control here" idle_is config canPowerOff false
lock_by_ipc
check_within "$GUARD" "locked" compositor_locked
check "the lock screen not black at first" lock_black_is false
check_within "$GUARD" "… its notification shows" card_shown
check_timed 10 "5 s without input at the lock screen: the lock surface goes black" lock_black_is true
check_within "$GUARD" "… the notification is gone from it" card_gone
move_pointer 700 400
move_pointer 720 410
check_within "$GUARD" "input: the lock screen shows again" lock_black_is false
check_within "$GUARD" "… the notification with it" card_shown
check "… still locked" compositor_locked
