# The shell dies while locked and cannot start again (here: its shell.qml broken in the
# run's copy — as a bad edit, a missing library). The launcher's restarts all fail; each
# counts towards its limit while locked (scripts/launch.sh, "Restarts while locked"): after
# 3 it gives up and ends, and the compositor keeps the session locked — it never showed
# unlocked. Once the shell can start again (the file mended), the owner starts the launcher
# by hand: the shell comes up LOCKED (the marker). Unlocked, the launcher gives up on a
# shell that cannot start after 5 restarts in 2 minutes, as before.
#
# The launcher's first pause is shortened (H2S_LAUNCHER_TEST_TIMINGS: 0.1 s).

stack_start --launcher-timings "first=0.1"

shell_qml=$LOCKTEST_SHELL/shell.qml
cp "$shell_qml" "$WORK/shell.qml.good"
break_shell() { echo "this is not QML {" > "$shell_qml"; log "shell.qml broken in the run's copy"; }
mend_shell() { cp "$WORK/shell.qml.good" "$shell_qml"; log "shell.qml mended"; }

lock_by_ipc
check_within "$GUARD" "locked" compositor_locked
check_within "$GUARD" "confirmed" state_is secure true
check "file watching is off while locked (breaking the file reloads nothing)" state_is watch_files false

start_lock_watch retry
supervisor=$SUPERVISOR_PID
break_shell
old_shell=$SHELL_PID
signal_shell KILL
check_within 30 "after 3 failed restarts while locked, the launcher gives up" \
    grep -aq "after 3 restarts since the last unlock: not starting it again. The session stays locked." "$WORK/shell.log"
check_within "$GUARD" "… and ends" test ! -e "/proc/$supervisor"
check "each failed start counted" test "$(shell_log_count "while locked)")" = 3
check "the compositor is still locked" compositor_locked
check "the marker still says locked" marker_file_is locked
stop_lock_watch
check "the compositor never reported unlocked" lock_watch_never_unlocked
cp "$WORK/shell.log" "$WORK/shell-first-launcher.log"

mend_shell
start_lock_watch by-hand
start_launcher
log "a launcher started by hand: pid $SUPERVISOR_PID, its shell $SHELL_PID"
supervisor=$SUPERVISOR_PID
check_within 10 "it comes up locked (the marker)" state_is phase locked
check_within "$GUARD" "confirmed" state_is secure true
sleep 1 # fixed sleep: a negative claim: the lock watch sees no unlock after the restart either
stop_lock_watch
check "the compositor never reported unlocked" lock_watch_never_unlocked
wake_prompt || fail "the prompt did not wake"
check_within "$GUARD" "the methods are known" state_is armed true
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked
check_within "$GUARD" "the marker says unlocked" marker_file_is unlocked

# Unlocked: a shell that cannot start is given up
break_shell
old_shell=$SHELL_PID
signal_shell KILL
check_within 20 "unlocked, the launcher gives up on a shell that cannot start" \
    grep -aq "times in 2 minutes: not starting it again" "$WORK/shell.log"
check_within "$GUARD" "and ends" test ! -e "/proc/$supervisor"
mend_shell
