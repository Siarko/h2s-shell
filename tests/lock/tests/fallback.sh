# The password fallback, end to end. It is chosen from the machine as the methods script
# chooses the password config (LockIoRules.passwordFallback): the system-wide
# h2s-shell-password when readable. Here the "system" directory is the test's own
# (H2S_LOCK_SYSTEM_PAM_DIR) and that config is the test password stack — so the fallback
# can unlock, and nothing typed can reach the machine's real PAM.
#
# 1. The methods script fails: the fallback serves, and the right password unlocks.
# 2. The methods script names a password config PamContext cannot start: the first attempt
#    says so, the next one takes the fallback — and unlocks.

methods_script=$WORK/failing-methods.sh
printf '#!%s\necho "methods script: deliberately failing" >&2\nexit 3\n' "$(command -v bash)" > "$methods_script"
stack_start --methods-script "$methods_script" --system-password-stack

check_within 5 "the shell looked for its fallback" state_is fallback_known true
check "the fallback is the (test's) system-wide config" state_is password_fallback "$WORK/system-pam/h2s-shell-password"
lock_by_ipc --any-safe-config
check_within 5 "locked" compositor_locked
check_within 5 "the methods are known (after the failure)" state_is methods_status known
check "the password uses the fallback" state_is password_config "$WORK/system-pam/h2s-shell-password"
wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the right password unlocks through the fallback" compositor_unlocked
check "the test stack checked it" grep -qx right "$WORK/pam/check.log"

# The methods script now names a stack that is not there
printf '#!%s\nprintf "password\\t%s\\t%s\\n"\n' "$(command -v bash)" "$WORK/pam" "no-such-stack" > "$WORK/pam/methods.sh"
lock_by_ipc --any-safe-config
check_within 5 "locked again" compositor_locked
check_within 5 "the password config is the missing one" state_is password_config "$WORK/pam/no-such-stack"
wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the first attempt cannot start" state_is error "Password check could not start"
check "still locked" compositor_locked
checks_before=$(grep -c . "$WORK/pam/check.log")
wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the next attempt takes the fallback and unlocks" compositor_unlocked
check "the fallback (the test stack) checked it" lines_more_than "$checks_before" right "$WORK/pam/check.log"
