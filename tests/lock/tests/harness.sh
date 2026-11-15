# The test bed checks itself: the stack comes up isolated, the real shell locks the
# nested compositor, a key wakes the prompt, and Escape (kept as a deliberate unlock for
# now, docs/plans/lockscreen.md §5) unlocks.

inhibitors_before=$(real_inhibitors)
stack_start

# The shell and everything it starts inherit this environment: no real bus, no real
# runtime dir, no real config
check "shell sees no real system bus" \
    test "$(process_env "$SHELL_PID" DBUS_SYSTEM_BUS_ADDRESS)" = "unix:path=$RUN/no-system-bus"
check "shell sees no real session bus" \
    test "$(process_env "$SHELL_PID" DBUS_SESSION_BUS_ADDRESS)" = "unix:path=$RUN/no-session-bus"
check "shell uses the private runtime dir" test "$(process_env "$SHELL_PID" XDG_RUNTIME_DIR)" = "$RUN"
check "shell uses a private config dir" test "$(process_env "$SHELL_PID" XDG_CONFIG_HOME)" = "$WORK/xdg/config"
for helper in $(pgrep -P "$SHELL_PID"); do
    check "helper $helper ($(tr '\0' ' ' < "/proc/$helper/cmdline" 2> /dev/null | cut -c1-60)) sees no real system bus" \
        test "$(process_env "$helper" DBUS_SYSTEM_BUS_ADDRESS)" = "unix:path=$RUN/no-system-bus"
done
sleep 2 # the logind monitors and the sleep inhibitor start with the shell: time to fail
check "no h2s-shell inhibitor added to the real logind" test "$(real_inhibitors)" = "$inhibitors_before"
# Connected to a bus, `gdbus monitor` and `systemd-inhibit` would still be running
bus_helpers=""
for pid in $(run_processes); do
    case "$(cat "/proc/$pid/comm" 2> /dev/null)" in
        gdbus | systemd-inhibit) bus_helpers="$bus_helpers $pid" ;;
    esac
done
check "the shell's logind helpers failed, none running (found:${bus_helpers:- none})" test -z "$bus_helpers"

check "starts unlocked (compositor)" compositor_unlocked
check "starts unlocked (shell)" shell_status_is unlocked

lock_by_ipc
check_within 5 "lock by IPC locks the compositor" compositor_locked
check_within 5 "the compositor confirmed the lock (secure)" state_is secure true
check "shell says locked" shell_status_is locked
check_within 5 "the shell's methods are the test stacks" state_is auth.passwordConfig "$WORK/pam/password"

sleep 1 # the surface takes keys after 300 ms, and fades in
screenshot locked-asleep
check "prompt not shown before any input" state_is promptActive false

press_key Tab
check_within 3 "a key press wakes the prompt" state_is promptActive true
sleep 1 # the prompt fades in
screenshot locked-awake
if cmp -s "$WORK/locked-asleep.png" "$WORK/locked-awake.png"; then
    fail "the screen changed when the prompt woke (screenshots identical)"
else
    pass "the screen changed when the prompt woke"
fi

press_key Escape
check_within 5 "Escape unlocks the compositor" compositor_unlocked
describe_lock
