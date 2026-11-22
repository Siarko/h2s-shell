# Keys right after waking by a key are not lost: the key that wakes the prompt
# is the first character, then a wrong character, Backspace, the rest of the password and
# Enter, all typed at once while the prompt is still fading in — and it unlocks. Then an
# Enter right after a key wake, alone, is refused as empty rather than sent.
#
# First the screensaver (after 5 s idle) takes the keyboard: a key at it wakes the screen and
# reaches no window — the stand-in desktop window, focused, records every key it gets — and
# the keyboard is given back at once: a key during its (long, 5 s) fade out reaches the
# window while the screensaver's surface is still mapped.

stack_start --window --settings '{"lockscreen.screensaverEnabled": true, "lockscreen.screensaverTimeout": 5,
    "lockscreen.fadeOutDuration": 5000}'

screensaver_layer() {
    hyprctl -j layers | python3 -I -c '
import json, sys
layers = json.load(sys.stdin)
found = any(surface.get("namespace") == "screensaver"
            for monitor in layers.values() for level in monitor["levels"].values() for surface in level)
sys.exit(0 if found else 1)'
}
window_keys() { grep -c '^key' "$WORK/window.log"; }
window_keys_above() { [ "$(window_keys)" -gt "$1" ]; }
# window_keys_stay <seconds> <count>: the window got no key beyond <count>, polled for that long
window_keys_stay() {
    local deadline=$((${EPOCHREALTIME/[.,]/} + $1 * 1000000))
    while [ "${EPOCHREALTIME/[.,]/}" -lt "$deadline" ]; do
        [ "$(window_keys)" -le "$2" ] || return 1
        sleep 0.1 # fixed sleep: the poll's pause, not a wait for anything
    done
    return 0
}

# ---- The screensaver takes the keyboard ----
press_key a
check_within "$GUARD" "a key on the desktop reaches the window (it has the keyboard)" window_keys_above 0
before=$(window_keys)
check_within "$GUARD" "5 s without input: the screensaver shows" state_is screensaver true
check_within "$GUARD" "… its layer is on the screen" screensaver_layer
press_key a
check_within "$GUARD" "a key at the screensaver wakes the screen" state_is screensaver false
check "… and reaches no window" window_keys_stay 1 "$before"
press_key a
check_within "$GUARD" "during the fade out: keys reach the window again" window_keys_above "$before"
check "… while the screensaver's surface is still mapped (the keyboard given back before the fade out ends)" screensaver_layer

lock_by_ipc
check_within "$GUARD" "locked" compositor_locked
check_within "$GUARD" "the compositor confirmed the lock" state_is secure true
sleep 0.5 # fixed sleep: a negative claim: nothing wakes the prompt by itself
check "the prompt sleeps" state_is prompt_awake false

# An Enter that wakes the prompt: nothing typed, nothing sent, refused as empty
press_key Return
check_within "$GUARD" "Enter wakes the prompt" state_is prompt_awake true
check_within "$GUARD" "and is refused as an empty password" state_is refusal empty
check "nothing was checked" test ! -e "$WORK/pam/check.log"

# Back to sleep: Escape at an awake prompt hides it (as its time-out would, 10 s later)
press_key Escape
check_within "$GUARD" "Escape puts the prompt back to sleep" state_is prompt_awake false
check "… still locked" compositor_locked
check "… the refusal is gone with it" state_is refusal ""

first=${LOCKTEST_PASSWORD:0:1}
rest=${LOCKTEST_PASSWORD:1}
# One burst, no waiting in between: the first key wakes the prompt
send_input "type $first" "type x" "key BackSpace" "type $rest" "key Return"
check_within 10 "the key-woken password, with a typo corrected, unlocks" compositor_unlocked
log "password checks: $(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)"
check "it was checked once, and right" test "$(tr '\n' ' ' < "$WORK/pam/check.log" 2> /dev/null)" = "right "
