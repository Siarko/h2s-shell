import QtQuick
import Quickshell

QtObject {
    id: suite

    property string suiteName: "Unnamed"
    property int _passed: 0
    property int _failed: 0
    // A suite that needs the event loop (input sent to a window, things settling) sets
    // this and does its work in runAsync(), started once every suite is built, calling
    // finish() at the end. tests.qml waits for it (`done`) before quitting.
    property bool asynchronous: false
    // Whether this suite runs: tests/run-unit.sh names the suites to run in H2S_TEST_SUITES
    // (their types, "FormatTest:LockRulesTest"; not set: all of them). A suite's type is its
    // suiteName followed by "Test". One that is left out does nothing and reports nothing.
    readonly property bool selected: {
        const names = Quickshell.env("H2S_TEST_SUITES");
        return typeof names !== "string" || names === "" || names.split(":").includes(suiteName + "Test");
    }
    property bool done: !asynchronous || !selected
    // How long an asynchronous suite may take before its runner fails it as timed out, in ms,
    // from the moment its process starts the suites. 0 takes the runner's default:
    // tests.qml's 90 s, tests-modules.qml's 20 s, which it caps at 60 s. A suite with many
    // concurrent scenarios sets more than the default.
    property int timeLimitMs: 0
    // Whether this suite needs a Quickshell process of its own: tests/run-unit.sh reads it
    // from the suite's file (a line `ownProcess: true`) and never puts another suite in that
    // shard. Set by a suite that changes what is shared in one process with others that do
    // too (the module host, Config's module list, the keyboard a window takes). Such a suite
    // says so when it starts (OWN-PROCESS), and the runner's verdict fails a process where
    // other suites reported beside it: a plan that missed the line fails loudly.
    property bool ownProcess: false
    // Whether this suite tests an animation itself: tests.qml makes every animation instant
    // (Theme.instantAnimations) unless a suite selected in its process sets this; then the
    // whole process runs them at the theme's durations
    property bool animations: false
    // When it started (ms since the epoch), for the time its summary gives: tests/run-unit.sh
    // plans its shards from those times
    property real _startedMs: 0
    // How long it took, from its start to finish(): its summary may come later (finish)
    property real _tookMs: -1
    // finish() was called: its summary may still wait (finish)
    property bool _finished: false
    // The shared state when this suite started (SharedState.snapshot), compared when it reports;
    // null when it is not checked
    property var _stateBefore: null
    // The asynchronous suites that ran while this one did: a difference may be theirs
    property var _beside: []

    function assert(condition, message) {
        if (condition) {
            _passed++;
            console.log("  PASS: " + message);
        } else {
            _failed++;
            console.error("  FAIL: " + message);
        }
    }

    function assertEqual(actual, expected, message) {
        if (actual === expected) {
            _passed++;
            console.log("  PASS: " + message);
        } else {
            _failed++;
            console.error("  FAIL: " + message + " — expected " + JSON.stringify(expected) + ", got " + JSON.stringify(actual));
        }
    }

    function fail(message) {
        _failed++;
        console.error("  FAIL: " + message);
    }

    function run() {}

    function runAsync() {}

    // Whether this suite's leftovers are checked: when the runner checks, and the suite shares
    // its process (a suite with a process of its own may leave it changed)
    readonly property bool _stateChecked: SharedState.checking && !ownProcess

    function _takeState() {
        if (_stateChecked)
            _stateBefore = SharedState.snapshot();
    }

    // Fails the suite when it left the shared state other than it found it, naming what changed
    function _checkState() {
        if (_stateBefore === null)
            return;
        const changed = SharedState.changedKeys(_stateBefore, SharedState.snapshot());
        _stateBefore = null;
        if (changed.length > 0)
            fail("left " + SharedState.listed(changed, SharedState.maxListed) + " changed"
                 + (_beside.length > 0 ? " (beside it ran: " + _beside.join(", ") + ")" : ""));
    }

    function _summary() {
        const total = _passed + _failed;
        console.log("--- " + suiteName + ": " + _passed + "/" + total + " passed" + (_failed > 0 ? ", " + _failed + " FAILED" : "")
                    + " (" + (_tookMs >= 0 ? _tookMs : Math.max(0, Math.round(Date.now() - _startedMs))) + " ms) ---\n");
    }

    function finish() {
        if (_finished)
            return;
        _finished = true;
        _tookMs = Math.max(0, Math.round(Date.now() - _startedMs));
        SharedState.running = SharedState.running.filter(other => other !== suite);
        // A checked suite is judged later (SharedState.judgeLater): once no suite that ran
        // beside it still runs — what one of them changed for a while would count as this
        // one's — and the state has settled, so that a write this suite left to the event
        // loop is judged on it
        if (_stateBefore !== null) {
            SharedState.judgeLater(suite);
            return;
        }
        _report();
    }

    // The verdict: what it left changed (when checked), its summary, and done
    function _report() {
        _checkState();
        _summary();
        done = true;
    }

    Component.onCompleted: {
        if (!selected)
            return;
        if (ownProcess)
            console.log("OWN-PROCESS: " + suiteName);
        if (ownProcess && SharedState.checking)
            console.log("SHARED-STATE: not checked for " + suiteName + ": it runs in a process of its own");
        if (asynchronous) {
            const start = () => {
                console.log("\n=== " + suite.suiteName + " ===");
                for (const other of SharedState.running) {
                    other._beside = other._beside.concat([suite.suiteName]);
                    suite._beside = suite._beside.concat([other.suiteName]);
                }
                SharedState.running = SharedState.running.concat([suite]);
                suite._startedMs = Date.now();
                try {
                    suite.runAsync();
                } catch (error) {
                    suite.fail("threw: " + error);
                    suite.finish();
                }
            };
            // A checked suite starts once the shell's startup has written what it writes, or
            // that would count as the suite's; the suites starting together take their
            // snapshots before any of them runs
            if (_stateChecked)
                SharedState.whenSettled(() => suite._takeState(), start);
            else
                Qt.callLater(start);
            return;
        }
        console.log("\n=== " + suiteName + " ===");
        _startedMs = Date.now();
        _takeState();
        // A suite that throws counts as failed, not as missing: it used to stop before its
        // summary, and nothing said so
        try {
            run();
        } catch (error) {
            fail("threw: " + error);
        }
        _checkState();
        _summary();
    }
}
