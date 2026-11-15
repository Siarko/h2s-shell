# The shell dies while locked and cannot start again (here: its shell.qml broken in the
# run's copy — as a bad edit, a missing library). The launcher's quick restarts all fail;
# while the screen was locked it must not give up (the owner would be left at the
# compositor's dead-lock screen with no shell at all): it goes on trying every minute (2 s
# here), and logs each attempt. Once the shell can start again (the file mended), the next
# attempt comes up LOCKED, and the compositor never showed unlocked. Unlocked, the launcher
# gives up as before: a shell that cannot start is not started forever.
#
# The launcher's pauses are shortened (H2S_LAUNCHER_TEST_TIMINGS: first 0.1 s, slow 2 s).

stack_start --launcher-timings "first=0.1 slow=2"

shell_qml=$LOCKTEST_SHELL/shell.qml
cp "$shell_qml" "$WORK/shell.qml.good"
break_shell() { echo "this is not QML {" > "$shell_qml"; log "shell.qml broken in the run's copy"; }
mend_shell() { cp "$WORK/shell.qml.good" "$shell_qml"; log "shell.qml mended"; }

lock_by_ipc
check_within 5 "locked" compositor_locked
check_within 5 "confirmed" state_is secure true
check "file watching is off while locked (breaking the file reloads nothing)" state_is watch_files false

start_lock_watch retry
supervisor=$SUPERVISOR_PID
break_shell
old_shell=$SHELL_PID
signal_shell KILL
check_within 20 "after the quick restarts failed, the launcher goes on slowly" \
    grep -aq "while the screen was locked: trying again every 2 s" "$WORK/shell.log"
slow_attempts() { grep -ac "while the screen was locked: starting it again in 2 s" "$WORK/shell.log"; }
attempts_before=$(slow_attempts)
more_slow_attempts() { [ "$(slow_attempts)" -ge $((attempts_before + 2)) ]; }
check_within 15 "… each attempt logged, two more of them" more_slow_attempts
check "the launcher is still there" kill -0 "$supervisor"
check "it did not give up" test "$(shell_log_count "not starting it again")" = 0
check "the compositor is still locked" compositor_locked
check "the marker still says locked" marker_file_is locked

mend_shell
# A shell whose IPC answers (the broken attempts never get that far)
shell_up() { local pid; pid=$(_find_shell_pid) || return 1; SHELL_PID=$pid; shell_ipc lockscreen status > /dev/null 2>&1; }
check_within 15 "the next attempt starts a shell that stays" shell_up
_track_shell_group
check_within 10 "it comes up locked (the marker)" state_is phase locked
check_within 5 "confirmed" state_is secure true
sleep 1
stop_lock_watch
check "the compositor never reported unlocked" lock_watch_never_unlocked
wake_prompt || fail "the prompt did not wake"
check_within 5 "the methods are known" state_is armed true
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked
check_within 3 "the marker says unlocked" marker_file_is unlocked

# Unlocked: a shell that cannot start is given up
break_shell
old_shell=$SHELL_PID
signal_shell KILL
check_within 20 "unlocked, the launcher gives up on a shell that cannot start" \
    grep -aq "times in 2 minutes: not starting it again" "$WORK/shell.log"
check_within 3 "and ends" test ! -e "/proc/$supervisor"
mend_shell
