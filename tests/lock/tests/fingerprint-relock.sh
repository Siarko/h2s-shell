# The fingerprint stand-in unlocks on the second and the third lock too — the old shell
# never started the reader again after its first unlock (plan, section 1).

stack_start --methods "password fingerprint"

# The first lock, out by password, so that the fingerprint's later locks follow an unlock
# that it did not do itself
lock_by_ipc
check_within "$GUARD" "lock 1: locked" compositor_locked
wake_prompt || fail "lock 1: the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "lock 1: the password unlocks" compositor_unlocked

for lock in 2 3; do
    lock_by_ipc
    check_within "$GUARD" "lock $lock: locked" compositor_locked || break
    check_within "$GUARD" "lock $lock: a fingerprint conversation is waiting" state_is fingerprint_waiting true
    check_within "$GUARD" "lock $lock: exactly one conversation of the stand-in waits" _one_finger_waiter
    finger ok
    check_within 10 "lock $lock: the finger unlocks" compositor_unlocked
    check "lock $lock: by the fingerprint" grep -aq "unlocked (authenticated, fingerprint), session $(state_field session)" "$WORK/shell.log"
done
