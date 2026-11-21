# The methods script prints nothing and exits 0: an empty answer. The lock takes the
# password fallback (the test's stand-in for the system-wide config, which denies everything): a visible error, never a
# permanent "Verifying…".

methods_script=$WORK/empty-methods.sh
printf '#!%s\nexit 0\n' "$(command -v bash)" > "$methods_script"
stack_start --methods-script "$methods_script"

lock_by_ipc --any-safe-config
check_within "$GUARD" "locked" compositor_locked
check_within "$GUARD" "the methods are known (an empty answer)" state_is methods_status known
check "the password falls back to the fallback (the test's stand-in for the system-wide config, which denies)" \
    state_is password_config "$WORK/system-pam/h2s-shell-password"
check "the fallback is said to be one" state_is methods.passwordSource fallback

wake_prompt || fail "the prompt did not wake"
type_text "anything"
press_key Return
check_within 10 "a visible error, not a stuck verification" state_is error "Authentication failed"
check "not verifying" state_is verifying false
check "still locked" compositor_locked
