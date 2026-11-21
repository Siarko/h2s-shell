import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

// Reads whether something besides this shell locks the screen before sleep: logind's
// sleep inhibitors (ListInhibitors, a read: no polkit, nothing changed) and this user's uid,
// decided by LockIoRules.sleepLockers. One read at a time; read() while one runs is
// dropped (the running one answers with what is there now). A failed read is "unknown".
//
// `gdbus` is the one on PATH, or `toolDirectory`/gdbus (H2S_LOCK_TOOLS, the lock test bed's
// seam: its stand-in answers from the test's list, the real system bus being cut off there).
Scope {
    id: root

    // After each read, with its outcome (also in `lockers`)
    signal read(var lockers)

    property string toolDirectory: ""
    // The last read's outcome: { state: "present" | "possible" | "none" | "unknown", names }
    property var lockers: ({ state: "unknown", names: [] })
    // Reads answered so far
    property int reads: 0
    readonly property bool running: _query.running

    function start() {
        if (!_query.running)
            _query.running = true;
    }

    Process {
        id: _query
        property string _output: ""
        command: ["sh", "-c", "id -u && exec \"$0\" call --system --dest org.freedesktop.login1 "
            + "--object-path /org/freedesktop/login1 --method org.freedesktop.login1.Manager.ListInhibitors",
            root.toolDirectory !== "" ? root.toolDirectory + "/gdbus" : "gdbus"]
        stdout: StdioCollector {
            onStreamFinished: _query._output = text
        }
        onRunningChanged: {
            if (running)
                return;
            const outcome = LockIoRules.sleepLockersFromOutput(_output);
            _output = "";
            root.lockers = outcome;
            root.reads++;
            root.read(outcome);
        }
    }
}
