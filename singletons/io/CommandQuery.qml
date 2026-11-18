import QtQuick

// A command whose output is read line by line, run on request — `nmcli` queries, mostly:
// set `command`, call request(), get done(lines), the run's non-empty lines as printed
// (none when it could not be run). A request while it is running may have come too late
// for that run (a change reported mid-query), so it runs once more when it finishes rather
// than being dropped. No time limit. Run by a CommandRunner (which says more).
QtObject {
    id: root

    property var command: []

    // A run is going on
    readonly property bool running: _run !== null

    // The run's non-empty lines, as printed
    signal done(var lines)

    property var _run: null
    property bool _again: false

    function request() {
        if (_run !== null) {
            _again = true;
            return;
        }
        const lines = [];
        _run = _runner.start(command, {
            timeoutMs: 0,
            keepOutput: false,
            onLine: (line, stream) => {
                if (stream === "stdout" && line.trim() !== "")
                    lines.push(line);
            },
            done: result => {
                root._run = null;
                root.done(lines);
                if (root._again) {
                    root._again = false;
                    root.request();
                }
            }
        });
    }

    // null, or a function (argv) → "" or why a run is refused (CommandRunner.refuse)
    property var refuse: null

    property CommandRunner _runner: CommandRunner {
        refuse: root.refuse
    }
}
