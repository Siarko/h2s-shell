# The password fallback, end to end. It is chosen from the machine as the methods script
# chooses the password config (LockIoRules.passwordFallback): the system-wide
# h2s-shell-password when readable. Here the "system" directory is the test's own
# (H2S_LOCK_SYSTEM_PAM_DIR) and that config is the test password stack — so the fallback
# can unlock, and nothing typed can reach the machine's real PAM.
#
# 1. The methods script fails: the fallback serves, and the right password unlocks.
# 2. The methods script names a password config PamContext cannot start: the first attempt
#    says so, the next one takes the fallback — and unlocks.
# 3. Without the system-wide config, on NixOS: `login` in that directory. The shell is told
#    it is on NixOS (H2S_DISTRIBUTION=nixos: Distribution and the methods script both take
#    it; 1 and 2 do not depend on it: a readable system-wide config wins on every
#    system).
# 4. The shell's own methods script (which also answers what the fallback depends on)
#    cannot be run: the shell asks the machine itself, so the fallback still follows the
#    system-wide config coming back, and unlocks; and going away again, on NixOS: `login`.

methods_script=$WORK/failing-methods.sh
printf '#!%s\necho "methods script: deliberately failing" >&2\nexit 3\n' "$(command -v bash)" > "$methods_script"
stack_start --methods-script "$methods_script" --system-password-stack --shell-env H2S_DISTRIBUTION=nixos

check_within "$GUARD" "the shell looked for its fallback" state_is fallback_known true
check "the fallback is the (test's) system-wide config" state_is password_fallback "$WORK/system-pam/h2s-shell-password"
lock_by_ipc --any-safe-config
check_within "$GUARD" "locked" compositor_locked
check_within "$GUARD" "the methods are known (after the failure)" state_is methods_status known
check "the password uses the fallback" state_is password_config "$WORK/system-pam/h2s-shell-password"
wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the right password unlocks through the fallback" compositor_unlocked
check "the test stack checked it" grep -qx right "$WORK/pam/check.log"

# The methods script now names a stack that is not there
printf '#!%s\nprintf "password\\t%s\\t%s\\n"\n' "$(command -v bash)" "$WORK/pam" "no-such-stack" > "$WORK/pam/methods.sh"
lock_by_ipc --any-safe-config
check_within "$GUARD" "locked again" compositor_locked
check_within "$GUARD" "the password config is the missing one" state_is password_config "$WORK/pam/no-such-stack"
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

# No system-wide config any more; the methods script names the test stack, so that this
# lock can be ended (the fallback, `login` in the test's directory, is not there to start)
printf '#!%s\nprintf "password\\t%s\\t%s\\n"\n' "$(command -v bash)" "$WORK/pam" "password" > "$WORK/pam/methods.sh"
rm "$WORK/system-pam/h2s-shell-password"
lock_by_ipc --any-safe-config
check_within "$GUARD" "locked a third time" compositor_locked
check_within "$GUARD" "NixOS without the system-wide config: the fallback is login there" \
    state_is password_fallback "$WORK/system-pam/login"
check "the methods script was the one that answered" test "$(shell_log_count 'password fallback: no answer from the methods script')" = 0
check_within "$GUARD" "the password config is the test stack" state_is password_config "$WORK/pam/password"
unlock_for_test || fail "the third lock did not end"

# The shell's methods script cannot be run (the run's copy: no exec bit). Detection fails,
# so the password takes the fallback — and what the fallback depends on is asked directly
script=$LOCKTEST_SHELL/scripts/lock-auth-methods.sh
chmod -x "$script"
cp "$WORK/pam/password" "$WORK/system-pam/h2s-shell-password"
lock_by_ipc --any-safe-config
check_within "$GUARD" "locked with a methods script that cannot run" compositor_locked
check_within "$GUARD" "the fallback follows the machine without the script: the system-wide config again" \
    state_is password_fallback "$WORK/system-pam/h2s-shell-password"
check_within "$GUARD" "the shell says once that it asked the machine directly" \
    test "$(shell_log_count 'password fallback: no answer from the methods script')" = 1
# The failed detection took the fallback as it was at that moment (login: not there), the
# direct answer came after it; the attempt after one that cannot start takes the fallback
# as it is now. Which of the two this attempt meets is a matter of timing, so: one
# attempt, and a second only when the first could not start
checks_before=$(grep -c . "$WORK/pam/check.log")
unlocked_or_refused() { compositor_unlocked || state_is error "Password check could not start"; }
wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
wait_until 10 unlocked_or_refused
if ! compositor_unlocked; then
    wake_prompt || fail "the prompt did not wake"
    type_text "$LOCKTEST_PASSWORD"
    press_key Return
fi
check_within 10 "the right password unlocks though the methods script cannot run" compositor_unlocked
check "the fallback (the test stack) checked it" lines_more_than "$checks_before" right "$WORK/pam/check.log"

# Still without the script, the system-wide config gone again: the system the seam names
# decides (NixOS: login; any other system would take the shipped config). Nothing is typed
# and the lock is left standing: neither can be started here
rm "$WORK/system-pam/h2s-shell-password"
shell_ipc lockscreen lock > /dev/null
check_within "$GUARD" "locked a last time" compositor_locked
check_within "$GUARD" "without the script, NixOS without the system-wide config: login" \
    state_is password_fallback "$WORK/system-pam/login"
check "that was said once, not at every lock" test "$(shell_log_count 'password fallback: no answer from the methods script')" = 1
check "the machine itself always answered" test "$(shell_log_count 'password fallback: the machine could not be asked either')" = 0
