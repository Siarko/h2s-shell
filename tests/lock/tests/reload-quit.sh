# Quitting right after a reload. After each reload Quickshell shows its reload popup unless
# the shell inhibits it: an engine of its own for some 2 s (6 s after a failed reload). While
# it lives Quickshell answers no IPC ("Not ready to accept queries yet.") and `qs kill` ends
# its event loop with the shell still standing: the shell is destroyed after the application
# and crashes on its way out (a crash report under Quickshell's cache, "Quickshell has crashed"
# in its log). The shell inhibits the popup after a reload that worked and after one that
# failed, logging a failure itself; the launcher's stop waits while the shell takes no
# requests.
#
# (1) A file saved: an IPC call right after the reload is answered.
# (2) A file broken: the same, and the shell said the reload failed, once; saved again
#     unchanged, said once more.
# (3) Fixed again and, right after that reload, the launcher's --restart: the old shell
#     ends without a crash, and a new one starts.
#
# --restart stops every h2s-shell that `qs list --all` finds: checked first that it lists
# only the shell under test (as restart-launcher does).

stack_start --dev

[ "$XDG_RUNTIME_DIR" = "$RUN" ] && [ -n "$RUN" ] || abort "not in the private runtime dir: not running --restart"
crash_dir=$XDG_CACHE_HOME/quickshell/crashes
crash_reports() { find "$crash_dir" -type f 2> /dev/null | wc -l; }
crashes_before=$(shell_log_count "Quickshell has crashed")
loads() { shell_log_count "Configuration Loaded"; }
failures() { shell_log_count "Failed to load configuration"; }
# A raw `qs ipc` (not the launcher's, which tries again): what it said, "" when taken
raw_ipc_refusal() { "$LOCKTEST_QS" ipc --pid "$SHELL_PID" call settings close 2>&1 | grep -a "Not ready" | head -n 1; }
edited=$LOCKTEST_SHELL/Bar.qml
cp "$edited" "$WORK/Bar.qml.orig" || abort "cannot copy $edited"

# ---- (1) A reload that worked ----
before=$(loads)
echo "// written by tests/lock reload-quit.sh (1)" >> "$edited"
wait_until 15 lines_more_than "$before" "Configuration Loaded" "$WORK/shell.log" || abort "the shell did not reload on a file change"
refusal=$(raw_ipc_refusal)
check "an IPC call right after a reload is answered${refusal:+ (it said: $refusal)}" test -z "$refusal"

# ---- (2) A reload that failed ----
before=$(failures)
printf '\nBroken {\n' >> "$edited"
wait_until 15 lines_more_than "$before" "Failed to load configuration" "$WORK/shell.log" || abort "a broken file did not fail a reload"
refusal=$(raw_ipc_refusal)
check "an IPC call right after a failed reload is answered${refusal:+ (it said: $refusal)}" test -z "$refusal"
check_within "$GUARD" "the shell said the reload failed" lines_more_than 0 "Reload failed, the shell runs on as it was" "$WORK/shell.log"
check "… once" test "$(shell_log_count "Reload failed, the shell runs on as it was")" = 1
check "… naming what failed" grep -aq "Reload failed, the shell runs on as it was: Failed to load configuration" "$WORK/shell.log"
# The same broken file saved again: the same error, a reload of its own, said again
before=$(failures)
cp "$edited" "$WORK/Bar.qml.broken" && cat "$WORK/Bar.qml.broken" > "$edited"
wait_until 15 lines_more_than "$before" "Failed to load configuration" "$WORK/shell.log" || abort "saving the broken file again did not fail a reload"
check_within "$GUARD" "the same failure saved again is said again" lines_more_than 1 "Reload failed, the shell runs on as it was" "$WORK/shell.log"
check "… once more" test "$(shell_log_count "Reload failed, the shell runs on as it was")" = 2

# ---- (3) Quit right after a reload ----
listed=$("$LOCKTEST_QS" list --all 2> /dev/null | awk '/^ *Process ID:/ { print $3 }')
[ "$listed" = "$SHELL_PID" ] && [ "$(process_env "$SHELL_PID" LOCKTEST_RUN_ID)" = "$LOCKTEST_RUN_ID" ] \
    || abort "qs list --all lists \"$listed\", not only the shell under test: not running --restart"
old_shell=$SHELL_PID
old_supervisor=$SUPERVISOR_PID
supervisor_environment "$old_supervisor"
before=$(loads)
cp "$WORK/Bar.qml.orig" "$edited"
echo "// written by tests/lock reload-quit.sh (3)" >> "$edited"
wait_until 15 lines_more_than "$before" "Configuration Loaded" "$WORK/shell.log" || abort "the shell did not reload once the file was fixed"
spawn "$WORK/restart.log" env --default-signal=HUP -i "${environment[@]}" "$LOCKTEST_LAUNCHER" --restart
check_within 15 "the old shell is stopped" test ! -e "/proc/$old_shell"
check_within "$GUARD" "its supervisor let it go and ended" test ! -e "/proc/$old_supervisor"
new_supervisor_of_run() {
    local pid
    for pid in $(run_processes); do
        [ "$pid" = "$old_supervisor" ] && continue
        { tr '\0' ' ' < "/proc/$pid/cmdline"; } 2> /dev/null | grep -q "$LOCKTEST_SHELL/scripts/launch\.sh" || continue
        [ "$(awk '{ print $6 }' "/proc/$pid/stat" 2> /dev/null)" = "$pid" ] || continue
        echo "$pid"
        return 0
    done
    return 1
}
check_within 10 "a new supervisor runs" new_supervisor_of_run
SUPERVISOR_PID=$(new_supervisor_of_run)
assert_supervisor_process "$SUPERVISOR_PID"
# A session leader, so its process group is its pid: stopped with the stack
PROCESS_GROUPS+=("$SUPERVISOR_PID")
check_within 15 "it starts a new shell" wait_for_new_shell "$old_shell" 15
log "the launcher's log: $(tail -n 4 "$RUN/h2s-shell-launcher.log" 2> /dev/null | tr '\n' '|')"
check "the old shell did not crash on its way out (\"Quickshell has crashed\")" \
    test "$(shell_log_count "Quickshell has crashed")" = "$crashes_before"
check "… no crash report ($crash_dir)" test "$(crash_reports)" = 0
