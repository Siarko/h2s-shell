# The pointer at a lock surface: only somebody counts.
#
#   the lock appears under a resting pointer: the prompt stays asleep — through the fade
#   (Qt Quick re-sends the hover at the same place at every frame of it) and after;
#   a one-pixel move wakes it;
#   a press right as the lock appears (no waiting: the old rule dropped every pointer event
#   in a surface's first 300 ms) wakes it — the press is somebody.

stack_start

move_pointer 700 400
sleep 0.3 # fixed sleep: the move lands before the lock is asked for (another path, the IPC: no order between them)
lock_by_ipc
check_within "$GUARD" "locked under a resting pointer" compositor_locked
sleep 1.5 # fixed sleep: a negative claim: the resting pointer does not wake the prompt through the fade
check "the prompt stays asleep through the fade and after" state_is prompt_awake false
send_input "move 1 0"
check_within "$GUARD" "a one-pixel move wakes it" state_is prompt_awake true
unlock_for_test
check "out (the test password)" compositor_unlocked

shell_ipc lockscreen lock > /dev/null
wait_until 5 state_is surfaces 1 || abort "no lock surface"
send_input "click left"
check_within "$GUARD" "a press right as the lock appears wakes the prompt" state_is prompt_awake true
check_within "$GUARD" "locked" compositor_locked
unlock_for_test
check "out again" compositor_unlocked
