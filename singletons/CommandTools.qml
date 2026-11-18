pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The program the command runner puts around a run with a time limit: coreutils'
// `timeout`, looked for once, in system directories only (CommandRules.timeoutCandidates).
// A candidate counts when its file is there and `<candidate> --version` exits 0 — no
// shell, and a file that cannot run is not taken. Until `known`, runs with a limit wait
// (singletons/io/CommandRunner.qml); with none found (`timeout` ""), they run under the
// runner's own watchdog alone.
Singleton {
    id: root

    readonly property bool known: _known
    readonly property string timeout: _timeout

    // How long one candidate may take to answer
    readonly property int probeMs: 2000

    property bool _known: false
    property string _timeout: ""
    property int _index: -1
    // What the current candidate is asked: "file" (is it there), "run", or "" (answered)
    property string _asking: ""

    function _tryNext() {
        _index++;
        if (_index >= CommandRules.timeoutCandidates.length) {
            _known = true;
            console.warn("[Commands] no `timeout` in " + CommandRules.timeoutCandidates.join(", ")
                         + ": time limits are kept by the shell alone, and end with it");
            return;
        }
        _asking = "file";
        _deadline.restart();
        _file.path = CommandRules.timeoutCandidates[_index];
    }

    // Late answers lose: only the question that is open for the current candidate counts
    function _answered(index, question, ok) {
        if (_known || index !== _index || question !== _asking)
            return;
        if (ok && question === "file") {
            _asking = "run";
            _probe.command = [CommandRules.timeoutCandidates[_index], "--version"];
            _probe.running = true;
            return;
        }
        _asking = "";
        _deadline.stop();
        if (ok) {
            _timeout = CommandRules.timeoutCandidates[_index];
            _known = true;
            // The file's text is not what was asked for: let it go
            _file.path = "";
            return;
        }
        Qt.callLater(root._tryNext);
    }

    // Asked first, quietly: starting a program that is not there is a warning in the log
    // at every start of the shell, on the system whose candidate comes second
    property FileView _file: FileView {
        printErrors: false
        onLoaded: root._answered(root._index, "file", true)
        onLoadFailed: root._answered(root._index, "file", false)
    }

    property Process _probe: Process {
        property int code: -1
        onExited: (exitCode, exitStatus) => code = exitStatus === 0 ? exitCode : -1
        onRunningChanged: {
            if (running) {
                code = -1;
                return;
            }
            root._answered(root._index, "run", code === 0);
        }
    }

    property Timer _deadline: Timer {
        interval: root.probeMs
        onTriggered: {
            const index = root._index;
            const question = root._asking;
            if (_probe.running)
                _probe.running = false;
            root._answered(index, question, false);
        }
    }

    Component.onCompleted: _tryNext()
}
