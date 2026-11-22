# The shell's own screen-off, on the bed's private Hyprland and its own output (never the
# session's monitors: hyprctl here reaches only the bed's compositor): "Turn screens off
# after" 6 s cuts the output's power (Hyprland's dpmsStatus false) and input turns it back on
# (the bed's Hyprland does not do that itself: mouse_move_enables_dpms is off). Then the lock
# screen's own screen-off: locked, 5 s without input there — off; input at the lock screen —
# on, and the lock still there.

stack_start --settings '{"lockscreen.screenOffEnabled": true, "lockscreen.screenOffTimeout": 6,
    "lockscreen.lockedScreenOffTimeout": 5}'

# dpms_is <true|false>: every output of the bed's Hyprland says so
dpms_is() {
    hyprctl -j monitors | python3 -I -c '
import json, sys
monitors = json.load(sys.stdin)
sys.exit(0 if monitors and all(str(monitor.get("dpmsStatus")).lower() == sys.argv[1] for monitor in monitors) else 1)' "$1"
}
idle_field() { shell_ipc idle state | python3 -I -c 'import json, sys; print(json.dumps(json.load(sys.stdin)["state"][sys.argv[1]]))' "$1"; }
power_control() { [ "$(shell_ipc idle state | python3 -I -c 'import json, sys; print(json.dumps(json.load(sys.stdin)["config"]["canPowerOff"]))')" = true ]; }

check_within "$GUARD" "the shell can turn the bed's output off (Hyprland)" power_control
check "the output is on at start" dpms_is true

# ---- Turn screens off after ----
check_timed 12 "6 s without input: the output is off" dpms_is false
move_pointer 700 400
move_pointer 720 410
check_within "$GUARD" "input: the shell turns it on again" dpms_is true

# ---- The lock screen's own screen-off ----
lock_by_ipc
check_within "$GUARD" "locked" compositor_locked
check_timed 10 "5 s without input at the lock screen: the output is off" dpms_is false
check "… the lock surface not black: the output is read as off" test "$(idle_field lockBlack)" = false
move_pointer 700 400
move_pointer 720 410
check_within "$GUARD" "input at the lock screen: on again" dpms_is true
check "… still locked" compositor_locked
check_within "$GUARD" "the lock is ready for a password (test stack)" _password_stack_is_ours_and_safe
wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked
check "the output on after the unlock" dpms_is true
check "no protocol error" no_protocol_errors
