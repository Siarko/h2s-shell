import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons
import qs.singletons.screen

// The reading and the actions behind ScreenPower on Hyprland
// (singletons/screen/HyprlandScreenPower.qml), run for real against a stand-in for hyprctl
// (tests/fixtures/screen-power, linked into a scratch directory whose files it prints and
// where it records the dispatches): the monitors and their power read, one turned off by its
// id, a dispatch refused, an id not connected refused without a dispatch, a reading that
// fails and one that is not JSON — both leave the power unknown. Never the real hyprctl.
// And the shell's ScreenPower here, where no compositor backend runs: nothing can be
// turned off. Asynchronous: each step is a process.
TestCase {
    id: suite
    suiteName: "ScreenPowerReading"
    asynchronous: true

    readonly property string _fixtures: Quickshell.shellDir + "/tests/fixtures/screen-power"
    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-screen-power-reading-test-" + Date.now()
    readonly property string _samsung: "Samsung Electric Company|C27JG5x|H4ZMC00268"

    property var _power: null
    property bool _written: false
    property bool _shellDone: false
    property string _dispatches: ""
    // The actions answered, as "id:on:problem"
    property var _actions: []

    property Component _powerComponent: Component {
        HyprlandScreenPower {}
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
        _sh("rm -rf \"$1\"", [_scratch], () => suite.finish());
    }

    function _powers() {
        return (_power?.monitors ?? []).map(monitor => monitor.connector + "=" + monitor.power).join(" ");
    }

    // Runs a shell line in the scratch directory, then `next`
    function _inScratch(script, next) {
        _shellDone = false;
        _sh(script, [_scratch, _fixtures], code => {
            suite.assertEqual(code, 0, "the scratch directory is changed: " + script);
            suite._shellDone = true;
            next?.();
        });
    }

    function _readDispatches(next) {
        _sh("cat \"$1/dispatches\" 2> /dev/null || true", [_scratch], (code, output) => {
            suite._dispatches = output.trim();
            next?.();
        });
    }

    function runAsync() {
        assertEqual(ScreenPower.backend, "none", "the shell's ScreenPower under the suites' compositor: no backend");
        assert(!ScreenPower.canPowerOff, "… nothing can be turned off");
        assertEqual(JSON.stringify(ScreenPower.monitors), "[]", "… and nothing is read");

        _then("the stand-in is in place", () => _written, () => {
            _power = _powerComponent.createObject(suite, { hyprctl: _scratch + "/hyprctl" });
            _power.actionDone.connect((id, on, problem) => suite._actions = suite._actions.concat([id + ":" + on + ":" + problem]));
            _power.read();
        });
        _then("the first reading came", () => _power.monitorsRead, () => {
            assertEqual(_powers(), "DP-2=on eDP-1=on", "every monitor of hyprctl's answer, with its power");
            assertEqual(_power.monitors[0].id, _samsung, "… a monitor's id: make|model|serial");
            assertEqual(_power.monitors[1].id, "BOE|0x0BCA|", "… one without a serial: make|model|");
            assert(_power.monitors[1].builtIn && !_power.monitors[0].builtIn, "… the laptop's panel recognised");
            assertEqual(_power.readProblem, "", "… no problem");
            // The compositor will have the Samsung off once it is asked
            _inScratch("cp \"$2/samsung-off.json\" \"$1/monitors.json\"", () => suite._power.setPower(suite._samsung, false));
        });
        _then("the monitor was turned off and read again",
              () => _actions.length === 1 && _power.monitors[0]?.power === "off", () => {
            assertEqual(_actions[0], _samsung + ":false:", "the action answered, without a problem");
            assertEqual(_powers(), "DP-2=off eDP-1=on", "… the reading after it has the monitor off");
            _readDispatches(() => {
                suite.assertEqual(suite._dispatches, "hl.dsp.dpms({ action = \"disable\", monitor = \"DP-2\" })",
                                  "one dispatch, for that monitor's connector only");
                // An id no monitor has: refused, nothing dispatched
                suite._power.setPower("Nobody|Nothing|", true);
            });
        });
        _then("the unknown id was answered", () => _actions.length === 2, () => {
            assert(_actions[1].startsWith("Nobody|Nothing|:true:no connected monitor"), "an id not connected is refused: " + _actions[1]);
            _readDispatches(() => {
                suite.assertEqual(suite._dispatches.split("\n").length, 1, "… without a dispatch (Hyprland would turn every monitor off)");
                suite._inScratch(": > \"$1/dispatch-fails\"", () => suite._power.setPower(suite._samsung, true));
            });
        });
        _then("the refused dispatch was answered", () => _actions.length === 3, () => {
            assert(_actions[2].startsWith(_samsung + ":true:hyprctl dispatch failed: error"), "a dispatch Hyprland refuses is a problem: " + _actions[2]);
            assertEqual(_power.actionProblem, _actions[2].slice((_samsung + ":true:").length), "… kept as the last action's problem");
            _readDispatches(() => {
                suite.assertEqual(suite._dispatches.split("\n")[1], "hl.dsp.dpms({ action = \"enable\", monitor = \"DP-2\" })", "… the enable was asked");
                // A reading that fails: the power is unknown, the monitors still listed
                suite._inScratch("rm \"$1/dispatch-fails\"; : > \"$1/read-fails\"", () => suite._power.read());
            });
        });
        _then("the failing reading answered", () => _shellDone && !_power.monitorsRead, () => {
            assertEqual(_powers(), "DP-2=unknown eDP-1=unknown", "a failed reading: every power unknown, never off");
            assert(_power.readProblem.startsWith("hyprctl failed (1)"), "… the problem kept: " + _power.readProblem);
            _inScratch("rm \"$1/read-fails\"; cp \"$2/two-on.json\" \"$1/monitors.json\"", () => suite._power.read());
        });
        _then("a good reading came again", () => _power.monitorsRead, () => {
            assertEqual(_powers(), "DP-2=on eDP-1=on", "the next good reading is believed again");
            _inScratch("cp \"$2/malformed.json\" \"$1/monitors.json\"", () => suite._power.read());
        });
        _then("the malformed answer was read", () => !_power.monitorsRead, () => {
            assertEqual(_powers(), "DP-2=unknown eDP-1=unknown", "an answer that is not JSON: every power unknown");
            assertEqual(_power.readProblem, "hyprctl gave no readable answer", "… said so");
        });
        _clock.start();
        _sh("set -e; mkdir -p \"$1\"; ln -s \"$2/hyprctl\" \"$1/\"; cp \"$2/two-on.json\" \"$1/monitors.json\"",
            [_scratch, _fixtures], code => {
                suite.assertEqual(code, 0, "the stand-in is linked into a scratch directory");
                suite._written = true;
            });
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
