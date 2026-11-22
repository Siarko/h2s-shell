# The shell's own screen-off, on the bed's private Hyprland and its own output (never the
# session's monitors: hyprctl here reaches only the bed's compositor): "Turn screens off
# after" 6 s cuts the output's power (Hyprland's dpmsStatus false) and input turns it back on
# (the bed's Hyprland does not do that itself: mouse_move_enables_dpms is off). Then the lock
# screen's own screen-off: locked, 5 s without input there — off; input at the lock screen —
# on, and the lock still there. Between them, restarts: a shell killed while it had the
# output off turns it on again when it comes back (remembered in its config); an output
# another program turned off (as hypridle does) is left alone.

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
# dpms_stays <seconds> <true|false>: says so all along, polled for that long
dpms_stays() {
    local deadline=$((${EPOCHREALTIME/[.,]/} + $1 * 1000000))
    while [ "${EPOCHREALTIME/[.,]/}" -lt "$deadline" ]; do
        dpms_is "$2" || return 1
        sleep 0.2 # fixed sleep: the poll's pause, not a wait for anything
    done
    return 0
}
output_name() { hyprctl -j monitors | python3 -I -c 'import json, sys; print(json.load(sys.stdin)[0]["name"])'; }
remembered() { python3 -I -c 'import json, sys; print(" ".join(json.load(open(sys.argv[1])).get("screensOff", [])))' "$XDG_CONFIG_HOME/h2s_shell/config.json"; }
remembers_some() { [ -n "$(remembered)" ]; }
remembers_none() { [ -z "$(remembered)" ]; }
power_control() { [ "$(shell_ipc idle state | python3 -I -c 'import json, sys; print(json.dumps(json.load(sys.stdin)["config"]["canPowerOff"]))')" = true ]; }

check_within "$GUARD" "the shell can turn the bed's output off (Hyprland)" power_control
check "the output is on at start" dpms_is true

# ---- Turn screens off after ----
check_timed 12 "6 s without input: the output is off" dpms_is false
move_pointer 700 400
move_pointer 720 410
check_within "$GUARD" "input: the shell turns it on again" dpms_is true

# ---- A restart while the shell has the output off ----
check_timed 12 "off again" dpms_is false
check_within "$GUARD" "… remembered in the config as turned off by the shell" remembers_some
old_shell=$SHELL_PID
signal_shell KILL
check_within 10 "the launcher starts a new shell" wait_for_new_shell "$old_shell" 10
check_within "$GUARD" "the new shell turns the output on again" dpms_is true
check_within "$GUARD" "… and forgets it" remembers_none

# ---- An output another program turned off is left alone ----
hyprctl dispatch "hl.dsp.dpms({ action = \"disable\", monitor = \"$(output_name)\" })" > /dev/null
check_within "$GUARD" "(another program turns the output off)" dpms_is false
old_shell=$SHELL_PID
signal_shell KILL
check_within 10 "the launcher starts a new shell" wait_for_new_shell "$old_shell" 10
check_within "$GUARD" "(the new shell reads the monitors)" power_control
check "the new shell leaves it off: not one it turned off" dpms_stays 2 false
move_pointer 700 400
move_pointer 720 410
check "input does not turn it on either: the shell did not turn it off" dpms_stays 1 false
hyprctl dispatch "hl.dsp.dpms({ action = \"enable\", monitor = \"$(output_name)\" })" > /dev/null
check_within "$GUARD" "(on again)" dpms_is true

# ---- The lock screen's own screen-off ----
lock_by_ipc
check_within "$GUARD" "locked" compositor_locked
check_timed 10 "5 s without input at the lock screen: the output is off" dpms_is false
lock_black_is() { [ "$(idle_field lockBlack)" = "$1" ]; }
check_within "$GUARD" "… the lock surface not black: the output is read as off" lock_black_is false
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
