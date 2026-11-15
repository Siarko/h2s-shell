# Notifications on the lock screen show the app only by default — not the title, not the
# text (a one-time code in a message is not for whoever stands at the locked screen). The
# shell gets a private session bus here, so its notification server registers and a
# notification can be sent to it. One notification, with a title and a text, is shown by
# the screensaver (whose default is still "in full") and then by the lock screen: the lock
# screen's card is a single line, clearly shorter than the screensaver's. (What each
# detail shows, line by line, is checked in the unit suite: tests/LockViewTest.qml.)

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

check_within 8 "the screensaver shows" state_is screensaver true
sleep 1.2 # its fade in (800 ms by default)
screenshot_ppm screensaver
on_screensaver=$(card_height screensaver 30)
log "the notification's card on the screensaver (in full): $on_screensaver px"
check "the screensaver shows the card" test "$on_screensaver" -gt 0

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
