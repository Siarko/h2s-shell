# Five lock/unlock cycles in one shell instance, alternating the password and the
# fingerprint stand-in: each lock must arm afresh — new session, new conversations — and
# each unlock must leave nothing running (the "works once" family, plan section 1).

stack_start --methods "password fingerprint"

previous_session=0
for cycle in 1 2 3 4 5; do
    if [ $((cycle % 2)) = 1 ]; then way=password; else way=fingerprint; fi
    log "cycle $cycle: unlock by $way"
    lock_by_ipc
    check_within "$GUARD" "cycle $cycle: the compositor is locked" compositor_locked || break
    check_within "$GUARD" "cycle $cycle: the compositor confirmed the lock" state_is secure true
    check_within "$GUARD" "cycle $cycle: armed" state_is armed true
    session=$(state_field session)
    check "cycle $cycle: a new session ($session after $previous_session)" test "$session" -gt "$previous_session"
    previous_session=$session
    check_within "$GUARD" "cycle $cycle: one fingerprint conversation waits" _one_finger_waiter

    if [ "$way" = password ]; then
        wake_prompt || fail "cycle $cycle: the prompt did not wake"
        type_text "$LOCKTEST_PASSWORD"
        press_key Return
    else
        finger ok
    fi
    check_within 10 "cycle $cycle: $way unlocks the compositor" compositor_unlocked
    check_within "$GUARD" "cycle $cycle: the shell says unlocked" shell_status_is unlocked
    check "cycle $cycle: the lock ended authenticated" state_is last_end authenticated
    check_within "$GUARD" "cycle $cycle: the per-lock adapters are gone" state_is lock_scope false
    check_within "$GUARD" "cycle $cycle: no fingerprint conversation left" no_finger_waiters
    # Still locked: the failure is counted; the next cycle could prove nothing (the run
    # stops the stack, which ends the lock)
    compositor_locked && break
done
log "password checks: $(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)"
check "the three password unlocks each ran the test stack once, all right" \
    test "$(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)" = "right right right "
