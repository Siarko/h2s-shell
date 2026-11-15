# The fingerprint stand-in: at the first lock, a finger the reader rejects leaves the
# screen locked, and the reader is asked again — so an accepted finger after it unlocks.

stack_start --methods "password fingerprint"

lock_by_ipc
check_within 5 "lock by IPC locks the compositor" compositor_locked
check_within 5 "the compositor confirmed the lock" state_is secure true
check_within 5 "a fingerprint conversation is waiting" state_is auth.fingerprint.waiting true
wait_until 5 _one_finger_waiter || abort "no single fingerprint conversation waiting (found: $(finger_waiters | tr '\n' ' '))"
first_conversation=$(finger_waiters)

finger fail
sleep 1
check "a rejected finger leaves the compositor locked" compositor_locked
check "a rejected finger leaves the shell locked" shell_status_is locked
# The method starts a new round after a short pause (500 ms, doubling for quick failures)
check_within 5 "a new conversation waits after the rejection" _one_finger_waiter
second_conversation=$(finger_waiters)
log "conversations: $first_conversation rejected, $second_conversation waiting"
# The stand-in's own log: the first conversation took "fail", and a conversation started
# after that, the one now waiting
started_after_rejection() {
    awk -v first="$first_conversation" -v second="$second_conversation" '
        $1 == "result" && $2 == first && $3 == "fail" { rejected = 1 }
        rejected && $1 == "start" && $2 == second && second != first { found = 1 }
        END { exit !found }' "$WORK/finger/log"
}
check "it is a new conversation, started after the rejection" started_after_rejection
check "still locked" compositor_locked

finger ok
check_within 10 "an accepted finger afterwards unlocks" compositor_unlocked
