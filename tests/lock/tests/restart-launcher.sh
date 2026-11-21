# The launcher's own restart (`h2s-shell --restart`, what the settings' "Restart to apply"
# runs) while locked: the running shell is stopped on purpose — its supervisor told to let it
# go, then `qs kill` — and a new, supervised one is started detached. The compositor keeps
# the session locked across the gap, and the new shell finds the marker and locks again.
#
# --restart stops every h2s-shell that `qs list --all` finds. Quickshell looks for instances
# under $XDG_RUNTIME_DIR/quickshell (src/core/paths.cpp, baseRunDir; /run/user/<uid> only
# when XDG_RUNTIME_DIR is unset): here that is the test's private runtime dir. That is
# checked before --restart is run — the runtime dir is the private one, and every instance
# `qs list --all` lists there is a process of this run — or nothing is run.

stack_start

[ "$XDG_RUNTIME_DIR" = "$RUN" ] && [ -n "$RUN" ] || abort "not in the private runtime dir: not running --restart"
listed=$("$LOCKTEST_QS" list --all 2> /dev/null | awk '/^ *Process ID:/ { print $3 }')
log "qs list --all, in the private runtime dir: ${listed:-nothing}"
[ -n "$listed" ] || abort "qs list --all lists nothing: the test cannot tell what --restart would stop"
for pid in $listed; do
    [ "$pid" = "$SHELL_PID" ] && [ "$(process_env "$pid" LOCKTEST_RUN_ID)" = "$LOCKTEST_RUN_ID" ] \
        || abort "qs list --all lists $pid, which is not the shell under test: not running --restart"
done
pass "--restart can see only the shell under test"

lock_by_ipc
check_within "$GUARD" "locked" compositor_locked
check_within "$GUARD" "confirmed" state_is secure true

# The launcher, run as the shell was started (the supervisor's environment, as it began)
old_shell=$SHELL_PID
old_supervisor=$SUPERVISOR_PID
supervisor_environment "$old_supervisor"
start_lock_watch restart
spawn "$WORK/restart.log" env --default-signal=HUP -i "${environment[@]}" "$LOCKTEST_LAUNCHER" --restart
check_within 15 "the old shell is stopped" test ! -e "/proc/$old_shell"
check_within "$GUARD" "its supervisor let it go and ended" test ! -e "/proc/$old_supervisor"
check "it was not started again by the old supervisor" test "$(grep -ac 'starting it again' "$WORK/shell.log")" = 0

# The new supervisor: detached (a session of its own), running this copy's launcher
new_supervisor_of_run() {
    local pid
    for pid in $(run_processes); do
        [ "$pid" = "$old_supervisor" ] && continue
        tr '\0' ' ' < "/proc/$pid/cmdline" 2> /dev/null | grep -q "$LOCKTEST_SHELL/scripts/launch\.sh" || continue
        [ "$(awk '{ print $6 }' "/proc/$pid/stat" 2> /dev/null)" = "$pid" ] || continue
        echo "$pid"
        return 0
    done
    return 1
}
check_within 10 "a new supervisor runs, detached" new_supervisor_of_run
SUPERVISOR_PID=$(new_supervisor_of_run)
assert_supervisor_process "$SUPERVISOR_PID"
# A session leader, so its process group is its pid: stopped with the stack
PROCESS_GROUPS+=("$SUPERVISOR_PID")
check_within 15 "it starts a new shell" wait_for_new_shell "$old_shell" 15
check_within 10 "the new shell locks again (the marker)" state_is phase locked
check_within "$GUARD" "confirmed" state_is secure true
sleep 1 # fixed sleep: a negative claim: the lock watch sees no unlock after the restart either
stop_lock_watch
check "the compositor never reported unlocked across the restart" lock_watch_never_unlocked
check "only one shell instance" test "$("$LOCKTEST_QS" list --all 2> /dev/null | grep -c 'Process ID:')" = 1

wake_prompt || fail "the prompt did not wake"
check_within "$GUARD" "the methods are known" state_is armed true
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked
lock_by_ipc
check_within "$GUARD" "a later lock works" compositor_locked
wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "… and unlocks" compositor_unlocked
check "the new shell's supervisor still watches it" kill -0 "$SUPERVISOR_PID"
log "the new launcher's log: $(tail -n 3 "$RUN/h2s-shell-launcher.log" 2> /dev/null | tr '\n' '|')"
