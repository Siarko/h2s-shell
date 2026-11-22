# A crash Quickshell's own handler catches (SIGSEGV), while locked. The handler restarts the
# shell in the same process (execve, same pid) — unless it crashed within 10 s of starting,
# then it exits (status 255). Either way: never two shells (the launcher waits on the
# process, which did not end in the first case), the compositor stays locked throughout,
# and the shell that comes back locks again (the marker) and unlocks by password.
#
# Core dumps are off for this test's processes (ulimit -c 0): the crash handler's forked
# child re-raises the signal, and the system's core handler would otherwise store a dump.

ulimit -c 0
stack_start

# Count the shells over the whole test: children of the launcher running Quickshell
shell_count_now() {
    local count=0 pid
    for pid in $(pgrep -P "$SUPERVISOR_PID" 2> /dev/null); do
        [ "$(readlink -f "/proc/$pid/exe" 2> /dev/null)" = "$(_quickshell_binary)" ] && count=$((count + 1))
    done
    echo "$count"
}
( while :; do shell_count_now >> "$WORK/shell-count"; sleep 0.1; done ) &
counter=$!

# ---- Crash after 10 s: restarted in place ----
lock_by_ipc
check_within "$GUARD" "locked" compositor_locked
check_within "$GUARD" "confirmed" state_is secure true
started=$(stat -c %Y "/proc/$SHELL_PID")
until [ $(($(date +%s) - started)) -ge 12 ]; do sleep 0.5; done # fixed sleep: Quickshell restarts a crashed shell in place only after it ran 10 s: waited out
crashes_before=$(shell_log_count "Quickshell has been restarted")
failed_relaunches_before=$(shell_log_count 'Launching config: ""')
crashed_shell=$SHELL_PID
start_lock_watch crash
signal_shell SEGV
check_within 15 "Quickshell's handler restarts it" lines_more_than "$crashes_before" "Quickshell has been restarted" "$WORK/shell.log"
# Quickshell 0.3.2's in-place relaunch sometimes comes back without its config path
# (`Launching config: ""`, "Could not open config file", exit 255): the relaunched process
# and the crash reporter it forked read the instance info through one shared file offset,
# and the one that reads second finds nothing (a Quickshell defect). Then the
# launcher starts a fresh shell. Either way: one shell, and it locks again
wait_until 20 relaunch_decided "$failed_relaunches_before"
if [ "$(shell_log_count 'Launching config: ""')" -gt "$failed_relaunches_before" ]; then
    log "Quickshell's relaunch lost its config path: the launcher's restart must take over"
    check_within 15 "the launcher started a fresh shell" wait_for_new_shell "$crashed_shell" 15
    check "the launcher saw the failed relaunch exit (255)" grep -aq "the shell exited (status 255) while the screen was locked" "$WORK/shell.log"
else
    check "in the same process" kill -0 "$SHELL_PID"
    check "the launcher did not start another" test "$(shell_count_now)" = 1
fi
check_within 20 "the restarted shell answers" shell_ipc lockscreen status
check_within 10 "and locks again (the marker)" state_is phase locked
check_within "$GUARD" "confirmed" state_is secure true
sleep 1 # fixed sleep: a negative claim: the lock watch sees no unlock after the restart either
stop_lock_watch
check "the compositor never reported unlocked across the crash" lock_watch_never_unlocked
wake_prompt || fail "the prompt did not wake"
check_within "$GUARD" "the methods are known" state_is armed true
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked

# ---- Crash within 10 s of starting: the handler gives up, the launcher restarts ----
lock_by_ipc
check_within "$GUARD" "locked again" compositor_locked
check_within "$GUARD" "confirmed" state_is secure true
old_shell=$SHELL_PID
start_lock_watch early-crash
# A process started just now (Quickshell's clock starts at exec, which the in-place restart
# above did long enough ago): killed, the launcher starts a fresh one, and that one crashes
# within its first 10 s
signal_shell KILL
wait_for_new_shell "$old_shell" 10 || fail "the launcher did not start a new shell"
check_within 10 "the new shell locks (the marker)" state_is phase locked
old_shell=$SHELL_PID
failed_relaunches_before=$(shell_log_count 'Launching config: ""')
exits_before=$(shell_log_count "the shell exited (status 255) while the screen was locked")
signal_shell SEGV
check_within 15 "a crash within 10 s of starting is not restarted in place: the launcher starts a new shell" \
    wait_for_new_shell "$old_shell" 15
# The same race as above can take Quickshell's own decision from it: reading no instance
# info, it misses the launch time and relaunches with an empty config path, which exits
# with 255 as well. What the shell relies on holds either way: the launcher starts the next
if [ "$(shell_log_count 'Launching config: ""')" -gt "$failed_relaunches_before" ]; then
    log "Quickshell's relaunch read no instance info (its config path empty): the launcher's restart took over"
else
    check "Quickshell said it would not restart" grep -aq "crashed within 10 seconds of launching. Not restarting" "$WORK/shell.log"
fi
check "the launcher saw it exit with 255" lines_more_than "$exits_before" "the shell exited (status 255) while the screen was locked" "$WORK/shell.log"
check_within 10 "the new shell locks (the marker)" state_is phase locked
check_within "$GUARD" "confirmed" state_is secure true
sleep 1 # fixed sleep: a negative claim: the lock watch sees no unlock after the restart either
stop_lock_watch
check "the compositor never reported unlocked across the early crash" lock_watch_never_unlocked
wake_prompt || fail "the prompt did not wake"
check_within "$GUARD" "the methods are known" state_is armed true
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked

kill "$counter" 2> /dev/null
wait "$counter" 2> /dev/null
log "shells under the launcher, over the test: $(sort "$WORK/shell-count" | uniq -c | tr '\n' ' ')"
check "never two shells at once" test -z "$(grep -v '^[01]$' "$WORK/shell-count")"
