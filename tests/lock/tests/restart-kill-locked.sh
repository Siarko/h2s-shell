# The shell is killed while locked (SIGKILL: what the OOM killer does, and what a crash
# Quickshell's handler does not catch amounts to). The compositor keeps the session locked
# (Hyprland, allow_session_lock_restore on, as the test bed runs it); the launcher, which
# supervises the shell, starts a new one; that one finds the lock marker and locks again at
# once. The compositor must report locked on every poll across the gap.
#
# Also what the dead shell left: its fingerprint conversation's PAM helper (a fork of the
# shell, blocked in pam_authenticate) survives a SIGKILL — with a real pam_fprintd it keeps
# the reader claimed. The launcher kills it (scripts/launch.sh, clean_up_after): the old
# conversation ends, and the new shell's is the only one waiting (`finger` fails on two).

stack_start --methods "password fingerprint"

lock_by_ipc
check_within 5 "locked" compositor_locked
check_within 5 "confirmed" state_is secure true
check "the marker says locked" state_is marker locked
check_within 5 "a fingerprint conversation runs" _one_finger_waiter
old_conversation=$(finger_waiters)
old_helper=$(awk '{ print $4 }' "/proc/$old_conversation/stat" 2> /dev/null)
log "the fingerprint conversation $old_conversation, its PAM helper $old_helper"
check "the conversation's PAM helper is a child of the shell" test "$(awk '{ print $4 }' "/proc/$old_helper/stat" 2> /dev/null)" = "$SHELL_PID"

old_shell=$SHELL_PID
start_lock_watch kill
signal_shell KILL
check_within 3 "the killed shell is gone" test ! -e "/proc/$old_shell"
check "the compositor stays locked with no client" compositor_locked
check_within 10 "the launcher starts a new shell" wait_for_new_shell "$old_shell" 10
check "the launcher said why" grep -aq "the shell exited (status 137) while the screen was locked: starting it again" "$WORK/shell.log"
check_within 3 "the dead shell's PAM helper is gone (killed by the launcher)" test ! -e "/proc/$old_helper"
check "the launcher said so" grep -aq "killing what the shell left behind: $old_helper " "$WORK/shell.log"
check_within 3 "its fingerprint conversation ended" test ! -e "/proc/$old_conversation"
check "… as an orphan" grep -q "orphaned $old_conversation" "$WORK/finger/log"
check_within 10 "the new shell locks again (the marker)" state_is phase locked
check "it was the marker" grep -aq "the shell was locked when it stopped (the lock marker says so): locking again" "$WORK/shell.log"
check "the new shell says locked" shell_status_is locked
check_within 5 "the compositor confirmed the new shell's lock" state_is secure true
sleep 1
stop_lock_watch
check "the compositor never reported unlocked across the restart" lock_watch_never_unlocked
check "exactly one shell process under the launcher" test "$(pgrep -P "$SUPERVISOR_PID" | wc -l)" = 1

# The new shell's prompt; its fingerprint conversation is the only one
check_within 8 "the new shell runs its fingerprint conversation" _one_finger_waiter
wake_prompt || fail "the new shell's prompt did not wake"
check_within 5 "the methods are known" state_is armed true
finger ok
check_within 10 "the finger unlocks the new shell's lock" compositor_unlocked
check "the marker says unlocked" state_is marker unlocked

# Later cycles: by password, then by finger
lock_by_ipc
check_within 5 "locks again" compositor_locked
wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked
lock_by_ipc
check_within 5 "and once more" compositor_locked
check_within 8 "a fingerprint conversation runs" _one_finger_waiter
finger ok
check_within 10 "unlocked" compositor_unlocked
check "no protocol error in either log" no_protocol_errors
