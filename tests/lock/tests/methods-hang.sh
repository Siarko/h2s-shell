# The methods script never answers: after the rules' `detect` time-out (5 s) the lock goes
# on with the password fallback (the test's stand-in for the system-wide config, which denies everything), and a
# password typed then gets its verdict — never a permanent "Verifying…".

methods_script=$WORK/hanging-methods.sh
printf '#!%s\nwhile :; do read -r -t 1 _ < /dev/null; sleep 1; done\n' "$(command -v bash)" > "$methods_script"
stack_start --methods-script "$methods_script"

shell_ipc lockscreen lock > /dev/null
check_within 5 "locked" compositor_locked
check "the methods are being asked" state_is methods_status detecting
check_within 8 "after the time-out the fallback serves" state_is methods_status known
check "the password falls back to the fallback (the test's stand-in for the system-wide config, which denies)" \
    state_is password_config "$WORK/system-pam/h2s-shell-password"
check "the time-out was logged" grep -aq "detecting the methods timed out" "$WORK/shell.log"

wake_prompt || fail "the prompt did not wake"
type_text "anything"
press_key Return
check_within 10 "a visible error, not a stuck verification" state_is error "Authentication failed"
check "not verifying" state_is verifying false
