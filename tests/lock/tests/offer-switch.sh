# The "Fingerprint" switch (lockscreen.offerFingerprint), changed by a profile while the lock
# screen shows: switched off, the reader's conversation ends and the fingerprint is no longer
# offered, the password still unlocks; switched on again, a new conversation waits. A lock
# taken while it is off never starts the reader. The profile depends on a fact of the test's
# own, set over the profiles IPC (`simulate`).

mkdir -p "$XDG_CONFIG_HOME/h2s_shell"
python3 -I -c '
import json, sys
profiles = [
    {"name": "Full", "enabled": True, "when": {}, "set": {}},
    {"name": "No finger", "enabled": True, "when": {"fact": "locktest.nofinger", "is": True},
     "set": {"lockscreen.offerFingerprint": False}},
]
json.dump({"profiles": json.dumps(profiles), "widgetPresets": "{}"}, open(sys.argv[1], "w"), indent=2)
' "$XDG_CONFIG_HOME/h2s_shell/config.json" || abort "cannot write the config"

stack_start --methods "password fingerprint"

offered_is() { state_is settings.offered.fingerprint "$1"; }

# ---- Switched off and on while locked ----
lock_by_ipc
check_within "$GUARD" "locked" compositor_locked
check_within "$GUARD" "a fingerprint conversation is waiting" _one_finger_waiter
first=$(finger_waiters)

shell_ipc profiles simulate '{"locktest.nofinger": true}' > /dev/null
check_within "$GUARD" "the switch off reaches the lock" offered_is false
check_within "$GUARD" "the fingerprint is no longer offered" state_is fingerprint_available false
check_within "$GUARD" "… its conversation ended" no_finger_waiters
check "… the method unavailable, not broken" state_is fingerprint_status unavailable
check "still locked" compositor_locked

shell_ipc profiles clearSimulation > /dev/null
check_within "$GUARD" "switched on again: offered" state_is fingerprint_available true
check_within "$GUARD" "… a new conversation waits" _one_finger_waiter
check "… not the old one" test "$(finger_waiters)" != "$first"

shell_ipc profiles simulate '{"locktest.nofinger": true}' > /dev/null
check_within "$GUARD" "off again: the conversation ended" no_finger_waiters
wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked

# ---- A lock taken while it is off ----
lock_by_ipc
check_within "$GUARD" "locked again" compositor_locked
check_within "$GUARD" "the methods known" state_is armed true
check "the fingerprint is not offered" state_is fingerprint_available false
check "… no conversation of the reader" no_finger_waiters
shell_ipc profiles clearSimulation > /dev/null
check_within "$GUARD" "switched on during the lock: a conversation waits" _one_finger_waiter
finger ok
check_within 10 "… and the finger unlocks" compositor_unlocked
check "no protocol error" no_protocol_errors
