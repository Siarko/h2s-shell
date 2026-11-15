# A wrong password is rejected: the screen stays locked, the prompt shows an error, and
# the right password typed next still unlocks.

stack_start

lock_by_ipc
check_within 5 "lock by IPC locks the compositor" compositor_locked
check_within 5 "the compositor confirmed the lock" state_is secure true
check_within 5 "authentication is armed" state_is armed true

wake_prompt || fail "the prompt did not wake"
red_before=$(reddish_pixels before-wrong-password)
type_text "not-the-password"
press_key Return
check_within 10 "the wrong password is rejected with an error" state_is error "Authentication failed"
check "no longer verifying" state_is verifying false
check "still locked (compositor)" compositor_locked
check "still locked (shell)" shell_status_is locked
sleep 0.5 # the error's colour fades in
red_after=$(reddish_pixels after-wrong-password)
log "red pixels in the prompt area: $red_before before, $red_after after"
check "the prompt shows the error in red" test "$red_after" -gt $((red_before + 50))

type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the right password typed next unlocks" compositor_unlocked
# The verdicts came from the test stack's script, not from somewhere else
log "password checks: $(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)"
check "the test stack's check ran, saw the wrong password and then the right one" \
    test "$(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)" = "wrong right "
