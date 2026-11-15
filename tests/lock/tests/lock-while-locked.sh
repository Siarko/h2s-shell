# A lock request while locked changes nothing: no new session, the conversations under
# way keep going (the same fingerprint conversation, the same detection), the compositor
# stays locked — and the password still unlocks afterwards.

stack_start --methods "password fingerprint"

lock_by_ipc
check_within 5 "locked" compositor_locked
check_within 5 "the compositor confirmed the lock" state_is secure true
check_within 5 "a fingerprint conversation is waiting" state_is fingerprint_waiting true
wait_until 5 _one_finger_waiter || abort "no single fingerprint conversation waiting"
session=$(state_field session)
conversation=$(state_field fingerprint_conversation)
generation=$(state_field methods_generation)
waiter=$(finger_waiters)
log "session $session, fingerprint conversation $conversation (process $waiter), detection $generation"

check "the IPC's lock answers locked" test "$(shell_ipc lockscreen lock)" = locked
sleep 1
check "the same session" state_is session "$session"
check "the same fingerprint conversation" state_is fingerprint_conversation "$conversation"
check "the stand-in's same conversation still waits" test "$(finger_waiters)" = "$waiter"
check "no new detection" state_is methods_generation "$generation"
check "the shell logged the request as ignored" grep -aq 'ignored {"type":"lockRequested","source":"ipc"}: already locked' "$WORK/shell.log"
check "still locked (compositor)" compositor_locked
check "still confirmed" state_is secure true

wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password still unlocks" compositor_unlocked
