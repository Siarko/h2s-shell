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
    // too (the module host, Config's module list, the keyboard a window takes).
    property bool ownProcess: false
    // When it started (ms since the epoch), for the time its summary gives: tests/run-unit.sh
    // plans its shards from those times
    property real _startedMs: 0

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

    function _summary() {
        const total = _passed + _failed;
        console.log("--- " + suiteName + ": " + _passed + "/" + total + " passed" + (_failed > 0 ? ", " + _failed + " FAILED" : "")
                    + " (" + Math.max(0, Math.round(Date.now() - _startedMs)) + " ms) ---\n");
    }

    function finish() {
        if (done)
            return;
        _summary();
        done = true;
    }

    Component.onCompleted: {
        if (!selected)
            return;
        if (asynchronous) {
            Qt.callLater(() => {
                console.log("\n=== " + suite.suiteName + " ===");
                suite._startedMs = Date.now();
                try {
                    suite.runAsync();
                } catch (error) {
                    suite.fail("threw: " + error);
                    suite.finish();
                }
            });
            return;
        }
        console.log("\n=== " + suiteName + " ===");
        _startedMs = Date.now();
        // A suite that throws counts as failed, not as missing: it used to stop before its
        // summary, and nothing said so
        try {
            run();
        } catch (error) {
            fail("threw: " + error);
        }
        _summary();
    }
}
