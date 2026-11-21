# The screensaver and the lock screen together: the screensaver after 5 s idle, no idle lock
# (the locks come from logind's Lock and the IPC, so that each order can be set up), the
# screensaver commands on, each writing a line to a file — they run on idleness, so the file
# says when the shell saw the user go and come back, also under the lock.
#
#   screensaver up, then a lock: the lock takes the screen, the screensaver's layer goes; the
#   prompt wakes and takes the password; after the unlock no screensaver (the user is back)
#   and the end command ran once;
#   screensaver up, a lock, and an unlock without input (logind's Unlock): an unlock counts
#   as somebody back (IdleRules), so the screensaver does not show at once and the end
#   command runs; with still no input it comes again after its time; input ends it;
#   locked first, then idle: the shell sees the idle (the start command runs) and the
#   screensaver stays off the screen; the lock still works: the prompt wakes (the end
#   command runs) and the password unlocks.

commands=$WORK/screensaver-commands
: > "$commands"
stack_start --logind --settings '{"lockscreen.screensaverEnabled": true, "lockscreen.screensaverTimeout": 5,
    "lockscreen.lockscreenEnabled": false, "lockscreen.screensaverCommands": true,
    "lockscreen.screensaverStartCommand": "echo start >> '"$commands"'",
    "lockscreen.screensaverEndCommand": "echo end >> '"$commands"'"}'

screensaver_layer() {
    hyprctl -j layers | python3 -I -c '
import json, sys
layers = json.load(sys.stdin)
found = any(surface.get("namespace") == "screensaver"
            for monitor in layers.values() for level in monitor["levels"].values() for surface in level)
sys.exit(0 if found else 1)'
}
no_screensaver_layer() { ! screensaver_layer; }
# no_layer_for <seconds>: the screensaver's layer is never on the screen, polled for that long
# — the time an unwanted one would stay (its fade out: 400 ms with the defaults)
no_layer_for() {
    local deadline=$((${EPOCHREALTIME/[.,]/} + $1 * 1000000))
    while [ "${EPOCHREALTIME/[.,]/}" -lt "$deadline" ]; do
        screensaver_layer && return 1
    done
    return 0
}
commands_are() { [ "$(tr '\n' ' ' < "$commands")" = "$1" ]; }
locked_and_secure() { compositor_locked && state_is secure true; }
unlock_by_password() {
    wake_prompt || { fail "$1: the prompt did not wake"; return; }
    type_text "$LOCKTEST_PASSWORD"
    press_key Return
    check_within 10 "$1: the password unlocks" compositor_unlocked
    # The screensaver's window, not even mapped clear for a moment: a full-screen window
    # over the desktop until its fade out ended
    check "$1: no screensaver layer in the second after the unlock" no_layer_for 1
}

# ---- Screensaver up, then a lock ----
check_within "$GUARD" "5 s without input: the screensaver shows" state_is screensaver true
check_within "$GUARD" "… its layer is on the screen" screensaver_layer
check_within "$GUARD" "… the start command ran" commands_are "start "
logind_signal lock
check_within "$GUARD" "logind's Lock while the screensaver shows: locked" locked_and_secure
check_within "$GUARD" "the screensaver's layer goes under the lock" no_screensaver_layer
check "… and stays gone" no_screensaver_layer
check_within "$GUARD" "the lock is ready for a password (test stack)" _password_stack_is_ours_and_safe
unlock_by_password "over the screensaver"
check_within "$GUARD" "after the unlock no screensaver: the user is back" state_is screensaver false
check "… nor its layer" no_screensaver_layer
check_within "$GUARD" "the end command ran once, when the user came back" commands_are "start end "

# ---- Screensaver up, a lock, an unlock without input ----
check_within "$GUARD" "idle again: the screensaver shows" state_is screensaver true
check_within "$GUARD" "… the start command ran again" commands_are "start end start "
logind_signal lock
check_within "$GUARD" "locked over the screensaver" locked_and_secure
check_within "$GUARD" "… its layer gone" no_screensaver_layer
logind_signal unlock
check_within "$GUARD" "logind's Unlock: unlocked" compositor_unlocked
check "an unlock counts as somebody back: no screensaver in the second after it" no_layer_for 1
check "… the shell says so" state_is screensaver false
check_within "$GUARD" "… and the end command ran" commands_are "start end start end "
check_within "$GUARD" "still no input: the screensaver comes again after its time" screensaver_layer
check_within "$GUARD" "… a new idle period: the start command ran" commands_are "start end start end start "
move_pointer 700 400
move_pointer 720 410
check_within "$GUARD" "input ends it" state_is screensaver false
check_within "$GUARD" "… its layer goes" no_screensaver_layer
check_within "$GUARD" "… and the end command ran" commands_are "start end start end start end "

# ---- Locked first, then idle ----
lock_by_ipc
check_within "$GUARD" "locked by the IPC" locked_and_secure
check_within "$GUARD" "5 s without input under the lock: the shell sees the idle (start command)" \
    commands_are "start end start end start end start "
check "the screensaver stays off the screen: the lock is what shows" no_screensaver_layer
check "still locked" locked_and_secure
check "the prompt is asleep (nothing woke it)" state_is prompt_awake false
check_within "$GUARD" "the lock is ready for a password (test stack)" _password_stack_is_ours_and_safe
unlock_by_password "after idle under the lock"
check "the end command ran when the prompt was woken" commands_are "start end start end start end start end "
check_within "$GUARD" "no screensaver after the unlock" state_is screensaver false
check "… nor its layer" no_screensaver_layer
check "no protocol error" no_protocol_errors
