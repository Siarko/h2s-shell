# Sleep after idle (Idle, logind's Suspend), through the logind stand-ins (stack_start
# --logind): sleep 6 s after the last input, no idle lock. Idle reads logind's inhibitors
# first: a sleep block (a backup) pauses it. Then it calls Suspend(false) on the gdbus
# stand-in, which notes the call and, as logind does, sends PrepareForSleep(true); the wake
# is the test's. No bus is reached, nothing sleeps.
#
#   profile Full, "Lock before the computer sleeps" on: locked before the sleep is let go,
#   and after the wake no notice (it slept locked);
#   profile Unlocked (locktest.unlocked), lock before sleep off: it sleeps unlocked, as the
#   settings say — and the sleep notice says nothing about such a sleep.

mkdir -p "$XDG_CONFIG_HOME/h2s_shell" "$WORK/logind"
python3 -I -c '
import json, sys
profiles = [
    {"name": "Full", "enabled": True, "when": {}, "set": {
        "lockscreen.sleepEnabled": True, "lockscreen.sleepTimeout": 6, "lockscreen.lockOnSleep": True}},
    {"name": "Unlocked", "enabled": True, "when": {"fact": "locktest.unlocked", "is": True},
     "set": {"lockscreen.lockOnSleep": False}},
]
json.dump({"profiles": json.dumps(profiles), "widgetPresets": "{}"}, open(sys.argv[1], "w"), indent=2)
' "$XDG_CONFIG_HOME/h2s_shell/config.json" || abort "cannot write the config"
# A backup holds logind's sleep block from the start
echo "([('sleep', 'borg', 'Backup', 'block', uint32 0, uint32 4242)],)" > "$WORK/logind/inhibitors"

stack_start --logind

suspend_calls() { grep -c '^call Suspend' "$WORK/logind/log"; }
suspended() { [ "$(suspend_calls)" -ge "$1" ]; }
idle_field() { shell_ipc idle state | python3 -I -c 'import json, sys; print(json.dumps(eval(sys.argv[1], {}, json.load(sys.stdin))))' "$1"; }
notice_phase() { shell_ipc shelltest sleepNotice | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["notice"]["phase"])'; }
notices() {
    shell_ipc shelltest notifierRecorded | python3 -I -c '
import json, sys
print(sum(1 for n in json.load(sys.stdin) if n["kind"] == "show" and n["summary"] == "Not locked while asleep"))'
}
slept() { [ "$(shell_log_count '\[SleepLockNotice\] went to sleep')" -ge "$1" ]; }
last_slept() { grep -a '\[SleepLockNotice\] went to sleep' "$WORK/shell.log" | tail -n 1; }
lock_on_sleep_is() { [ "$(shell_ipc profiles status | python3 -I -c 'import json, sys; print(json.dumps(json.load(sys.stdin)["values"].get("lockscreen.lockOnSleep")))')" = "$1" ]; }

check_within "$GUARD" "logind asked whether it can sleep" grep -q '^call CanSuspend' "$WORK/logind/log"
check_within "$GUARD" "… yes" test "$(idle_field 'sleepSupport["canSuspend"]')" = '"yes"'

# ---- A backup blocks sleep: paused ----
blocked_logged() { [ "$(shell_log_count 'logind: sleep blocked by borg (Backup)')" -ge 1 ]; }
check_within 15 "6 s idle: logind's inhibitors read, the backup's sleep block seen" blocked_logged
check "… the shell says who blocks it" test "$(idle_field 'sleepBlockers[0]["who"]')" = '"borg"'
no_call() { ! wait_until 3 suspended 1; }
check "… no sleep asked while it holds" no_call

# ---- Free again; input starts a new idle period: the sleep, locked first ----
echo "(@a(ssssuu) [],)" > "$WORK/logind/inhibitors"
move_pointer 640 400
check_within 15 "6 s idle again: the sleep asked" suspended 1
check "… once, non-interactive (Suspend false: never a password)" test "$(grep '^call Suspend' "$WORK/logind/log")" = "call Suspend false"
check_within "$GUARD" "lock before sleep on: locked at the PrepareForSleep the call brought" compositor_locked
check_within "$GUARD" "… and the sleep let go once locked" test "$(state_field sleep) $(state_field inhibitor)" = "suspending released"
check_within "$GUARD" "the notice looked" slept 1
check "… and saw it locked" grep -q 'went to sleep locked ' <<< "$(last_slept)"
# The next idle period is the Unlocked profile's: switched before the wake
shell_ipc profiles simulate '{"locktest.unlocked": true}' > /dev/null
check_within "$GUARD" "the profile without lock before sleep is in force" lock_on_sleep_is false
logind_signal wake
check_within "$GUARD" "awake: Idle knows" test "$(idle_field 'state["sleeping"]')" = false
check "no notice (it slept locked)" test "$(notice_phase)" = quiet
wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked

# ---- Lock before sleep off, no idle lock: it sleeps unlocked, as the settings say ----
check_within 15 "6 s idle: the sleep asked again" suspended 2
check "… still not locked" compositor_unlocked
check_within "$GUARD" "the notice looked" slept 2
check "… unlocked, the idle sleep the settings leave so" grep -q 'went to sleep unlocked (the idle sleep, unlocked as the settings say)' <<< "$(last_slept)"
logind_signal wake
check_within "$GUARD" "awake" test "$(idle_field 'state["sleeping"]')" = false
quiet_after_wake() { ! wait_until 2 test "$(notices)" != 0; }
check "no notice after a sleep the settings left unlocked" quiet_after_wake
check "… the notice's state untouched" test "$(notice_phase)" = quiet
shell_ipc profiles clearSimulation > /dev/null
