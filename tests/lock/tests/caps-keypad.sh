# Caps Lock and the keypad. With Caps Lock on, letters come out as capitals — what reaches
# PAM is "LT…" for the keys l, t. The prompt says "Caps Lock is on" from the keyboard's LED
# (singletons/lock/CapsLockLed.qml), read when the prompt wakes and at each key; the nested
# compositor has no keyboard and so no LED, so the test writes the one the shell reads
# (caps_led: H2S_LOCK_LEDS_DIR) — on, off, or not there (unknown: no indicator). What the
# LED says stays the shell's only source: nothing is guessed from the keys, so nothing
# carries over to the next lock (the stale case at the end). Keypad digits with Num Lock on
# are digits, and the keypad's Enter submits.

LOCKTEST_PASSWORD="LT-test-905"
stack_start

caps_led none
lock_by_ipc
check_within "$GUARD" "locked" compositor_locked
check_within "$GUARD" "armed" state_is armed true
wake_prompt || fail "the prompt did not wake"
sleep 0.5 # fixed sleep: a negative claim: with no LED, the wake shows nothing of Caps Lock
check "no LED: Caps Lock unknown, no indicator" state_is caps_lock ""

caps_led 1
press_key Caps_Lock
keys_text "lt"
check_within "$GUARD" "the LED on: the shell says Caps Lock is on" state_is caps_lock true
screenshot_ppm caps-on
caps_led 0
press_key Caps_Lock
type_text "-test-"
check_within "$GUARD" "the LED off: off" state_is caps_lock false
screenshot_ppm caps-off
changed=$(prompt_region_changes caps-on caps-off)
log "pixels changed in the prompt between Caps Lock on and off: $changed"
check "the prompt shows something while Caps Lock is on that it does not show after" test "$changed" -gt 50

caps_led none
press_key Num_Lock
check_within "$GUARD" "the LED gone: unknown again, no indicator" state_is caps_lock ""
caps_led 1
press_key KP_9
check_within "$GUARD" "the LED back on: on (read at a key)" state_is caps_lock true
press_key KP_0
press_key KP_5
press_key KP_Enter
check_within 10 "Caps Lock letters, keypad digits and the keypad's Enter: unlocks" compositor_unlocked
log "password checks: $(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)"
check "PAM got exactly LT-test-905" test "$(password_details | tail -n 1)" = "$(password_detail_of "$LOCKTEST_PASSWORD")"

# Caps Lock on at the unlock, turned off at the desktop, locked again: the new lock says
# nothing of Caps Lock (it used to claim it was on, from the keys of the lock before)
press_key Num_Lock
caps_led 0
lock_by_ipc
check_within "$GUARD" "locked again" compositor_locked
check_within "$GUARD" "armed again" state_is armed true
check "before the prompt wakes: unknown (nothing of the last lock kept)" state_is caps_lock ""
wake_prompt || fail "the prompt did not wake"
check_within "$GUARD" "at the wake: read from the LED, off" state_is caps_lock false
