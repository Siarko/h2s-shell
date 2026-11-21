# The idle path, end to end (it had no test; "the screensaver never shows again after the
# first lock" was the root-cause bug of the rework): the shell's settings say screensaver
# after 3 s idle, lock 3 s after the screensaver. Idle time is the compositor's
# (ext-idle-notify); the virtual keyboard and pointer are input like any other.
#
#   no input: the screensaver shows (its layer is mapped, the shell says so);
#   the pointer moves: it goes;
#   idle again: it shows, and 3 s later the screen locks;
#   unlocked by the password: idle again, the screensaver shows AGAIN and locks AGAIN.

stack_start --settings '{"lockscreen.screensaverEnabled": true, "lockscreen.screensaverTimeout": 3,
    "lockscreen.lockscreenEnabled": true, "lockscreen.lockscreenTimeout": 3}'

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
check_timed 8 "3 s without input: the screensaver shows" state_is screensaver true
check_within "$GUARD" "its layer is on the screen" screensaver_layer
check "not locked by it" compositor_unlocked

move_pointer 700 400
move_pointer 720 410
check_within "$GUARD" "the pointer moves: the screensaver goes" state_is screensaver false
check_within "$GUARD" "its layer is gone (after the fade out)" no_screensaver_layer

check_timed 8 "idle again: it shows again" state_is screensaver true
check_timed 8 "3 s later the screen locks" compositor_locked
check_within "$GUARD" "the lock is ready for a password (test stack)" idle_lock_safe
check "locked by idle" test "$(grep -c 'lockRequested.*idle' "$WORK/shell.log")" -ge 1

wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked
check_within "$GUARD" "the screensaver is not up after the unlock" state_is screensaver false

# After the first lock: both again (the regression)
check_timed 8 "idle after the unlock: the screensaver shows AGAIN" state_is screensaver true
check_within "$GUARD" "its layer is on the screen again" screensaver_layer
check_timed 8 "and the screen locks AGAIN" compositor_locked
check_within "$GUARD" "the second lock is ready for a password" idle_lock_safe
wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks the second idle lock" compositor_unlocked
