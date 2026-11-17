# The launcher's side of modules (scripts/launch.sh, notes/plans/modules.md):
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
safe_mode_of_shell() { process_env "$SHELL_PID" H2S_SHELL_SAFE_MODE; }

# ---- (1) discovery ----
log "H2S_SHELL_MODULES: $(process_env "$SHELL_PID" H2S_SHELL_MODULES)"
check "the order: H2S_SHELL_MODULE_PATH, data home, data dirs; canonical; the symlinked duplicate once; the inherited list ignored" \
    test "$(process_env "$SHELL_PID" H2S_SHELL_MODULES)" = "$expected"
check "the inherited list's stale module: not loaded" test "$(module_field old-alpha state)" = absent
check "H2S_SHELL_MODULE_PATH is passed on unchanged" test "$(process_env "$SHELL_PID" H2S_SHELL_MODULE_PATH)" = "$WORK/dev/explicit"
check "explicit: loaded" module_state_is explicit loaded
check "alpha: loaded" module_state_is alpha loaded
check "beta (data home): loaded" module_state_is beta loaded
check "beta-copy (data dirs, same id): reported as a duplicate" module_state_is beta-copy duplicate
check "zeta: loaded" module_state_is zeta loaded
check "the launcher logged what it found" grep -aq "modules: 5 (" "$RUN/h2s-shell-launcher.log"

# ---- (2) safe mode ----
first=$SHELL_PID
signal_shell KILL
wait_for_new_shell "$first" 10 || abort "no new shell after the first kill"
check "one quick death: not safe mode" test -z "$(safe_mode_of_shell)"
check "… the modules load" module_state_is alpha loaded
second=$SHELL_PID
signal_shell KILL
wait_for_new_shell "$second" 10 || abort "no new shell after the second kill"
check "two quick deaths in a row: the next start is in safe mode" test "$(safe_mode_of_shell)" = 1
check "… the shell knows it" test "$(module_field - safeMode)" = true
check "… no module loads" module_state_is alpha safe-mode
check "… none of them" test "$(shell_ipc modules list | grep -o '"state":"loaded"' | wc -l)" = 0
check "… the launcher said so" grep -aq "starting it in safe mode (no modules)" "$RUN/h2s-shell-launcher.log"
lock_by_ipc
check_within 5 "in safe mode the lock locks" compositor_locked
wake_prompt || fail "the prompt did not wake"
check_within 5 "the methods are known" state_is armed true
type_text "$LOCKTEST_PASSWORD"
press_key Return
check_within 10 "… and the password unlocks" compositor_unlocked

# A start that lives past the quick-death window ends safe mode; a module installed meanwhile
# is found at the next start
make_module "$home_modules/gamma" gamma
third=$SHELL_PID
started_at=$(awk '{ print $22 }' "/proc/$third/stat" 2> /dev/null)
clock_ticks=$(getconf CLK_TCK)
uptime_ticks() { awk -v hz="$clock_ticks" '{ printf "%d", $1 * hz }' /proc/uptime; }
until [ $(( ($(uptime_ticks) - started_at) / clock_ticks )) -ge 32 ]; do sleep 0.5; done
log "the safe-mode shell has run for 32 s"
signal_shell KILL
wait_for_new_shell "$third" 10 || abort "no new shell after the third kill"
check "a start that lived 30 s ended safe mode" test -z "$(safe_mode_of_shell)"
check "… the modules load again" module_state_is alpha loaded
check "… and the module installed meanwhile is found" module_state_is gamma loaded
check "the supervisor is still the first one" kill -0 "$SUPERVISOR_PID"
