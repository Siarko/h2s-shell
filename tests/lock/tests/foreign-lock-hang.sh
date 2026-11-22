# On Hyprland every lock waits for a read of `hyprctl -j locked` (another program's lock would
# get the shell ended). A hyprctl that never answers — one that ignores the TERM of the
# `timeout` around it — must not hold the lock back: the read is taken as unknown at its
# deadline (2.5 s) and the lock is asked; the next lock reads again and comes too.

mkdir -p "$WORK/hang-bin"
printf '#!%s\ntrap "" TERM\nexec sleep 30\n' "$(command -v bash)" > "$WORK/hang-bin/hyprctl"
chmod +x "$WORK/hang-bin/hyprctl"
stack_start --shell-path "$WORK/hang-bin"

lock_by_ipc
check_within 10 "the lock comes all the same" compositor_locked
check "… after the read was taken as unknown" \
    grep -aq "could not read whether the compositor holds a session lock$" "$WORK/shell.log"
check_within "$GUARD" "confirmed" state_is secure true
wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked

lock_by_ipc
check_within 10 "a second lock: read again (still no answer), and it comes" compositor_locked
check_within "$GUARD" "confirmed" state_is secure true
wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked
