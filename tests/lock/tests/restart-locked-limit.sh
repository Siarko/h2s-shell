# The launcher's limit while locked (scripts/launch.sh, "Restarts while locked"): a shell
# killed while the screen is locked is started again at most 3 times while the session
# stays locked. Killed a fourth time, it is not started again: the launcher ends, and the
# compositor keeps the session locked throughout — never unlocked. The owner then starts
# the launcher by hand (as from a text console): its shell comes up locked (the marker),
# and once the session is unlocked it says, in one notification, what happened and where
# the log is. An unlock in between starts the count afresh (the shell overwrites the
# launcher's record).
#
# The launcher's first pause is shortened (H2S_LAUNCHER_TEST_TIMINGS: 0.1 s).

stack_start --launcher-timings "first=0.1"

record=$RUN/h2s-shell-lock-restarts
notice_file=$RUN/h2s-shell-lock-notice
record_is() { [ "$(cat "$record" 2> /dev/null)" = "$1" ]; }
# The notifications the shell recorded (a test tree is in module test mode: recorded, not
# sent) whose summary is the notice's
notices() {
    shell_ipc shelltest notifierRecorded | python3 -I -c '
import json, sys
print(sum(1 for n in json.load(sys.stdin) if n["summary"] == "The shell stopped while locked"))'
}
notices_are() { [ "$(notices)" = "$1" ]; }

# kill_locked <n>: the shell killed while locked; the launcher starts the next, which
# locks again from the marker
kill_locked() {
    local old=$SHELL_PID before
    before=$(shell_log_count "(restart $1 of 3 while locked)")
    signal_shell KILL
    check_within 10 "killed while locked ($1): the launcher starts a new shell" wait_for_new_shell "$old" 10
    check "… its restart $1 of 3 while locked, said so" lines_more_than "$before" "(restart $1 of 3 while locked)" "$WORK/shell.log"
    check_within 10 "… which locks again (the marker)" state_is phase locked
    check_within 5 "… confirmed" state_is secure true
}

# ---- An unlock in between starts the count afresh ----
lock_by_ipc
check_within 5 "locked" compositor_locked
check_within 5 "confirmed" state_is secure true
start_lock_watch limit
kill_locked 1
check "the launcher recorded it" record_is 1
sleep 1
stop_lock_watch
check "the compositor never reported unlocked across the restart" lock_watch_never_unlocked
unlock_for_test || fail "the password did not unlock"
check_within 3 "the marker says unlocked" marker_file_is unlocked
record_says_unlocked() { grep -q '^unlocked [0-9]*$' "$record" 2> /dev/null; }
check_within 3 "the unlock overwrote the launcher's record" record_says_unlocked

# ---- Four deaths under one lock ----
lock_by_ipc
check_within 5 "locked again" compositor_locked
check_within 5 "confirmed" state_is secure true
start_lock_watch limit-four
supervisor=$SUPERVISOR_PID
kill_locked 1
kill_locked 2
kill_locked 3
check "three restarts recorded" record_is 3
last=$SHELL_PID
signal_shell KILL
check_within 3 "the fourth time the killed shell is gone" test ! -e "/proc/$last"
check_within 10 "… and not started again: the launcher ends" test ! -e "/proc/$supervisor"
check "… it said why" grep -aq "after 3 restarts since the last unlock: not starting it again. The session stays locked." "$WORK/shell.log"
check "no shell of this run is left" test -z "$(_find_shell_pid)"
check "the launcher left its notice" test "$(cat "$notice_file" 2> /dev/null)" = 3
sleep 2
check "the compositor is still locked, with no client" compositor_locked
check "the marker still says locked" marker_file_is locked
stop_lock_watch
check "the compositor never reported unlocked across the four deaths" lock_watch_never_unlocked
cp "$WORK/shell.log" "$WORK/shell-first-launcher.log"

# ---- The launcher started by hand ----
start_lock_watch by-hand
start_launcher
log "a launcher started by hand: pid $SUPERVISOR_PID, its shell $SHELL_PID"
check_within 10 "its shell locks again (the marker)" state_is phase locked
check_within 5 "confirmed" state_is secure true
check "the launcher took the notice" test ! -e "$notice_file"
check "… and said so" grep -aq "the last launcher gave up on a shell that died while the screen was locked" "$WORK/shell.log"
check "the shell was handed it" test "$(process_env "$SHELL_PID" H2S_SHELL_LOCK_NOTICE)" = 3
sleep 4
check "while locked, the notice is not shown (nobody would see it)" notices_are 0
stop_lock_watch
check "the compositor never reported unlocked before the owner's password" lock_watch_never_unlocked
unlock_for_test || fail "the password did not unlock"
check_within 5 "unlocked, the shell shows the notice" notices_are 1
check "… saying what happened and where the log is" grep -q \
    "It stopped again after 3 restarts and was left locked. Log: $RUN/h2s-shell-launcher.log" \
    <<< "$(shell_ipc shelltest notifierRecorded)"
lock_by_ipc
check_within 5 "locks again" compositor_locked
unlock_for_test || fail "the password did not unlock"
sleep 1
check "… once: not at the next unlock" notices_are 1
check "no protocol error in either log" no_protocol_errors
