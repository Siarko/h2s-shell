# A HARD reload while locked (Quickshell.reload(true), through the test bed's seam): the new
# generation gets no old instances, so nothing can be carried over — the new WlSessionLock
# has a lock manager of its own, the old one is destroyed with its lock still in force, and
# Quickshell's process-wide manager keeps counting that lock as active: this process can
# never lock again (plan, section 1). What must happen anyway: the session stays locked,
# and the owner gets a prompt back. The new generation finds the marker, cannot take the
# lock (refused at once), quits with a failure, and the launcher starts a fresh shell that
# locks.

stack_start --reload-seam --hyprland-debug

lock_by_ipc
check_within 5 "locked" compositor_locked
check_within 5 "confirmed" state_is secure true

old_shell=$SHELL_PID
start_lock_watch hard
shell_ipc locktest reload true > /dev/null
check_within 20 "a fresh shell is started" wait_for_new_shell "$old_shell" 20
check_within 10 "the fresh shell locks (the marker)" state_is phase locked
check_within 5 "… confirmed" state_is secure true
sleep 1
stop_lock_watch
check "the compositor never reported unlocked" lock_watch_never_unlocked
log "what the old process said: $(grep -a -E 'cannot take the session lock back|quitting so that|not carried over|Reloading' "$WORK/shell.log" | sed 's/\x1b\[[0-9;]*m//g' | tr '\n' '|')"
log "how the old process ended: $(grep -a 'the shell exited' "$WORK/shell.log" | tail -n 1)"
check "the shell says locked" shell_status_is locked

wake_prompt || fail "the prompt did not wake"
check_within 5 "the methods are known" state_is armed true
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked
lock_by_ipc
check_within 5 "a later lock works" compositor_locked
press_key Escape
check_within 3 "(Escape wakes the prompt)" state_is prompt_awake true
press_key Escape
check_within 5 "… and unlocks" compositor_unlocked
log "Hyprland on the lock: $(sed 's/\x1b\[[0-9;]*m//g' "$WORK/hyprland.log" | grep -a -E 'SessionLock|sessionLock|lockscreen|Lock' | grep -v -i 'clock\|LED\|Mod index' | tr '\n' '|')"
