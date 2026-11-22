# The shell as on a user's machine: started without --dev or H2S_SHELL_DEV, it is not in
# development mode, so a file written in its folder (an update, a module install, an editor)
# does not reload it. File watching stays off through a lock and its unlock: the unlock puts
# back what development mode says, never simply "on". The other reload scenarios start with
# --dev; DevRules (tests/DevRulesTest.qml) decides between the variable and the flag.

stack_start

check "not in development mode" state_is dev_mode false
check "file watching is off while unlocked" state_is watch_files false
reloads_before=$(shell_log_count "Reloading configuration")
echo "// written by tests/lock dev-mode-off.sh while unlocked" >> "$LOCKTEST_SHELL/singletons/Theme.qml"
log "wrote to the shell's copy while unlocked"
sleep 3 # fixed sleep: a negative claim: no reload follows the edit
check "a file written does not reload the shell" test "$(shell_log_count "Reloading configuration")" = "$reloads_before"
check "the same process" kill -0 "$SHELL_PID"

lock_by_ipc
check_within "$GUARD" "locked" compositor_locked
check "file watching is off while locked" state_is watch_files false
unlock_for_test
check "unlocked" compositor_unlocked
check_within "$GUARD" "the shell says unlocked" shell_status_is unlocked
check "file watching is still off after the unlock (not switched on)" state_is watch_files false
