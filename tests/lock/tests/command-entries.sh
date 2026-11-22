# The command entries, each writing a line to a file when it runs: one when every screen
# is dark (the screensaver after 5 s), one at a lock, one before sleep — each with its
# "back" at the end of its own moment.
#
#   locked by the IPC: the lock entry's go; idle under the lock: the dark entry's go; the
#   prompt woken (input): the dark entry's back, not the lock's; the unlock: the lock's back;
#   the screensaver up, then logind's PrepareForSleep: the sleep entry's go; the resume
#   (PrepareForSleep(false)): the sleep entry's back and the dark entry's (a resume is
#   somebody back);
#   the screensaver again, then locked, then the shell killed: the launcher's new shell locks
#   again (the lock marker) and reads the record of the commands that ran — no second go of
#   the lock entry or the dark one; the prompt woken runs the dark back, the unlock the lock
#   back, once each.

commands=$WORK/commands
: > "$commands"
entry() { printf '{"id": "%s", "moment": "%s", "monitors": null, "go": "echo %s >> %s", "back": "echo %s >> %s"}' \
    "$1" "$2" "$3" "$commands" "$4" "$commands"; }
stack_start --logind --settings '{"lockscreen.screensaverEnabled": true, "lockscreen.screensaverTimeout": 5,
    "lockscreen.lockscreenEnabled": false, "lockscreen.lockOnSleep": false, "lockscreen.lockedScreenOffTimeout": 0,
    "lockscreen.commandEntries": ['"$(entry dark dark dark back),$(entry lock lock locked unlocked),$(entry sleep sleep sleep wake)"']}'

commands_are() { [ "$(tr '\n' ' ' < "$commands")" = "$1" ]; }
locked_and_secure() { compositor_locked && state_is secure true; }

# ---- Locked: the lock entry; idle under it: the dark entry ----
lock_by_ipc
check_within "$GUARD" "locked by the IPC" locked_and_secure
check_within "$GUARD" "… the lock entry's go ran" commands_are "locked "
check_within "$GUARD" "5 s without input under the lock: the dark entry's go" commands_are "locked dark "
check_within "$GUARD" "the lock is ready for a password (test stack)" _password_stack_is_ours_and_safe
wake_prompt || fail "the prompt did not wake"
check_within "$GUARD" "input at the lock screen: the dark entry's back, not the lock's" commands_are "locked dark back "
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked
check_within "$GUARD" "the unlock: the lock entry's back" commands_are "locked dark back unlocked "

# ---- Before sleep ----
check_within "$GUARD" "5 s without input: the dark entry's go again" commands_are "locked dark back unlocked dark "
logind_signal sleep
check_within "$GUARD" "PrepareForSleep: the sleep entry's go" commands_are "locked dark back unlocked dark sleep "
check "not locked (lock before sleep off)" compositor_unlocked
logind_signal wake
# The two backs start together, detached: either may write first
resumed() { commands_are "locked dark back unlocked dark sleep wake back " || commands_are "locked dark back unlocked dark sleep back wake "; }
check_within "$GUARD" "the resume: the sleep entry's back and the dark one's" resumed

# ---- Restarted while locked ----
last_is_dark() { [ "$(tail -n 1 "$commands")" = dark ]; }
check_within "$GUARD" "5 s after the resume: the dark entry's go" last_is_dark
before=$(tr '\n' ' ' < "$commands")
lock_by_ipc
check_within "$GUARD" "locked again: the lock entry's go" commands_are "${before}locked "
record_kept() { grep -q '"moment":"lock"' "$XDG_RUNTIME_DIR/h2s-shell-idle-commands" && grep -q '"moment":"dark"' "$XDG_RUNTIME_DIR/h2s-shell-idle-commands"; }
check_within "$GUARD" "the record of the commands that ran is kept in the runtime directory" record_kept
before=$(tr '\n' ' ' < "$commands")
old_shell=$SHELL_PID
signal_shell KILL
check_within "$GUARD" "the killed shell is gone" test ! -e "/proc/$old_shell"
check_within 10 "the launcher starts a new shell" wait_for_new_shell "$old_shell" 10
check_within 10 "the new shell locks again (the marker)" state_is phase locked
# The order is the order the gos ran in (under load the screensaver's may come before the lock)
record_read() { grep -a 'commands that ran before the restart: ' "$WORK/shell.log" | grep -q 'lock (lock)' \
    && grep -a 'commands that ran before the restart: ' "$WORK/shell.log" | grep -q 'dark (dark)'; }
check_within "$GUARD" "the new shell read the record" record_read
sleep 7 # fixed sleep: a negative claim: past the screensaver's 5 s under the lock, no go runs again
check "no second go of the lock entry or the dark one" commands_are "$before"
check_within "$GUARD" "the lock is ready for a password (test stack)" _password_stack_is_ours_and_safe
wake_prompt || fail "the new shell's prompt did not wake"
check_within "$GUARD" "input at the lock screen: the kept dark back" commands_are "${before}back "
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked
check_within "$GUARD" "the unlock: the kept lock back, once" commands_are "${before}back unlocked "
record_empty() { [ ! -s "$XDG_RUNTIME_DIR/h2s-shell-idle-commands" ]; }
check_within "$GUARD" "none due any more: the record emptied" record_empty
check "no protocol error" no_protocol_errors
