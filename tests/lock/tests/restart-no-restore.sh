# The shell dies while locked, with Hyprland's misc:allow_session_lock_restore OFF (its
# default, and the owner's config as it is today). Hyprland keeps the session locked and
# shows its "lockscreen app died" screen, and refuses a new lock — and kills the client that
# asked (observed: `wl_display#1: error 0: invalid object …`, Quickshell's get_lock_surface on
# the lock Hyprland destroyed when refusing it). So the restarted shell asks Hyprland first
# (getoption, locked) and does not ask for a lock it would be refused: it must not claim
# "unlocked" (its status says "compositor-locked"), must not loop hot (it asks Hyprland again
# after 5 s, 10 s, 20 s, … up to a minute), must not get itself killed (the launcher has
# nothing to restart), and the compositor stays locked.
#
# The way back without killing Hyprland: switch the setting on at runtime — from a TTY,
# `hyprctl -i 0 eval 'hl.config({ misc = { allow_session_lock_restore = true } })'`
# (`hyprctl keyword` is gone with the Lua config: "unknown request"); the shell's next look
# then takes the lock, and the owner gets a prompt.

stack_start --no-lock-restore --hyprland-debug

lock_by_ipc
check_within 5 "locked" compositor_locked
check_within 5 "confirmed" state_is secure true

old_shell=$SHELL_PID
start_lock_watch no-restore
signal_shell KILL
check_within 10 "the launcher starts a new shell" wait_for_new_shell "$old_shell" 10
check_within 10 "the new shell's lock is refused by the compositor" state_is restore_pending true
check "it says why" grep -aq "the compositor refused to let this shell take back the lock it had" "$WORK/shell.log"
check "the shell does not claim unlocked: its status is compositor-locked" shell_status_is compositor-locked
check "the shell counts as locked for the rest of the shell (no idle lock, no screensaver logic)" state_is screensaver true
check "the compositor is still locked" compositor_locked
check "the marker file still says locked" marker_file_is locked
check "it did not ask for a lock Hyprland would refuse" test "$(shell_log_count '"type":"lockRequested","source":"restore"')" = 0
looks_at_refusal=$(shell_log_count "taking the lock back again in")
refused_shell=$SHELL_PID
sleep 12
looks=$(( $(shell_log_count "taking the lock back again in") - looks_at_refusal ))
log "looks at Hyprland in 12 s after the first refusal: $looks"
check "no hot loop: at most 2 more looks in 12 s (after 5 s, then 10 s)" test "$looks" -le 2
check "… but it does look again" test "$looks" -ge 1
check "still no lock asked for" test "$(shell_log_count '"type":"lockRequested","source":"restore"')" = 0
check "the shell was not killed, the launcher restarted nothing" test "$(_find_shell_pid)" = "$refused_shell"
check "the compositor is still locked" compositor_locked
check "the status still says compositor-locked" shell_status_is compositor-locked
shell_ipc lockscreen lock > /dev/null
sleep 1
check "a lock request meanwhile does not ask the compositor either" test "$(shell_log_count '"type":"lockRequested"')" = 1
check "… and the shell is still the same process" test "$(_find_shell_pid)" = "$refused_shell"

# The way back: the setting switched on at runtime (keyword is gone with the Lua config)
answer=$(hyprctl keyword misc:allow_session_lock_restore 1 2>&1)
log "hyprctl keyword misc:allow_session_lock_restore 1 → $answer"
answer=$(hyprctl eval 'hl.config({ misc = { allow_session_lock_restore = true } })' 2>&1)
log "hyprctl eval 'hl.config({ misc = { allow_session_lock_restore = true } })' → $answer"
option=$(hyprctl -j getoption misc:allow_session_lock_restore 2>&1 | tr -d '\n ')
log "getoption → $option"
check "hyprctl eval switches the setting on at runtime" grep -q '"bool":true' <<< "$option"
check_within 45 "the shell's next look takes the lock" state_is phase locked
check_within 5 "confirmed" state_is secure true
check "its status says locked" shell_status_is locked
stop_lock_watch
check "the compositor never reported unlocked throughout" lock_watch_never_unlocked
wake_prompt || fail "the prompt did not wake"
check_within 5 "the methods are known" state_is armed true
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked
check_within 3 "the marker says unlocked" state_is marker unlocked
log "Hyprland on the lock: $(sed 's/\x1b\[[0-9;]*m//g' "$WORK/hyprland.log" | grep -a -E 'SessionLock|sessionLock|lockscreen|relock|restore' | grep -v -i 'clock\|LED\|Mod index' | tr '\n' '|')"
