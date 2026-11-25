# Lock requests around a reload. A Quickshell reload builds the
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
# (3) A PrepareForSleep while the shell reloads: the lock goes up, and logind — which
#     refuses new inhibitors once the sleep is under way — would sleep only after the
#     compositor locked: the last inhibitor held when the signal came is let go after the
#     lock, and the lock comes within logind's 5 s maximum delay of the signal. The new
#     generation may hear of the sleep before it has read its settings (lock before sleep
#     still at its default, off): the setting read then locks (LockRules._settingsChanged).
# Lock before sleep is off by default: switched on here.

stack_start --dev --logind --settings '{"lockscreen.lockOnSleep": true}'

wait_until 5 logind_monitor_running || abort "the logind monitor did not start"
wait_until 5 inhibitor_held || abort "the inhibitor is not held"
reloads() { shell_log_count "Configuration Loaded"; }
# When the shell logged the compositor's confirmation, the first after line <n> of its log
# (the launcher starts it with --log-times: wall-clock stamps), as seconds since the epoch
confirmed_after() {
    local after line
    # Read whole, then searched: grep -m 1 at the end of a pipe ends early, and the writers
    # still writing then die of SIGPIPE
    after=$(tail -n +"$(($1 + 1))" "$WORK/shell.log" | sed 's/\x1b\[[0-9;]*m//g')
    line=$(grep -a -m 1 '"type":"compositorLocked"' <<< "$after")
    [ -n "$line" ] || return 0
    date -d "${line:0:23}" +%s.%N 2> /dev/null
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
check_within "$GUARD" "locked" compositor_locked
echo "// written by tests/lock reload-window.sh while locked" >> "$LOCKTEST_SHELL/singletons/Theme.qml"
reloads_before=$(reloads)
unlock_for_test || fail "logind's Unlock did not unlock"
launcher_ipc lockscreen lock > "$WORK/ipc-1.out" 2>&1
check "a lock by the launcher's IPC right after the unlock is taken (status 0)" test $? = 0
check_within "$GUARD" "… and locks" compositor_locked
check "no reload came with the unlock" test "$(reloads)" = "$reloads_before"
unlock_for_test || fail "logind's Unlock did not unlock"
wait_until 5 inhibitor_held
logind_signal sleep
check_within "$GUARD" "a PrepareForSleep right after an unlock locks" compositor_locked
wait_until "$GUARD" inhibitor_released
log "PrepareForSleep to the release (the lock confirmed before it): $(release_seconds_after_signal) s"
check "… locked and let go within 4 s of the PrepareForSleep (logind sleeps 5 s after it at the latest)" \
    released_after_signal_within 4
wake_and_settle
unlock_for_test || fail "logind's Unlock did not unlock"
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
check_within "$GUARD" "… and the screen locks" compositor_locked
check "the call did not end on \"Not ready\"" test "$(grep -c 'Not ready' "$WORK/ipc-2.out")" = 0
wait_until 10 shell_status_is locked
unlock_for_test || fail "logind's Unlock did not unlock"

# ---- (3) PrepareForSleep while the shell reloads ----
# What decides it is what logind waits for (systemd's src/login/logind-dbus.c): after
# PrepareForSleep(true) it sleeps as soon as no delay inhibitor is left, or InhibitDelayMaxSec
# (5 s) after the signal, whichever comes first — and it refuses new delay inhibitors until
# the wake (the stand-in does too). So the inhibitors that count are the ones held when the
# signal went out, and the machine sleeps at min(the last of their releases, signal + 5 s):
# the lock must be confirmed by then. One of them may be an earlier reload's, still in its
# grace, let go before the lock: harmless, logind waits for the last.
grace=$(sed -n 's/.*readonly property int graceSeconds: *\([0-9.]*\).*/\1/p' "$LOCKTEST_SHELL/singletons/lock/SleepInhibitor.qml")
[ -n "$grace" ] || abort "graceSeconds not found in SleepInhibitor.qml"
delay_max=5
for offset in 0 0.4; do
    wait_until 10 shell_status_is unlocked
    wait_until 5 inhibitor_held || fail "[$offset] the inhibitor is not held before the reload"
    before=$(shell_log_count "Reloading configuration")
    echo "// written by tests/lock reload-window.sh, unlocked (3, $offset)" >> "$LOCKTEST_SHELL/singletons/Theme.qml"
    wait_until 5 reloading_since "$before" || abort "the shell did not reload on a file change"
    sleep "$offset" # fixed sleep: the moment into the reload is the subject (SERIAL)
    signal_line=$(wc -l < "$WORK/shell.log")
    logind_signal sleep
    # The signal's time: taken by logind_signal once the stand-in refuses new inhibitors, and
    # each hold's time is taken before the stand-in looks — so a hold recorded is one granted
    # before the signal, and one granted just before it (the new generation starting as the
    # signal goes out) is held at the signal, as logind would count it
    signal_at=$LOGIND_SIGNAL_AT
    # The inhibitors held when the signal went out — the ones logind waits for — oldest first;
    # read again at each use, as a hold granted just before the signal may be written after it
    held_at_signal() { awk -v since="$signal_at" '$3 + 0 > since + 0 { next } $1 == "hold" { held[$2] = ++n } $1 == "release" { delete held[$2] } END { for (pid in held) print held[pid], pid }' "$WORK/logind/log" | sort -n | awk '{ print $2 }'; }
    if wait_until 8 compositor_locked; then
        pass "[$offset] a PrepareForSleep during a reload locks"
    else
        fail "[$offset] a PrepareForSleep during a reload locks (the lid-close lock was LOST)"
    fi
    # Until the shell logged the confirmation and every inhibitor held at the signal was let
    # go, or logind's maximum delay ran out (a wait, not a fixed sleep)
    settled() {
        [ -n "$(confirmed_after "$signal_line")" ] || return 1
        awk -v now="${EPOCHREALTIME/,/.}" -v since="$signal_at" -v max="$delay_max" 'BEGIN { exit !(now + 0 > since + max) }' && return 0
        local pid
        for pid in $(held_at_signal); do
            awk -v pid="$pid" '$1 == "release" && $2 == pid { found = 1 } END { exit !found }' "$WORK/logind/log" || return 1
        done
    }
    wait_until 8 settled || log "[$offset] not settled within 8 s (confirmation logged and the inhibitors let go)"
    held_at_signal=$(held_at_signal)
    locked_at=$(confirmed_after "$signal_line")
    last_release=0
    released=""
    for pid in $held_at_signal; do
        released=$(awk -v pid="$pid" '$1 == "release" && $2 == pid { print $3 }' "$WORK/logind/log" | tail -n 1)
        log "[$offset] inhibitor $pid, held when the signal came: released at ${released:-not yet}"
        last_release=$(awk -v a="$last_release" -v b="${released:-9999999999}" 'BEGIN { printf "%.6f", (b + 0 > a + 0) ? b : a }')
    done
    [ -n "$held_at_signal" ] || fail "[$offset] no inhibitor was held when the signal came (logind sleeps at once)"
    # Asked for once the shell knew of the sleep: none. The stand-in refuses every request
    # while the sleep is under way and a hold recorded is one granted before the signal, so
    # its record cannot tell; the shell's own log can, in its order: no holdInhibitor effect
    # after the shell took the PrepareForSleep (a request made earlier, as the new generation
    # starts, is refused by logind and harmless)
    holds_during=$(tail -n +"$((signal_line + 1))" "$WORK/shell.log" | sed 's/\x1b\[[0-9;]*m//g' \
        | awk '/\[Lockscreen\] event \{"type":"prepareForSleep"/ { known = 1 } known && /\[Lockscreen\] effect \{"type":"holdInhibitor"/ { n++ } END { print n + 0 }')
    refusals=$(awk -v since="$signal_at" '$1 == "refuse" && $3 + 0 > since + 0 { n++ } END { print n + 0 }' "$WORK/logind/log")
    sleeps_at=$(awk -v r="$last_release" -v s="$signal_at" -v max="$delay_max" 'BEGIN { c = s + max; printf "%.6f", (r + 0 < c) ? r : c }')
    # The timings. The old generation's inhibitor is the newest held at the signal: its input
    # closed at the old generation's teardown, and it ended `grace` seconds after that.
    log "[$offset] timings (s): $(awk -v s="$signal_at" -v t="${released:-9999999999}" -v g="$grace" -v l="${locked_at:-9999999999}" -v z="$sleeps_at" -v r="$last_release" -v max="$delay_max" \
        'BEGIN { td = t - g; printf "signal->teardown %.3f, teardown->locked %.3f, signal->locked %.3f, logind sleeps at signal+%.3f (%s), margin %.3f", td - s, l - td, l - s, z - s, (r + 0 < s + max) ? "last release" : "InhibitDelayMaxSec", z - l }'); holdInhibitor after the shell took the sleep: $holds_during, refused: $refusals"
    check "[$offset] no inhibitor was asked for once the shell took the sleep (logind refuses them)" test "$holds_during" = 0
    check "[$offset] logind would sleep only after the lock: the last inhibitor held at the signal is let go after it, within InhibitDelayMaxSec of the signal" \
        awk -v z="$sleeps_at" -v l="${locked_at:-9999999999}" 'BEGIN { exit !(l + 0 <= z + 0) }'
    log "[$offset] how the shell heard of it: $(sed 's/\x1b\[[0-9;]*m//g' "$WORK/shell.log" | grep -a -E 'PreparingForSleep|"type":"prepareForSleep"' | tail -n 2 | sed 's/^.*\[Lockscreen\] //' | tr '\n' '|')"
    wake_and_settle
    unlock_for_test || fail "[$offset] logind's Unlock did not unlock"
done
check "no protocol error" no_protocol_errors
