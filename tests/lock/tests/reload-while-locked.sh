# A file written in the folder the shell runs from, while locked, must not reload the shell:
# a reload's new WlSessionLock starts with `locked` false and unlocks the session with no
# authentication (the review's demonstration). The stop-gap: Quickshell.watchFiles is off
# from the lock to the unlock. After the unlock file watching works again (a write reloads
# the shell), and the reloaded shell still locks. Carrying a lock across a reload is Stage 4.

stack_start

check "file watching is on while unlocked" state_is watch_files true
lock_by_ipc
check_within "$GUARD" "locked" compositor_locked
check_within "$GUARD" "confirmed" state_is secure true
check "file watching is off while locked" state_is watch_files false

reloads_before=$(grep -ac "Reloading configuration" "$WORK/shell.log")
echo "// written by tests/lock reload-while-locked.sh while locked" >> "$LOCKTEST_SHELL/singletons/Theme.qml"
log "wrote to the shell's copy while locked"
sleep 4 # fixed sleep: a negative claim: no reload follows the edit
check "no reload while locked" test "$(grep -ac "Reloading configuration" "$WORK/shell.log")" = "$reloads_before"
check "still locked (compositor)" compositor_locked
check "still locked (shell)" shell_status_is locked
check "the shell still runs" kill -0 "$SHELL_PID"

wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked
check_within "$GUARD" "file watching is on again after the unlock" state_is watch_files true
sleep 1 # fixed sleep: a negative claim: no reload follows the unlock
check "the unlock itself did not reload (edit-while-locked.sh)" \
    test "$(grep -ac "Reloading configuration" "$WORK/shell.log")" = "$reloads_before"

echo "// written by tests/lock reload-while-locked.sh after the unlock" >> "$LOCKTEST_SHELL/singletons/Theme.qml"
log "wrote to the shell's copy after the unlock"
check_within 10 "a file written after the unlock reloads the shell (file watching works again)" \
    lines_more_than "$reloads_before" "Reloading configuration" "$WORK/shell.log"
check_within 10 "the reloaded shell answers" shell_status_is unlocked
check "the same process (a reload, not a restart)" kill -0 "$SHELL_PID"

lock_by_ipc
check_within "$GUARD" "the reloaded shell locks" compositor_locked
check_within "$GUARD" "… and the compositor confirms it" state_is secure true
unlock_for_test
check "… and unlocks again" compositor_unlocked
