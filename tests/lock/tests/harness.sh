# The test bed checks itself: the stack comes up isolated, the real shell locks the
# nested compositor, a key wakes the prompt, and Escape (kept as a deliberate unlock for
# now, docs/plans/lockscreen.md §5) unlocks.

stack_start

# The shell and everything it starts inherit this environment: no real bus, no real
# runtime dir, no real config, the run's copy of the checkout
check "shell sees no real system bus" \
    test "$(process_env "$SHELL_PID" DBUS_SYSTEM_BUS_ADDRESS)" = "unix:path=$RUN/no-system-bus"
check "shell sees no real session bus" \
    test "$(process_env "$SHELL_PID" DBUS_SESSION_BUS_ADDRESS)" = "unix:path=$RUN/no-session-bus"
check "shell uses the private runtime dir" test "$(process_env "$SHELL_PID" XDG_RUNTIME_DIR)" = "$RUN"
check "shell uses a private config dir" test "$(process_env "$SHELL_PID" XDG_CONFIG_HOME)" = "$WORK/xdg/config"
check "shell runs from the run's copy of the checkout" \
    test "$(process_env "$SHELL_PID" H2S_SHELL_DIR)" = "$LOCKTEST_SHELL"
# setuid programs (pkexec, unix_chkpwd) gain nothing in it: no polkit dialog, no real
# password check, whatever the shell starts
check "shell runs with no new privileges" grep -qx 'NoNewPrivs:[[:space:]]*1' "/proc/$SHELL_PID/status"
for helper in $(pgrep -P "$SHELL_PID"); do
    # A helper that has exited since pgrep listed it says nothing either way
    environment=$({ tr '\0' '\n' < "/proc/$helper/environ"; } 2> /dev/null) || continue
    [ -n "$environment" ] || continue
    check "helper $helper ($(tr '\0' ' ' < "/proc/$helper/cmdline" 2> /dev/null | cut -c1-60)) sees no real system bus" \
        grep -qxF "DBUS_SYSTEM_BUS_ADDRESS=unix:path=$RUN/no-system-bus" <<< "$environment"
done
sleep 2 # the logind monitors and the sleep inhibitor start with the shell: time to fail
check "the real logind's inhibitor list can be read" real_inhibitor_list_readable
check "no process of the run holds an inhibitor on the real logind" test -z "$(run_inhibitors)"
# Connected to a bus, `gdbus monitor` and `systemd-inhibit` would keep running. Without
# one they fail at once, and the shell starts them again after a growing pause (1 s, 2 s,
# … for the inhibitor): a moment's look can catch one in its few milliseconds of failing.
# So a helper counts as running only when the same process is still there a second later.
bus_helpers=""
for pid in $(run_processes); do
    case "$(cat "/proc/$pid/comm" 2> /dev/null)" in
        gdbus | systemd-inhibit) bus_helpers="$bus_helpers $pid:$(cut -d' ' -f22 "/proc/$pid/stat" 2> /dev/null)" ;;
    esac
done
sleep 1
lasting=""
for entry in $bus_helpers; do
    # The same pid and the same start time: the same process
    [ "$(cut -d' ' -f22 "/proc/${entry%%:*}/stat" 2> /dev/null)" = "${entry#*:}" ] && lasting="$lasting ${entry%%:*}"
done
check "the shell's logind helpers failed, none running (found:${lasting:- none})" test -z "$lasting"

check "starts unlocked (compositor)" compositor_unlocked
check "starts unlocked (shell)" shell_status_is unlocked

lock_by_ipc
check_within 5 "lock by IPC locks the compositor" compositor_locked
check_within 5 "the compositor confirmed the lock (secure)" state_is secure true
check "shell says locked" shell_status_is locked
check "the shell's methods are the test stacks" state_is password_config "$WORK/pam/password"

sleep 1 # the surface fades in
screenshot locked-asleep
screenshot_ppm locked-asleep
check "prompt not shown before any input" state_is prompt_awake false

press_key Tab
check_within 3 "a key press wakes the prompt" state_is prompt_awake true
sleep 1 # the prompt fades in
screenshot locked-awake
screenshot_ppm locked-awake
changed=$(prompt_region_changes locked-asleep locked-awake)
log "pixels changed in the prompt's area: $changed"
check "the prompt's area changed when the prompt woke" test "$changed" -gt 500

press_key Escape
check_within 5 "Escape unlocks the compositor" compositor_unlocked
describe_lock
