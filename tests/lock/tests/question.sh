# A PAM stack that asks a second question after the password (the shape of a one-time
# code): the question is shown in place of "Password", the field empties for the answer,
# and the right answer unlocks. A wrong answer first fails, and the whole conversation
# starts again with the next password.

stack_start --methods "password=password-question"

lock_by_ipc
check_within "$GUARD" "locked" compositor_locked
check_within "$GUARD" "armed" state_is armed true
wake_prompt || fail "the prompt did not wake"

type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the question is asked" state_is password_status asking
check "it is shown as the placeholder" state_is placeholder "STRESS Password"
check "its answer is hidden" state_is view.answerVisible false
check "not busy while waiting for the answer" state_is verifying false
screenshot question

type_text "wrong-answer"
press_key Return
check_within 10 "a wrong answer fails" state_is error "Authentication failed"
check "still locked" compositor_locked

type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the question is asked again" state_is password_status asking
type_text "$LOCKTEST_ANSWER"
press_key Return
check_within 10 "the right answer unlocks" compositor_unlocked
log "checks: $(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)"
check "the stack checked: password, wrong answer, password, right answer" \
    test "$(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)" = "right answer-wrong right answer-right "
