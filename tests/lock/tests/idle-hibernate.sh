# Hibernation after idle (Idle, logind's Hibernate and SuspendThenHibernate), through the
# logind stand-ins (stack_start --logind), which answer CanHibernate and
# CanSuspendThenHibernate "yes" here. No bus is reached, nothing sleeps or hibernates: the
# gdbus stand-in notes the call and, as logind does, sends PrepareForSleep(true); the wake
# is the test's.
#
#   profile Full: sleep off, the idle lock at 3 s, hibernation 4 s after it — counted from
#   the lock: Hibernate(false) at 7 s, from the locked session;
#   profile Sleepy (locktest.sleepy): sleep at 4 s with hibernation on — the sleep asks
#   SuspendThenHibernate(false) (the delay after it is the system's), no Hibernate of its own.

mkdir -p "$XDG_CONFIG_HOME/h2s_shell" "$WORK/logind"
python3 -I -c '
import json, sys
profiles = [
    {"name": "Full", "enabled": True, "when": {}, "set": {
        "lockscreen.lockscreenEnabled": True, "lockscreen.lockAfter": 3,
        "lockscreen.hibernateEnabled": True, "lockscreen.hibernateTimeout": 4, "lockscreen.lockOnSleep": False}},
    {"name": "Sleepy", "enabled": True, "when": {"fact": "locktest.sleepy", "is": True},
     "set": {"lockscreen.lockscreenEnabled": False, "lockscreen.sleepEnabled": True, "lockscreen.sleepTimeout": 4}},
]
json.dump({"profiles": json.dumps(profiles), "widgetPresets": "{}"}, open(sys.argv[1], "w"), indent=2)
' "$XDG_CONFIG_HOME/h2s_shell/config.json" || abort "cannot write the config"
echo yes > "$WORK/logind/can-hibernate"
echo yes > "$WORK/logind/can-suspend-then-hibernate"

stack_start --logind

calls_of() { grep -c "^call $1 " "$WORK/logind/log"; }
called() { [ "$(calls_of "$1")" -ge "$2" ]; }
idle_field() { shell_ipc idle state | python3 -I -c 'import json, sys; print(json.dumps(eval(sys.argv[1], {}, json.load(sys.stdin))))' "$1"; }
sleepy_in_force() { [ "$(shell_ipc profiles status | python3 -I -c 'import json, sys; print(json.dumps(json.load(sys.stdin)["values"].get("lockscreen.sleepEnabled")))')" = true ]; }

check_within "$GUARD" "logind asked whether it can hibernate" grep -q '^call CanHibernate' "$WORK/logind/log"
check_within "$GUARD" "… yes: hibernation counted from the lock, at 7 s" test "$(idle_field 'config["hibernateAfter"]')" = 7
check "… from the lock" test "$(idle_field 'config["hibernate"]["from"]')" = '"lock"'

# ---- Sleep off: the lock, then Hibernate ----
move_pointer 640 400
check_within 15 "3 s idle: the idle lock" compositor_locked
check "… no hibernation yet" test "$(calls_of Hibernate)" = 0
check_within 15 "4 s after the lock: Hibernate asked" called Hibernate 1
check "… once, non-interactive (Hibernate false: never a password)" test "$(grep '^call Hibernate' "$WORK/logind/log")" = "call Hibernate false"
check "… no Suspend asked" test "$(calls_of Suspend) $(calls_of SuspendThenHibernate)" = "0 0"
check_within "$GUARD" "Idle knows it is going down" test "$(idle_field 'state["sleeping"]')" = true
# The next idle period is Sleepy's: switched before the wake
shell_ipc profiles simulate '{"locktest.sleepy": true}' > /dev/null
check_within "$GUARD" "the profile with sleep on is in force" sleepy_in_force
logind_signal wake
check_within "$GUARD" "awake: Idle knows" test "$(idle_field 'state["sleeping"]')" = false
wake_prompt || fail "the prompt did not wake"
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked

# ---- Sleep on: the sleep asks SuspendThenHibernate ----
check_within "$GUARD" "sleep on: hibernation after sleeping (the system's delay), no stage of its own" \
    test "$(idle_field '[config["sleepThenHibernate"], config["hibernateAfter"]]')" = "[true, 0]"
check_within 15 "4 s idle: SuspendThenHibernate asked" called SuspendThenHibernate 1
check "… once, non-interactive" test "$(grep '^call SuspendThenHibernate' "$WORK/logind/log")" = "call SuspendThenHibernate false"
check "… no plain Suspend, no second Hibernate" test "$(calls_of Suspend) $(calls_of Hibernate)" = "0 1"
logind_signal wake
check_within "$GUARD" "awake" test "$(idle_field 'state["sleeping"]')" = false
shell_ipc profiles clearSimulation > /dev/null
