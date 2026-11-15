# Lock requests around a reload (the review of Stage 4, B1). A Quickshell reload builds the
# new generation with the event loop blocked, then tears the old one down; for that time
# (about two seconds) an IPC call gets "Not ready to accept queries yet." — and `qs ipc`
# exits 0 all the same — and a PrepareForSleep reaches neither generation's logind monitor
# (the old one's lines are never read, the new one starts after the teardown). The lock at
# unlock that reloaded edits made while locked opened that window right after every such
# unlock: the owner's Super+L was lost and a lid closed then slept unlocked. That reload is
# gone; for every other reload (a file saved while unlocked — the normal case) the window is
# narrowed: the launcher's `ipc` tries a dropped call again, and the new generation asks
# logind whether a sleep is under way once its monitor listens, while the old generation's
# inhibitor, kept a few seconds after its holder vanished, makes logind wait.
#
# (1) An edit while locked, unlock, then at once a lock by the launcher's IPC and a
#     PrepareForSleep: both lock (no reload in between any more).
# (2) A file saved while unlocked: a lock by the launcher's IPC sent while the shell
#     reloads is taken (tried again), and it exits 0 only when taken.
# (3) A PrepareForSleep while the shell reloads: the lock goes up, and the inhibitor held
#     when the signal came is let go only after the compositor locked.

stack_start --logind

wait_until 5 logind_monitor_running || abort "the logind monitor did not start"
wait_until 5 inhibitor_held || abort "the inhibitor is not held"
reloads() { shell_log_count "Configuration Loaded"; }
# When the shell logged the compositor's confirmation, the first after line <n> of its log
# (the launcher starts it with --log-times: wall-clock stamps), as seconds since the epoch
confirmed_after() {
    local line
    line=$(tail -n +"$(($1 + 1))" "$WORK/shell.log" | sed 's/\x1b\[[0-9;]*m//g' | grep -a -m 1 '"type":"compositorLocked"') || return 0
    date -d "${line:0:23}" +%s.%N 2> /dev/null
}
unlock_by_escape() {
    press_key Escape
    wait_until 3 state_is prompt_awake true
    press_key Escape
    wait_until 5 compositor_unlocked
}
# The end of a sleep, and a wait until the shell has handled it (taken or ignored, its
# "resumed" event is logged) — instead of a fixed sleep before the next key
wake_and_settle() {
    local resumes
    resumes=$(shell_log_count '"type":"resumed"')
    logind_signal wake
    wait_until 5 lines_more_than "$resumes" '"type":"resumed"' "$WORK/shell.log" \
        || log "the shell did not log the end of the sleep within 5 s"
}

# ---- (1) Right after an unlock with edits made while locked ----
lock_by_ipc
check_within 5 "locked" compositor_locked
echo "// written by tests/lock reload-window.sh while locked" >> "$LOCKTEST_SHELL/singletons/Theme.qml"
reloads_before=$(reloads)
unlock_by_escape || fail "Escape did not unlock"
launcher_ipc lockscreen lock > "$WORK/ipc-1.out" 2>&1
check "a lock by the launcher's IPC right after the unlock is taken (status 0)" test $? = 0
check_within 5 "… and locks" compositor_locked
check "no reload came with the unlock" test "$(reloads)" = "$reloads_before"
unlock_by_escape || fail "Escape did not unlock"
wait_until 5 inhibitor_held
logind_signal sleep
check_within 5 "a PrepareForSleep right after an unlock locks" compositor_locked
wake_and_settle
unlock_by_escape || fail "Escape did not unlock"
check "still no reload" test "$(reloads)" = "$reloads_before"

# ---- (2) The launcher's IPC while the shell reloads ----
wait_until 5 inhibitor_held
reloading_since() { lines_more_than "$1" "Reloading configuration" "$WORK/shell.log"; }
before=$(shell_log_count "Reloading configuration")
echo "// written by tests/lock reload-window.sh, unlocked (2)" >> "$LOCKTEST_SHELL/singletons/Theme.qml"
wait_until 5 reloading_since "$before" || abort "the shell did not reload on a file change"
raw=$("$LOCKTEST_QS" ipc --pid "$SHELL_PID" call lockscreen status 2>&1)
log "a raw qs ipc call as the reload began: $raw"
launcher_ipc lockscreen lock > "$WORK/ipc-2.out" 2>&1
status=$?
log "the launcher's call: status $status, said: $(tr '\n' ' ' < "$WORK/ipc-2.out")"
check "the launcher's lock during the reload ends with status 0" test "$status" = 0
check_within 5 "… and the screen locks" compositor_locked
check "the call did not end on \"Not ready\"" test "$(grep -c 'Not ready' "$WORK/ipc-2.out")" = 0
wait_until 10 shell_status_is locked
unlock_by_escape || fail "Escape did not unlock"

# ---- (3) PrepareForSleep while the shell reloads ----
for offset in 0 0.4; do
    wait_until 10 shell_status_is unlocked
    wait_until 5 inhibitor_held || fail "[$offset] the inhibitor is not held before the reload"
    before=$(shell_log_count "Reloading configuration")
    echo "// written by tests/lock reload-window.sh, unlocked (3, $offset)" >> "$LOCKTEST_SHELL/singletons/Theme.qml"
    wait_until 5 reloading_since "$before" || abort "the shell did not reload on a file change"
    sleep "$offset"
    # The inhibitors held when the signal goes out: the ones logind would wait for
    held_at_signal=$(awk '$1 == "hold" { held[$2] = 1 } $1 == "release" { delete held[$2] } END { for (pid in held) print pid }' "$WORK/logind/log")
    signal_line=$(wc -l < "$WORK/shell.log")
    logind_signal sleep
    locked_at=""
    if wait_until 8 compositor_locked; then
        pass "[$offset] a PrepareForSleep during a reload locks"
    else
        fail "[$offset] a PrepareForSleep during a reload locks (the lid-close lock was LOST)"
    fi
    # Until the shell logged the confirmation and every inhibitor held at the signal was let
    # go (a wait, not a fixed sleep; one never let go within it counts as let go after)
    settled() {
        [ -n "$(confirmed_after "$signal_line")" ] || return 1
        local pid
        for pid in $held_at_signal; do
            awk -v pid="$pid" '$1 == "release" && $2 == pid { found = 1 } END { exit !found }' "$WORK/logind/log" || return 1
        done
    }
    wait_until 8 settled || log "[$offset] not settled within 8 s (confirmation logged and the inhibitors let go)"
    locked_at=$(confirmed_after "$signal_line")
    for pid in $held_at_signal; do
        released=$(awk -v pid="$pid" '$1 == "release" && $2 == pid { print $3 }' "$WORK/logind/log" | tail -n 1)
        log "[$offset] inhibitor $pid, held when the signal came: released at ${released:-not yet}, the compositor locked at ${locked_at:-never}"
        check "[$offset] the inhibitor held when the signal came is let go only after the lock (logind waits for it)" \
            awk -v released="${released:-9999999999}" -v locked="${locked_at:-9999999999}" 'BEGIN { exit !(released + 0 >= locked + 0) }'
    done
    [ -n "$held_at_signal" ] || fail "[$offset] no inhibitor was held when the signal came"
    log "[$offset] how the shell heard of it: $(sed 's/\x1b\[[0-9;]*m//g' "$WORK/shell.log" | grep -a -E 'PreparingForSleep|"type":"prepareForSleep"' | tail -n 2 | sed 's/^.*\[Lockscreen\] //' | tr '\n' '|')"
    wake_and_settle
    unlock_by_escape || fail "[$offset] Escape did not unlock"
done
check "no protocol error" no_protocol_errors
