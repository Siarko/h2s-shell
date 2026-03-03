import QtQuick

QtObject {
    property string suiteName: "Unnamed"
    property int _passed: 0
    property int _failed: 0

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

    Component.onCompleted: {
        console.log("\n=== " + suiteName + " ===");
        run();
        const total = _passed + _failed;
        console.log("--- " + suiteName + ": " + _passed + "/" + total + " passed" + (_failed > 0 ? ", " + _failed + " FAILED" : "") + " ---\n");
    }
}
