# The test bed checks its fingerprint stand-in: a conversation whose PAM helper dies —
# what Quickshell's PamContext.abort() does, SIGKILL without pam_end — must end on its own
# instead of lingering, where it could take an answer meant for a later conversation.
# The helper is killed from here, which imitates an abort; what the shell does about its
# conversation dying is not what this checks.

stack_start --methods "password fingerprint"

lock_by_ipc
check_within 5 "lock by IPC locks the compositor" compositor_locked
check_within 5 "a fingerprint conversation is waiting" _one_finger_waiter
waiter=$(finger_waiters)
helper=$(awk '{ print $4 }' "/proc/$waiter/stat")
log "conversation $waiter, PAM helper $helper ($(tr '\0' ' ' < "/proc/$helper/cmdline" | cut -c1-80))"
check "the PAM helper is a child of the shell under test" \
    test "$(awk '{ print $4 }' "/proc/$helper/stat")" = "$SHELL_PID"

kill -KILL "$helper"
check_within 2 "the orphaned conversation ends by itself" test ! -e "/proc/$waiter"
check "it says why" grep -q "orphaned $waiter" "$WORK/finger/log"
check "it left no waiting file behind" test ! -e "$WORK/finger/waiting.$waiter"
check "the compositor is still locked" compositor_locked
