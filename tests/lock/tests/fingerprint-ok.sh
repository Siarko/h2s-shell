# The fingerprint stand-in: at the first lock, a finger the reader accepts unlocks with
# nothing typed. A fresh shell, since after one unlock today's shell no longer arms
# anything (see relock.sh).

stack_start --methods "password fingerprint"

lock_by_ipc
check_within 5 "lock by IPC locks the compositor" compositor_locked
check_within 5 "the compositor confirmed the lock" state_is secure true
check_within 5 "the fingerprint method is offered" state_is auth.fingerprint.available true
check_within 5 "a fingerprint conversation is waiting" state_is auth.fingerprint.waiting true

finger ok
check_within 10 "an accepted finger unlocks the compositor" compositor_unlocked
