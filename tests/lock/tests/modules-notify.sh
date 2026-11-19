# A module's progress notification (module API 1.33) on its real path: the `good` fixture's
# main calls module.notify with a progress over its own IPC (`good progress`); the handle
# sends with the real gdbus to the shell's own notification server on the bed's private
# session bus. A test tree is in module test mode, where notifications are only recorded:
# H2S_SHELL_TEST_MODULE_NOTIFY=1 has them sent all the same. Checked from the shell's state
# (`shelltest notificationState`) and the module's (`good progressState`):
#
# - the notification is there, its bar at the module's value, its toast staying
#   ("whileRunning");
# - its action pressed (as its card runs it) reaches the module's callback, which cancels
#   the job: the entry stays, its state cancelled;
# - the module turned off (`modules setEnabled`): its notification is closed, the entry
#   gone;
# - no gdbus process left over.

good=$(cd "$LOCKTEST_SHELL/tests/fixtures/modules/good" && pwd -P) || abort "no good fixture in the copy"
stack_start --session-bus --modules "$good" --shell-env H2S_SHELL_TEST_MODULE_NOTIFY=1
check_within 10 "the shell's notification server is on the private bus" notification_server_up

good_state_is() {
    shell_ipc modules list | python3 -I -c '
import json, sys
modules = [m for m in json.load(sys.stdin)["modules"] if m["id"] == "good"]
sys.exit(0 if modules and modules[0]["state"] == sys.argv[1] else 1)' "$1"
}
check_within 15 "good: loaded" good_state_is loaded
check "the seam is in force" grep -q H2S_SHELL_TEST_MODULE_NOTIFY <<< "$(shell_ipc modules list)"

# job_is <python expression over the module's notification's entry `n`, None when it is
# not there>
job_is() {
    shell_ipc shelltest notificationState | python3 -I -c '
import json, sys
n = next((n for n in json.load(sys.stdin) if n["summary"] == "Good job"), None)
sys.exit(0 if eval(sys.argv[1]) else 1)' "$1"
}
module_job_is() { [ "$(shell_ipc good progressState)" = "$1" ]; }

check "good progress: a handle" test "$(shell_ipc good progress)" != none
check_within 5 "the module's notification is on the private bus, its bar at 30" \
    job_is 'n is not None and n["progress"]["shown"] and n["progress"]["value"] == 0.3 and n["progress"]["state"] == "running"'
check_within 5 "… its toast stays (whileRunning)" job_is 'n["toast"] == {"shown": True, "duration": 0}'
check_within 5 "… the module's handle runs" module_job_is running
id=$(shell_ipc shelltest notificationState | python3 -I -c '
import json, sys
print(next(n["id"] for n in json.load(sys.stdin) if n["summary"] == "Good job"))')
log "the module's notification: $id"
screenshot module-progress

check "its action pressed as its card runs it" test -z "$(shell_ipc shelltest notificationAction "$id" stop)"
check_within 5 "… reached the module's callback: the job cancelled" module_job_is cancelled
check_within 5 "… the entry stays, cancelled" job_is 'n is not None and n["progress"]["state"] == "cancelled"'

check "modules setEnabled good false" test -z "$(shell_ipc modules setEnabled good false)"
check_within 5 "good: disabled" good_state_is disabled
check_within 5 "turned off: its notification closed, the entry gone" job_is 'n is None'

no_gdbus_left() { ! test_pgrep -f "org.freedesktop.Notifications" > /dev/null; }
check_within 5 "no gdbus process left over" no_gdbus_left
