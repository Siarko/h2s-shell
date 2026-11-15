import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

// logind's sleep "delay" inhibitor, held as a level: `wanted` says whether it should be
// held (the rules' holdInhibitor / releaseInhibitor), and this keeps it so. While it is
// held, logind waits (up to its InhibitDelayMaxSec, 5 s by default) before suspending, so
// the screen can lock first. Lives for the shell's lifetime.
//
// The lock is held for as long as `systemd-inhibit` runs; it ends when a line arrives on
// its input (the release), or when the shell goes away and that input closes with it — so
// a crashed shell leaves no inhibitor behind. When it ends while still wanted (logind
// restarted, no system bus) it is taken again after a growing pause
// (LockIoRules.restartDelay), never in a tight loop; after a release this shell asked for,
// a new hold starts at once.
//
// `systemd-inhibit` is the one on PATH, or `toolDirectory`/systemd-inhibit when the driver
// names a directory (H2S_LOCK_TOOLS, the lock test bed's seam: its stand-in records holds
// and releases, the real system bus being cut off there).
Scope {
    id: root

    signal logLine(string level, string message)

    property bool wanted: false
    // Where `systemd-inhibit` is taken from: "" for PATH (see the header)
    property string toolDirectory: ""
    // Whether a systemd-inhibit process is running (held, or being released)
    readonly property bool running: _process.running

    readonly property var _restartTable: ({ minimum: 1000, maximum: 60000, healthyRun: 60000 })

    property double _startedAt: 0
    property int _delay: 0
    // A release was written and the process has not ended yet
    property bool _releasing: false

    onWantedChanged: _apply()

    function _apply() {
        if (wanted) {
            if (!_process.running && !_retry.running)
                _start();
        } else {
            _retry.stop();
            if (_process.running && !_releasing) {
                _releasing = true;
                _process.write("\n");
            }
        }
    }

    function _start() {
        _startedAt = Date.now();
        _releasing = false;
        _process.running = true;
    }

    Process {
        id: _process
        stdinEnabled: true
        command: [root.toolDirectory !== "" ? root.toolDirectory + "/systemd-inhibit" : "systemd-inhibit",
            "--what=sleep", "--mode=delay", "--who=h2s-shell",
            "--why=Lock the screen before sleep", "sh", "-c", "read -r release"]

        onRunningChanged: {
            if (running)
                return;
            const released = root._releasing;
            root._releasing = false;
            if (!root.wanted)
                return;
            if (released) {
                // Released on request, and wanted again meanwhile: hold it again now
                root._start();
                return;
            }
            const ran = Date.now() - root._startedAt;
            root._delay = LockIoRules.restartDelay(root._delay, ran, root._restartTable);
            root.logLine("warning", "the sleep inhibitor ended after " + Math.round(ran / 1000)
                + " s while wanted: taken again in " + Math.round(root._delay / 1000) + " s");
            _retry.interval = root._delay;
            _retry.start();
        }
    }

    Timer {
        id: _retry
        repeat: false
        onTriggered: {
            if (root.wanted && !_process.running)
                root._start();
        }
    }
}
