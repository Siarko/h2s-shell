# Keys right after waking by a key are not lost (defect 9): the key that wakes the prompt
# is the first character, then a wrong character, Backspace, the rest of the password and
# Enter, all typed at once while the prompt is still fading in — and it unlocks. Then an
# Enter right after a key wake, alone, is refused as empty rather than sent.

stack_start

lock_by_ipc
check_within 5 "locked" compositor_locked
check_within 5 "the compositor confirmed the lock" state_is secure true
sleep 0.5
check "the prompt sleeps" state_is prompt_awake false

# An Enter that wakes the prompt: nothing typed, nothing sent, refused as empty
press_key Return
check_within 3 "Enter wakes the prompt" state_is prompt_awake true
check_within 2 "and is refused as an empty password" state_is refusal empty
check "nothing was checked" test ! -e "$WORK/pam/check.log"

# Back to sleep: Escape at an awake prompt hides it (as its time-out would, 10 s later)
press_key Escape
check_within 3 "Escape puts the prompt back to sleep" state_is prompt_awake false
check "… still locked" compositor_locked
check "… the refusal is gone with it" state_is refusal ""

first=${LOCKTEST_PASSWORD:0:1}
rest=${LOCKTEST_PASSWORD:1}
# One burst, no waiting in between: the first key wakes the prompt
send_input "type $first" "type x" "key BackSpace" "type $rest" "key Return"
check_within 10 "the key-woken password, with a typo corrected, unlocks" compositor_unlocked
log "password checks: $(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)"
check "it was checked once, and right" test "$(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)" = "right "
