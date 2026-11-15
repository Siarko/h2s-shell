# The regression behind the rework (docs/plans/lockscreen.md §1): lock, unlock with the
# password, lock again, unlock with the password again. The second unlock must work as
# the first did.
#
# It failed before stage 2: Quickshell 0.3.2 never notifies WlSessionLock's unlock, and the
# old shell hung everything on that notify, so it never re-armed after the first unlock and
# dropped the second password before PAM saw it. The driver no longer reads that property
# through a binding (singletons/Lockscreen.qml). The checks after the first unlock say
# which part would break.

stack_start

for cycle in 1 2; do
    log "cycle $cycle"
    lock_by_ipc
    check_within 5 "cycle $cycle: lock by IPC locks the compositor" compositor_locked || break
    check_within 5 "cycle $cycle: the compositor confirmed the lock" state_is secure true
    check "cycle $cycle: shell says locked" shell_status_is locked
    check_within 5 "cycle $cycle: authentication is armed" state_is armed true

    wake_prompt || fail "cycle $cycle: the prompt did not wake"
    type_text "$LOCKTEST_PASSWORD"
    press_key Return
    check_within 10 "cycle $cycle: the password unlocks the compositor" compositor_unlocked
    screenshot "cycle-$cycle-after-password"
    describe_lock

    # The shell must know it is unlocked, or the next lock is not armed
    check_within 3 "cycle $cycle: shell says unlocked afterwards" shell_status_is unlocked
    check "cycle $cycle: the shell's lock mirror is false" state_is locked false

    # Still locked: the failure is counted; the next cycle could prove nothing (the run
    # stops the stack, which ends the lock)
    compositor_locked && break
done
