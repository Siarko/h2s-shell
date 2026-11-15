import QtQuick
import Quickshell.Io

// Commands that change something (nmcli connection modify, busctl set-property…), run one
// after another, each answered with how it went: `run(command, done)` calls
// done({ ok, code, lines, error }) — ok when it exited 0; `lines` its non-empty stdout
// lines; `error` its stderr, trimmed (nmcli writes its errors there: "Error: …").
// `environment` ({ NAME: value }) is added to the command's: the way to hand it a secret —
// a process's environment is its owner's to read, its command line anyone's (`ps`). A command
// asked for while another runs waits its turn, never dropped. Started by run(), never by a
// declarative `running: true` (CLAUDE.md).
QtObject {
    id: root

    // Something is running or waiting
    readonly property bool busy: _process.running || _queue.length > 0

    property var _queue: []
    property var _current: null

    function run(command, done, environment) {
        _queue = _queue.concat([{ command: command, done: done ?? null, environment: environment ?? {} }]);
        _next();
    }

    function _next() {
        if (_process.running || _queue.length === 0)
            return;
        _current = _queue[0];
        _queue = _queue.slice(1);
        _process.lines = [];
        _process.errorText = "";
        _process.command = _current.command;
        _process.environment = _current.environment;
        _process.running = true;
    }

    property Process _process: Process {
        property var lines: []
        property string errorText: ""
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                if (line.trim() !== "")
                    root._process.lines.push(line);
            }
        }
        stderr: SplitParser {
            splitMarker: ""
            onRead: data => root._process.errorText += data
        }
        onExited: (exitCode, exitStatus) => {
            const job = root._current;
            root._current = null;
            const result = { ok: exitCode === 0, code: exitCode, lines: lines, error: errorText.trim() };
            if (job?.done)
                job.done(result);
            Qt.callLater(root._next);
        }
    }
}
