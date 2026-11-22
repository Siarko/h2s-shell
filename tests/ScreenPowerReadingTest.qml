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
// And the shell's ScreenPower here, not on Hyprland's backend. Asynchronous: each step is
// a process.
TestCase {
    id: suite
    suiteName: "ScreenPowerReading"
    asynchronous: true

    readonly property string _fixtures: Quickshell.shellDir + "/tests/fixtures/screen-power"
    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-screen-power-reading-test-" + Date.now()
    readonly property string _samsung: "Samsung Electric Company|C27JG5x|H4ZMC00268"
    readonly property string _builtIn: "BOE|0x0BCA|"

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

    // Lets the held reading answer, once a reading has taken the hold. The steps that hold
    // one wait until every reading has answered, so no release outlives its step.
    function _release() {
        _inScratch("n=0; until [ -e \"$1/read-held\" ] || [ $n -ge 500 ]; do sleep 0.02; n=$((n + 1)); done; rm \"$1/read-held\"");
    }

    function _readDispatches(next) {
        _sh("cat \"$1/dispatches\" 2> /dev/null || true", [_scratch], (code, output) => {
            suite._dispatches = output.trim();
            next?.();
        });
    }

    // The dispatches the stand-in recorded, read again while a step waits on them
    property bool _dispatchesReading: false
    function _dispatchList() {
        if (!_dispatchesReading) {
            _dispatchesReading = true;
            _readDispatches(() => suite._dispatchesReading = false);
        }
        return _dispatches === "" ? [] : _dispatches.split("\n");
    }

    function _dpms(action, connector) {
        return "hl.dsp.dpms({ action = \"" + action + "\", monitor = \"" + connector + "\" })";
    }

    function runAsync() {
        // wlopm may be on this machine's PATH: WlopmScreenPowerReadingTest checks the choice
        // without it
        assert(ScreenPower.backend !== "hyprland", "the shell's ScreenPower under the suites' compositor: not Hyprland's");

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
            // The compositor has the Samsung off once it is asked
            _inScratch("cp \"$2/samsung-off.json\" \"$1/after-dispatch.json\"", () => suite._power.setPower(suite._samsung, false));
        });
        _then("the monitor was turned off", () => _actions.length === 1, () => {
            assertEqual(_actions[0], _samsung + ":false:", "the action answered without a problem: the reading after it has the monitor off");
            assertEqual(_powers(), "DP-2=off eDP-1=on", "… published");
            // Hyprland answers "ok" but the monitor stays as it was
            _power.setPower(_samsung, true);
        });
        _then("the action that changed nothing answered", () => _actions.length === 2, () => {
            assertEqual(_actions[1], _samsung + ":true:it is still off", "\"ok\" with the monitor unchanged: a problem");
            _dispatchList(); // a fresh read of the dispatches, for the next step
        });
        _then("two dispatches recorded", () => _dispatchList().length === 2, () => {
            assertEqual(_dispatches, _dpms("disable", "DP-2") + "\n" + _dpms("enable", "DP-2"), "each for that monitor's connector only");
            // An id no monitor has: refused, nothing dispatched
            _power.setPower("Nobody|Nothing|", true);
        });
        _then("the unknown id was answered", () => _actions.length === 3, () => {
            assert(_actions[2].startsWith("Nobody|Nothing|:true:no connected monitor"), "an id not connected is refused: " + _actions[2]);
            _inScratch(": > \"$1/dispatch-fails\"", () => suite._power.setPower(suite._samsung, true));
        });
        _then("the failed dispatch was answered", () => _actions.length === 4, () => {
            assert(_actions[3].startsWith(_samsung + ":true:hyprctl dispatch failed (1): Couldn't connect"), "a dispatch that fails is a problem: " + _actions[3]);
            assertEqual(_power.actionProblem, _actions[3].slice((_samsung + ":true:").length), "… kept as the last action's problem");
            _inScratch("rm \"$1/dispatch-fails\"; : > \"$1/read-fails\"", () => suite._power.setPower(suite._samsung, true));
        });
        _then("the action after a failed reading was answered", () => _actions.length === 5, () => {
            assertEqual(_actions[4], _samsung + ":true:the monitors could not be read", "an action whose reading fails is refused");
            assertEqual(_powers(), "DP-2=unknown eDP-1=unknown", "… every power unknown, never off");
            assert(_power.readProblem.startsWith("hyprctl failed (1)"), "… the reading's problem kept: " + _power.readProblem);
            // A monitor event while the action's reading runs
            _inScratch("rm \"$1/read-fails\"; : > \"$1/read-wait\"", () => {
                suite._power.setPower(suite._samsung, false);
                suite._power.monitorEvent();
                suite._release();
            });
        });
        _then("the action with an event under it was answered", () => _actions.length === 6 && _shellDone && !_power._query.running && _power._runner.running === 0, () => {
            assertEqual(_actions[5], _samsung + ":false:the monitors changed while it was asked", "a monitor event between the reading and the dispatch: refused");
            // Another reading started while the action's runs
            _inScratch(": > \"$1/read-wait\"", () => {
                suite._power.setPower(suite._samsung, false);
                suite._power.read();
                suite._release();
            });
        });
        _then("the action with a reading under it was answered", () => _actions.length === 7 && _shellDone && !_power._query.running && _power._runner.running === 0, () => {
            assertEqual(_actions[6], _samsung + ":false:the monitors changed while it was asked", "a reading started under the action: refused");
            _dispatchList(); // a fresh read of the dispatches, for the next step
        });
        _then("no dispatch for the refused actions", () => !_dispatchesReading && _dispatchList().length === 3, () => {
            // A reading pending when the action is asked: the action reads after it, and works
            _inScratch(": > \"$1/read-wait\"; cp \"$2/two-on.json\" \"$1/after-dispatch.json\"", () => {
                suite._power.read();
                suite._power.setPower(suite._samsung, true);
                suite._release();
            });
        });
        _then("the action after a pending reading was answered", () => _actions.length === 8 && _shellDone && !_power._query.running && _power._runner.running === 0, () => {
            assertEqual(_actions[7], _samsung + ":true:", "an action asked while a reading was pending: done, from its own reading");
            assertEqual(_powers(), "DP-2=on eDP-1=on", "… published");
            // Two requests for one monitor: the newer wins, the older dispatches nothing
            _inScratch(": > \"$1/read-wait\"; cp \"$2/samsung-off.json\" \"$1/after-dispatch.json\"", () => {
                suite._power.setPower(suite._samsung, false);
                suite._power.setPower(suite._samsung, true);
                suite._power.setPower(suite._samsung, false);
                suite._release();
            });
        });
        _then("the superseded requests were answered", () => _actions.length === 10 && _shellDone && !_power._query.running && _power._runner.running === 0, () => {
            assertEqual(_actions[8], _samsung + ":false:a newer request came", "the request under way when a newer came: superseded");
            assertEqual(_actions[9], _samsung + ":false:", "… the newest done; the one in between replaced in the queue");
            assertEqual(_powers(), "DP-2=off eDP-1=on", "… published");
            // An action that turns another monitor off too: that one is turned back on
            _inScratch("cp \"$2/two-on.json\" \"$1/monitors.json\"; cp \"$2/both-off.json\" \"$1/after-dispatch.json\"", () => suite._power.read());
        });
        _then("both on again", () => _powers() === "DP-2=on eDP-1=on", () => {
            // The action turns the other monitor off too; the recovery's enable brings it back;
            // a queued action for that other monitor comes after, unhindered
            _inScratch("cp \"$2/both-off.json\" \"$1/after-dispatch.json\"; cp \"$2/samsung-off.json\" \"$1/after-dispatch-2.json\";"
                       + " cp \"$2/both-off.json\" \"$1/after-dispatch-3.json\"", () => {
                suite._power.setPower(suite._samsung, false);
                suite._power.setPower(suite._builtIn, false);
            });
        });
        _then("the recovery and the queued action were answered", () => _actions.length === 12, () => {
            assertEqual(_actions[10], _samsung + ":false:", "the action itself worked, by the reading after its recovery");
            assertEqual(_actions[11], _builtIn + ":false:", "… the action queued behind it worked: neither refused nor raced");
            assertEqual(_powers(), "DP-2=off eDP-1=off", "… published");
            _dispatchList();
        });
        _then("the recovery's dispatches read", () => !_dispatchesReading && _dispatchList().length === 8, () => {
            assertEqual(JSON.stringify(_dispatches.split("\n").slice(-3)), JSON.stringify([_dpms("disable", "DP-2"), _dpms("enable", "eDP-1"), _dpms("disable", "eDP-1")]),
                        "the monitor turned off besides the target turned back on, by its connector, before the next action");
            _inScratch("cp \"$2/two-on.json\" \"$1/monitors.json\"", () => suite._power.read());
        });
        _then("both on before the unplug", () => _powers() === "DP-2=on eDP-1=on", () => {
            // The target is unplugged under the dispatch: Hyprland turns the rest off, and a
            // monitor event arrives before the reading after it
            _inScratch(": > \"$1/dispatch-wait\"; cp \"$2/edp-off-alone.json\" \"$1/after-dispatch.json\"; cp \"$2/edp-on-alone.json\" \"$1/after-dispatch-2.json\"",
                       () => suite._power.setPower(suite._samsung, false));
        });
        _then("the dispatch waits", () => _dispatchList().length === 9, () => {
            _power.monitorEvent();
            _power.read();
            _inScratch("rm \"$1/dispatch-wait\"");
        });
        _then("the unplugged target's action was answered", () => _actions.length === 13, () => {
            assertEqual(_actions[12], _samsung + ":false:the monitor is gone", "the target gone under the action: a problem");
            assertEqual(_powers(), "eDP-1=on", "… every other monitor that was on is on again, whatever event came meanwhile");
            _dispatchList();
        });
        _then("the unplug's dispatches read", () => !_dispatchesReading && _dispatchList().length === 10, () => {
            assertEqual(_dispatches.split("\n").slice(-1)[0], _dpms("enable", "eDP-1"), "… by its connector");
            // A reading older than the one published is not published
            _inScratch("cp \"$2/two-on.json\" \"$1/monitors.json\"; : > \"$1/read-wait\"", () => {
                suite._power.read();
                suite._inScratch("n=0; until [ -e \"$1/read-held\" ] || [ $n -ge 500 ]; do sleep 0.02; n=$((n + 1)); done;"
                                 + " cp \"$2/samsung-off.json\" \"$1/monitors.json\"", () => suite._power._readOnce(() => {}));
            });
        });
        _then("the newer reading was published", () => _powers() === "DP-2=off eDP-1=on", () => {
            _inScratch("rm \"$1/read-held\"");
        });
        _then("the older reading answered", () => _shellDone && !_power._query.running, () => {
            assertEqual(_powers(), "DP-2=off eDP-1=on", "a reading started before the published one, answering after it: not published");
            _inScratch("cp \"$2/twins.json\" \"$1/monitors.json\"", () => suite._power.read());
        });
        _then("the twins were read", () => _power.monitors.length === 2 && _power.monitors[0].connector === "DP-1", () => {
            assertEqual(_power.monitors.map(monitor => monitor.id).join(" "), "Dell Inc.|U2419H||DP-1 Dell Inc.|U2419H||DP-3", "twins read: told apart");
            _inScratch("cp \"$2/twin-alone.json\" \"$1/monitors.json\"", () => suite._power.read());
        });
        _then("one twin was read alone", () => _power.monitors.length === 1, () => {
            assertEqual(_power.monitors[0].id, "Dell Inc.|U2419H||DP-1", "a twin left alone keeps its id");
            _inScratch("cp \"$2/malformed.json\" \"$1/monitors.json\"", () => suite._power.read());
        });
        _then("the malformed answer was read", () => !_power.monitorsRead, () => {
            assertEqual(_powers(), "DP-1=unknown", "an answer that is not JSON: every power unknown");
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
