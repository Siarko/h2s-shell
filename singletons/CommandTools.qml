pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The two programs the command runner puts around a run (CommandRules.wrapperTools):
// coreutils' `timeout`, which ends a command with a time limit, and util-linux's
// `setpriv`, which makes the command die with `timeout`, or with the shell where there is
// no `timeout` around it. Each is looked for
// once, on PATH, and only a trusted match is taken (ModuleRules.programVerdict: only root
// can change it) — the first, in PATH order, that also runs its probe with exit 0: no
// shell, and a file that cannot run, or a `setpriv` without --pdeathsig, is not taken.
// Until `known`, runs wait (singletons/io/CommandRunner.qml); with `timeout` missing, a
// limit is kept by the runner's own watchdog alone, and with `setpriv` missing runs are
// started bare.
Singleton {
    id: root

    readonly property bool known: _known
    readonly property string timeout: _found.timeout ?? ""
    readonly property string setpriv: _found.setpriv ?? ""

    // How long the look-up, and then each candidate's probe, may take
    readonly property int lookupMs: 5000
    readonly property int probeMs: 2000

    property bool _known: false
    property var _found: ({})
    // What is left to try: [{ tool, path }], in order
    property var _queue: []
    // Counts the questions, so that an answer names the one it is for; `_open` while the
    // current one has not been answered
    property int _question: 0
    property bool _open: false

    function _ask() {
        _question++;
        _open = true;
        return _question;
    }

    // Late answers lose: only the question that is open counts, once
    function _takes(question) {
        if (_known || !_open || question !== _question)
            return false;
        _open = false;
        _deadline.stop();
        return true;
    }

    function _lookUp() {
        _lookup.lines = [];
        _lookup.question = _ask();
        // The shell's PATH is searched; the probe's own tools come from the system's
        // directories (ModuleRules.probeToolPath), never from the PATH it judges
        _lookup.command = [ModuleRules.probeShell, "-c", ModuleRules.programProbeScript, "sh", "all", Quickshell.env("PATH") ?? ""]
            .concat(CommandRules.wrapperTools.map(tool => tool.name));
        _deadline.interval = lookupMs;
        _deadline.restart();
        _lookup.running = true;
    }

    function _lookedUp(question, lines) {
        if (!_takes(question))
            return;
        const queue = [];
        for (const tool of CommandRules.wrapperTools) {
            for (const path of ModuleRules.trustedPrograms(lines, tool.name))
                queue.push({ tool: tool, path: path });
        }
        _queue = queue;
        Qt.callLater(root._tryNext);
    }

    function _tryNext() {
        if (_known)
            return;
        // A tool found already: its other candidates are not tried
        while (_queue.length > 0 && _found[_queue[0].tool.name])
            _queue = _queue.slice(1);
        if (_queue.length === 0) {
            _finish();
            return;
        }
        _probe.question = _ask();
        _probe.command = [_queue[0].path].concat(_queue[0].tool.probe);
        _deadline.interval = probeMs;
        _deadline.restart();
        _probe.running = true;
    }

    function _probed(question, ok) {
        if (!_takes(question))
            return;
        const candidate = _queue[0];
        _queue = _queue.slice(1);
        if (ok)
            _found = Object.assign({}, _found, { [candidate.tool.name]: candidate.path });
        Qt.callLater(root._tryNext);
    }

    function _finish() {
        _known = true;
        const missing = CommandRules.wrapperTools.filter(tool => !_found[tool.name]);
        if (missing.length > 0)
            console.warn("[Commands] " + missing.map(tool => "no trusted `" + tool.name + "` on PATH").join("; ")
                         + ": time limits are kept by the shell alone, and end with it");
    }

    property Process _lookup: Process {
        environment: ({ PATH: ModuleRules.probeToolPath })
        property int question: 0
        property var lines: []
        stdout: SplitParser {
            onRead: data => _lookup.lines.push(data)
        }
        onRunningChanged: {
            if (!running)
                root._lookedUp(question, lines);
        }
    }

    property Process _probe: Process {
        property int question: 0
        property int code: -1
        onExited: (exitCode, exitStatus) => code = exitStatus === 0 ? exitCode : -1
        onRunningChanged: {
            if (running) {
                code = -1;
                return;
            }
            root._probed(question, code === 0);
        }
    }

    // A look-up that does not answer in time: what it printed so far counts; a probe: the
    // candidate is not taken. The process's own answer, when it comes, is late
    property Timer _deadline: Timer {
        onTriggered: {
            if (_lookup.running) {
                root._lookedUp(_lookup.question, _lookup.lines.slice());
                _lookup.running = false;
            } else if (_probe.running) {
                root._probed(_probe.question, false);
                _probe.running = false;
            }
        }
    }

    Component.onCompleted: _lookUp()
}
