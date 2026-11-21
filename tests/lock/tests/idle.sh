# The idle path, end to end (it had no test; "the screensaver never shows again after the
# first lock" was the root-cause bug of the rework): the shell's settings say screensaver
# after 5 s idle (the idle monitors' base time, the shortest there is), lock after 8 s —
# both counted from the last input. Idle time is the compositor's (ext-idle-notify); the
# virtual keyboard and pointer are input like any other.
#
#   no input: the screensaver shows (its layer is mapped, the shell says so);
#   the pointer moves: it goes;
#   idle again: it shows, and 8 s after the last input the screen locks — not 8 s after
#   the screensaver;
#   unlocked by the password: idle again, the screensaver shows AGAIN and locks AGAIN.

stack_start --settings '{"lockscreen.screensaverEnabled": true, "lockscreen.screensaverTimeout": 5,
    "lockscreen.lockscreenEnabled": true, "lockscreen.lockAfter": 8}'

idle_field() { shell_ipc idle state | python3 -I -c 'import json, sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"; }
screensaver_layer() {
    hyprctl -j layers | python3 -I -c '
import json, sys
layers = json.load(sys.stdin)
found = any(surface.get("namespace") == "screensaver"
            for monitor in layers.values() for level in monitor["levels"].values() for surface in level)
sys.exit(0 if found else 1)'
}
no_screensaver_layer() { ! screensaver_layer; }
idle_lock_safe() { compositor_locked && _password_stack_is_ours_and_safe; }

check "not idle at start" state_is screensaver false
check_timed 10 "5 s without input: the screensaver shows" state_is screensaver true
check_within "$GUARD" "its layer is on the screen" screensaver_layer
check "not locked by it" compositor_unlocked

move_pointer 700 400
move_pointer 720 410
check_within "$GUARD" "the pointer moves: the screensaver goes" state_is screensaver false
check_within "$GUARD" "its layer is gone (after the fade out)" no_screensaver_layer

check_timed 10 "idle again: it shows again" state_is screensaver true
check_timed 8 "8 s after the last input the screen locks" compositor_locked
idle_at_lock=$(idle_field idleFor)
log "time since the last input when the lock came: ${idle_at_lock:-?} ms"
# Counted from the screensaver (5 s) it would be 13 s
check "the lock counted from the last input (8 s), not from the screensaver" \
    awk -v idle="${idle_at_lock:-99999}" 'BEGIN { exit !(idle >= 7500 && idle < 11000) }'
check_within "$GUARD" "the lock is ready for a password (test stack)" idle_lock_safe
check "locked by idle" test "$(grep -c 'lockRequested.*idle' "$WORK/shell.log")" -ge 1
wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked
check_within "$GUARD" "the screensaver is not up after the unlock" state_is screensaver false

# After the first lock: both again (the regression)
check_timed 10 "idle after the unlock: the screensaver shows AGAIN" state_is screensaver true
check_within "$GUARD" "its layer is on the screen again" screensaver_layer
check_timed 8 "and the screen locks AGAIN" compositor_locked
check_within "$GUARD" "the second lock is ready for a password" idle_lock_safe
wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks the second idle lock" compositor_unlocked
