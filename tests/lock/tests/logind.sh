# logind's signals, delivered through the stand-ins (stack_start --logind: a `gdbus` that
# prints what logind_signal appends, a `systemd-inhibit` that records holds and releases;
# the real bus stays cut off): Lock locks, Unlock unlocks (another session's does not),
# PrepareForSleep locks before sleep with the inhibitor held until the compositor has
# confirmed, no passive method runs while suspending and they start again after the wake.
# Also: a monitor that dies is started again, an inhibitor that dies is taken again, and
# the resume ends a screensaver that was up when the machine went to sleep (it counts as
# input), and the lock is reported to logind (SetLockedHint, recorded by the stand-in); the
# sleep notice's look waits for the shell's own lock and says nothing after it. Lock
# before sleep is off by default: switched on here; the screensaver too.

stack_start --logind --methods "password fingerprint" --settings '{"lockscreen.lockOnSleep": true,
    "lockscreen.screensaverEnabled": true, "lockscreen.screensaverTimeout": 5}'

idle_sleeping() { [ "$(shell_ipc idle state | python3 -I -c 'import json, sys; print(json.dumps(json.load(sys.stdin)["state"]["sleeping"]))')" = true ]; }
# saver_shown_for <seconds>: the screensaver counts as shown all along, polled for that long
saver_shown_for() {
    local deadline=$((${EPOCHREALTIME/[.,]/} + $1 * 1000000))
    while [ "${EPOCHREALTIME/[.,]/}" -lt "$deadline" ]; do
        saver_shown || return 1
    done
    return 0
}
hints() { grep -a '^call SetLockedHint' "$WORK/logind/log" | awk '{ print $3 "=" $4 }' | tr '\n' ' '; }
hints_are() { [ "$(hints)" = "$1" ]; }
saver_shown() { [ "$(shell_ipc idle state | python3 -I -c 'import json, sys; print(json.dumps(json.load(sys.stdin)["saverShown"]))')" = true ]; }

check_within "$GUARD" "the shell follows the test's logind session" state_is logind_session "$LOCKTEST_SESSION_PATH"
check_within "$GUARD" "the logind monitor (stand-in) runs" logind_monitor_running
# A hint left true by a shell that crashed while locked (or a failed call) is cleared
check_within "$GUARD" "started unlocked: SetLockedHint false, once" hints_are "$LOCKTEST_SESSION_PATH=false "
check_within "$GUARD" "the sleep inhibitor is held while awake" inhibitor_held
check "the rules hold it" state_is inhibitor held

# ---- Lock and Unlock ----
logind_signal lock
check_within "$GUARD" "logind's Lock locks" compositor_locked
check_within "$GUARD" "confirmed" state_is secure true
check_within "$GUARD" "the lock reported to logind: SetLockedHint true for the session" \
    hints_are "$LOCKTEST_SESSION_PATH=false $LOCKTEST_SESSION_PATH=true "
check_within "$GUARD" "a fingerprint conversation runs" _one_finger_waiter
logind_signal unlock-other
sleep 1 # fixed sleep: a negative claim: another session's Unlock does nothing
check "another session's Unlock does not unlock" compositor_locked
logind_signal unlock
check_within "$GUARD" "logind's Unlock unlocks" compositor_unlocked
check "the lock ended by logind" state_is last_end logind
check_within "$GUARD" "the unlock reported: SetLockedHint false" \
    hints_are "$LOCKTEST_SESSION_PATH=false $LOCKTEST_SESSION_PATH=true $LOCKTEST_SESSION_PATH=false "
check_within "$GUARD" "no fingerprint conversation left" no_finger_waiters

# ---- Lock before sleep, from unlocked, the screensaver up ----
check_within "$GUARD" "5 s without input: the screensaver shows" saver_shown
holds_before=$(grep -c '^hold' "$WORK/logind/log")
sleep_line=$(($(wc -l < "$WORK/shell.log") + 1))
logind_signal sleep
check_within "$GUARD" "PrepareForSleep locks" compositor_locked
check_within "$GUARD" "the inhibitor is let go" inhibitor_released
log "PrepareForSleep to the release (the lock confirmed before it): $(release_seconds_after_signal) s"
check "… locked and let go within 4 s of the PrepareForSleep (logind sleeps 5 s after it at the latest)" \
    released_after_signal_within 4
check "the rules say suspending, inhibitor released" test "$(state_field sleep) $(state_field inhibitor)" = "suspending released"
# The order, from the shell's own log after the PrepareForSleep: the compositor's
# confirmation first, the release after it
order=$(tail -n +"$sleep_line" "$WORK/shell.log" | grep -a -o 'event {"type":"compositorLocked"[^}]*}\|effect {"type":"releaseInhibitor"}' | head -n 2 | tr '\n' ' ')
log "after PrepareForSleep: $order"
check "the inhibitor was released only after the compositor confirmed the lock" \
    test "$order" = 'event {"type":"compositorLocked","session":2} effect {"type":"releaseInhibitor"} '
# The sleep notice's look (SleepLockNotice): the shell's own lock, coming up after the
# PrepareForSleep, is waited for — never a false "unlocked"
notice_looked() { tail -n +"$sleep_line" "$WORK/shell.log" | grep -aq '\[SleepLockNotice\] went to sleep'; }
check_within "$GUARD" "the sleep notice looked" notice_looked
check "… and saw it locked" grep -aq '\[SleepLockNotice\] went to sleep locked ' <<< "$(tail -n +"$sleep_line" "$WORK/shell.log")"
sleep 1 # fixed sleep: a negative claim: no conversation starts while suspending
check "no fingerprint conversation while suspending" no_finger_waiters
check "the fingerprint is paused" state_is fingerprint_status paused

check_within "$GUARD" "Idle knows the machine is going to sleep" idle_sleeping
# The hand that closed the lid: input while going to sleep is no wake
move_pointer 700 400
move_pointer 720 410
check "asleep, the pointer moved: the screensaver stays as it was until the wake" saver_shown_for 1
wake_line=$(($(wc -l < "$WORK/shell.log") + 1))
logind_signal wake
# From the log, not the state: with still no input the screensaver comes again 5 s later
saver_ended_after_wake() { tail -n +"$wake_line" "$WORK/shell.log" | grep -aq '\[Idle\] the screensaver goes'; }
check_within "$GUARD" "the resume (PrepareForSleep(false)) ends the screensaver" saver_ended_after_wake
notice_phase() { shell_ipc shelltest sleepNotice | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["notice"]["phase"])'; }
check "no sleep notice after the resume (the sleep went down locked)" test "$(notice_phase)" = quiet
check_within "$GUARD" "after the wake the inhibitor is taken again" lines_more_than "$holds_before" '^hold' "$WORK/logind/log"
check_within "$GUARD" "after the wake a fingerprint conversation runs" _one_finger_waiter
finger ok
check_within 10 "and the finger unlocks" compositor_unlocked

# ---- Sleep while locked: a running conversation stops, and starts again ----
lock_by_ipc
check_within "$GUARD" "locked again" compositor_locked
check_within "$GUARD" "a fingerprint conversation runs" _one_finger_waiter
first=$(finger_waiters)
logind_signal sleep
check_within "$GUARD" "going to sleep stops it" no_finger_waiters
check "paused" state_is fingerprint_status paused
check "still locked" compositor_locked
logind_signal wake
check_within "$GUARD" "after the wake a new conversation runs" _one_finger_waiter
check "a new one" test "$(finger_waiters)" != "$first"

# ---- Helpers that die are started again ----
inhibitor_pid=$(awk '$1 == "hold" { pid = $2 } END { print pid }' "$WORK/logind/log")
holds=$(grep -c '^hold' "$WORK/logind/log")
[ "$(process_env "$inhibitor_pid" LOCKTEST_RUN_ID)" = "$LOCKTEST_RUN_ID" ] || abort "the inhibitor stand-in $inhibitor_pid is not a process of this run: not killing it"
kill "$inhibitor_pid"
check_within "$GUARD" "an inhibitor that dies while wanted is taken again" \
    lines_more_than "$holds" '^hold' "$WORK/logind/log"
monitors=$(grep -c '^monitor' "$WORK/logind/log")
pkill -f "tail -n .* -F $WORK/logind/signals"
check_within 10 "a logind monitor that dies is started again" \
    lines_more_than "$monitors" '^monitor' "$WORK/logind/log"
check "and its restart was logged" grep -aq "the logind monitor ended after" "$WORK/shell.log"
wait_until 3 logind_monitor_running
logind_signal unlock
check_within "$GUARD" "the restarted monitor's Unlock unlocks" compositor_unlocked

# ---- A crashed shell leaves no helper behind ----
# Its children survive a crash; the monitor's sh and the inhibitor read a pipe only the
# shell writes to, so they end when it goes. Killed with SIGKILL, as a crash would — only
# after making sure it is the shell under test.
monitor_alive() { pgrep -f "tail -n .* -F $WORK/logind/signals" > /dev/null; }
monitor_gone() { ! monitor_alive; }
inhibitor_alive() { pgrep -f "$WORK/standins/systemd-inhibit" > /dev/null; }
inhibitor_gone() { ! inhibitor_alive; }
[ "$(process_env "$SHELL_PID" LOCKTEST_RUN_ID)" = "$LOCKTEST_RUN_ID" ] \
    && [ "$(readlink -f "/proc/$SHELL_PID/exe")" = "$(_quickshell_binary)" ] \
    || abort "pid $SHELL_PID is not the shell under test: not killing it"
check_within "$GUARD" "before the crash the logind monitor runs" monitor_alive
check_within "$GUARD" "before the crash the inhibitor is held" inhibitor_alive
# The launcher would start a new shell, whose own monitor and inhibitor these checks would
# then see: it lets this one go first (restarts are tests/lock/tests/restart-*.sh's)
supervisor_release
kill -KILL "$SHELL_PID"
check_within "$GUARD" "after a crash the logind monitor ends by itself" monitor_gone
check_within "$GUARD" "after a crash the inhibitor is let go" inhibitor_gone
