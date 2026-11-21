# As restart-no-restore, but the shell cannot ask Hyprland about its lock (no
# HYPRLAND_INSTANCE_SIGNATURE: the generic path, any compositor). The restarted shell asks
# for the lock back; Hyprland refuses it and kills the shell (a protocol error on the refused
# lock). The launcher starts it again with a growing pause, at most 3 times while the session
# stays locked (scripts/launch.sh, "Restarts while locked"); then it gives up and ends. No
# hot loop, and the compositor stays locked throughout — never unlocked. The owner's way
# back is then a TTY (notes/plans/lockscreen.md, section 7, "Recovery"): the setting
# switched on, and the launcher started again.
#
# The launcher's first pause is shortened (0.1 s instead of 1 s: H2S_LAUNCHER_TEST_TIMINGS);
# the schedule is the same.

stack_start --no-lock-restore --no-hyprland-ipc --launcher-timings "first=0.1"

lock_by_ipc
check_within 5 "locked" compositor_locked
check_within 5 "confirmed" state_is secure true

start_lock_watch generic
supervisor=$SUPERVISOR_PID
signal_shell KILL
check_within 30 "after 3 restarts while locked the launcher gives up" \
    grep -aq "after 3 restarts since the last unlock: not starting it again. The session stays locked." "$WORK/shell.log"
check_within 5 "… and ends" test ! -e "/proc/$supervisor"
stop_lock_watch
log "pauses: $(grep -ao 'starting it again in [0-9.]* s' "$WORK/shell.log" | awk '{ print $5 }' | tr '\n' ' ')"
log "how the restarted shells ended: $(sed 's/\x1b\[[0-9;]*m//g' "$WORK/shell.log" | grep -a -E 'wl_display|fatal error|the shell exited' | sed 's/^.*launcher[^:]*: //' | sort | uniq -c | tr '\n' '|')"
check "the pauses grew (0.1 0.2 0.4 s)" \
    test "$(grep -ao 'starting it again in [0-9.]* s' "$WORK/shell.log" | awk '{ print $5 }' | tr '\n' ' ')" = "0.1 0.2 0.4 "
check "each restarted shell asked for the lock back (the marker)" \
    test "$(shell_log_count '"type":"lockRequested","source":"restore"')" -ge 3
check "the compositor never reported unlocked" lock_watch_never_unlocked
check "the compositor is still locked" compositor_locked
check "the marker file still says locked" marker_file_is locked
