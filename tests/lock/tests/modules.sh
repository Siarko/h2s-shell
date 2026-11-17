# Modules in the real shell (notes/plans/modules.md): the shell started by the launcher with
# H2S_SHELL_MODULE_PATH naming the fixture modules (tests/fixtures/modules — a directory of
# modules, which the launcher's discovery turns into one canonical directory each), broken
# ones among them: a syntax error, a main that throws, a manifest that is not JSON, another
# with fields missing, a wrong API, keys outside the namespace, a forbidden import, two
# modules with one id, a missing program, a slot contribution that does not compile, a main
# that is a link out of its module. The shell comes up, `ipc call modules list` reports each
# fixture's state, a module's own IPC answers; the `good` fixture's widget is in the bar (a
# bar section of the test's config names it) and drawn, its settings page opens, and turning
# it off over IPC (`modules setEnabled`) takes the widget and its IPC away, on again brings
# them back — and the lock still locks and unlocks by password with all of them installed
# (plan §4, item 6).

fixtures=$(cd "$LOCKTEST_SHELL/tests/fixtures/modules" && pwd -P) || abort "no fixture modules in the copy"
stack_start --modules "$fixtures" \
    --settings '{"bar.left": [{"type": "good", "preset": ""}, {"type": "clock", "preset": ""}]}'

# One field of a module's status, the module found by its directory's name ("absent" when
# it is not listed)
module_field() {
    shell_ipc modules list | python3 -I -c '
import json, sys
modules = [m for m in json.load(sys.stdin)["modules"] if m["directory"].endswith("/" + sys.argv[1])]
value = modules[0][sys.argv[2]] if modules else "absent"
print(json.dumps(value) if isinstance(value, (list, dict)) else str(value).lower() if isinstance(value, bool) else value)' "$1" "$2"
}
module_state_is() { [ "$(module_field "$1" state)" = "$2" ]; }
modules_settled() {
    shell_ipc modules list | python3 -I -c '
import json, sys
data = json.load(sys.stdin)
sys.exit(0 if data["modules"] and not data["checkingPrograms"] and all(m["state"] != "pending" for m in data["modules"]) else 1)'
}
listed_modules() { process_env "$SHELL_PID" H2S_SHELL_MODULES | tr ':' '\n' | grep -c .; }

check "the launcher handed the shell one canonical directory per fixture (14)" test "$(listed_modules)" = 14
check "… in the fixtures' directory" test "$(process_env "$SHELL_PID" H2S_SHELL_MODULES | cut -d: -f1)" = "$fixtures/bad-manifest"
check "no safe mode" test -z "$(process_env "$SHELL_PID" H2S_SHELL_SAFE_MODE)"
check_within 10 "the modules have settled (the program check answered)" modules_settled
log "modules list: $(shell_ipc modules list | head -c 3000)"

check "good: loaded" module_state_is good loaded
check "good: no errors" test "$(module_field good errors)" = "[]"
check "vpn-slots: loaded (a VPN provider and the three VPN slots, API 1.1)" module_state_is vpn-slots loaded
check "broken: failed (its syntax error contained)" module_state_is broken failed
check "broken: the error names its file" grep -q "Main.qml" <<< "$(module_field broken errors)"
check "broken-main: loaded (its exception is the engine's to print)" module_state_is broken-main loaded
check "wrong-api: incompatible" module_state_is wrong-api incompatible
check "key-collision: loaded" module_state_is key-collision loaded
check "key-collision: the core's key refused" grep -q "lockscreen.enabled" <<< "$(module_field key-collision errors)"
check "bad-manifest: failed" module_state_is bad-manifest failed
check "bad-manifest-fields: failed" module_state_is bad-manifest-fields failed
check "forbidden-import: loaded, with a warning" grep -q "qs.singletons" <<< "$(module_field forbidden-import warnings)"
check "forbidden-import: loaded" module_state_is forbidden-import loaded
check "duplicate-id: loaded" module_state_is duplicate-id loaded
check "duplicate-id-2: reported as a duplicate" module_state_is duplicate-id-2 duplicate
check "needs-program: missing-program" module_state_is needs-program missing-program
check "needs-program: the missing program named" test "$(module_field needs-program missingPrograms)" = '["h2s-fixture-no-such-program"]'
check "a module's own IPC handler answers (good's main)" test "$(shell_ipc good ping)" = "pong 1"
check "… and reads its setting through its handle" test "$(shell_ipc good greeting)" = "hello"
check "broken-slot: loaded (its slot file is built only where the slot is)" module_state_is broken-slot loaded
check "link-escape: failed (its main links out of its directory: never opened)" module_state_is link-escape failed
check "link-escape: said so" grep -q "leaves the module directory" <<< "$(module_field link-escape errors)"
check "the start guard: a fresh process counts 0" test "$(shell_ipc modules list | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["startGuard"]["count"])')" = 0
check "… in its file, under its identity (pid, no crash)" test "$(cat "$RUN/h2s-shell-module-starts" 2> /dev/null)" = "$SHELL_PID: 0"

# The good fixture's widget in the bar (bar.left names it), drawn
cell_rect() { shell_ipc shelltest cellRect good; }
cell_shown() { python3 -I -c 'import json,sys; r=json.loads(sys.argv[1]); sys.exit(0 if r.get("width",0) > 0 and r.get("height",0) > 0 else 1)' "$(cell_rect)"; }
check_within 10 "good's widget is in the bar" cell_shown
check "… built with its module's handle (set before it completed)" test "$(shell_ipc good widgetHandle)" = true
rect=$(cell_rect)
log "good's cell: $rect"
screenshot good-widget
screenshot_ppm good-on

# Its settings page (System tab, from its manifest)
check "its settings page opens (settings openPage good)" test -z "$(shell_ipc settings openPage good)"
sleep 1
screenshot good-settings
check "… built without an error (a page that fails is recorded in its status)" test "$(module_field good errors)" = "[]"
shell_ipc settings close > /dev/null

# Its popup (its manifest's popupPanel), opened by a click on its cell
cell_x=$(python3 -I -c 'import json,sys; r=json.loads(sys.argv[1]); print(r["x"] + r["width"] // 2)' "$rect")
cell_y=$(python3 -I -c 'import json,sys; r=json.loads(sys.argv[1]); print(r["y"] + r["height"] // 2)' "$rect")
move_pointer "$cell_x" "$cell_y"
send_input "click left"
popup_is() { shell_ipc shelltest popupState | python3 -I -c 'import json,sys; s=json.load(sys.stdin); sys.exit(0 if (s["open"], s["content"]) == (sys.argv[1] == "open", sys.argv[2]) else 1)' "$1" "$2"; }
check_within 5 "a click on its cell opens its popup panel" popup_is open good
screenshot good-popup

# Off over IPC: the widget and its IPC go; on again: back
check "modules setEnabled good false" test -z "$(shell_ipc modules setEnabled good false)"
check_within 5 "good: disabled" module_state_is good disabled
cell_gone() { ! cell_shown; }
check_within 5 "its widget left the bar (its bar entry kept, nothing shown)" cell_gone
popup_gone() { ! popup_is open good; }
check_within 5 "… and its popup, open, closed" popup_gone
screenshot_ppm good-off
region_changes() {
    python3 -I -c "$_PPM_READER"'
import json
rect = json.loads(sys.argv[3])
width, height, first = read_ppm(sys.argv[1])
_, _, second = read_ppm(sys.argv[2])
count = 0
for y in range(rect["y"], min(height, rect["y"] + rect["height"])):
    for x in range(rect["x"], min(width, rect["x"] + rect["width"])):
        offset = (y * width + x) * 3
        if max(abs(first[offset + c] - second[offset + c]) for c in range(3)) > 40:
            count += 1
print(count)' "$WORK/$1.ppm" "$WORK/$2.ppm" "$3"
}
changed=$(region_changes good-on good-off "$rect")
log "pixels of good's cell that changed when it went: $changed"
check "the screenshot showed it (its cell changed when it went)" test "${changed:-0}" -gt 20
check "its IPC target went with its main" test "$(shell_ipc good ping 2>&1)" != "pong 1"
check "modules setEnabled good true" test -z "$(shell_ipc modules setEnabled good true)"
check_within 5 "good: loaded again" module_state_is good loaded
check_within 10 "… its widget back in the bar" cell_shown
check "… its IPC back, one main" test "$(shell_ipc good ping)" = "pong 1"
check "the shell logged the broken module" grep -aq "\[Modules\] broken failed" "$WORK/shell.log"
check "the shell logged the exception it could not see" grep -aq "broken-main fixture: thrown on purpose" "$WORK/shell.log"

# The lock, with every one of them installed
lock_by_ipc
check_within 5 "lock by IPC locks the compositor" compositor_locked
check_within 5 "the compositor confirmed it" state_is secure true
wake_prompt || fail "the prompt did not wake"
check_within 5 "the methods are known" state_is armed true
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked
check "the same shell throughout (nothing crashed it)" test "$(_find_shell_pid)" = "$SHELL_PID"
check "no protocol error" no_protocol_errors

# The start guard counts Quickshell's in-place relaunches after a crash (what the launcher
# cannot see): a crash past 10 s comes back in the same process with a count of 1 — no safe
# mode yet (2 in a row would be). A fresh process (this start) counted 0 (checked above).
ulimit -c 0
started=$(stat -c %Y "/proc/$SHELL_PID")
until [ $(($(date +%s) - started)) -ge 12 ]; do sleep 0.5; done
crashed_shell=$SHELL_PID
failed_relaunches_before=$(shell_log_count 'Launching config: ""')
signal_shell SEGV
sleep 2
guard_count() { shell_ipc modules list 2> /dev/null | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["startGuard"]["count"])'; }
guard_count_is() { [ "$(guard_count)" = "$1" ]; }
if [ "$(shell_log_count 'Launching config: ""')" -gt "$failed_relaunches_before" ]; then
    # Quickshell 0.3.2's relaunch sometimes loses its config path (restart-crash-locked.sh):
    # the launcher starts a fresh process, which counts 0
    log "Quickshell's relaunch lost its config path: the launcher's restart takes over"
    check_within 15 "the launcher started a fresh shell" wait_for_new_shell "$crashed_shell" 15
    check_within 20 "… which counts 0 (a fresh process)" guard_count_is 0
else
    check "relaunched in the same process" test "$SHELL_PID" = "$crashed_shell"
    check_within 20 "the relaunched shell counted the crash: 1" guard_count_is 1
    check "… in its file, under its identity (pid:crash)" grep -Eq "^$SHELL_PID:[0-9]+ 1\$" "$RUN/h2s-shell-module-starts"
    # Modules arrive after the shell is up (their files are read by a process): waited for
    check_within 15 "… not safe mode yet (good loads)" module_state_is good loaded
fi
