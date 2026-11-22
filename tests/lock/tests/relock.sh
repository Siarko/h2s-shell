# Lock, unlock with the password, lock again, unlock with the password again. The second
# unlock must work as the first did.
#
# Why it can fail: Quickshell 0.3.2 never notifies WlSessionLock's unlock; a driver that
# waits on that notify never re-arms after the first unlock and drops the second password
# before PAM sees it, so the driver does not read that property through a binding
# (singletons/Lockscreen.qml). The checks after the first unlock say which part would break.

stack_start

for cycle in 1 2; do
    log "cycle $cycle"
    lock_by_ipc
    check_within "$GUARD" "cycle $cycle: lock by IPC locks the compositor" compositor_locked || break
    check_within "$GUARD" "cycle $cycle: the compositor confirmed the lock" state_is secure true
    check "cycle $cycle: shell says locked" shell_status_is locked
    check_within "$GUARD" "cycle $cycle: authentication is armed" state_is armed true

    wake_prompt || fail "cycle $cycle: the prompt did not wake"
    type_text "$LOCKTEST_PASSWORD"
    press_key Return
    check_within 10 "cycle $cycle: the password unlocks the compositor" compositor_unlocked
    screenshot "cycle-$cycle-after-password"
    describe_lock

    # The shell must know it is unlocked, or the next lock is not armed
    check_within "$GUARD" "cycle $cycle: shell says unlocked afterwards" shell_status_is unlocked
    check "cycle $cycle: the shell's lock mirror is false" state_is locked false

    # Still locked: the failure is counted; the next cycle could prove nothing (the run
    # stops the stack, which ends the lock)
    compositor_locked && break
done
