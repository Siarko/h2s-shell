# Locking on its own idle timer, with no screensaver: settings lock after 6 s idle (from
# the last input). It locks, unlocks by password, and locks again on the next idle — and
# activity before the time is up keeps it from locking.

stack_start --settings '{"lockscreen.screensaverEnabled": false, "lockscreen.lockscreenEnabled": true,
    "lockscreen.lockAfter": 6}'

idle_lock_safe() { compositor_locked && _password_stack_is_ours_and_safe; }

# Activity every second for 8 s: never 6 s idle
for second in 1 2 3 4 5 6 7 8; do
    move_pointer $((600 + second * 10)) 400
    sleep 1 # fixed sleep: activity once a second, never 6 s apart, is the subject
done
check "kept busy: not locked" compositor_unlocked
check "and no screensaver (it is off)" state_is screensaver false

check_timed 10 "6 s without input: locked" compositor_locked
check_within "$GUARD" "ready for a password (test stack)" idle_lock_safe
wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked

check_timed 10 "idle again: locked AGAIN" compositor_locked
check_within "$GUARD" "the second lock is ready for a password" idle_lock_safe
wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks the second idle lock" compositor_unlocked
check "locked by idle both times" test "$(grep -c 'lockRequested.*idle' "$WORK/shell.log")" -ge 2
