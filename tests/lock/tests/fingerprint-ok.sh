# The fingerprint stand-in: at the first lock, a finger the reader accepts unlocks with
# nothing typed. (Later locks: fingerprint-relock.sh, cycles.sh.)

stack_start --methods "password fingerprint"

lock_by_ipc
check_within 5 "lock by IPC locks the compositor" compositor_locked
check_within 5 "the compositor confirmed the lock" state_is secure true
check_within 5 "the fingerprint method is offered" state_is fingerprint_available true
check_within 5 "a fingerprint conversation is waiting" state_is fingerprint_waiting true

finger ok
check_within 10 "an accepted finger unlocks the compositor" compositor_unlocked
