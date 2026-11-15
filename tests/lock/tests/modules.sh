# Modules in the real shell (docs/plans/modules.md): the shell started by the launcher with
# H2S_SHELL_MODULES naming the fixture modules (tests/fixtures/modules — a directory of
# modules, which the launcher's discovery turns into one canonical directory each), broken
# ones among them: a syntax error, a main that throws, a manifest that is not JSON, another
# with fields missing, a wrong API, keys outside the namespace, a forbidden import, two
# modules with one id, a missing program. The shell comes up, `ipc call modules list` reports
# each fixture's state, a module's own IPC answers — and the lock still locks and unlocks by
# password with all of them installed (plan §4, item 6).

fixtures=$(cd "$LOCKTEST_SHELL/tests/fixtures/modules" && pwd -P) || abort "no fixture modules in the copy"
stack_start --modules "$fixtures"

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

check "the launcher handed the shell one canonical directory per fixture (11)" test "$(listed_modules)" = 11
check "… in the fixtures' directory" test "$(process_env "$SHELL_PID" H2S_SHELL_MODULES | cut -d: -f1)" = "$fixtures/bad-manifest"
check "no safe mode" test -z "$(process_env "$SHELL_PID" H2S_SHELL_SAFE_MODE)"
check_within 10 "the modules have settled (the program check answered)" modules_settled
log "modules list: $(shell_ipc modules list | head -c 3000)"

check "good: loaded" module_state_is good loaded
check "good: no errors" test "$(module_field good errors)" = "[]"
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
check "a module's own IPC handler answers (good's main)" test "$(shell_ipc good-fixture ping)" = "pong 1"
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
