# A crash Quickshell's handler catches (SIGSEGV) while a fingerprint conversation runs.
# The handler restarts the shell in the same process (execve, same pid): the conversation's
# PAM helper, a fork of the old image, is still a child of that pid, and the launcher saw no
# exit, so its clean-up does not run. With the real pam_fprintd at `timeout=-1` such a helper
# would keep the reader claimed for good. The restarted shell kills what its process left
# (Lockscreen: _helperSweep): the old conversation ends, the new shell's is the only one
# waiting (`finger` fails on two), and a finger unlocks.
#
# Then the launcher's side: that shell (relaunched in place) killed, the launcher kills its
# PAM helper (below). Core dumps are off for this test's processes (ulimit -c 0), as in
# restart-crash-locked.

ulimit -c 0
stack_start --methods "password fingerprint"

lock_by_ipc
check_within "$GUARD" "locked" compositor_locked
check_within "$GUARD" "confirmed" state_is secure true
check_within "$GUARD" "a fingerprint conversation runs" _one_finger_waiter
old_conversation=$(finger_waiters)
old_helper=$(awk '{ print $4 }' "/proc/$old_conversation/stat" 2> /dev/null)
log "the fingerprint conversation $old_conversation, its PAM helper $old_helper"
check "the conversation's PAM helper is a child of the shell" test "$(awk '{ print $4 }' "/proc/$old_helper/stat" 2> /dev/null)" = "$SHELL_PID"

# Quickshell restarts in place only a shell that ran for 10 s or more
started=$(stat -c %Y "/proc/$SHELL_PID")
until [ $(($(date +%s) - started)) -ge 12 ]; do sleep 0.5; done # fixed sleep: Quickshell restarts a crashed shell in place only after it ran 10 s: waited out
crashes_before=$(shell_log_count "Quickshell has been restarted")
failed_relaunches_before=$(shell_log_count 'Launching config: ""')
crashed_shell=$SHELL_PID
signal_shell SEGV
check_within 15 "Quickshell's handler restarts it" lines_more_than "$crashes_before" "Quickshell has been restarted" "$WORK/shell.log"
wait_until 20 relaunch_decided "$failed_relaunches_before"
if [ "$(shell_log_count 'Launching config: ""')" -gt "$failed_relaunches_before" ]; then
    # Quickshell 0.3.2's relaunch sometimes loses its config path (restart-crash-locked):
    # then the launcher starts a fresh shell, and its own clean-up kills the helper
    log "Quickshell's relaunch lost its config path: the launcher's restart takes over"
    check_within 15 "the launcher started a fresh shell" wait_for_new_shell "$crashed_shell" 15
    in_place=0
else
    check "in the same process" kill -0 "$SHELL_PID"
    in_place=1
fi
check_within 20 "the restarted shell answers" shell_ipc lockscreen status
# Killed, it stays a zombie of the restarted image (which never waits for it): dead all the
# same — its D-Bus connection, and so a real reader's claim, is gone
helper_dead() { [ ! -e "/proc/$old_helper" ] || [ "$(awk '{ print $3 }' "/proc/$old_helper/stat" 2> /dev/null)" = Z ]; }
check_within "$GUARD" "the old PAM helper is dead (gone, or a zombie)" helper_dead
if [ "$in_place" = 1 ]; then
    check "the restarted shell killed it" grep -aq "killed a PAM helper this process left before it was restarted in place: $old_helper" "$WORK/shell.log"
fi
check_within "$GUARD" "its fingerprint conversation ended" test ! -e "/proc/$old_conversation"
check "… as an orphan" grep -q "orphaned $old_conversation" "$WORK/finger/log"
check_within 10 "and locks again (the marker)" state_is phase locked
check_within "$GUARD" "confirmed" state_is secure true
check_within 10 "the new shell's fingerprint conversation is the only one" _one_finger_waiter
finger ok
check_within 10 "a finger unlocks" compositor_unlocked

# ---- The launcher's clean-up when a shell Quickshell relaunched in place dies ----
# The relaunched process carries __QUICKSHELL_CRASH_INFO_FD (and _DUMP_PID, _SIGNAL) in its
# exec-time environment, and so does every PAM helper it forks. The launcher took any
# `^__QUICKSHELL_CRASH` for Quickshell's crash reporter and spared it: the dead shell's
# fingerprint helper (timeout=-1) lived on. Only the reporter has __QUICKSHELL_CRASH_DUMP_FD.
relaunched_in_place() { grep -q '^__QUICKSHELL_CRASH_INFO_FD=' <<< "$(tr '\0' '\n' < "/proc/$SHELL_PID/environ" 2> /dev/null)"; }
if [ "$in_place" = 0 ]; then
    log "the relaunch was not in place: crashing once more, for a shell relaunched in place"
    started=$(stat -c %Y "/proc/$SHELL_PID")
    until [ $(($(date +%s) - started)) -ge 12 ]; do sleep 0.5; done # fixed sleep: Quickshell restarts a crashed shell in place only after it ran 10 s: waited out
    crashes_before=$(shell_log_count "Quickshell has been restarted")
    failed_relaunches_before=$(shell_log_count 'Launching config: ""')
    crashed_shell=$SHELL_PID
    signal_shell SEGV
    crash_handled() { lines_more_than "$crashes_before" "Quickshell has been restarted" "$WORK/shell.log" || ! kill -0 "$crashed_shell" 2> /dev/null; }
    wait_until 15 crash_handled && wait_until 20 relaunch_decided "$failed_relaunches_before"
    if [ "$(shell_log_count "Quickshell has been restarted")" -gt "$crashes_before" ] && kill -0 "$crashed_shell" 2> /dev/null \
        && [ "$(shell_log_count 'Launching config: ""')" = "$failed_relaunches_before" ]; then
        in_place=1
    else
        wait_for_new_shell "$crashed_shell" 20 || abort "no shell after the second crash"
    fi
    wait_until 20 shell_ipc lockscreen status || abort "the shell does not answer"
fi
if [ "$in_place" = 1 ]; then
    check "the shell was relaunched in place (its exec-time environment says so)" relaunched_in_place
    lock_by_ipc
    check_within "$GUARD" "the relaunched shell locks" compositor_locked
    check_within "$GUARD" "a fingerprint conversation runs" _one_finger_waiter
    conversation=$(finger_waiters)
    helper=$(awk '{ print $4 }' "/proc/$conversation/stat" 2> /dev/null)
    check "its PAM helper is the shell's child" test "$(awk '{ print $4 }' "/proc/$helper/stat" 2> /dev/null)" = "$SHELL_PID"
    check "the helper carries __QUICKSHELL_CRASH_* too (not the reporter's DUMP_FD)" \
        sh -c "tr '\\0' '\\n' < /proc/$helper/environ | grep -q '^__QUICKSHELL_CRASH_INFO_FD=' && ! tr '\\0' '\\n' < /proc/$helper/environ | grep -q '^__QUICKSHELL_CRASH_DUMP_FD='"
    old_shell=$SHELL_PID
    signal_shell KILL
    check_within 10 "the launcher starts a new shell" wait_for_new_shell "$old_shell" 10
    helper_gone() { [ ! -e "/proc/$helper" ] || [ "$(awk '{ print $3 }' "/proc/$helper/stat" 2> /dev/null)" = Z ]; }
    check_within "$GUARD" "the dead shell's PAM helper was killed by the launcher" helper_gone
    check "the launcher said so" grep -aq "killing what the shell left behind: $helper " "$WORK/shell.log"
    check_within 10 "the new shell locks" state_is phase locked
    check_within 10 "exactly one fingerprint conversation (the orphan's is over)" _one_finger_waiter
    finger ok
    check_within 10 "a finger unlocks" compositor_unlocked
else
    log "NOT exercised: Quickshell's relaunch was not in place twice in a row"
fi
