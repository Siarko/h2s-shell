# The shell is killed while UNLOCKED: the launcher starts it again, and the new shell comes
# up unlocked (the marker says "unlocked": no lock out of nowhere), and locks and unlocks as
# usual. A shell stopped on purpose while unlocked (SIGTERM, a clean quit) is not started
# again.

stack_start

lock_by_ipc
check_within 5 "locked" compositor_locked
unlock_for_test
check "unlocked" compositor_unlocked
check_within 3 "the marker says unlocked" state_is marker unlocked

old_shell=$SHELL_PID
signal_shell KILL
check_within 10 "the launcher starts a new shell" wait_for_new_shell "$old_shell" 10
check "the launcher said why" grep -aq "the shell exited (status 137): starting it again" "$WORK/shell.log"
sleep 2
check "the new shell is unlocked (compositor)" compositor_unlocked
check "the new shell is unlocked (shell)" shell_status_is unlocked
check "it did not lock" test "$(shell_log_count 'locking again')" = 0
check "no lock request was made" test "$(shell_log_count '"type":"lockRequested"')" = 1

lock_by_ipc
check_within 5 "the new shell locks" compositor_locked
check_within 5 "confirmed" state_is secure true
wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked

# Stopped on purpose while unlocked: not started again
# (once the marker says so: within 250 ms of an unlock it still says "locked", and a shell
# that stops then is started again and locks — fail closed, notes/plans/lockscreen.md, section 7)
check_within 3 "the marker says unlocked" marker_file_is unlocked
old_shell=$SHELL_PID
signal_shell TERM
check_within 5 "SIGTERM stops the shell" test ! -e "/proc/$old_shell"
sleep 3
check "the launcher did not start another" test -z "$(_find_shell_pid)"
check "it said the shell was stopped" grep -aq "the shell was stopped (status 143)" "$WORK/shell.log"
check_within 3 "and ended itself" test ! -e "/proc/$SUPERVISOR_PID"
