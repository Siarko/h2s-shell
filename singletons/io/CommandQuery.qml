import Quickshell.Io

// A command whose output is read line by line, run on request — `nmcli` queries, mostly.
// A request while it is running may have come too late for that run (a change reported
// mid-query), so it runs once more when it finishes rather than being dropped. Started by
// request(), never by a declarative `running: true` (see CLAUDE.md).
Process {
    id: root

    // The run's non-empty lines, as printed
    signal done(var lines)

    property var _lines: []
    property bool _again: false

    function request() {
        if (running) {
            _again = true;
            return;
        }
        _lines = [];
        running = true;
    }

    stdout: SplitParser {
        splitMarker: "\n"
        onRead: line => {
            if (line.trim() !== "")
                root._lines.push(line);
        }
    }

    onRunningChanged: {
        if (running)
            return;
        const lines = _lines;
        _lines = [];
        root.done(lines);
        if (_again) {
            _again = false;
            request();
        }
    }
}
