import QtQuick

// A command read on request whose answer counts only when nothing changed during the run:
// set `command`, call request(), get answered(lines, result) — the run's non-empty stdout
// lines and the runner's result (CommandRunner: ok, code, stderr, timedOut, failedToStart,
// truncated…). A request while it runs means the state may have changed under that run:
// its answer is dropped, never handed over, and the command runs once more, so the answer
// that lands is always from a run started after the last request (CLAUDE.md, "late answers
// lose"). Unlike CommandQuery, it says whether the run worked. No time limit unless
// `timeoutMs` is set. The shell's own; not part of the module API.
QtObject {
    id: root

    property var command: []
    property int timeoutMs: 0

    // A run is going on
    readonly property bool running: _run !== null

    signal answered(var lines, var result)

    property var _run: null
    property bool _again: false

    function request() {
        if (_run !== null) {
            _again = true;
            return;
        }
        const lines = [];
        _run = _runner.start(command, {
            timeoutMs: timeoutMs,
            // stderr is what tells a refused field from another failure; stdout comes
            // line by line below
            maxOutputBytes: 262144,
            onLine: (line, stream) => {
                if (stream === "stdout" && line.trim() !== "")
                    lines.push(line);
            },
            done: result => {
                root._run = null;
                if (root._again) {
                    root._again = false;
                    root.request();
                    return;
                }
                root.answered(lines, result);
            }
        });
    }

    property CommandRunner _runner: CommandRunner {}
}
