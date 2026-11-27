# The launcher's side of modules (scripts/launch.sh):
#
# (1) Discovery: H2S_SHELL_MODULES as the shell gets it — H2S_SHELL_MODULE_PATH's entries
#     first, then $XDG_DATA_HOME/h2s-shell/modules/*, then each data dir's
#     h2s-shell/modules/* (--data-dirs); only directories with a module.json; canonical (a
#     symlink resolved), each once. A module
#     with an id already taken comes later in the list and the shell reports it. An inherited
#     H2S_SHELL_MODULES (the launcher's output, which a --restart run from inside the shell
#     inherits) is not input: a stale module named there is not loaded.
# (2) Crash-loop safe mode: the shell killed quickly twice (SIGKILL, through signal_shell,
#     which checks the pid is the shell under test) — the third start has
#     H2S_SHELL_SAFE_MODE=1, loads no module, and the lock still works; a start that lives
#     past the quick-death window (30 s) ends it, and the next start picks up a module
#     installed meanwhile (discovery runs before every start).
# (3) Sources and confirmations: each module's
#     source in `modules list` (a data dir the user can write is not the system's); the first
#     start acknowledges the hand-placed modules it finds
#     on (the config file keeps them) and writes the modules on to the runtime directory; the
#     safe-mode start tells them and loads them in place on `modules loadWithoutSafeMode`; the
#     module installed meanwhile starts unconfirmed — `modules setEnabled` refuses it, `modules
#     confirm` with its directory turns it on (without, or with another, it is refused) and the config file keeps it; one put there while the shell runs is
#     found by `modules rediscover`, without a restart.
#
# The launcher's first pause is 0.2 s here (H2S_LAUNCHER_TEST_TIMINGS): the schedule of the
# restarts is not the subject.

make_module() {
    mkdir -p "$1" || abort "cannot make $1"
    printf '{ "id": "%s", "name": "%s", "version": "1.0.0", "api": "1.0" }\n' "$2" "$2" > "$1/module.json"
}
canonical() { (cd "$1" && pwd -P); }

home_modules=$XDG_DATA_HOME/h2s-shell/modules
system_root=$WORK/system-data
system_modules=$system_root/h2s-shell/modules
make_module "$WORK/dev/explicit" explicit
make_module "$home_modules/alpha" alpha
make_module "$home_modules/beta" beta
mkdir -p "$home_modules/not-a-module"
# The same module twice: data home, and a symlink to it among the system's
mkdir -p "$system_modules" && ln -s "$home_modules/alpha" "$system_modules/alpha-link" || abort "cannot link alpha"
make_module "$system_modules/beta-copy" beta
make_module "$system_modules/zeta" zeta
# An old list inherited (as from a shell started before a module update): a module of an id
# the list also has elsewhere, which would win if this were taken as input
make_module "$WORK/stale/old-alpha" alpha
export H2S_SHELL_MODULES="$WORK/stale/old-alpha:$WORK/stale"
expected="$(canonical "$WORK/dev/explicit"):$(canonical "$home_modules/alpha"):$(canonical "$home_modules/beta"):$(canonical "$system_modules/beta-copy"):$(canonical "$system_modules/zeta")"

stack_start --modules "$WORK/dev/explicit" --data-dirs "$system_root:$WORK/no-such-dir" --launcher-timings "first=0.2"

module_field() {
    shell_ipc modules list | python3 -I -c '
import json, sys
data = json.load(sys.stdin)
if sys.argv[1] == "-":
    print(str(data[sys.argv[2]]).lower())
else:
    modules = [m for m in data["modules"] if m["directory"].endswith("/" + sys.argv[1])]
    print(modules[0][sys.argv[2]] if modules else "absent")' "$1" "$2"
}
module_state_is() { [ "$(module_field "$1" state)" = "$2" ]; }
# The state of every module the shell lists, in its order ("explicit: loaded, alpha: …")
module_states() {
    shell_ipc modules list | python3 -I -c '
import json, sys
print(", ".join("%s: %s" % (module["directory"].rsplit("/", 1)[-1], module["state"]) for module in json.load(sys.stdin)["modules"]))'
}
module_states_are() { [ "$(module_states)" = "$1" ]; }
safe_mode_of_shell() { process_env "$SHELL_PID" H2S_SHELL_SAFE_MODE; }

# ---- (1) discovery ----
log "H2S_SHELL_MODULES: $(process_env "$SHELL_PID" H2S_SHELL_MODULES)"
check "the order: H2S_SHELL_MODULE_PATH, data home, data dirs; canonical; the symlinked duplicate once; the inherited list ignored" \
    test "$(process_env "$SHELL_PID" H2S_SHELL_MODULES)" = "$expected"
check "the inherited list's stale module: not loaded" test "$(module_field old-alpha state)" = absent
check "H2S_SHELL_MODULE_PATH is passed on unchanged" test "$(process_env "$SHELL_PID" H2S_SHELL_MODULE_PATH)" = "$WORK/dev/explicit"
# (Modules arrive after the shell answers: their files are read by a process. Waited for,
# here and after every start below)
check_within 15 "explicit: loaded" module_state_is explicit loaded
check_within 15 "alpha: loaded" module_state_is alpha loaded
check_within 15 "beta (data home): loaded" module_state_is beta loaded
check "beta-copy (data dirs, same id): reported as a duplicate" module_state_is beta-copy duplicate
check_within 15 "zeta: loaded" module_state_is zeta loaded
check "the launcher logged what it found" grep -aq "modules: 5 (" "$RUN/h2s-shell-launcher.log"
check "the shell the launcher started confirms modules" test "$(module_field - confirmations)" = true
# (The test's "system" data dir is the test's own, which the user can write: its modules are
# the user's, never the system's)
check "sources: the development path's, the user root's, a user-writable data dir's: user" \
    test "$(module_field explicit source) $(module_field alpha source) $(module_field beta source) $(module_field zeta source)" = "developer user user user"
config_file=$XDG_CONFIG_HOME/h2s_shell/config.json
# The ids the config file holds acknowledgements for, sorted ("none" while never written)
acknowledged() {
    python3 -I -c '
import json, sys
try:
    text = json.load(open(sys.argv[1])).get("acknowledgedModules", "")
except Exception:
    text = ""
print(" ".join(sorted(json.loads(text))) if text else "none")' "$config_file"
}
acknowledged_are() { [ "$(acknowledged)" = "$1" ]; }
check_within "$GUARD" "the first start acknowledged the hand-placed modules it found on, in the config file" acknowledged_are "alpha beta zeta"
modules_on() { tr '\n' ' ' < "$RUN/h2s-shell-modules-on" 2> /dev/null; }
modules_on_are() { [ "$(modules_on)" = "$1" ]; }
check_within "$GUARD" "the modules on are written to the runtime directory" modules_on_are "alpha beta explicit zeta "

# ---- (2) safe mode ----
first=$SHELL_PID
signal_shell KILL
wait_for_new_shell "$first" 10 || abort "no new shell after the first kill"
check "one quick death: not safe mode" test -z "$(safe_mode_of_shell)"
check_within 15 "… the modules load" module_state_is alpha loaded
second=$SHELL_PID
signal_shell KILL
wait_for_new_shell "$second" 10 || abort "no new shell after the second kill"
check "two quick deaths in a row: the next start is in safe mode" test "$(safe_mode_of_shell)" = 1
check "… the shell knows it" test "$(module_field - safeMode)" = true
check_within 15 "… no module loads" module_state_is alpha safe-mode
# (Every one, waited for: a module still pending when alpha has its state could load yet.
# The second beta is still told apart as a duplicate: that is read before safe mode is)
check_within 15 "… none of them: each is in safe-mode, the duplicate a duplicate" \
    module_states_are "explicit: safe-mode, alpha: safe-mode, beta: safe-mode, beta-copy: duplicate, zeta: safe-mode"
log "modules in safe mode: $(module_states)"
check "… the launcher said so" grep -aq "starting it in safe mode (no modules)" "$RUN/h2s-shell-launcher.log"
check "… it tells the modules on in the last run" test "$(module_field - previousModulesOn)" = "['alpha', 'beta', 'explicit', 'zeta']"
check "… which safe mode left as they were" test "$(modules_on)" = "alpha beta explicit zeta "
lock_by_ipc
check_within "$GUARD" "in safe mode the lock locks" compositor_locked
wake_prompt || fail "the prompt did not wake"
check_within "$GUARD" "the methods are known" state_is armed true
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "… and the password unlocks" compositor_unlocked
check "modules loadWithoutSafeMode: started" test -z "$(shell_ipc modules loadWithoutSafeMode)"
check_within 15 "… out of safe mode in place, the modules load" module_state_is alpha loaded
check "… the same shell" test "$(module_field - safeMode)" = false

# A start that lives past the quick-death window ends safe mode; a module installed meanwhile
# is found at the next start
make_module "$home_modules/gamma" gamma
third=$SHELL_PID
started_at=$(awk '{ print $22 }' "/proc/$third/stat" 2> /dev/null)
clock_ticks=$(getconf CLK_TCK)
uptime_ticks() { awk -v hz="$clock_ticks" '{ printf "%d", $1 * hz }' /proc/uptime; }
until [ $(( ($(uptime_ticks) - started_at) / clock_ticks )) -ge 32 ]; do sleep 0.5; done # fixed sleep: the launcher's quick-death window (30 s) is lived out: it has no seam (scripts/launch.sh)
log "the safe-mode shell has run for 32 s"
signal_shell KILL
wait_for_new_shell "$third" 10 || abort "no new shell after the third kill"
check "a start that lived 30 s ended safe mode" test -z "$(safe_mode_of_shell)"
check_within 15 "… the modules load again" module_state_is alpha loaded
check_within 15 "… and the module installed meanwhile is found: off until confirmed" module_state_is gamma unconfirmed
check "… its source: user" test "$(module_field gamma source)" = user
check "modules setEnabled refuses it, saying why" \
    test "$(shell_ipc modules setEnabled gamma true)" = "gamma is new and not part of h2s-shell: confirm it first (modules confirm gamma <directory>)"
check "modules confirm without the directory: refused" \
    test "$(shell_ipc modules confirm gamma "")" = "Give the module's directory as modules list shows it: modules confirm <id> <directory>"
check "modules confirm for another directory: refused" \
    test "$(shell_ipc modules confirm gamma "$home_modules/beta")" = "The module changed: gamma is now $(module_field gamma directory)"
check "… still unconfirmed" module_state_is gamma unconfirmed
check "modules confirm with its directory: done" test -z "$(shell_ipc modules confirm gamma "$(module_field gamma directory)")"
check_within 15 "… it loads" module_state_is gamma loaded
check_within "$GUARD" "… the config file keeps its acknowledgement" acknowledged_are "alpha beta gamma zeta"
fourth=$SHELL_PID
make_module "$home_modules/delta" delta
check "modules rediscover: started" test -z "$(shell_ipc modules rediscover)"
check_within 15 "… the module put there while the shell runs is found, off until confirmed" module_state_is delta unconfirmed
check "… without a restart" test "$SHELL_PID" = "$fourth"
# The others load again too, a moment after delta: a load makes their data directories again
# first (a run of its own), which delta, off, does not wait for
check_within 15 "… the others still loaded" module_states_are "explicit: loaded, alpha: loaded, beta: loaded, delta: unconfirmed, gamma: loaded, beta-copy: duplicate, zeta: loaded"
check "the supervisor is still the first one" kill -0 "$SUPERVISOR_PID"
