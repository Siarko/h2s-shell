# Files of the shell edited while it is locked: no reload while locked (file watching is
# off from the lock to the unlock — kept from the stop-gap, though a reload would now carry
# the lock over: reloads are the recovery path, not one to take at every file written while
# the owner is away). Quickshell's new watcher at the unlock does not see what changed before
# it, so the shell looks for QML/JS files changed since the lock and reloads ONCE, right
# after the unlock (complete by then: nothing of the lock is carried). An unlock with no
# edit does not reload.

stack_start

# ---- No edit: no reload at the unlock ----
lock_by_ipc
check_within 5 "locked" compositor_locked
reloads_before=$(shell_log_count "Reloading configuration")
press_key Escape
check_within 3 "(Escape wakes the prompt)" state_is prompt_awake true
press_key Escape
check_within 5 "unlocked" compositor_unlocked
sleep 3
check "no edit while locked: no reload at the unlock" test "$(shell_log_count "Reloading configuration")" = "$reloads_before"

# ---- An edit while locked ----
lock_by_ipc
check_within 5 "locked again" compositor_locked
check "file watching is off while locked" state_is watch_files false
sleep 1.1 # the edit must be after the lock's second (find -newermt has 1 s steps)
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
check_within 10 "the edit made while locked is reloaded right after the unlock" \
    lines_more_than "$reloads_before" "Reloading configuration" "$WORK/shell.log"
check "the shell said why" grep -aq "files of the shell changed while it was locked" "$WORK/shell.log"
sleep 2
check "exactly one reload" test "$(shell_log_count "Reloading configuration")" = "$((reloads_before + 1))"
check_within 10 "the reloaded shell answers, unlocked" shell_status_is unlocked
check "the compositor stayed unlocked" compositor_unlocked
check "the same process" kill -0 "$SHELL_PID"
check "file watching is on" state_is watch_files true

lock_by_ipc
check_within 5 "the reloaded shell locks" compositor_locked
press_key Escape
check_within 3 "(Escape wakes the prompt)" state_is prompt_awake true
press_key Escape
check_within 5 "… and unlocks" compositor_unlocked
sleep 3
check "no edit during that lock: no further reload" test "$(shell_log_count "Reloading configuration")" = "$((reloads_before + 1))"
