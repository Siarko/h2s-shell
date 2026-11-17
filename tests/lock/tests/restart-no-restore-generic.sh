# As restart-no-restore, but the shell cannot ask Hyprland about its lock (no
# HYPRLAND_INSTANCE_SIGNATURE: the generic path, any compositor). The restarted shell asks
# for the lock back; Hyprland refuses it and kills the shell (a protocol error on the refused
# lock). The launcher starts it again with a growing pause; after 5 restarts in 2 minutes it
# does NOT give up while the screen was locked (giving up would leave the owner at the
# compositor's dead-lock screen with no shell at all): it goes on trying, slowly. No hot
# loop, and the compositor stays locked throughout — never unlocked. The owner's way back is
# then a TTY (notes/plans/lockscreen.md, section 7, "Recovery"), or the setting switched on.
#
# The launcher's pauses are shortened (first 0.1 s, slow 1 s instead of 1 s and 60 s:
# H2S_LAUNCHER_TEST_TIMINGS); the schedule is the same.

stack_start --no-lock-restore --no-hyprland-ipc --launcher-timings "first=0.1 slow=1"

lock_by_ipc
check_within 5 "locked" compositor_locked
check_within 5 "confirmed" state_is secure true

start_lock_watch generic
supervisor=$SUPERVISOR_PID
signal_shell KILL
check_within 60 "after 5 quick restarts the launcher goes on slowly (the screen was locked)" \
    grep -aq "times in 2 minutes while the screen was locked: trying again every 1 s" "$WORK/shell.log"
slow_attempts() { grep -ac "starting it again in 1 s" "$WORK/shell.log"; }
attempts_before=$(slow_attempts)
more_slow_attempts() { [ "$(slow_attempts)" -ge $((attempts_before + 2)) ]; }
check_within 40 "… and keeps trying (two more slow attempts)" more_slow_attempts
check "the launcher did not give up" test "$(shell_log_count "not starting it again")" = 0
check "the launcher still runs" kill -0 "$supervisor"
stop_lock_watch
log "pauses: $(grep -ao 'starting it again in [0-9.]* s' "$WORK/shell.log" | awk '{ print $5 }' | tr '\n' ' ')"
log "how the restarted shells ended: $(sed 's/\x1b\[[0-9;]*m//g' "$WORK/shell.log" | grep -a -E 'wl_display|fatal error|the shell exited' | sed 's/^.*launcher[^:]*: //' | sort | uniq -c | tr '\n' '|')"
check "the quick pauses grew (0.1 0.2 0.4 0.8 1.6 s), then 1 s" \
    test "$(grep -ao 'starting it again in [0-9.]* s' "$WORK/shell.log" | awk '{ print $5 }' | head -n 6 | tr '\n' ' ')" = "0.1 0.2 0.4 0.8 1.6 1 "
check "each restarted shell asked for the lock back (the marker)" \
    test "$(shell_log_count '"type":"lockRequested","source":"restore"')" -ge 5
check "the compositor never reported unlocked" lock_watch_never_unlocked
check "the compositor is still locked" compositor_locked
check "the marker file still says locked" marker_file_is locked
