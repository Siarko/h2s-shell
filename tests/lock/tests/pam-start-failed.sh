# The password's PAM config is not there, so PamContext.start() refuses (it says so only
# through its return value): the prompt shows "Password check could not start", never a
# permanent "Verifying…". Nothing typed reaches any PAM stack: there is none to start.

methods_script=$WORK/missing-stack-methods.sh
printf '#!%s\nprintf "password\\t%s\\t%s\\n"\n' "$(command -v bash)" "$WORK/pam" "no-such-stack" > "$methods_script"
stack_start --methods-script "$methods_script"

lock_by_ipc --any-safe-config
check_within "$GUARD" "locked" compositor_locked
check "the password config is the missing one" state_is password_config "$WORK/pam/no-such-stack"
check "which is indeed not there" test ! -e "$WORK/pam/no-such-stack"

wake_prompt || fail "the prompt did not wake"
red_before=$(reddish_pixels before-start-failed)
type_text "anything"
press_key Return
check_within 10 "a visible error" state_is error "Password check could not start"
check "not verifying" state_is verifying false
check "the refusal was logged" grep -aq "password: PAM refused to start the conversation" "$WORK/shell.log"
check_within "$GUARD" "the prompt shows the error in red" reddish_above $((red_before + 50)) after-start-failed
red_after=$(reddish_pixels after-start-failed)
log "red pixels in the prompt area: $red_before before, $red_after after"
check "still locked" compositor_locked
