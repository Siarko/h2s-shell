# A password check whose PAM child says nothing at all — not even the marker line its config
# starts with — is taken to be stuck before its first module (Quickshell forks the child
# from the multi-threaded shell, and a dlopen inside pam_start can then wait for good on a
# loader lock), aborted and started again: the right password typed once unlocks, checked
# once. After the marker, a module that waits without a word is never started again.
#
# The stand-in (pam/password-stall, pam/stall.sh): at the first start the marker module is
# missing, so that start says nothing, and its silent module waits until its helper is
# killed; it links the marker in, so the next start says the marker and goes on. Without the
# restart the first start would wait for the lock's 90 s verify time-out.

# Its subject is the restart: stack_stop does not count these as unexpected
PAM_SILENT_STARTS_EXPECTED=1
stack_start --methods "password=password-stall" --timings '{"firstWord":2000}'
echo before > "$WORK/pam/stall/mode"

lock_by_ipc
check_within "$GUARD" "locked" compositor_locked
check_within "$GUARD" "authentication is armed" state_is armed true
check "the password config is the stalling stack" state_is password_config "$WORK/pam/password-stall"
check "the marker module is not there yet" test ! -e "$WORK/pam/marker/pam_echo.so"

wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 20 "the silent check is started again and the right password unlocks" compositor_unlocked
log "stall log: $(tr '\n' ' ' < "$WORK/pam/stall/log" 2> /dev/null)"
log "password checks: $(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)"
check "two starts: the first said no marker, the second did" \
    test "$(awk '$1 == "start" { printf "%s ", $3 }' "$WORK/pam/stall/log")" = "nomarker marker "
check "the password reached PAM once (no second prompt, no extra failed attempt)" \
    test "$(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)" = "right "
check "the restart was logged" grep -aq "password: PAM said nothing in 2 s" "$WORK/shell.log"
check_within "$GUARD" "the first start's silent module ended with its killed helper" grep -q "^orphaned" "$WORK/pam/stall/log"

# After the marker: a module silent for twice the first-word time is waited for
check_within "$GUARD" "shell says unlocked" shell_status_is unlocked
: > "$WORK/pam/check.log"
: > "$WORK/pam/stall/log"
echo 4 > "$WORK/pam/stall/seconds"
echo after > "$WORK/pam/stall/mode"
check "the marker module is there now" test -e "$WORK/pam/marker/pam_echo.so"
lock_by_ipc
check_within "$GUARD" "locked again" compositor_locked
check_within "$GUARD" "authentication is armed again" state_is armed true
wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 20 "a module silent after the marker is waited for, and the password unlocks" compositor_unlocked
log "stall log: $(tr '\n' ' ' < "$WORK/pam/stall/log" 2> /dev/null)"
check "one start, its silent module done on its own" \
    test "$(awk '{ printf "%s %s ", $1, ($1 == "start" ? $3 : "") }' "$WORK/pam/stall/log")" = "start marker done  "
check "the password reached PAM once" test "$(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)" = "right "
check "no second restart was logged" test "$(shell_log_count "PAM said nothing")" = 1
