# Escape never unlocks (it did until 2026-11-15: plan section 5). On a sleeping prompt it
# wakes it, as any key; at an awake prompt it hides the prompt, as its time-out does, and the
# field empties with it; pressed again and again it only goes on toggling the prompt. What
# was typed before an Escape never reaches PAM: the password typed after it unlocks alone.

stack_start

lock_by_ipc
check_within "$GUARD" "locked" compositor_locked
check_within "$GUARD" "the compositor confirmed the lock" state_is secure true
check_within "$GUARD" "armed" state_is armed true
sleep 0.5 # fixed sleep: a negative claim: nothing wakes the prompt by itself
check "the prompt sleeps" state_is prompt_awake false

press_key Escape
check_within "$GUARD" "Escape at a sleeping prompt wakes it" state_is prompt_awake true
sleep 0.5 # fixed sleep: a negative claim: Escape does not unlock
check "and does not unlock (compositor)" compositor_locked
check "and does not unlock (shell)" shell_status_is locked

type_text "typed-then-dropped"
epoch=$(state_field field_epoch)
press_key Escape
check_within "$GUARD" "Escape at the awake prompt hides it" state_is prompt_awake false
check "the field emptied with it (a new field epoch)" test "$(state_field field_epoch)" -gt "$epoch"
sleep 0.5 # fixed sleep: a negative claim: hiding the prompt does not unlock
check "still locked (compositor)" compositor_locked
check "still locked (shell)" shell_status_is locked

# Many presses in a burst, awake and asleep alternately: nothing but the prompt changes
send_input "key Escape" "key Escape" "key Escape" "key Escape" "key Escape" \
           "key Escape" "key Escape" "key Escape" "key Escape" "key Escape" "key Escape"
sleep 1 # fixed sleep: a negative claim: eleven presses decide nothing
check "eleven more presses: still locked (compositor)" compositor_locked
check "… (shell)" shell_status_is locked
check "… nothing was sent to PAM" test ! -e "$WORK/pam/check.log"
check "… no unlock was even decided" test "$(shell_log_count 'unlocked (')" = 0

# The prompt is awake after an odd number of presses: one more hides it, then the password
# (its first key wakes the prompt) unlocks — checked once, and right: nothing typed before
# the Escape went with it
press_key Escape
check_within "$GUARD" "(asleep again)" state_is prompt_awake false
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password typed after Escape unlocks" compositor_unlocked
check "ended authenticated" state_is last_end authenticated
log "password checks: $(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)"
check "checked once, right (the text before Escape was dropped)" \
    test "$(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)" = "right "
