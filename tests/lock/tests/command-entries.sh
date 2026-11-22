# The command entries, each writing a line to a file when it runs: one when every screen
# is dark (the screensaver after 5 s), one at a lock, one before sleep — each with its
# "back" at the end of its own moment.
#
#   locked by the IPC: the lock entry's go; idle under the lock: the dark entry's go; the
#   prompt woken (input): the dark entry's back, not the lock's; the unlock: the lock's back;
#   the screensaver up, then logind's PrepareForSleep: the sleep entry's go; the resume
#   (PrepareForSleep(false)): the sleep entry's back, then the dark entry's (a resume is
#   somebody back).

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
check_within "$GUARD" "the resume: the sleep entry's back, then the dark one's" \
    commands_are "locked dark back unlocked dark sleep wake back "
check "no protocol error" no_protocol_errors
