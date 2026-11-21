# The test bed checks its fingerprint stand-in: a conversation whose PAM helper dies —
# what Quickshell's PamContext.abort() does, SIGKILL without pam_end — must end on its own
# instead of lingering, where it could take an answer meant for a later conversation.
# The helper is killed from here, which imitates an abort; what the shell does about its
# conversation dying is not what this checks.

stack_start --methods "password fingerprint"

lock_by_ipc
check_within "$GUARD" "lock by IPC locks the compositor" compositor_locked
wait_until 5 _one_finger_waiter || abort "no single fingerprint conversation waiting (found: $(finger_waiters | tr '\n' ' '))"
waiter=$(finger_waiters)
helper=$(awk '{ print $4 }' "/proc/$waiter/stat" 2> /dev/null)
log "conversation $waiter, PAM helper ${helper:-?} ($(tr '\0' ' ' < "/proc/$helper/cmdline" 2> /dev/null | cut -c1-80))"

# The process about to be SIGKILLed must be the shell's PAM helper and nothing else: had
# the conversation already been re-parented, its parent would be the nearest subreaper
# (systemd --user, say). So: a child of the shell under test, running Quickshell's
# binary, carrying this run's marker — or nothing is killed.
[[ "$helper" =~ ^[0-9]+$ ]] || abort "cannot read the conversation's parent"
helper_parent=$(awk '{ print $4 }' "/proc/$helper/stat" 2> /dev/null)
[ "$helper_parent" = "$SHELL_PID" ] \
    || abort "the conversation's parent $helper is not a child of the shell under test (its parent: ${helper_parent:-gone}): not killing it"
[ "$(readlink -f "/proc/$helper/exe" 2> /dev/null)" = "$(_quickshell_binary)" ] \
    || abort "the conversation's parent $helper does not run Quickshell ($(readlink "/proc/$helper/exe" 2> /dev/null)): not killing it"
[ "$(process_env "$helper" LOCKTEST_RUN_ID)" = "$LOCKTEST_RUN_ID" ] \
    || abort "the conversation's parent $helper does not carry this run's marker: not killing it"
pass "the PAM helper is the shell under test's child, running Quickshell, of this run"

kill -KILL "$helper"
check_within "$GUARD" "the orphaned conversation ends by itself" test ! -e "/proc/$waiter"
check "it says why" grep -q "orphaned $waiter" "$WORK/finger/log"
check "it left no waiting file behind" test ! -e "$WORK/finger/waiting.$waiter"
check "the compositor is still locked" compositor_locked
