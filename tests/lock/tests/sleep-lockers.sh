# Telling the user when locking before sleep is in conflict with what else locks
# (SleepLockNotice): the shell reads logind's sleep inhibitors — here from the gdbus
# stand-in, whose list the test writes (logind_inhibitors) — first 0.3 s after the start and
# then every 0.3 s (the test timings sleepLockers, sleepLockersEvery; 30 s and 15 min
# otherwise).
#
#   "Lock before the computer sleeps" off, nothing else locks: one notice, the screen stays
#   unlocked during sleep — remembered in the config, not repeated at the next reads;
#   switched on: nothing to say (the key forgotten after two such reads); another locker
#   appears: one notice, two programs lock, never advising to turn the shell's lock off;
#   swayidle or hypridle alone (they may lock, ask logind to — which the shell follows — or
#   not lock): nothing; while locked no reads and nothing is said, and what is due is said
#   once unlocked; a read that fails says nothing.
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

stack_start --logind --timings '{"sleepLockers": 300, "sleepLockersEvery": 300}'

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
check_within "$GUARD" "… remembered in the config" remembered_is none
wait_reads 3
check "three reads later: still once" notices_of_are "$UNLOCKED_SUMMARY" 1
check "the outcome logged once, not at every read" outcome_logged_once none

# ---- Switched on: nothing to say; another locker appears ----
shell_ipc profiles simulate '{"locktest.lockOnSleep": true}' > /dev/null
check_within "$GUARD" "switched on: the inhibitor is taken" inhibitor_held
check_within "$GUARD" "… nothing to say: two reads later the remembered notice is forgotten" remembered_is ""
logind_inhibitors swayidle "Setup Up Lock Screen"
check_within 10 "on, swayidle alone: read as a possible locker" outcome_logged_once "possible: swayidle"
wait_reads 2
check "… nothing said (it may ask logind to lock, which the shell follows)" notices_of_are "$BOTH_SUMMARY" 0
logind_inhibitors "GNOME Shell" "GNOME needs to lock the screen"
check_within 10 "on, and GNOME Shell locks too: the notice comes" notices_of_are "$BOTH_SUMMARY" 1
check "… saying what the two do" grep -q 'This shell locks it, and GNOME Shell does too. One lock is enough.' \
    <<< "$(shell_ipc shelltest notifierRecorded)"
check_within "$GUARD" "… remembered" remembered_is "both:GNOME Shell"
check "the new outcome logged" outcome_logged_once "present: GNOME Shell"
wait_reads 3
check "three reads later: still once" notices_of_are "$BOTH_SUMMARY" 1

# ---- hypridle alone: it may or may not lock — nothing to say, on or off ----
logind_inhibitors hypridle "Hypridle wants to delay sleep until its before_sleep handling is done."
check_within 10 "hypridle alone: read as a possible locker" outcome_logged_once "possible: hypridle"
check_within "$GUARD" "… the remembered notice forgotten" remembered_is ""
shell_ipc profiles clearSimulation > /dev/null
check_within "$GUARD" "switched off: the inhibitor is let go" inhibitor_released
wait_reads 2
check "off with hypridle: no notice" notices_of_are "$UNLOCKED_SUMMARY" 1
check "… on with it neither" notices_of_are "$BOTH_SUMMARY" 1

# ---- While locked nothing is said; once unlocked, it is ----
lock_by_ipc
check_within "$GUARD" "locked" compositor_locked
logind_inhibitors
wait_reads 1 # one already under way may still answer
locked_reads=$(reads)
no_read_while_locked() { ! wait_until 1.5 lines_more_than "$locked_reads" '^call ListInhibitors' "$WORK/logind/log"; }
check "locked: no reads for 1.5 s (every 0.3 s otherwise)" no_read_while_locked
check "off, nothing else locks, but locked: not said (nobody would see it)" notices_of_are "$UNLOCKED_SUMMARY" 1
logind_signal unlock
check_within "$GUARD" "unlocked" compositor_unlocked
check_within "$GUARD" "… the reads go on, and it is said" notices_of_are "$UNLOCKED_SUMMARY" 2
# The config is written a moment after a change: wait for it, so the check below is of a
# key that was on disk before the failing reads, not of a write still pending
check_within "$GUARD" "… remembered in the config" remembered_is none

# ---- A read that fails says nothing and forgets nothing ----
echo "not a list" > "$WORK/logind/inhibitors"
check_within 10 "an unreadable answer: unknown" outcome_logged_once unknown
wait_reads 2
check "… two more unreadable reads later the remembered notice is kept" remembered_is none
check "… nothing new said" notices_of_are "$UNLOCKED_SUMMARY" 2
