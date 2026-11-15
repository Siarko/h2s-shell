# The lock marker's hygiene. A starting shell locks at once only for a marker that says
# "locked" for THIS compositor session — its key is the boot id, the Wayland display and its
# socket's identity (device, inode, ctime), which a reboot or a new compositor changes. A
# marker left by a compositor session that is gone (the compositor crashed while locked, or
# was killed from a TTY to get out of a dead lock — then a new login is the new session) is
# ignored and overwritten: it cannot lock a fresh session, let alone forever. Positive
# control: a marker with the right key does lock. And the marker lives in the private
# runtime dir (0700, the user's), where no other user can plant, remove or read it.

stack_start

marker=$RUN/h2s-shell-lock
key_of() { echo "$1:wayland-1:$(stat -L -c '%d:%i:%Z' "$RUN/wayland-1")"; }
this_boot=$(cat /proc/sys/kernel/random/boot_id)
# restart_with_marker <content>: the shell stopped while unlocked (its launcher letting it
# go), the marker set, and a new launcher and shell started — as at a new login, and with
# the marker in place before the shell can look
restart_with_marker() {
    local old=$SHELL_PID old_supervisor=$SUPERVISOR_PID
    check "unlocked before the restart" shell_status_is unlocked
    supervisor_release
    signal_shell KILL
    wait_until 3 test ! -e "/proc/$old" -a ! -e "/proc/$old_supervisor" || fail "the shell and its launcher did not end"
    printf '%s\n' "$1" > "$marker"
    log "marker set to: $1"
    start_launcher
    log "a new launcher and shell: pid $SHELL_PID"
}

check "the runtime dir is private (0700, the user's)" test "$(stat -c '%a %u' "$RUN")" = "700 $(id -u)"
check "no marker before the first lock" test ! -e "$marker"
lock_by_ipc
check_within 5 "locked" compositor_locked
check "the marker is in the private runtime dir, the user's, not a link" \
    test -f "$marker" -a ! -L "$marker" -a "$(stat -c %u "$marker")" = "$(id -u)"
check "it says locked, with this session's key" test "$(cat "$marker")" = "locked $(key_of "$this_boot")"
press_key Escape
check_within 3 "(Escape wakes the prompt)" state_is prompt_awake true
press_key Escape
check_within 5 "unlocked" compositor_unlocked
check_within 3 "the marker says unlocked (a moment after the unlock: its request is sent by then)" marker_file_is unlocked

# ---- From another boot ----
restart_with_marker "locked $(key_of 00000000-0000-0000-0000-000000000000)"
sleep 2
check "a marker of another boot does not lock" compositor_unlocked
check "… the shell says unlocked" shell_status_is unlocked
check "… it says why" grep -aq "a lock marker from another compositor session" "$WORK/shell.log"
check "… and the marker is overwritten" test "$(cat "$marker")" = "unlocked"

# ---- From another compositor (same boot, another socket) ----
restart_with_marker "locked $this_boot:wayland-1:1:12345:1000000000"
sleep 2
check "a marker of another compositor session does not lock" compositor_unlocked
check "… the shell says unlocked" shell_status_is unlocked
check "… and the marker is overwritten" test "$(cat "$marker")" = "unlocked"

# ---- Junk ----
restart_with_marker "garbage"
sleep 2
check "a marker that says nothing known does not lock" compositor_unlocked

# ---- Positive control: this session's key locks ----
restart_with_marker "locked $(key_of "$this_boot")"
check_within 10 "a marker of this session locks at once" compositor_locked
check_within 5 "the compositor confirms it" state_is secure true
check "the shell says locked" shell_status_is locked
wake_prompt || fail "the prompt did not wake"
check_within 5 "the methods are known" state_is armed true
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked
check_within 3 "the marker says unlocked (a moment after the unlock: its request is sent by then)" marker_file_is unlocked

# ---- A key the old shell did not know yet ("?": it locked before its probe answered) ----
restart_with_marker "locked ?"
check_within 10 "an unknown key counts as this session's (fail closed): locks" compositor_locked
wake_prompt || fail "the prompt did not wake"
check_within 5 "the methods are known" state_is armed true
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "… and the password unlocks it: not locked for good" compositor_unlocked
