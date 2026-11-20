# Lock before sleep as it comes (off by default): with the setting left unset, no sleep
# inhibitor is taken and a PrepareForSleep does not lock; a profile that switches it on
# takes the inhibitor, and switching it off again lets it go — at runtime, without a restart.
# The profile depends on a fact of the test's own, set and cleared over the profiles IPC
# (`simulate`), so nothing of the machine running the test decides it.

mkdir -p "$XDG_CONFIG_HOME/h2s_shell"
python3 -I -c '
import json, sys
profiles = [
    {"name": "Full", "enabled": True, "when": {}, "set": {}},
    {"name": "Sleep", "enabled": True, "when": {"fact": "locktest.lockOnSleep", "is": True},
     "set": {"lockscreen.lockOnSleep": True}},
]
json.dump({"profiles": json.dumps(profiles), "widgetPresets": "{}"}, open(sys.argv[1], "w"), indent=2)
' "$XDG_CONFIG_HOME/h2s_shell/config.json" || abort "cannot write the config"

stack_start --logind

check_within 5 "the shell follows the test's logind session" state_is logind_session "$LOCKTEST_SESSION_PATH"
check_within 5 "the logind monitor (stand-in) runs" logind_monitor_running
check "the setting is off: unset, the schema's default" \
    test "$(shell_ipc profiles status | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["values"].get("lockscreen.lockOnSleep"))')" = False
check "no inhibitor is held" inhibitor_released
check "no inhibitor was ever taken" test "$(grep -c '^hold' "$WORK/logind/log")" = 0
check "the rules hold none" state_is inhibitor released

# ---- A sleep and a wake do not lock ----
logind_signal sleep
check_within 5 "the shell heard the PrepareForSleep" state_is sleep suspending
check "it did not lock" compositor_unlocked
check "the rules did not lock" state_is phase unlocked
logind_signal wake
not_suspending() { ! state_is sleep suspending; }
check_within 5 "the shell heard the wake" not_suspending
check "still unlocked" compositor_unlocked
check "still no inhibitor taken" test "$(grep -c '^hold' "$WORK/logind/log")" = 0

# ---- Switched on, then off, while running ----
shell_ipc profiles simulate '{"locktest.lockOnSleep": true}' > /dev/null
check_within 5 "switched on: the inhibitor is taken" inhibitor_held
check_within 5 "the rules hold it" state_is inhibitor held
shell_ipc profiles clearSimulation > /dev/null
check_within 5 "switched off: the inhibitor is let go" inhibitor_released
check_within 5 "the rules hold none" state_is inhibitor released
check "never locked" compositor_unlocked
