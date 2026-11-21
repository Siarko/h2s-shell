# Module discovery is on the path of every start of the shell, the re-lock after a crash
# included, and it is bounded (scripts/launch.sh, discover_modules): a search that hangs (a
# hung mount under a data dir) is cut off after 3 s and the shell starts without modules.
# Here every search hangs — H2S_LAUNCHER_TEST_TIMINGS "discoveryhang=60": the search sleeps
# 60 s first; no real mount is involved.
#
# (1) The first start: the shell is up within the bound, with no modules although one is
#     installed, the launcher said why, and the search left nothing running. The shell's own
#     search again (`modules rediscover`, which runs the launcher's search: it hangs too) is
#     bounded as well: cut off, said in the shell's log, the modules left as they are, nothing
#     left running.
# (2) Killed while locked: the new shell comes up through the same bounded search and locks
#     again — while locked it refuses to search again or to confirm a module over IPC; the
#     password unlocks it.
# (3) A stop request (SIGUSR1, as a --restart's stop_shell sends) while the search runs:
#     the supervisor ends without starting a shell — one started then would be a shell the
#     restarting launcher never sees, and the restart would not happen.

make_module() {
    mkdir -p "$1" || abort "cannot make $1"
    printf '{ "id": "%s", "name": "%s", "version": "1.0.0", "api": "1.0" }\n' "$2" "$2" > "$1/module.json"
}
make_module "$XDG_DATA_HOME/h2s-shell/modules/alpha" alpha

stack_start --launcher-timings "first=0.2 discoveryhang=60"

launcher_log=$RUN/h2s-shell-launcher.log
# Seconds from the first line matching $1 to the next one matching $2, in the launcher's log
seconds_between() {
    awk -v from="$1" -v to="$2" '
        function seconds(line,   parts) { split(substr(line, 12, 12), parts, ":"); return parts[1] * 3600 + parts[2] * 60 + parts[3] }
        start == "" && index($0, from) { start = seconds($0); next }
        start != "" && index($0, to) { printf "%.1f", seconds($0) - start; exit }' "$launcher_log"
}
hung_searches() {
    local pid
    for pid in $(test_pgrep -x sleep); do
        [ "$(tr '\0' ' ' < "/proc/$pid/cmdline" 2> /dev/null)" = "sleep 60 " ] && echo "$pid"
    done
}

# ---- (1) the first start ----
took=$(seconds_between "supervising the shell" "started the shell: pid")
log "from the supervisor's start to the shell's: ${took:-?} s"
check "the shell started within the bound (3 s, and a little)" awk -v took="${took:-99}" 'BEGIN { exit !(took < 4.5) }'
check "the launcher said the search took too long" grep -aq "module discovery took longer than 3 s: starting the shell without modules" "$launcher_log"
check "no modules for the shell" test -z "$(process_env "$SHELL_PID" H2S_SHELL_MODULES)"
check "… so the installed one is not loaded" test "$(shell_ipc modules list | grep -c '"state":"loaded"')" = 0
check "the cut-off search left nothing running" test -z "$(hung_searches)"

# ---- (1b) the shell's own search again ----
shell_logged() { [ "$(shell_log_count "$1")" -gt 0 ]; }
check "modules rediscover: started" test -z "$(shell_ipc modules rediscover)"
check_within 10 "… cut off by the shell's bound, said in its log" shell_logged "the module search took longer than"
check "… the modules left as they are: none loaded" test "$(shell_ipc modules list | grep -c '"state":"loaded"')" = 0
check_within 5 "… the cut-off search left nothing running" test -z "$(hung_searches)"

# ---- (2) killed while locked: the re-lock goes through the bounded search ----
lock_by_ipc
check_within 5 "locked" compositor_locked
check_within 5 "confirmed" state_is secure true
old_shell=$SHELL_PID
start_lock_watch kill
signal_shell KILL
check_within 3 "the killed shell is gone" test ! -e "/proc/$old_shell"
check_within 10 "the launcher starts a new shell" wait_for_new_shell "$old_shell" 10
check_within 10 "the new shell locks again" state_is phase locked
check_within 5 "the compositor confirmed the new shell's lock" state_is secure true
stop_lock_watch
check "the compositor never reported unlocked across the restart" lock_watch_never_unlocked
check "locked: modules rediscover refused" test "$(shell_ipc modules rediscover)" = "Refused while the session is locked"
check "locked: modules confirm refused" test "$(shell_ipc modules confirm alpha)" = "Refused while the session is locked"
check "locked: modules setEnabled refused" test "$(shell_ipc modules setEnabled alpha true)" = "Refused while the session is locked"
check "the search was cut off again" test "$(grep -ac "module discovery took longer than 3 s" "$launcher_log")" -ge 2
wake_prompt || fail "the new shell's prompt did not wake"
check_within 5 "the methods are known" state_is armed true
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked
check "the cut-off searches left nothing running" test -z "$(hung_searches)"

# ---- (3) a stop request while the search runs ----
starts=$(grep -ac "started the shell: pid" "$launcher_log")
restarts=$(grep -ac "starting it again in" "$launcher_log")
restart_decided() { [ "$(grep -ac "starting it again in" "$launcher_log")" -gt "$restarts" ]; }
signal_shell KILL
wait_until 5 restart_decided \
    || abort "the launcher did not decide to start the shell again"
# The pause is 0.2 s; the search then runs for 3 s
sleep 1
supervisor_release
check_within 6 "the supervisor ended" test ! -e "/proc/$SUPERVISOR_PID"
check "… without starting a shell" test "$(grep -ac "started the shell: pid" "$launcher_log")" = "$starts"
check "… having been told during the search" grep -aq "told to let the shell go (SIGUSR1)" "$launcher_log"
check "no shell process of this test" test -z "$(_find_shell_pid)"
check_within 5 "the search left nothing running" test -z "$(hung_searches)"
