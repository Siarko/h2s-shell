# The password fallback while the shell does not know yet which distribution it is on.
# The methods script cannot be run (the run's copy: no exec bit), so the shell asks the
# machine directly — and that question needs Distribution's answer, which is held back
# here (H2S_DISTRIBUTION_HOLD: while the file is there, Distribution does not answer).
#
# 1. Held: the methods script's failure is seen, but the fallback stays not known — no
#    answer is made up from the silence (not "not NixOS").
# 2. Let go: the question is asked when Distribution answers (H2S_DISTRIBUTION=nixos), and
#    the fallback is known: the (test's) system-wide config.
# 3. Without that config, on NixOS: `login` in that directory, Distribution's answer.

chmod -x "$LOCKTEST_SHELL/scripts/lock-auth-methods.sh"
hold=$WORK/distribution-hold
: > "$hold"
stack_start --shell-env H2S_DISTRIBUTION=nixos --shell-env H2S_DISTRIBUTION_HOLD="$hold"

check_within "$GUARD" "the methods script's failure is seen" \
    test "$(shell_log_count 'password fallback: no answer from the methods script')" = 1
check "the distribution not known: the fallback is not known either" state_is fallback_known false

rm "$hold"
check_within "$GUARD" "the distribution answered: the fallback is known" state_is fallback_known true
check "… the system-wide config" state_is password_fallback "$WORK/system-pam/h2s-shell-password"

rm "$WORK/system-pam/h2s-shell-password"
shell_ipc lockscreen lock > /dev/null
check_within "$GUARD" "locked" compositor_locked
check_within "$GUARD" "NixOS without the system-wide config: login there" \
    state_is password_fallback "$WORK/system-pam/login"
