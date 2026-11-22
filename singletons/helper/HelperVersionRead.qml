import QtQuick
import qs.singletons
import qs.singletons.io

// Asks a helper program its version and protocol, once (`h2s-helper --version`), and keeps
// what HelperRules makes of it. The shell's one instance is Helper's; the program is a
// property, so a suite points it at a stand-in (tests/HelperTest.qml).
QtObject {
    id: root

    // The program; "" for none
    property string path: ""

    // "missing" | "checking" | "ready" | "outdated" | "failed" (HelperRules.readVersion)
    property string state: path === "" ? "missing" : "checking"
    property string version: ""
    property string problem: ""

    // Read again (the path changed, or a test asks)
    function read() {
        _stamp += 1;
        const stamp = _stamp;
        if (path === "") {
            _apply(stamp, { state: "missing", version: "", problem: "" });
            return;
        }
        state = "checking";
        _runner.start([path, "--version"], {
            timeoutMs: 5000,
            maxOutputBytes: 4096,
            done: result => root._apply(stamp, HelperRules.readVersion(result))
        });
    }

    property int _stamp: 0

    // A late answer (from a reading before the last) loses
    function _apply(stamp, reading) {
        if (stamp !== _stamp)
            return;
        const line = HelperRules.logLine(path, reading);
        if (line !== "" && reading.state !== state)
            console.warn("Helper: " + line);
        state = reading.state;
        version = reading.version;
        problem = reading.problem;
    }

    onPathChanged: read()
    Component.onCompleted: read()

    property CommandRunner _runner: CommandRunner {}
}
