pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The two programs the command runner puts around a run with a time limit
// (CommandRules.wrapperTools): coreutils' `timeout`, which ends the command, and
// util-linux's `setpriv`, which makes the command die with `timeout`. Each is looked for
// once, in system directories only. A candidate counts when its file is there and it
// runs its probe with exit 0 — no shell, and a file that cannot run, or a `setpriv`
// without --pdeathsig, is not taken. Until `known`, runs with a limit wait
// (singletons/io/CommandRunner.qml); with one of the two missing, they run bare, under the
// runner's own watchdog alone.
Singleton {
    id: root

    readonly property bool known: _known
    readonly property string timeout: _found.timeout ?? ""
    readonly property string setpriv: _found.setpriv ?? ""

    // How long one candidate may take to answer
    readonly property int probeMs: 2000

    property bool _known: false
    property var _found: ({})
    // Which tool, which of its candidates
    property int _tool: 0
    property int _index: -1
    // What the current candidate is asked: "file" (is it there), "run", or "" (answered)
    property string _asking: ""
    // Counts the questions, so that an answer names the one it is for
    property int _question: 0

    function _candidate() {
        return CommandRules.wrapperTools[_tool].candidates[_index];
    }

    function _tryNext() {
        const tools = CommandRules.wrapperTools;
        _index++;
        if (_index >= tools[_tool].candidates.length) {
            _tool++;
            _index = 0;
        }
        if (_tool >= tools.length) {
            _known = true;
            _file.path = "";
            const missing = tools.filter(tool => !_found[tool.name]);
            if (missing.length > 0)
                console.warn("[Commands] " + missing.map(tool => "no `" + tool.name + "` in " + tool.candidates.join(", ")).join("; ")
                             + ": time limits are kept by the shell alone, and end with it");
            return;
        }
        _question++;
        _asking = "file";
        _deadline.restart();
        _file.path = _candidate();
    }

    // Late answers lose: only the question that is open counts
    function _answered(question, asked, ok) {
        if (_known || question !== _question || asked !== _asking)
            return;
        if (ok && asked === "file") {
            _asking = "run";
            _probe.command = [_candidate()].concat(CommandRules.wrapperTools[_tool].probe);
            _probe.running = true;
            return;
        }
        _asking = "";
        _deadline.stop();
        if (ok) {
            _found = Object.assign({}, _found, { [CommandRules.wrapperTools[_tool].name]: _candidate() });
            // The next tool
            _index = CommandRules.wrapperTools[_tool].candidates.length;
        }
        Qt.callLater(root._tryNext);
    }

    // Asked first, quietly: starting a program that is not there is a warning in the log
    // at every start of the shell, on the system whose candidate comes second
    property FileView _file: FileView {
        printErrors: false
        onLoaded: root._answered(root._question, "file", true)
        onLoadFailed: root._answered(root._question, "file", false)
    }

    property Process _probe: Process {
        property int code: -1
        onExited: (exitCode, exitStatus) => code = exitStatus === 0 ? exitCode : -1
        onRunningChanged: {
            if (running) {
                code = -1;
                return;
            }
            root._answered(root._question, "run", code === 0);
        }
    }

    property Timer _deadline: Timer {
        interval: root.probeMs
        onTriggered: {
            const question = root._question;
            const asked = root._asking;
            if (_probe.running)
                _probe.running = false;
            root._answered(question, asked, false);
        }
    }

    Component.onCompleted: _tryNext()
}
