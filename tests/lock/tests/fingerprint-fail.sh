# The fingerprint stand-in: at the first lock, a finger the reader rejects leaves the
# screen locked, and the reader is asked again — so an accepted finger after it unlocks.

stack_start --methods "password fingerprint"

lock_by_ipc
check_within 5 "lock by IPC locks the compositor" compositor_locked
check_within 5 "the compositor confirmed the lock" state_is secure true
check_within 5 "a fingerprint conversation is waiting" state_is auth.fingerprint.waiting true
first_conversation=$(finger_waiters)

finger fail
sleep 1
check "a rejected finger leaves the compositor locked" compositor_locked
check "a rejected finger leaves the shell locked" shell_status_is locked
# The method starts a new round after a short pause (500 ms, doubling for quick failures)
check_within 5 "a new conversation waits after the rejection" _one_finger_waiter
check "it is a new conversation" test "$(finger_waiters)" != "$first_conversation"
check "still locked" compositor_locked

finger ok
check_within 10 "an accepted finger afterwards unlocks" compositor_unlocked
