# The supervisor itself (scripts/launch.sh), from the review of Stage 4:
#
# (1) A STOPPED shell (SIGSTOP while debugging, SIGTTIN/SIGTTOU from a terminal) is left
#     alone: with job control on, a plain `wait` returns at a stop, and the supervisor took
#     the stopped shell for a dead one — killed it and started another.
# (2) Exactly one supervisor per session: a second plain start of the launcher (a second
#     autostart line, a terminal) waits for the lock the first one holds, and gives up with
#     a clear message; one shell throughout.
# (3) `--restart` while the supervisor sleeps in its pause before a restart (the shell just
#     died): stop_shell used to signal only supervisors of shells that were alive, so the
#     old supervisor started a shell too — two shells, clobbering one marker. Now the
#     supervisor holding the lock is told whether or not a shell is alive.
# And SIGHUP to the launcher (its terminal closed) does not stop it, nor the shell.
#
# The launcher's first pause is 3 s here (so that --restart lands inside it) and a new
# launcher waits 5 s for the lock (H2S_LAUNCHER_TEST_TIMINGS).

stack_start --launcher-timings "first=3 lockwait=5"

# Shells of this run right now: processes running Quickshell's binary that answer to the
# instance registry of the private runtime dir
instances() { "$LOCKTEST_QS" list --all 2> /dev/null | grep -c 'Process ID:'; }
launchers_of_run() {
    local pid
    for pid in $(run_processes); do
        tr '\0' ' ' < "/proc/$pid/cmdline" 2> /dev/null | grep -q "$LOCKTEST_SHELL/scripts/launch\.sh" && echo "$pid"
    done
}

# ---- (1) SIGSTOP ----
stopped=$SHELL_PID
signal_shell STOP
sleep 3
check "a stopped shell is left alone (not killed)" test -e "/proc/$stopped"
check "… it is still stopped" test "$(awk '{ print $3 }' "/proc/$stopped/stat" 2> /dev/null)" = T
check "… and no other shell was started" test "$(_find_shell_pid)" = "$stopped"
check "… nor anything killed" test "$(shell_log_count "killing what the shell left behind")" = 0
signal_shell CONT
check_within 5 "continued, it answers" shell_ipc lockscreen status
check "the supervisor still watches it" kill -0 "$SUPERVISOR_PID"

# ---- SIGHUP to the launcher (the terminal it was started from closed): not a stop ----
assert_supervisor_process "$SUPERVISOR_PID"
kill -HUP "$SUPERVISOR_PID"
log "sent SIGHUP to the launcher (pid $SUPERVISOR_PID)"
sleep 1
check "SIGHUP: the launcher carries on" kill -0 "$SUPERVISOR_PID"
check "… and so does the shell, untouched" test "$(_find_shell_pid)" = "$stopped"
check_within 3 "… it said so" grep -aq "SIGHUP (the terminal it was started from closed?): the shell runs on, supervised" "$WORK/shell.log"

# ---- (2) A second plain launcher ----
check "the supervisor holds the lock and wrote its pid" test "$(cat "$RUN/h2s-shell-launcher.lock")" = "$SUPERVISOR_PID"
spawn "$WORK/second-launcher.log" env "${LAUNCHER_ENV[@]}" "$LOCKTEST_LAUNCHER"
second=$SPAWNED_PID
sleep 1
check "while it waits, one shell" test "$(instances)" = 1
check_within 10 "the second launcher gives up" grep -aq "still supervises the shell of this session: not starting a second one" "$WORK/second-launcher.log"
check_within 3 "… and ends" test -z "$(pgrep -P "$second")"
check "one shell, the first one" test "$(instances)" = 1 -a "$(_find_shell_pid)" = "$stopped"
check "it said why while waiting" grep -aq "another launcher (pid $SUPERVISOR_PID) supervises the shell" "$WORK/second-launcher.log"

# ---- (3) --restart during the supervisor's pause ----
[ "$XDG_RUNTIME_DIR" = "$RUN" ] && [ -n "$RUN" ] || abort "not in the private runtime dir: not running --restart"
for pid in $("$LOCKTEST_QS" list --all 2> /dev/null | awk '/^ *Process ID:/ { print $3 }'); do
    [ "$(process_env "$pid" LOCKTEST_RUN_ID)" = "$LOCKTEST_RUN_ID" ] \
        || abort "qs list --all lists $pid, which is not of this run: not running --restart"
done
old_supervisor=$SUPERVISOR_PID
assert_supervisor_process "$old_supervisor"
mapfile -d '' environment < "/proc/$old_supervisor/environ"
dying=$SHELL_PID
( while :; do instances >> "$WORK/instance-count"; sleep 0.1; done ) &
counter=$!
signal_shell KILL
wait_until 3 test ! -e "/proc/$dying"
check_within 3 "the supervisor is in its pause" grep -aq "starting it again in 3 s" "$WORK/shell.log"
spawn "$WORK/restart.log" env -i "${environment[@]}" "$LOCKTEST_LAUNCHER" --restart
check_within 6 "the old supervisor was told and ended (during its pause)" test ! -e "/proc/$old_supervisor"
new_supervisor() { local pid; for pid in $(launchers_of_run); do [ "$pid" != "$old_supervisor" ] && echo "$pid" && return 0; done; return 1; }
check_within 10 "a new supervisor runs" new_supervisor
SUPERVISOR_PID=$(new_supervisor)
assert_supervisor_process "$SUPERVISOR_PID"
[ "$(awk '{ print $6 }' "/proc/$SUPERVISOR_PID/stat" 2> /dev/null)" = "$SUPERVISOR_PID" ] && PROCESS_GROUPS+=("$SUPERVISOR_PID")
check_within 15 "it starts a shell" wait_for_new_shell "$dying" 15
sleep 5
kill "$counter" 2> /dev/null
wait "$counter" 2> /dev/null
log "instances over the race: $(sort "$WORK/instance-count" | uniq -c | tr '\n' ' ')"
check "never two shells" test -z "$(grep -v '^[01]$' "$WORK/instance-count")"
check "one shell after --restart raced the supervisor's pause" test "$(instances)" = 1
check "one launcher of this run" test "$(launchers_of_run | wc -l)" = 1
check "the old supervisor did not start a shell" test "$(shell_log_count "started the shell: pid")" = 1
check "the lock names the new supervisor" test "$(cat "$RUN/h2s-shell-launcher.lock")" = "$SUPERVISOR_PID"
lock_by_ipc
check_within 5 "the new shell locks" compositor_locked
press_key Escape
check_within 3 "(Escape wakes the prompt)" state_is prompt_awake true
press_key Escape
check_within 5 "… and unlocks" compositor_unlocked
log "the launcher log: $(tr '\n' '|' < "$RUN/h2s-shell-launcher.log")"
