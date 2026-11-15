# Escape (kept as an unlock for now: the owner's decision, plan section 5) unlocks only at
# an awake prompt; at a sleeping prompt it only wakes it.

stack_start

lock_by_ipc
check_within 5 "locked" compositor_locked
check_within 5 "the compositor confirmed the lock" state_is secure true
sleep 0.5
check "the prompt sleeps" state_is prompt_awake false

press_key Escape
check_within 3 "Escape at a sleeping prompt wakes it" state_is prompt_awake true
sleep 0.5
check "and does not unlock (compositor)" compositor_locked
check "and does not unlock (shell)" shell_status_is locked

press_key Escape
check_within 5 "Escape at the awake prompt unlocks" compositor_unlocked
check "the lock ended by escape" state_is last_end escape
check "the shell says unlocked" shell_status_is unlocked
