# Caps Lock and the keypad. With Caps Lock on, letters come out as capitals — what reaches
# PAM is "LT…" for the keys l, t — and the prompt says Caps Lock is on (the shell knows it
# from the case of what is typed: Qt reports no Caps Lock state); off again, it says
# nothing. Keypad digits with Num Lock on are digits, and the keypad's Enter submits.

LOCKTEST_PASSWORD="LT-test-905"
stack_start

lock_by_ipc
check_within 5 "locked" compositor_locked
check_within 5 "armed" state_is armed true
wake_prompt || fail "the prompt did not wake"
check "Caps Lock not known yet" state_is caps_lock ""

press_key Caps_Lock
keys_text "lt"
check_within 2 "letters typed with Caps Lock on: the shell knows it is on" state_is caps_lock true
screenshot_ppm caps-on
press_key Caps_Lock
type_text "-test-"
check_within 2 "off again: known off" state_is caps_lock false
screenshot_ppm caps-off
changed=$(prompt_region_changes caps-on caps-off)
log "pixels changed in the prompt between Caps Lock on and off: $changed"
check "the prompt shows something while Caps Lock is on that it does not show after" test "$changed" -gt 50

press_key Num_Lock
press_key KP_9
press_key KP_0
press_key KP_5
press_key KP_Enter
check_within 10 "Caps Lock letters, keypad digits and the keypad's Enter: unlocks" compositor_unlocked
log "password checks: $(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)"
check "PAM got exactly LT-test-905" test "$(password_details | tail -n 1)" = "$(password_detail_of "$LOCKTEST_PASSWORD")"
