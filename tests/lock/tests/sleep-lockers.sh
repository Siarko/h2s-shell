# Telling the user when locking before sleep is in conflict with what else locks
# (SleepLockNotice): the shell reads logind's sleep inhibitors — here from the gdbus
# stand-in, whose list the test writes (logind_inhibitors) — first 1 s after the start and
# then every second (the test timings sleepLockers, sleepLockersEvery; 30 s and 15 min
# otherwise).
#
#   "Lock before the computer sleeps" off, nothing else locks: one notice, the screen stays
#   unlocked during sleep — remembered in the config, not repeated at the next reads;
#   switched on: nothing to say; another locker appears: one notice, two programs lock;
#   hypridle alone (it may or may not lock): nothing; while locked nothing is said, and
#   what is due is said once unlocked; a read that fails says nothing.
# The outcome is logged when it changes, not at every read.

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

stack_start --logind --timings '{"sleepLockers": 1000, "sleepLockersEvery": 1000}'

UNLOCKED_SUMMARY="The screen stays unlocked during sleep"
BOTH_SUMMARY="Two programs lock the screen before sleep"
# How many notifications the shell recorded with that summary (a test tree records them)
notices_of() {
    shell_ipc shelltest notifierRecorded | python3 -I -c '
import json, sys
print(sum(1 for n in json.load(sys.stdin) if n["summary"] == sys.argv[1]))' "$1"
}
notices_of_are() { [ "$(notices_of "$1")" = "$2" ]; }
remembered() {
    python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1])).get("sleepLockNotice", ""))' \
        "$XDG_CONFIG_HOME/h2s_shell/config.json" 2> /dev/null
}
remembered_is() { [ "$(remembered)" = "$1" ]; }
reads() { grep -c '^call ListInhibitors' "$WORK/logind/log"; }
# wait_reads <n>: until n more reads than now have been answered
wait_reads() {
    local target=$(($(reads) + $1))
    wait_until 10 lines_more_than $((target - 1)) '^call ListInhibitors' "$WORK/logind/log"
}
outcome_lines() { shell_log_count "\[SleepLockNotice\] other lockers before sleep: $1\$"; }
outcome_logged_once() { [ "$(outcome_lines "$1")" = 1 ]; }

# ---- Off (the default), nothing else locks ----
check_within 10 "off, nothing else locks: the notice comes" notices_of_are "$UNLOCKED_SUMMARY" 1
check "… saying how to turn it on" grep -q 'Nothing locks it before the computer sleeps. Turn on \\"Lock before the computer sleeps\\" in Settings' \
    <<< "$(shell_ipc shelltest notifierRecorded)"
check_within 5 "… remembered in the config" remembered_is none
wait_reads 3
check "three reads later: still once" notices_of_are "$UNLOCKED_SUMMARY" 1
check "the outcome logged once, not at every read" outcome_logged_once none

# ---- Switched on: nothing to say; another locker appears ----
shell_ipc profiles simulate '{"locktest.lockOnSleep": true}' > /dev/null
check_within 5 "switched on: the inhibitor is taken" inhibitor_held
check_within 5 "… nothing to say: the remembered notice is forgotten" remembered_is ""
logind_inhibitors swayidle "Setup Up Lock Screen"
check_within 10 "on, and swayidle locks too: the notice comes" notices_of_are "$BOTH_SUMMARY" 1
check "… naming it" grep -q 'swayidle locks it too.' <<< "$(shell_ipc shelltest notifierRecorded)"
check_within 5 "… remembered" remembered_is "both:swayidle"
check "the new outcome logged" outcome_logged_once "present: swayidle"
wait_reads 3
check "three reads later: still once" notices_of_are "$BOTH_SUMMARY" 1

# ---- hypridle alone: it may or may not lock — nothing to say, on or off ----
logind_inhibitors hypridle "Hypridle wants to delay sleep until its before_sleep handling is done."
check_within 10 "hypridle alone: read as a possible locker" outcome_logged_once "possible: hypridle"
check_within 5 "… the remembered notice forgotten" remembered_is ""
shell_ipc profiles clearSimulation > /dev/null
check_within 5 "switched off: the inhibitor is let go" inhibitor_released
wait_reads 2
check "off with hypridle: no notice" notices_of_are "$UNLOCKED_SUMMARY" 1
check "… on with it neither" notices_of_are "$BOTH_SUMMARY" 1

# ---- While locked nothing is said; once unlocked, it is ----
lock_by_ipc
check_within 5 "locked" compositor_locked
logind_inhibitors
wait_reads 3
check "off, nothing else locks, but locked: not said (nobody would see it)" notices_of_are "$UNLOCKED_SUMMARY" 1
logind_signal unlock
check_within 5 "unlocked" compositor_unlocked
check_within 5 "… now said" notices_of_are "$UNLOCKED_SUMMARY" 2

# ---- A read that fails says nothing and forgets nothing ----
echo "not a list" > "$WORK/logind/inhibitors"
check_within 10 "an unreadable answer: unknown" outcome_logged_once unknown
check "… the remembered notice kept" remembered_is none
check "… nothing new said" notices_of_are "$UNLOCKED_SUMMARY" 2
