# Adopted from the system-side review (review-fprintd-timeout.sh): pam_fprintd ends a round
# nobody touches after its `timeout` (30 s by default) with PAM_AUTHINFO_UNAVAIL, which
# Quickshell reports as Error. Counted as faults, five of them broke the fingerprint for the
# rest of the lock — after ~4.5 minutes of an untouched lock, until the next wake from
# sleep. A full-length round that ends in Error is a time-out with nobody trying: not
# counted, tried again at once (LockRules: _passiveTimedOut).
#
# Minutes in seconds: the shell's quickRound is 3 s and its errorRetry 1 s
# (H2S_LOCK_TEST_TIMINGS), the stand-in's rounds time out with an Error after 4 s
# (finger_timeout). Without the rule, the fifth such round breaks the method (~21 s).

stack_start --methods "password fingerprint" --timings '{"quickRound": 3000, "errorRetry": 1000, "retryMin": 500}'
finger_timeout 4

lock_by_ipc
check_within 5 "locked" compositor_locked
check_within 5 "a fingerprint conversation runs" _one_finger_waiter

timed_out() { lines_more_than "$1" 'an Error, as pam_fprintd' "$WORK/finger/log"; }
check_within 45 "six rounds in a row time out with an Error (more than errorLimit)" timed_out 5
check_within 5 "each ended in PAM's Error (the stack's error line ran)" lines_more_than 5 '^error ' "$WORK/finger/log"
check_within 5 "the shell got them as Errors" lines_more_than 5 '"method":"fingerprint","result":"error","type":"pamCompleted"' "$WORK/shell.log"
log "fingerprint: $(state_field fingerprint_status), $(grep -c 'an Error, as pam_fprintd' "$WORK/finger/log") rounds timed out"
check "the fingerprint is not broken by time-outs" test "$(state_field fingerprint_status)" != broken
check "it was never broken" test "$(grep -ac 'fingerprint cannot be used' "$WORK/shell.log")" = 0
check "no time-out was counted as a fault" test "$(grep -ac 'fingerprint: PAM error ([0-9]' "$WORK/shell.log")" = 0

# Somebody comes back and touches the reader: it still unlocks
finger_timeout 0
check_within 10 "a fingerprint conversation still waits" _one_finger_waiter
# The round now running may have started with the 4 s time-out: wait for one without it
sleep 4.5
check_within 10 "… a fresh one" _one_finger_waiter
finger ok
check_within 10 "a finger still unlocks after the time-outs" compositor_unlocked
check "unlocked by the fingerprint" state_is phase.lastEnd authenticated
