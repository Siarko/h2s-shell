# The sleep notice by outcome (SleepLockNotice), through the logind stand-ins (stack_start
# --logind) and the bed's own Hyprland, lock before sleep off (the default): the shell holds
# an inhibitor of its own while awake and lets it go once it has looked whether the session
# is locked: at once when locked, at the look's 1 s deadline when not (it reads again every
# quarter second meanwhile: another locker may still come up) — within 1.5 s here. Unlocked (the bed's Hyprland says so: `hyprctl -j
# locked`; the stand-in's LockedHint false alone would be unknown) → after the resume the
# critical notice, once; closed → waiting, the page's line, remembered in the config; another
# unlocked sleep while waiting → no second notice; a locked sleep → fixed, nothing said; the
# next unlocked sleep is told again.

stack_start --logind

SUMMARY="Not locked while asleep"
notice_field() { shell_ipc shelltest sleepNotice | python3 -I -c 'import json, sys; d = json.load(sys.stdin); print(eval(sys.argv[1], {}, d))' "$1"; }
notice_is() { [ "$(notice_field 'notice["phase"]')" = "$1" ]; }
phase_is() { [ "$(notice_field phase)" = "$1" ]; }
# The notices shown (each show of a notification with a handle that Notifier recorded)
shows() {
    shell_ipc shelltest notifierRecorded | python3 -I -c '
import json, sys
print(sum(1 for n in json.load(sys.stdin) if n["kind"] == "show" and n["summary"] == sys.argv[1]))' "$SUMMARY"
}
shows_are() { [ "$(shows)" = "$1" ]; }
last_shown_handle() {
    shell_ipc shelltest notifierRecorded | python3 -I -c '
import json, sys
print([n["handle"] for n in json.load(sys.stdin) if n["kind"] == "show" and n["summary"] == sys.argv[1]][-1])' "$SUMMARY"
}
remembered_phase() {
    python3 -I -c '
import json, sys
text = json.load(open(sys.argv[1])).get("sleepLockNotice", "")
print(json.loads(text)["phase"] if text else "quiet")' "$XDG_CONFIG_HOME/h2s_shell/config.json" 2> /dev/null
}
remembered_is() { [ "$(remembered_phase)" = "$1" ]; }
# The notice's inhibitor, from the stand-in's record ("check-hold", "check-release")
check_held() { [ "$(grep -c '^check-hold' "$WORK/logind/log")" -gt "$(grep -c '^check-release' "$WORK/logind/log")" ]; }
check_released() { ! check_held; }
# check_released_within <seconds>: its first release after the last logind_signal came that soon
check_released_within() {
    awk -v since="${LOGIND_SIGNAL_AT:-0}" -v limit="$1" '
        $1 == "check-release" && $3 + 0 >= since + 0 { found = 1; exit !($3 - since < limit) }
        END { if (!found) exit 1 }' "$WORK/logind/log"
}
check_release_seconds() {
    awk -v since="${LOGIND_SIGNAL_AT:-0}" '$1 == "check-release" && $3 + 0 >= since + 0 { printf "%.2f", $3 - since; exit }' "$WORK/logind/log"
}
slept() { [ "$(shell_log_count '\[SleepLockNotice\] went to sleep')" -ge "$1" ]; }
slept_as() { tail -n 1 <<< "$(grep -a '\[SleepLockNotice\] went to sleep' "$WORK/shell.log")" | grep -q "went to sleep $1 "; }

check_within "$GUARD" "the notice's inhibitor is held while awake" check_held
check "the lock's own is not (lock before sleep is off)" test "$(grep -c '^hold' "$WORK/logind/log")" = 0

# ---- An unlocked sleep: the notice after the resume ----
logind_signal sleep
check_within "$GUARD" "PrepareForSleep, unlocked: the inhibitor let go" check_released
log "PrepareForSleep to the release: $(check_release_seconds) s"
check "… within 1.5 s (the look's deadline is 1 s)" check_released_within 1.5
check "… not before the deadline" test "$(check_release_seconds | cut -d. -f1)" -ge 1
check_within "$GUARD" "the look ended" slept 1
check "… unlocked" slept_as unlocked
check "nothing said before the resume" shows_are 0
logind_signal wake
check_within "$GUARD" "after the resume: the notice" shows_are 1
check "… shown" notice_is shown
check_within "$GUARD" "the inhibitor taken again" check_held

# ---- Closed: waiting, with the page's line ----
check "the notice closed as its × would" test "$(shell_ipc shelltest notifierDismiss "$(last_shown_handle)")" = ""
check_within "$GUARD" "closed: waiting for a fix" notice_is waiting
check "… the page's line has the sleep's time" test "$(notice_field 'waitingSince > 0')" = True
check_within "$GUARD" "… remembered in the config" remembered_is waiting

# ---- Another unlocked sleep while waiting: no second notice ----
logind_signal sleep
check_within "$GUARD" "asleep again" slept 2
check "… unlocked" slept_as unlocked
check_within "$GUARD" "… the inhibitor let go" check_released
logind_signal wake
check_within "$GUARD" "awake" phase_is awake
check "no second notice" shows_are 1
check "still waiting" notice_is waiting

# ---- A locked sleep: fixed, nothing said ----
lock_by_ipc
check_within "$GUARD" "locked" compositor_locked
logind_signal sleep
check_within "$GUARD" "asleep, locked: the inhibitor let go" check_released
log "PrepareForSleep to the release: $(check_release_seconds) s"
check "… at once (within 0.5 s)" check_released_within 0.5
check_within "$GUARD" "the look ended" slept 3
check "… locked" slept_as locked
logind_signal wake
check_within "$GUARD" "after the resume: fixed" notice_is quiet
check "nothing said" shows_are 1
check_within "$GUARD" "… forgotten in the config" remembered_is quiet
logind_signal unlock
check_within "$GUARD" "unlocked" compositor_unlocked

# ---- Unlocked again: told again ----
check_within "$GUARD" "the inhibitor held again" check_held
logind_signal sleep
check_within "$GUARD" "asleep, unlocked" slept 4
logind_signal wake
check_within "$GUARD" "after the resume: the notice again" shows_are 2
check "… shown" notice_is shown
