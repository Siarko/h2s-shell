# The log the owner reads after a failed attempt on the real machine (Stage 6):
# scripts/lock-log.sh finds the running shell's Quickshell log and prints its lock lines,
# wall-clock stamped and in order, with the supervisor's log. A lock, a wrong password, the
# right one, the unlock — every step must leave a line, and none may hold typed text.
# (The journal part reads the real system journal: left out here, --no-journal.)

stack_start --logind

lock_by_ipc
check_within 5 "locked" compositor_locked
wake_prompt || fail "the prompt did not wake"
type_text "lt-wrong-pass-99"
press_key Return
check_within 10 "the wrong password is refused" state_is password_status failed
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the right one unlocks" compositor_unlocked

# As the owner runs it: the copy's script, the session's runtime dir (here the private one),
# qs found beside the running shell's binary when it is not on PATH. Run again until it
# shows the marker's "unlocked" (written a moment after the unlock; Quickshell's log file
# may lag its stderr): a wait, not a fixed sleep. The last run's output is what is checked.
lock_log_status=1
run_lock_log() {
    "$LOCKTEST_SHELL/scripts/lock-log.sh" --no-journal --minutes 10 > "$WORK/lock-log.txt" 2> "$WORK/lock-log.err"
    lock_log_status=$?
    [ "$lock_log_status" = 0 ] && grep -q 'lock marker: unlocked' "$WORK/lock-log.txt"
}
wait_until 10 run_lock_log || log "lock-log.sh did not show the marker's \"unlocked\" within 10 s"
check "the script ran" test "$lock_log_status" = 0
log "lock-log.sh printed $(wc -l < "$WORK/lock-log.txt") lines (lock-log.txt)"
check "it found the running shell's log" grep -q "== Shell instance .*(RUNNING, pid $SHELL_PID)" "$WORK/lock-log.txt"
check "it names the supervisor" grep -q "scripts/launch.sh" "$WORK/lock-log.txt"
check "it shows the supervisor's own log" grep -q "h2s-shell launcher\[$SUPERVISOR_PID\]: supervising the shell" "$WORK/lock-log.txt"

# Each step, in this order, each line stamped with the wall clock. One pair is unordered:
# the compositor's confirmation (compositorLocked) and the methods script's answer
# (methodsDetected) are independent and come in either order — both after the lock's step
# (which logs everything up to "the lock screen is up") and both before the first submit.
# The rest is guaranteed: a step logs its event, then its effects in the rules' order, then
# what the view showed; PAM starts only once the methods are known and is answered only
# after it asked; the marker's "unlocked" comes a moment after the unlock's step.
first_line_after() { awk -v from="$1" -v step="$2" 'NR > from && index($0, step) { print NR; exit }' "$WORK/lock-log.txt"; }
check_in_order() {
    local step line
    for step in "$@"; do
        line=$(first_line_after "$position" "$step")
        if [ -n "$line" ]; then
            pass "in order: $step"
            position=$line
        else
            fail "in order: $step (not found after line $position)"
        fi
    done
}
position=0
check_in_order \
    'event {"type":"lockRequested","source":"ipc"}' \
    'effect {"type":"lockCompositor"' \
    'lock marker: locked ' \
    'locking (ipc), session 1' \
    'effect {"type":"detectMethods"' \
    'the lock screen is up'
lock_up=$position
first_submit=$(first_line_after "$lock_up" 'event {"type":"submit","text":"<redacted>"')
for step in 'event {"type":"compositorLocked"' '"type":"methodsDetected"'; do
    line=$(first_line_after "$lock_up" "$step")
    if [ -n "$line" ] && [ -n "$first_submit" ] && [ "$line" -lt "$first_submit" ]; then
        pass "after the lock's step, before the first submit (either order): $step (line $line)"
    else
        fail "after the lock's step, before the first submit (either order): $step (line ${line:-none}; lock step ends at line $lock_up, first submit at line ${first_submit:-none})"
    fi
done
steps=(
    'prompt awake on surface'
    'event {"type":"submit","text":"<redacted>"'
    'effect {"type":"startPam","method":"password"'
    'effect {"type":"respondPam","method":"password","conversation":'
    'ended: failed after'
    'password not accepted (failed)'
    'prompt shows: '
    'ended: success after'
    'effect {"type":"unlockCompositor"'
    'unlocked (authenticated, password), session 1'
    'the lock screen is gone'
    'lock marker: unlocked'
)
check_in_order "${steps[@]}"
# The marker's "unlocked" a moment after the unlock request, not in the same step: a shell
# killed in between comes back locked instead of believing a session unlocked that the
# compositor may still hold
# (from the shell's stderr, stamped to the millisecond; Quickshell's log file keeps seconds)
stamp_of() { local line; line=$(sed 's/\x1b\[[0-9;]*m//g' "$WORK/shell.log" | grep -a -m 1 -- "$1"); date -d "${line:0:23}" +%s.%N 2> /dev/null; }
unlock_at=$(stamp_of '"type":"unlockCompositor"')
marker_at=$(stamp_of 'lock marker: unlocked')
log "unlock requested at $unlock_at, marker unlocked at $marker_at"
check "the marker says unlocked only ≥ 0.2 s after the unlock was asked for" \
    awk -v unlock="${unlock_at:-0}" -v marker="${marker_at:-0}" 'BEGIN { exit !(unlock > 0 && marker - unlock >= 0.2) }'
check "every lock line has a wall-clock stamp" \
    test -z "$(grep '\[Lockscreen\]' "$WORK/lock-log.txt" | grep -vE '^  [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3} ')"
check "no typed text: not the right password" test "$(grep -c -- "$LOCKTEST_PASSWORD" "$WORK/lock-log.txt")" = 0
check "… nor the wrong one" test "$(grep -c -- "lt-wrong-pass" "$WORK/lock-log.txt")" = 0
check "… nor a length of either" test "$(grep -ciE 'length|"len' "$WORK/lock-log.txt")" = 0
check "the password stack's own messages are not logged" test "$(grep -c '"method":"password","conversation":[0-9]*,"message":"[^<]' "$WORK/lock-log.txt")" = 0
sed 's/^/        /' "$WORK/lock-log.txt" | grep -E 'Lockscreen|launcher|==' | head -n 120
