import QtQuick

// Commands that change something (nmcli connection modify, busctl set-property…), run one
// after another, each answered with how it went: `run(command, done)` calls
// done({ ok, code, lines, error }) — ok when it exited 0; `lines` its non-empty stdout
// lines; `error` its stderr, trimmed (nmcli writes its errors there: "Error: …"), or why it
// was not run at all (`code` is then -1).
// `environment` ({ NAME: value }) is added to the command's: the way to hand it a secret —
// a process's environment is its owner's to read, its command line anyone's (`ps`). A command
// asked for while another runs waits its turn, never dropped. No time limit: the command
// decides how long it takes. Run by a CommandRunner (which says more).
QtObject {
    id: root

    // Something is running or waiting
    readonly property bool busy: _current !== null || _queue.length > 0

    property var _queue: []
    property var _current: null

    function run(command, done, environment) {
        _queue = _queue.concat([{ command: command, done: done ?? null, environment: environment ?? {} }]);
        _next();
    }

    function _next() {
        if (_current !== null || _queue.length === 0)
            return;
        const job = _queue[0];
        _queue = _queue.slice(1);
        _current = job;
        const lines = [];
        let errorText = "";
        _runner.start(job.command, {
            timeoutMs: 0,
            keepOutput: false,
            environment: job.environment,
            onLine: (line, stream) => {
                if (stream === "stdout" && line.trim() !== "")
                    lines.push(line);
            },
            onStderr: text => errorText += text,
            done: result => {
                root._current = null;
                const error = errorText.trim() || result.error || (result.failedToStart ? "the program could not be started" : "");
                if (job.done)
                    job.done({ ok: result.ok, code: result.code, lines: lines, error: error });
                Qt.callLater(root._next);
            }
        });
    }

    property CommandRunner _runner: CommandRunner {}
}
