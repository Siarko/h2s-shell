# Another program's session lock (a second Quickshell, tests/lock/locker/shell.qml) in the
# bed's Hyprland. The shell sees it at the idle lock's deadline (hyprctl -j locked), and
# reads before any lock it asks (an IPC lock here): no lock is asked over it, its status is not "unlocked"
# but "foreign-locked", the `screen.locked` fact is true; when the other lock ends (read
# again after a pause of at most 1 s here, the test timing foreignPollMaximum), all of that
# returns, and the shell's own idle lock works again. Hyprland runs with
# misc:allow_session_lock_restore off (its default): with it on, a new lock takes the session
# over from the one in force instead of being refused.

stack_start --no-lock-restore --timings '{"foreignPollMaximum": 1000}' \
    --settings '{"lockscreen.screensaverEnabled": false, "lockscreen.lockscreenEnabled": true, "lockscreen.lockAfter": 6}'

LOCKER=$LOCKTEST_DIR/locker/shell.qml
locker_unlock() { echo unlock > "$WORK/locker.control"; log "locker: unlock asked"; }
screen_locked_fact() {
    shell_ipc profiles status | python3 -I -c 'import json, sys; print(str(json.load(sys.stdin)["facts"]["screen.locked"]).lower())'
}
fact_is() { [ "$(screen_locked_fact)" = "$1" ]; }
idle_asks() { shell_log_count "lockRequested.*idle"; }
idle_lock_safe() { compositor_locked && _password_stack_is_ours_and_safe; }

# ---- At the idle lock's deadline ----
echo lock > "$WORK/locker.control"
spawn "$WORK/locker.log" env QT_QPA_PLATFORM=wayland LOCKER_CONTROL="$WORK/locker.control" "$LOCKTEST_QS" -p "$LOCKER"
wait_until 15 grep -q "locker: locked" "$WORK/locker.log" || abort "the other locker did not lock (see locker.log)"
check "the other program holds the session lock" compositor_locked
check_within 12 "6 s idle: the shell reads it and says foreign-locked" shell_status_is foreign-locked
check "… the screen.locked fact is true" fact_is true
check "… said once" test "$(shell_log_count "another program holds the session lock")" = 1
check "… no idle lock asked of the compositor" test "$(idle_asks)" = 0
check "… no lock of its own" state_is phase unlocked
sleep 4 # fixed sleep: a negative claim: the idle lock is not asked again while the other lock lasts
check "still no idle lock asked" test "$(idle_asks)" = 0
check "… nor a refusal" test "$(shell_log_count "the compositor refused the lock")" = 0

# A lock asked over it (the IPC, as Super+L): read first, the compositor not asked
pid_before=$SHELL_PID
shell_ipc lockscreen lock > /dev/null
check_within 5 "an IPC lock over it: ended as another program's" state_is last_end foreign
check "… the compositor was not asked" test "$(shell_log_count "the compositor is not asked")" -ge 1
check "… the status still foreign-locked" shell_status_is foreign-locked
check "… the fact still true" fact_is true
check "… the shell survives (not ended by Hyprland)" test "$(_find_shell_pid)" = "$pid_before"

locker_unlock
check_within 5 "the other lock ends" compositor_unlocked
check_within 5 "the shell reads the end: unlocked again" shell_status_is unlocked
check "… the fact false again" fact_is false
check "… the end said" test "$(shell_log_count "the other program's session lock ended")" = 1

check_within 10 "idle again: the shell's own idle lock comes" compositor_locked
check_within "$GUARD" "… the shell's lock, ready for a password (test stack)" idle_lock_safe
check "… asked by idle" test "$(idle_asks)" -ge 1
wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked

# Not asking is what keeps the shell alive: Hyprland, the restore off, ends a client that asks
# for a lock while another stands (notes/plans/lockscreen.md, section 1). The refusal itself
# (elsewhere, and its read) is LockRulesTest's.
check "the shell was never restarted" test "$(grep -c "the shell exited" "$WORK/shell.log")" = 0
check "no protocol error" no_protocol_errors
