# A reload asked for while locked (Quickshell.reload(), through the test bed's seam: nothing
# in the shell calls it, and file changes do not reload while locked) keeps the session
# locked: the new WlSessionLock takes the old one's lock over, because the driver sets its
# `locked` before Quickshell realizes it (PersistentProperties `_carried`, Lockscreen.qml),
# and the rules go on from `restored`. Without that, the new WlSessionLock starts with
# `locked` false and unlocks the session with no authentication.
#
# Checked: the compositor never reports unlocked across the reload (polled every 50 ms) and
# Hyprland's debug log shows no new lock across it (it logs each lock, and no unlock), the
# shell says locked, the same process, a prompt that wakes, the password unlocks, no
# protocol error in either log; a later lock and unlock work (the process can lock again).
# Then two reloads in a row while locked. (A reload while the compositor has not yet
# confirmed the lock cannot be reproduced here — it confirms in milliseconds; the rules'
# `restored { secure: false }` covers it in tests/LockRulesTest.qml.)
#
# Observed with Hyprland's debug log (--hyprland-debug): each reload adds one
# get_lock_surface on the same lock for the output while the old surface still exists
# (Quickshell makes new surfaces rather than reusing the old windows), no new lock, and no
# protocol error; the old WlSessionLock's destructor logs "destroyed without unlocking",
# harmless since its lock manager was handed over.

stack_start --reload-seam --hyprland-debug

# Hyprland logs every new session lock ("Session got locked by"), and no unlock at all: an
# unlock and a lock again across a reload would show as one lock too many
hyprland_locks() { sed 's/\x1b\[[0-9;]*m//g' "$WORK/hyprland.log" | grep -ac "Session got locked by"; }

lock_by_ipc
check_within 5 "locked" compositor_locked
check_within 5 "confirmed" state_is secure true
check "a reload now would carry the lock over" state_is carried_held true
session_before=$(state_field session)
reloads_before=$(shell_log_count "Reloading configuration")

start_lock_watch reload
shell_ipc locktest reload false > /dev/null
check_within 10 "the shell reloaded" lines_more_than "$reloads_before" "Reloading configuration" "$WORK/shell.log"
check_within 10 "the reloaded shell answers" shell_status_is locked
sleep 2
stop_lock_watch
check "the compositor never reported unlocked across the reload" lock_watch_never_unlocked
check "still locked (compositor)" compositor_locked
check "still locked (shell)" shell_status_is locked
check "the lock was carried over (restored)" grep -aq 'event {"type":"restored","secure":true}' "$WORK/shell.log"
check "… and confirmed: the rules say locked" state_is phase locked
check "the compositor's lock is still secure" state_is secure true
check "the same process (a reload, not a restart)" kill -0 "$SHELL_PID"
check "file watching is off while locked (also after the reload)" state_is watch_files false
check_within 5 "the reloaded shell has its lock surface" state_is surfaces 1
check "Hyprland's own log: one lock, never a new one across the reload" test "$(hyprland_locks)" = 1
log "surface instances the rules know: $(state_field surfaces); session $(state_field session) (was $session_before)"
describe_lock

wake_prompt || fail "the prompt did not wake after the reload"
check_within 5 "the methods are known" state_is armed true
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks after the reload" compositor_unlocked
check "the shell says unlocked" shell_status_is unlocked
check_within 3 "the marker says unlocked" state_is marker unlocked

lock_by_ipc
check_within 5 "the reloaded shell locks again" compositor_locked
check_within 5 "… and the compositor confirms it" state_is secure true

# Twice in a row, while locked
start_lock_watch reload-twice
reloads_before=$(shell_log_count "Reloading configuration")
shell_ipc locktest reload false > /dev/null
check_within 10 "a second reload" lines_more_than "$reloads_before" "Reloading configuration" "$WORK/shell.log"
wait_until 10 shell_status_is locked
reloads_before=$(shell_log_count "Reloading configuration")
shell_ipc locktest reload false > /dev/null
check_within 10 "and a third, right after it" lines_more_than "$reloads_before" "Reloading configuration" "$WORK/shell.log"
check_within 10 "the shell answers, locked" shell_status_is locked
sleep 2
stop_lock_watch
check "the compositor never reported unlocked across two reloads in a row" lock_watch_never_unlocked
check "Hyprland's own log: the second lock only, no new one across the two reloads" test "$(hyprland_locks)" = 2
check "the same process" kill -0 "$SHELL_PID"
wake_prompt || fail "the prompt did not wake after two reloads"
check_within 5 "the methods are known" state_is armed true
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks after two reloads" compositor_unlocked

lock_by_ipc
check_within 5 "and a last lock works" compositor_locked
press_key Escape
check_within 3 "(Escape wakes the prompt)" state_is prompt_awake true
press_key Escape
check_within 5 "… and unlocks" compositor_unlocked

errors=$(protocol_errors)
[ -n "$errors" ] && log "protocol errors: $errors"
check "no protocol error in Hyprland's or the shell's log" test -z "$errors"
log "Hyprland's log about the lock: $(grep -ai 'lock' "$WORK/hyprland.log" | tail -n 20 | tr '\n' '|')"
