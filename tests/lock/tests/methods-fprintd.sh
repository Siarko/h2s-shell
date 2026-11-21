# The shell with its REAL methods script (the run's copy), which asks a stand-in fprintd
# over a stand-in gdbus (stack_start --fprintd): what the script answers is what the lock
# does.
#
# 1. A finger enrolled: the fingerprint is offered, its conversation runs, a finger unlocks.
# 2. No finger enrolled: not offered, and that is an answer (not a failure: no re-asking).
# 3. fprintd hangs: the script gives up within the shell's detection time and exits
#    non-zero; the shell logs why, goes on with the password fallback, and — the last
#    detection having failed — asks again when somebody comes back to the prompt after the
#    `redetect` time (30 s; 3 s here, by the test's timings); fprintd answering by then,
#    the fingerprint is offered.

stack_start --fprintd enrolled --timings '{"redetect": 3000}'

lock_by_ipc --any-safe-config
check_within "$GUARD" "locked" compositor_locked
check_within "$GUARD" "the methods are known" state_is methods_status known
check "the script answered (no failure)" state_is methods.lastResult answered
check "the password config is the (test's) system-wide one" \
    state_is password_config "$WORK/system-pam/h2s-shell-password"
check "fingerprint offered, with the (test's) system-wide config" state_is fingerprint_available true
check "fprintd was asked for the caller, not a named user" grep -q "call ListEnrolledFingers user='' " "$WORK/fprintd/log"
check_within "$GUARD" "the fingerprint conversation runs" _one_finger_waiter
finger ok
check_within 10 "a finger unlocks" compositor_unlocked

# 2. No finger enrolled
fprintd_mode none
lock_by_ipc --any-safe-config
check_within "$GUARD" "locked again" compositor_locked
check_within "$GUARD" "the methods are known" state_is methods_status known
check "no finger: an answer, not a failure" state_is methods.lastResult answered
check "no finger: fingerprint not offered" state_is fingerprint_available false
check "no fingerprint conversation" no_finger_waiters
generation=$(state_field methods_generation)
wake_prompt || fail "the prompt did not wake"
sleep 1 # fixed sleep: a negative claim: the wake does not ask again
check "a clean 'not here' is not asked again at the prompt's wake" state_is methods_generation "$generation"
unlock_for_test
check "out by logind's Unlock (the stand-in)" compositor_unlocked

# 3. fprintd hangs
# (nothing is typed in this part, so the lock need not wait for a safe password config)
fprintd_mode hang
shell_ipc lockscreen lock > /dev/null
check_within "$GUARD" "locked a third time" compositor_locked
check "the methods are being asked" state_is methods_status detecting
# (The shell asked by now: its pause counts from a moment before this one)
asked_by_ms=$(( ${EPOCHREALTIME//[.,]/} / 1000 ))
check_within "$GUARD" "after the script gives up, the methods are known" state_is methods_status known
check "it was a failure" state_is methods.lastResult failed
check "the failure was the script's exit status, not the shell's time-out" \
    grep -aq "detecting the methods failed (the script exited with status 1)" "$WORK/shell.log"
check "the shell logged why, in the script's words" \
    grep -aq "methods script: lock-auth-methods: cannot tell whether a finger is enrolled: fprintd GetDevices: timeout" "$WORK/shell.log"
check "the password uses the fallback (the test's stand-in system-wide config)" \
    state_is password_config "$WORK/system-pam/h2s-shell-password"
check "fingerprint not offered meanwhile" state_is fingerprint_available false
no_stuck_call() { ! test_pgrep -f "$(sed -n 's/^    hang) exec \(.*\) ;;$/\1/p' "$WORK/standins/gdbus-fprintd")" > /dev/null; }
check "the stuck fprintd call did not linger" no_stuck_call

fprintd_mode enrolled
generation=$(state_field methods_generation)
redetect_due() { [ $(( ${EPOCHREALTIME//[.,]/} / 1000 )) -ge $((asked_by_ms + 3000)) ]; }
wait_until "$GUARD" redetect_due
log "the re-detection pause (3 s) is over"
wake_prompt || fail "the prompt did not wake"
generation_changed() { [ "$(state_field methods_generation)" != "$generation" ]; }
check_within "$GUARD" "coming back to the prompt asks again" generation_changed
check_within "$GUARD" "fprintd answering now, the fingerprint is offered" state_is fingerprint_available true
check "that answer was a clean one" state_is methods.lastResult answered
check_within "$GUARD" "the fingerprint conversation runs" _one_finger_waiter
finger ok
check_within 10 "a finger unlocks" compositor_unlocked
