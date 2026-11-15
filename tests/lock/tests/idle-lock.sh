# Locking on its own idle timer, with no screensaver: settings lock after 3 s idle. It
# locks, unlocks by password, and locks again on the next idle — and activity before the
# time is up keeps it from locking.

stack_start --settings '{"lockscreen.screensaverEnabled": false, "lockscreen.lockscreenEnabled": true,
    "lockscreen.lockscreenTimeout": 3}'

idle_lock_safe() { compositor_locked && _password_stack_is_ours_and_safe; }

# Activity every second for 5 s: never 3 s idle
for second in 1 2 3 4 5; do
    move_pointer $((600 + second * 10)) 400
    sleep 1
done
check "kept busy: not locked" compositor_unlocked
check "and no screensaver (it is off)" state_is screensaver false

check_within 8 "3 s without input: locked" compositor_locked
check_within 5 "ready for a password (test stack)" idle_lock_safe
wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked

check_within 8 "idle again: locked AGAIN" compositor_locked
check_within 5 "the second lock is ready for a password" idle_lock_safe
wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks the second idle lock" compositor_unlocked
check "locked by idle both times" test "$(grep -c 'lockRequested.*idle' "$WORK/shell.log")" -ge 2
