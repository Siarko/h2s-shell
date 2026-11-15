# Files of the shell edited while it is locked: no reload while locked (file watching is
# off from the lock to the unlock — a reload would carry the lock over, but reloads are the
# recovery path, not one to take at every file written while the owner is away), and NO
# reload at the unlock either: file watching is simply switched back on, and the edits take
# effect at the next file change. (A reload right after the unlock was tried and removed:
# for its ~2 s lock requests by IPC were dropped and logind's PrepareForSleep missed —
# reload-window.sh.)

stack_start

lock_by_ipc
check_within 5 "locked" compositor_locked
check "file watching is off while locked" state_is watch_files false
reloads_before=$(shell_log_count "Reloading configuration")
echo "// written by tests/lock edit-while-locked.sh while locked" >> "$LOCKTEST_SHELL/widgets/Clock.qml" 2> /dev/null \
    || echo "// written by tests/lock edit-while-locked.sh while locked" >> "$LOCKTEST_SHELL/singletons/Theme.qml"
log "wrote to the shell's copy while locked"
sleep 3
check "no reload while locked" test "$(shell_log_count "Reloading configuration")" = "$reloads_before"
check "still locked (compositor)" compositor_locked
check "still locked (shell)" shell_status_is locked

wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked
check_within 3 "file watching is on again" state_is watch_files true
sleep 3
check "no reload at the unlock (the edit waits for the next file change)" \
    test "$(shell_log_count "Reloading configuration")" = "$reloads_before"
check "the shell did not look for edits" test "$(shell_log_count "changed while it was locked")" = 0
check "the same process" kill -0 "$SHELL_PID"

# The next file change reloads, once, and takes the earlier edit with it
echo "// written by tests/lock edit-while-locked.sh after the unlock" >> "$LOCKTEST_SHELL/singletons/Theme.qml"
check_within 10 "a file written after the unlock reloads the shell" \
    lines_more_than "$reloads_before" "Reloading configuration" "$WORK/shell.log"
check_within 10 "the reloaded shell answers, unlocked" shell_status_is unlocked
sleep 2
check "exactly one reload" test "$(shell_log_count "Reloading configuration")" = "$((reloads_before + 1))"
check "the compositor stayed unlocked" compositor_unlocked

lock_by_ipc
check_within 5 "the reloaded shell locks" compositor_locked
unlock_for_test
check "… and unlocks" compositor_unlocked
