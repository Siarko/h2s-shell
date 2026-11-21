# Adopted from the Stage 2 review (defect 8): the prompt's 10 s sleep must not abort a
# verification under way — the prompt goes to sleep while PAM is still checking, and the
# verdict still unlocks.

stack_start

lock_by_ipc
check_within "$GUARD" "armed" state_is armed true
wake_prompt || fail "the prompt did not wake"
touch "$WORK/pam/slow"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within "$GUARD" "verifying" state_is verifying true
check_within 15 "the prompt goes to sleep during the verification" state_is prompt_awake false
check "still verifying while asleep" state_is password_status verifying
sleep 1 # fixed sleep: a negative claim: asleep, nothing ends the verification
rm -f "$WORK/pam/slow"
touch "$WORK/pam/release"
check_within 10 "the verification's verdict still unlocks" compositor_unlocked
