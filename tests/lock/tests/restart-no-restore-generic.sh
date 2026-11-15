# As restart-no-restore, but the shell cannot ask Hyprland about its lock (no
# HYPRLAND_INSTANCE_SIGNATURE: the generic path, any compositor). The restarted shell asks
# for the lock back; Hyprland refuses it and kills the shell (a protocol error on the refused
# lock). The launcher starts it again with a growing pause, and gives up after 5 restarts in
# 2 minutes: no hot loop, and the compositor stays locked throughout — never unlocked. The
# owner's way back is then a TTY (docs/plans/lockscreen.md, section 7, "Recovery").

stack_start --no-lock-restore --no-hyprland-ipc

lock_by_ipc
check_within 5 "locked" compositor_locked
check_within 5 "confirmed" state_is secure true

start_lock_watch generic
supervisor=$SUPERVISOR_PID
signal_shell KILL
check_within 90 "the launcher gives up" grep -aq "times in 2 minutes: not starting it again" "$WORK/shell.log"
check_within 5 "and ends" test ! -e "/proc/$supervisor"
stop_lock_watch
restarts=$(shell_log_count "starting it again in")
log "restarts: $restarts; pauses: $(grep -ao 'starting it again in [0-9]* s' "$WORK/shell.log" | awk '{ print $5 }' | tr '\n' ' ')"
log "how the restarted shells ended: $(sed 's/\x1b\[[0-9;]*m//g' "$WORK/shell.log" | grep -a -E 'wl_display|fatal error|the shell exited' | sort | uniq -c | tr '\n' '|')"
check "at most 5 restarts" test "$restarts" -le 5
check "each restarted shell asked for the lock back (the marker)" \
    test "$(shell_log_count '"type":"lockRequested","source":"restore"')" -ge "$restarts"
check "the pauses grew (1 2 4 8 16 s)" test "$(grep -ao 'starting it again in [0-9]* s' "$WORK/shell.log" | awk '{ print $5 }' | tr '\n' ' ')" = "1 2 4 8 16 "
check "the compositor never reported unlocked" lock_watch_never_unlocked
check "the compositor is still locked" compositor_locked
check "the marker file still says locked" marker_file_is locked
