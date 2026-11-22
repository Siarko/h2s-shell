# pam_fprintd ends a round
# nobody touches after its `timeout` (30 s by default) with PAM_AUTHINFO_UNAVAIL, which
# Quickshell reports as Error. Counted as faults, five of them broke the fingerprint for the
# rest of the lock — after ~4.5 minutes of an untouched lock, until the next wake from
# sleep. A full-length round that ends in Error is a time-out with nobody trying: not
# counted, tried again at once (LockRules: _passiveTimedOut).
#
# Minutes in seconds: the shell's quickRound is 0.8 s and its errorRetry 0.5 s
# (H2S_LOCK_TEST_TIMINGS), the stand-in's rounds time out with an Error after 1.5 s
# (finger_timeout) — longer than quickRound however late the shell's clock starts, since
# it starts before the stand-in's. Without the rule, the fifth such round breaks the
# method.

stack_start --methods "password fingerprint" --timings '{"quickRound": 800, "errorRetry": 500, "retryMin": 200}'
finger_timeout 1.5

lock_by_ipc
check_within "$GUARD" "locked" compositor_locked
check_within "$GUARD" "a fingerprint conversation runs" _one_finger_waiter

timed_out() { lines_more_than "$1" 'an Error, as pam_fprintd' "$WORK/finger/log"; }
check_within 45 "six rounds in a row time out with an Error (more than errorLimit)" timed_out 5
check_within "$GUARD" "each ended in PAM's Error (the stack's error line ran)" lines_more_than 5 '^error ' "$WORK/finger/log"
check_within "$GUARD" "the shell got them as Errors" lines_more_than 5 '"method":"fingerprint","result":"error","type":"pamCompleted"' "$WORK/shell.log"
log "fingerprint: $(state_field fingerprint_status), $(grep -c 'an Error, as pam_fprintd' "$WORK/finger/log") rounds timed out"
check "the fingerprint is not broken by time-outs" test "$(state_field fingerprint_status)" != broken
check "it was never broken" test "$(grep -ac 'fingerprint cannot be used' "$WORK/shell.log")" = 0
check "no time-out was counted as a fault" test "$(grep -ac 'fingerprint: PAM error ([0-9]' "$WORK/shell.log")" = 0

# Somebody comes back and touches the reader: it still unlocks
finger_timeout 0
# The round now running may have started with the time-out: wait for one started after it
# went (a round reads it after its "start" line)
rounds_before=$(grep -c '^start ' "$WORK/finger/log")
fresh_round() { lines_more_than "$rounds_before" '^start ' "$WORK/finger/log" && _one_finger_waiter; }
check_within 10 "a fresh fingerprint conversation waits, without the time-out" fresh_round
finger ok
check_within 10 "a finger still unlocks after the time-outs" compositor_unlocked
check "unlocked by the fingerprint" state_is phase.lastEnd authenticated
