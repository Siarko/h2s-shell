import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

// Reads whether an app holds logind's `idle` block inhibitor (`systemd-inhibit
// --what=idle`, video players): ListInhibitors (a read: no polkit, nothing changed) and this
// user's uid, decided by LockParseRules.idleBlock. Idle says when (IdleRules.logindReadDue).
// One read at a time; start() while one runs is dropped (the running one answers with what
// is there now). A failed, timed-out or malformed read is "unknown", never "free"; a read
// that has not answered after `watchdog` ms (gdbus's own timeout covers the call, not
// connecting to the bus) is ended and answers "unknown", whatever it printed so far.
//
// `gdbus` is the one on PATH, or `toolDirectory`/gdbus (H2S_LOCK_TOOLS, the lock test bed's
// seam: its stand-in answers from the test's list, the real system bus being cut off there).
// The path reaches the shell as `$0`, never inside the script's text.
Scope {
    id: root

    // After each read, with its outcome (also in `block`)
    signal read(var block)

    property string toolDirectory: ""
    property int watchdog: 7000
    // The last read's outcome: { held: true | false | "unknown", holders: [{ who, why }] }
    property var block: ({ held: "unknown", holders: [] })
    // Reads answered so far
    property int reads: 0
    readonly property bool running: _query.running

    function start() {
        if (_query.running)
            return;
        _query._timedOut = false;
        _query.running = true;
        _watchdog.restart();
    }

    Timer {
        id: _watchdog
        interval: root.watchdog
        repeat: false
        onTriggered: {
            if (!_query.running)
                return;
            _query._timedOut = true;
            _query.running = false;
        }
    }

    Process {
        id: _query
        property string _output: ""
        property bool _timedOut: false
        // A logind that does not answer must not hold the stage it is read for: gdbus gives
        // up after 5 s (its default is 25)
        command: ["sh", "-c", "id -u && exec \"$0\" call --system --dest org.freedesktop.login1 "
            + "--object-path /org/freedesktop/login1 --timeout 5 --method org.freedesktop.login1.Manager.ListInhibitors",
            root.toolDirectory !== "" ? root.toolDirectory + "/gdbus" : "gdbus"]
        stdout: StdioCollector {
            onStreamFinished: _query._output = text
        }
        onRunningChanged: {
            if (running)
                return;
            _watchdog.stop();
            const outcome = _timedOut ? LockParseRules.idleBlock(null, null) : LockParseRules.idleBlockFromOutput(_output);
            _output = "";
            root.block = outcome;
            root.reads++;
            root.read(outcome);
        }
    }
}
