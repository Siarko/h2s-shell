# The methods script fails (exits non-zero, prints nothing): the lock goes on with the
# password fallback — in the test bed a stand-in for the system-wide config that denies everything — so a typed
# password gets a visible "Authentication failed", never a permanent "Verifying…".

methods_script=$WORK/failing-methods.sh
printf '#!%s\necho "methods script: deliberately failing" >&2\nexit 3\n' "$(command -v bash)" > "$methods_script"
stack_start --methods-script "$methods_script"

lock_by_ipc --any-safe-config
check_within 5 "locked" compositor_locked
check_within 5 "the methods are known (after the failure)" state_is methods_status known
check "the password falls back to the fallback (the test's stand-in for the system-wide config, which denies)" \
    state_is password_config "$WORK/system-pam/h2s-shell-password"
check "the failure was logged, with its reason" \
    grep -aq "detecting the methods failed (the script exited with status 3)" "$WORK/shell.log"

wake_prompt || fail "the prompt did not wake"
type_text "anything"
press_key Return
check_within 10 "a visible error, not a stuck verification" state_is error "Authentication failed"
check "not verifying" state_is verifying false
check "still locked" compositor_locked
