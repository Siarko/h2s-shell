import QtQuick
import Quickshell.Io
import qs.singletons
import qs.tests

// Idle's word to the helper (singletons/Idle.qml: ScreenSaverClient's `own`), with the
// real helper (H2S_SHELL_HELPER) on tests/run-helper.sh's private bus: every idle stage
// off (the defaults) → org.freedesktop.ScreenSaver left free, said "released"; the idle
// lock turned on in the profile → the name owned; off again → free again. The bus is asked
// itself (NameHasOwner), so the wiring, not only the rule, is what passes. Each step waits
// on its condition.
TestCase {
    id: suite
    suiteName: "IdleService"
    asynchronous: true

    // A suite to wait for first: one on the same bus whose helper must own the name alone
    property var after: null

    property var _steps: []
    property var _step: null
    property int _waited: 0
    // The bus's answer: "true", "false", "" while not known
    property string _hasOwner: ""

    property Process _ask: Process {
        command: ["gdbus", "call", "--session", "--dest", "org.freedesktop.DBus", "--object-path", "/org/freedesktop/DBus",
                  "--method", "org.freedesktop.DBus.NameHasOwner", "org.freedesktop.ScreenSaver"]
        stdout: SplitParser {
            onRead: data => suite._hasOwner = data.indexOf("true") >= 0 ? "true" : data.indexOf("false") >= 0 ? "false" : ""
        }
    }

    function _owner(wanted) {
        if (!_ask.running) {
            const known = _hasOwner;
            _hasOwner = "";
            _ask.running = true;
            return known === wanted;
        }
        return false;
    }

    function runAsync() {
        if (Helper.path === "") {
            fail("no helper given (H2S_SHELL_HELPER: run tests/run-helper.sh)");
            finish();
            return;
        }
        _steps = [
            { what: "the suite before it done (its helper owns the name alone)", long: true, until: () => after === null || after.done },
            { what: "the helper ready", until: () => Helper.available },
            { what: "every idle stage off: the name left free, said released",
              until: () => Idle.screenSaverService.state === "released" && _owner("false") },
            { what: "the idle lock turned on: the name owned",
              run: () => Profiles.writeInEffect("lockscreen.lockscreenEnabled", true),
              until: () => Idle.screenSaverService.state === "answering" && _owner("true") },
            { what: "off again: the name free again",
              run: () => Profiles.writeInEffect("lockscreen.lockscreenEnabled", false),
              until: () => Idle.screenSaverService.state === "released" && _owner("false") }
        ];
        _next();
    }

    function _next() {
        _step = _steps.shift() ?? null;
        if (_step === null) {
            finish();
            return;
        }
        _waited = 0;
        _hasOwner = "";
        try {
            _step.run?.();
        } catch (error) {
            fail(_step.what + ": threw " + error);
        }
        _clock.start();
    }

    property Timer _clock: Timer {
        interval: 50
        repeat: true
        onTriggered: {
            suite._waited += interval;
            let reached = false;
            try {
                reached = suite._step.until();
            } catch (error) {
                reached = false;
            }
            if (!reached && suite._waited < (suite._step.long ? 50000 : 8000))
                return;
            stop();
            suite.assert(reached, suite._step.what + " (service " + JSON.stringify(Idle.screenSaverService) + ", bus " + suite._hasOwner + ")");
            if (!reached)
                suite._steps = [];
            suite._next();
        }
    }
}
