# A shell restarted while locked asks Hyprland (`hyprctl`) whether it would give the lock
# back before asking for it. A hyprctl that never answers used to stall that for good —
# no prompt, and the IPC status saying "unlocked" over a locked session. Each question is
# now bounded (2 s); without an answer the lock is asked for anyway (the generic path).
# Here the shell's hyprctl is a stand-in that hangs (put first on its PATH); the nested
# Hyprland allows restoring, so the lock is given back.

mkdir -p "$WORK/hang-bin"
printf '#!%s\nexec sleep 30\n' "$(command -v bash)" > "$WORK/hang-bin/hyprctl"
chmod +x "$WORK/hang-bin/hyprctl"
stack_start --shell-path "$WORK/hang-bin"

lock_by_ipc
check_within "$GUARD" "locked" compositor_locked
check_within "$GUARD" "confirmed" state_is secure true

start_lock_watch hang
old_shell=$SHELL_PID
signal_shell KILL
check_within 10 "the launcher starts a new shell" wait_for_new_shell "$old_shell" 10
check_within 15 "Hyprland's silence is noticed" grep -aq "Hyprland did not answer (hyprctl, 2 s each): asking for the lock back anyway" "$WORK/shell.log"
check_within 10 "and the lock is asked for and given back" state_is phase locked
check_within "$GUARD" "confirmed" state_is secure true
sleep 1 # fixed sleep: a negative claim: the lock watch sees no unlock after the restart either
stop_lock_watch
check "the compositor never reported unlocked" lock_watch_never_unlocked
wake_prompt || fail "the prompt did not wake"
check_within "$GUARD" "the methods are known" state_is armed true
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked
