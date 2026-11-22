# logind's idle block and the idle lock (lock after 6 s idle, no screensaver): Idle reads
# logind's inhibitors from the gdbus stand-in when the lock is due. A read that never
# answers (logind/hang) is ended by the reader's watchdog (1 s here, the test timing
# logindIdleWatchdog; 7 s otherwise) and counts as unknown: the lock still comes. An app's
# idle block (mpv) holds the lock while unlocked.

mkdir -p "$WORK/logind"
touch "$WORK/logind/hang"
stack_start --logind --timings '{"logindIdleWatchdog": 1000}' \
    --settings '{"lockscreen.screensaverEnabled": false, "lockscreen.lockscreenEnabled": true, "lockscreen.lockAfter": 6}'

idle_lock_safe() { compositor_locked && _password_stack_is_ours_and_safe; }
read_at_least_once() { grep -q '^call ListInhibitors' "$WORK/logind/log"; }

check_timed 12 "logind does not answer: the idle lock comes all the same" compositor_locked
check "… logind was asked" read_at_least_once
check "… the unanswered read logged as unreadable" test "$(shell_log_count "could not read logind's idle inhibitors")" -ge 1
check_within "$GUARD" "ready for a password (test stack)" idle_lock_safe
wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked

# An app holds logind's idle block: the lock waits
rm -f "$WORK/logind/hang"
echo "([('idle', 'mpv', 'Playing', 'block', uint32 $(id -u), uint32 4242)],)" > "$WORK/logind/inhibitors"
move_pointer 640 400
held_logged() { [ "$(shell_log_count "logind: an app keeps the screen on: mpv (Playing)")" -ge 1 ]; }
check_within 12 "an idle block of this user's: read as held" held_logged
stays_unlocked() { ! wait_until 6 compositor_locked; }
check "… no idle lock while it holds" stays_unlocked
