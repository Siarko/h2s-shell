# A second submit while the first is being verified is refused ("busy") and does not
# empty the field: what was typed meanwhile is still there, and sent by the next Enter
# once the first verdict is in. The password stack is made slow for this (pam/slow: each
# check waits for pam/release).

stack_start

lock_by_ipc
check_within 5 "locked" compositor_locked
check_within 5 "armed" state_is armed true
wake_prompt || fail "the prompt did not wake"

touch "$WORK/pam/slow"
type_text "not-the-password"
press_key Return
check_within 5 "the wrong password is being verified" state_is verifying true
wait_until 5 grep -q waiting "$WORK/pam/check.log" || fail "the slow check did not start"
epoch=$(state_field field_epoch)

# Typed during the verification, then Enter: refused, field kept
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 3 "a second submit is refused as busy" state_is refusal busy
check "the field was not emptied (the epoch did not move)" state_is field_epoch "$epoch"
check "still verifying the first" state_is verifying true
check "no second check was started" test "$(grep -c waiting "$WORK/pam/check.log")" = 1

# The first verdict: wrong
rm -f "$WORK/pam/slow"
touch "$WORK/pam/release"
check_within 10 "the first password is rejected" state_is error "Authentication failed"
check "still locked" compositor_locked
check "the field still was not emptied" state_is field_epoch "$epoch"

# The field still holds the right password typed during the verification
press_key Return
check_within 10 "Enter sends what was typed during the verification, and it unlocks" compositor_unlocked
log "password checks: $(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)"
check "the checks were: the slow wrong one, then the right one" \
    test "$(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)" = "waiting wrong right "
