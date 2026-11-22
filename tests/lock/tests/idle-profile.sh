# A profile switch while the screensaver shows (unplugging a laptop, a battery level, a
# module's fact) is no input: the idle monitors are made once, so nothing starts the idle
# count again. The profiles depend on facts of the test's own, set over the profiles IPC
# (`simulate`); the "every screen dark" command entry writes a line for each command to a file.
#
#   a profile with another screensaver time: the screensaver stays, no command runs;
#   back again: it stays;
#   a profile with the screensaver off: it goes, without the end command (the user is still
#   away); input then ends the idle period: the end command runs, once.
# Full still carries the old `lockscreenTimeout` and the old commands' switch on (neither
# read any more): the log says so, once each.

commands=$WORK/screensaver-commands
: > "$commands"
mkdir -p "$XDG_CONFIG_HOME/h2s_shell"
python3 -I -c '
import json, sys
commands = sys.argv[2]
profiles = [
    {"name": "Full", "enabled": True, "when": {}, "set": {
        "lockscreen.screensaverEnabled": True, "lockscreen.screensaverTimeout": 5,
        "lockscreen.lockscreenTimeout": 5, "lockscreen.screensaverCommands": True,
        "lockscreen.commandEntries": [{"id": "dark", "moment": "dark", "monitors": None,
                                       "go": "echo start >> " + commands, "back": "echo end >> " + commands}]}},
    {"name": "Longer", "enabled": True, "when": {"fact": "locktest.longer", "is": True},
     "set": {"lockscreen.screensaverTimeout": 600}},
    {"name": "Off", "enabled": True, "when": {"fact": "locktest.off", "is": True},
     "set": {"lockscreen.screensaverEnabled": False}},
]
json.dump({"profiles": json.dumps(profiles), "widgetPresets": "{}"}, open(sys.argv[1], "w"), indent=2)
' "$XDG_CONFIG_HOME/h2s_shell/config.json" "$commands" || abort "cannot write the config"

stack_start

screensaver_layer() {
    hyprctl -j layers | python3 -I -c '
import json, sys
layers = json.load(sys.stdin)
found = any(surface.get("namespace") == "screensaver"
            for monitor in layers.values() for level in monitor["levels"].values() for surface in level)
sys.exit(0 if found else 1)'
}
no_screensaver_layer() { ! screensaver_layer; }
# layer_for <seconds>: the screensaver's layer is on the screen all along, polled for that
# long — the time a fade out (400 ms) and the old 5 s idle count would take to show
layer_for() {
    local deadline=$((${EPOCHREALTIME/[.,]/} + $1 * 1000000))
    while [ "${EPOCHREALTIME/[.,]/}" -lt "$deadline" ]; do
        screensaver_layer || return 1
    done
    return 0
}
timeout_is() { [ "$(profile_value lockscreen.screensaverTimeout)" = "$1" ]; }
# commands_stay <seconds> <lines>: the commands file says that all along, polled for that long
commands_stay() {
    local deadline=$((${EPOCHREALTIME/[.,]/} + $1 * 1000000))
    while [ "${EPOCHREALTIME/[.,]/}" -lt "$deadline" ]; do
        commands_are "$2" || return 1
    done
    return 0
}
commands_are() { [ "$(tr '\n' ' ' < "$commands")" = "$1" ]; }
profile_value() {
    shell_ipc profiles status | python3 -I -c 'import json, sys; print(json.dumps(json.load(sys.stdin)["values"].get(sys.argv[1])))' "$1"
}

check_within "$GUARD" "5 s without input: the screensaver shows" screensaver_layer
check_within "$GUARD" "… the start command ran" commands_are "start "

# ---- Another time ----
shell_ipc profiles simulate '{"locktest.longer": true}' > /dev/null
check_within "$GUARD" "the profile with 600 s is in force" timeout_is 600
check "the screensaver stays through the switch" layer_for 2
check "… the shell says so" state_is screensaver true
shell_ipc profiles clearSimulation > /dev/null
check_within "$GUARD" "back to 5 s" timeout_is 5
check "the screensaver stays through the switch back" layer_for 2
check "no command ran: the same idle period" commands_are "start "

# ---- The screensaver switched off ----
shell_ipc profiles simulate '{"locktest.off": true}' > /dev/null
check_within "$GUARD" "a profile with the screensaver off: it goes" no_screensaver_layer
check "… the shell says so" state_is screensaver false
check "no end command: the user is still away" commands_stay 1 "start "
shell_ipc profiles clearSimulation > /dev/null
check_within "$GUARD" "on again, still no input: it shows again" screensaver_layer
check "… in the same idle period: no second start command" commands_are "start "
move_pointer 700 400
move_pointer 720 410
check_within "$GUARD" "input ends it" no_screensaver_layer
check_within "$GUARD" "… and the end command ran, once" commands_are "start end "
check "the old lockscreenTimeout in a profile: told once, naming lockAfter" \
    test "$(grep -ac 'still sets lockscreen.lockscreenTimeout.*lockscreen.lockAfter' "$WORK/shell.log")" = 1
check "the old commands' switch on in a profile: told once, naming commandEntries" \
    test "$(grep -ac 'still sets lockscreen.screensaverCommands.*lockscreen.commandEntries' "$WORK/shell.log")" = 1
check "no protocol error" no_protocol_errors
