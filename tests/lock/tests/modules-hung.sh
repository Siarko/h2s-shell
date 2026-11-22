# A module whose files hang on read: the shell reads no module file on its GUI thread —
# module.json, qmldir and the texts for the import check come out of the host's file check, a process under a deadline —
# and nothing the lock screen needs waits for the module host (Profiles reads ModuleLists,
# plain values). Here every read the check makes hangs: H2S_SHELL_TEST_MODULE_CHECK_PATH puts
# a `head` that sleeps 40 s first on the check's PATH only (no real mount is involved; the
# rest of the shell keeps the real PATH), and the checks' deadline is 15 s
# (H2S_SHELL_TEST_MODULE_CHECK_MS).
#
# While the module is "hung" (pending): the shell is up, the lock locks and the password
# unlocks it. After the deadline: the module is failed, with the reason, and the shell goes on.

standins=$WORK/hung-check
mkdir -p "$standins" || abort "cannot make $standins"
cat > "$standins/head" << 'EOF'
#!/bin/sh
# A read that does not answer (a hung mount): longer than the host's deadline, then gives up
sleep 40 # fixed sleep: a stand-in that never answers
exit 1
EOF
chmod +x "$standins/head"
good=$(cd "$LOCKTEST_SHELL/tests/fixtures/modules/good" && pwd -P) || abort "no good fixture in the copy"

stack_start --modules "$good" --shell-env H2S_SHELL_TEST_MODULE_CHECK_PATH="$standins" \
    --shell-env H2S_SHELL_TEST_MODULE_CHECK_MS=15000
started=$(date +%s)

module_state() {
    shell_ipc modules list | python3 -I -c '
import json, sys
modules = [m for m in json.load(sys.stdin)["modules"] if m["directory"].endswith("/good")]
print(modules[0]["state"] if modules else "absent")'
}
module_state_is() { [ "$(module_state)" = "$1" ]; }
module_errors() {
    shell_ipc modules list | python3 -I -c '
import json, sys
modules = [m for m in json.load(sys.stdin)["modules"] if m["directory"].endswith("/good")]
print("; ".join(modules[0]["errors"]) if modules else "")'
}

check_within "$GUARD" "the shell answers while the module's files hang" module_state_is pending
check "the lock screen's settings are there (lockscreen.lockOnSleep, through Profiles)" \
    test -n "$(shell_ipc profiles status | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["values"].get("lockscreen.lockOnSleep"))')"

lock_by_ipc
check_within "$GUARD" "lock by IPC locks the compositor (module still hung)" compositor_locked
check_within "$GUARD" "the compositor confirmed it" state_is secure true
wake_prompt || fail "the prompt did not wake"
check_within "$GUARD" "the methods are known" state_is armed true
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "the password unlocks" compositor_unlocked
elapsed=$(($(date +%s) - started))
log "locked and unlocked ${elapsed} s after the start; the module: $(module_state)"
check "… all while the module's check was still hung (within its 15 s deadline)" test "$elapsed" -lt 15

check_within 25 "after the deadline the module is failed" module_state_is failed
check "… with the reason (module.json could not be read in time)" grep -q "module.json cannot be read" <<< "$(module_errors)"
log "its errors: $(module_errors)"
check "the same shell throughout" test "$(_find_shell_pid)" = "$SHELL_PID"
check "no protocol error" no_protocol_errors
