import QtQuick

QtObject {
    id: suite

    property string suiteName: "Unnamed"
    property int _passed: 0
    property int _failed: 0
    // A suite that needs the event loop (input sent to a window, things settling) sets
    // this and does its work in runAsync(), started once every suite is built, calling
    // finish() at the end. tests.qml waits for it (`done`) before quitting.
    property bool asynchronous: false
    property bool done: !asynchronous

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
        console.log("--- " + suiteName + ": " + _passed + "/" + total + " passed" + (_failed > 0 ? ", " + _failed + " FAILED" : "") + " ---\n");
    }

    function finish() {
        if (done)
            return;
        _summary();
        done = true;
    }

    Component.onCompleted: {
        if (asynchronous) {
            Qt.callLater(() => {
                console.log("\n=== " + suite.suiteName + " ===");
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
