# An unlock that arrives right after the lock request, before the compositor can have sent
# `locked`: ext-session-lock-v1 makes unlock_and_destroy a protocol error then (Quickshell
# sends it whenever WlSessionLock.locked is set false before `locked`). The rules keep such
# an unlock PENDING and carry it out at the compositor's confirmation. The evidence that no
# protocol error happened: the shell is still connected (it answers, and locks again), and
# neither log reports one.

stack_start --logind

check_within "$GUARD" "the shell follows the test's logind session" state_is logind_session "$LOCKTEST_SESSION_PATH"
check_within "$GUARD" "the logind monitor (stand-in) runs" logind_monitor_running

no_protocol_error() {
    ! grep -aiq "protocol error\|invalid_unlock\|invalid_destroy" "$WORK/hyprland.log" \
        && ! grep -aiq "protocol error\|fatal error\|Wayland connection" "$WORK/shell.log"
}

# ---- logind's Lock and Unlock in one read: the Unlock is handled while locking ----
logind_signals lock unlock
check_within "$GUARD" "the lock ends" state_is phase unlocked
check "ended by logind's Unlock" state_is last_end logind
check "the unlock was held until the compositor confirmed the lock" \
    grep -aq "decided before the compositor confirmed the lock" "$WORK/shell.log"
check "… and carried out at the confirmation" grep -aq "carrying out the pending unlock (logind)" "$WORK/shell.log"
check_within "$GUARD" "the compositor is unlocked" compositor_unlocked
check "the shell still runs" kill -0 "$SHELL_PID"
check "no protocol error (compositor and shell logs)" no_protocol_error
lock_by_ipc
check_within "$GUARD" "the shell can lock again" compositor_locked
check_within "$GUARD" "… confirmed" state_is secure true
wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "… and the password unlocks it" compositor_unlocked

# ---- A lock request cancels a pending unlock: Lock, Unlock, Lock in one read ----
logind_signals lock unlock lock
check_within "$GUARD" "Lock, Unlock, Lock: locked" compositor_locked
check_within "$GUARD" "… confirmed, and the pending unlock dropped" state_is phase locked
check "the drop was logged" grep -aq "the pending unlock (logind) is dropped" "$WORK/shell.log"
wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "a fresh authentication unlocks it" compositor_unlocked
check "no protocol error" no_protocol_error

# ---- Escape twice, as fast as the test bed can send it after the lock request: no unlock ----
# (Escape ended a lock until 2026-11-15; an unlock decided while locking is logind's, above)
shell_ipc lockscreen lock > /dev/null
send_input "key Escape" "key Escape"
check_within "$GUARD" "Escape right after the lock request: locked" compositor_locked
check_within "$GUARD" "… confirmed, nothing pending" state_is phase locked
sleep 1 # fixed sleep: a negative claim: nothing unlocks it
check "… and stays locked" state_is phase locked
unlock_for_test
check "logind's Unlock then ends it" compositor_unlocked
check "the shell still runs" kill -0 "$SHELL_PID"
check "no protocol error" no_protocol_error
lock_by_ipc
check_within "$GUARD" "the shell can lock again" compositor_locked
check_within "$GUARD" "… confirmed" state_is secure true
