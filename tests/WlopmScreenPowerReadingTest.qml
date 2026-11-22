import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons
import qs.singletons.screen

// The reading and the actions behind ScreenPower on wlopm
// (singletons/screen/WlopmScreenPower.qml), run for real against a stand-in for wlopm
// (tests/fixtures/wlopm, linked into a scratch directory whose `outputs.json` it prints and
// where it records the commands): the monitors read, their ids from the screens Qt knows,
// one turned off and on by its id, an id not connected refused without a command, a
// command that fails, and readings that fail, hang or are not JSON — each leaves the power
// unknown. And the backend's choice (ScreenPowerBackend): wlopm where it is found, none
// where neither Hyprland nor wlopm is there. Never the real wlopm. Asynchronous: each step
// is a process.
TestCase {
    id: suite
    suiteName: "WlopmScreenPowerReading"
    asynchronous: true

    readonly property string _fixtures: Quickshell.shellDir + "/tests/fixtures/wlopm"
    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-wlopm-reading-test-" + Date.now()
    readonly property var _screens: [
        { name: "DP-2", manufacturer: "Samsung Electric Company", model: "C27JG5x", serialNumber: "" },
        { name: "eDP-1", model: "0x0BCA", serialNumber: "" },
        { name: "DP-1", model: "U2419H", serialNumber: "" },
        { name: "DP-3", model: "U2419H", serialNumber: "" }
    ]
    readonly property string _samsung: "Samsung Electric Company|C27JG5x|"

    property var _power: null
    property var _none: null
    property var _found: null
    property bool _written: false
    property string _commands: ""
    property bool _commandsReading: false
    // The actions answered, as "id:on:problem"
    property var _actions: []
    property var _noneActions: []

    property Component _powerComponent: Component {
        WlopmScreenPower {}
    }
    property Component _backendComponent: Component {
        ScreenPowerBackend {}
    }

    // ---- A tiny scheduler: each step waits for its condition (or its deadline), then runs ----
    property var _steps: []

    function _then(description, condition, action) {
        _steps.push({ description: description, condition: condition, action: action });
    }

    property Timer _clock: Timer {
        interval: 25
        repeat: true
        property int waited: 0
        onTriggered: {
            const step = suite._steps[0];
            if (!step) {
                stop();
                suite._end();
                return;
            }
            waited += interval;
            let ready = false;
            try {
                ready = step.condition();
            } catch (error) {}
            if (!ready && waited < 10000)
                return;
            waited = 0;
            suite._steps.shift();
            if (!ready)
                suite.fail("timed out waiting: " + step.description);
            try {
                step.action();
            } catch (error) {
                suite.fail("threw in \"" + step.description + "\": " + error);
            }
        }
    }

    function _end() {
        _power?.destroy();
        _none?.destroy();
        _found?.destroy();
        _sh("rm -rf \"$1\"", [_scratch], () => suite.finish());
    }

    function _powers() {
        return (_power?.monitors ?? []).map(monitor => monitor.connector + "=" + monitor.power).join(" ");
    }

    // Runs a shell line in the scratch directory, then `next`
    function _inScratch(script, next) {
        _sh(script, [_scratch, _fixtures], code => {
            suite.assertEqual(code, 0, "the scratch directory is changed: " + script);
            next?.();
        });
    }

    // The commands the stand-in recorded, read again while a step waits on them
    function _commandList() {
        if (!_commandsReading) {
            _commandsReading = true;
            _sh("cat \"$1/commands\" 2> /dev/null || true", [_scratch], (code, output) => {
                suite._commands = output.trim();
                suite._commandsReading = false;
            });
        }
        return _commands === "" ? [] : _commands.split("\n");
    }

    function runAsync() {
        // Neither Hyprland nor wlopm: nothing can be turned off, and the page is told why
        _none = _backendComponent.createObject(suite, { hyprland: false, wlopm: _scratch + "/no-such-wlopm" });
        _none.actionDone.connect((id, on, problem) => suite._noneActions = suite._noneActions.concat([problem]));
        _then("the missing wlopm was looked for", () => _none._wlopm?.program === "missing", () => {
            assertEqual(_none.backend, "none", "neither program: no backend");
            assert(!_none.canPowerOff, "… nothing can be turned off");
            assertEqual(JSON.stringify(_none.monitors), "[]", "… nothing listed");
            assertEqual(_none.unavailable.reason, "Not supported here", "… the page says so");
            assertEqual(_none.unavailable.hint, "Install wlopm to turn monitors off", "… and names wlopm once");
            _none.setPower(_samsung, false);
        });
        _then("the action without a backend was answered", () => _noneActions.length === 1, () => {
            assertEqual(_noneActions[0], "no way to turn monitors off here", "an action without a backend: refused");
            _found = _backendComponent.createObject(suite, { hyprland: false, wlopm: _scratch + "/wlopm" });
        });
        _then("the stand-in wlopm was found", () => _found.backend === "wlopm", () => {
            assert(_found.canPowerOff, "wlopm on hand: monitors can be turned off");
            assert(_found._wlopm.screens.length > 0 && typeof _found._wlopm.screens[0].name === "string" && "manufacturer" in _found._wlopm.screens[0],
                   "… the screens from Qt's own list, with their make: " + JSON.stringify(_found._wlopm.screens));
            assertEqual(_found.unavailable.reason, "", "… nothing to say on the page");
            _power = _powerComponent.createObject(suite, { wlopm: _scratch + "/wlopm", screens: _screens, timeoutMs: 1500, retryMs: 300 });
            _power.actionDone.connect((id, on, problem) => suite._actions = suite._actions.concat([id + ":" + on + ":" + problem]));
            _power.read();
        });
        _then("the first reading came", () => _power.monitorsRead, () => {
            assertEqual(_powers(), "DP-2=on eDP-1=on", "every output of wlopm's answer, with its power");
            assertEqual(_power.monitors[0].id, _samsung, "… an id from the screen of that name: make|model|serial, as Qt reports them");
            assert(_power.monitors[1].builtIn && !_power.monitors[0].builtIn, "… the laptop's panel recognised");
            assertEqual(_power.program, "found", "… the program found");
            _power.setPower(_samsung, false);
        });
        _then("the monitor was turned off", () => _actions.length === 1, () => {
            assertEqual(_actions[0], _samsung + ":false:", "the action answered without a problem: the reading after it has the monitor off");
            assertEqual(_powers(), "DP-2=off eDP-1=on", "… published");
            _power.setPower(_samsung, true);
        });
        _then("the monitor was turned on", () => _actions.length === 2, () => {
            assertEqual(_actions[1], _samsung + ":true:", "on again");
            assertEqual(_powers(), "DP-2=on eDP-1=on", "… published");
            // An id no monitor has: refused, nothing run
            _power.setPower("|Nothing|", false);
        });
        _then("the unknown id was answered", () => _actions.length === 3, () => {
            assert(_actions[2].startsWith("|Nothing|:false:no connected monitor"), "an id not connected is refused: " + _actions[2]);
            _commandList();
        });
        _then("two commands recorded", () => !_commandsReading && _commandList().length === 2, () => {
            assertEqual(_commands, "--off DP-2\n--on DP-2", "each for that monitor's connector only, argv words as given");
            _inScratch(": > \"$1/action-fails\"", () => suite._power.setPower(suite._samsung, false));
        });
        _then("the failed command was answered", () => _actions.length === 4, () => {
            assert(_actions[3].startsWith(_samsung + ":false:wlopm failed (1): ERROR: Setting power mode failed"), "a command that fails is a problem: " + _actions[3]);
            assertEqual(_powers(), "DP-2=on eDP-1=on", "… the monitor as the reading after it has it");
            _inScratch("rm \"$1/action-fails\"; : > \"$1/read-fails\"", () => suite._power.setPower(suite._samsung, false));
        });
        _then("the action after a failed reading was answered", () => _actions.length === 5, () => {
            assertEqual(_actions[4], _samsung + ":false:the monitors could not be read", "an action whose reading fails is refused");
            assertEqual(_powers(), "DP-2=unknown eDP-1=unknown", "… every power unknown, never off");
            assert(_power.readProblem.startsWith("wlopm failed (1): ERROR: Compositor does not support"), "… the reading's problem kept: " + _power.readProblem);
            _commandList();
        });
        _then("no command for the refused action", () => !_commandsReading && _commandList().length === 3, () => {
            _inScratch("rm \"$1/read-fails\"", () => suite._power.read());
        });
        _then("read again", () => _power.monitorsRead, () => {
            assertEqual(_powers(), "DP-2=on eDP-1=on", "a reading that works again: the power known again");
            _inScratch(": > \"$1/read-hangs\"", () => suite._power.read());
        });
        _then("the hanging reading ended", () => !_power.monitorsRead, () => {
            assertEqual(_power.readProblem, "wlopm did not answer", "a reading that hangs ends at its time limit");
            assertEqual(_powers(), "DP-2=unknown eDP-1=unknown", "… every power unknown");
            assertEqual(_power.program, "found", "… the program is still there");
            _inScratch("rm \"$1/read-hangs\"; : > \"$1/read-garbled\"", () => suite._power.read());
        });
        _then("the garbled answer was read", () => _power.readProblem === "wlopm gave no readable answer", () => {
            assertEqual(_powers(), "DP-2=unknown eDP-1=unknown", "an answer that is not JSON: every power unknown");
            _inScratch("rm \"$1/read-garbled\"; cp \"$2/twins.json\" \"$1/outputs.json\"", () => suite._power.read());
        });
        _then("the twins were read", () => _power.monitorsRead, () => {
            assertEqual(_power.monitors.map(monitor => monitor.id).join(" "), "|U2419H||DP-1 |U2419H||DP-3", "two of one model without a serial: told apart by connector");
            assertEqual(_powers(), "DP-1=on DP-3=off", "… each with its power");
            _inScratch("cp \"$2/two-on.json\" \"$1/outputs.json\"", () => suite._power.read());
        });
        _then("two on again", () => _powers() === "DP-2=on eDP-1=on", () => {
            // A screen change while an action's reading runs: turning off is refused …
            _power.setPower(_samsung, false);
            _power.monitorEvent();
        });
        _then("the off under a screen change was answered", () => _actions.length === 6, () => {
            assertEqual(_actions[5], _samsung + ":false:the monitors changed while it was asked", "off under a screen change: refused");
            // … turning on is not: a wake is never lost
            _power.setPower(_samsung, true);
            _power.monitorEvent();
        });
        _then("the on under a screen change was answered", () => _actions.length === 7, () => {
            assertEqual(_actions[6], _samsung + ":true:", "on under a screen change: done");
            _commandList();
        });
        _then("the on's command recorded", () => !_commandsReading && _commandList().length === 4, () => {
            assertEqual(_commands.split("\n")[3], "--on DP-2", "… its command ran");
            // wlopm gone after it was found: a reading that failed, the backend kept
            _inScratch("rm \"$1/wlopm\"; sed -i 's/\"on\"/\"off\"/' \"$1/outputs.json\"", () => suite._power.read());
        });
        _then("the reading without wlopm failed", () => _power.readProblem === "wlopm could not be started", () => {
            assertEqual(_power.program, "found", "a failed start after the first reading: still found");
            assertEqual(_powers(), "DP-2=unknown eDP-1=unknown", "… the monitors kept, their power unknown");
            // wlopm back, its readings failing: turning on still runs, by the last connector
            _inScratch(": > \"$1/read-fails\"; ln -s \"$2/wlopm\" \"$1/\"", () => suite._power.setPower(suite._samsung, true));
        });
        _then("the on after failed readings was answered", () => _actions.length === 8, () => {
            assertEqual(_actions[7], _samsung + ":true:the monitors could not be read after it", "on with every reading failing: tried, the reading after it says why");
            _commandList();
        });
        _then("the on's command ran anyway", () => !_commandsReading && _commandList().length === 5, () => {
            assertEqual(_commands.split("\n")[4], "--on DP-2", "a wake by the connector last published");
            _inScratch("rm \"$1/read-fails\"");
        });
        _then("read again by itself", () => _power.monitorsRead, () => {
            assertEqual(_powers(), "DP-2=on eDP-1=off", "the failed reading tried again on its own, after a backoff: the wake shows");
            assertEqual(_power.readProblem, "", "… no problem");
        });
        _clock.start();
        _sh("set -e; mkdir -p \"$1\"; ln -s \"$2/wlopm\" \"$1/\"; cp \"$2/two-on.json\" \"$1/outputs.json\"",
            [_scratch, _fixtures], code => {
                suite.assertEqual(code, 0, "the stand-in is linked into a scratch directory");
                suite._written = true;
            });
        _steps.unshift({ description: "the stand-in is in place", condition: () => suite._written, action: () => {} });
    }

    function _sh(script, args, done) {
        const process = _shell.createObject(suite, { command: ["sh", "-c", script, "sh"].concat(args), done: done });
        process.running = true;
    }

    property Component _shell: Component {
        Process {
            id: _process
            property var done: null
            property string output: ""
            stdout: SplitParser {
                splitMarker: ""
                onRead: data => _process.output += data
            }
            onExited: code => {
                _process.done?.(code, _process.output);
                _process.destroy();
            }
        }
    }
}
