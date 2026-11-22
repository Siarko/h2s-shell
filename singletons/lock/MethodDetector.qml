import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

// One run of scripts/lock-auth-methods.sh for the rules' detectMethods effect, reported
// once, as methodsDetected or methodsFailed, with the generation it was asked under. One
// object per run: the lock's scope destroys the previous run when a newer one is asked for,
// and destroying a Process kills it (SIGKILL), so an older run can neither keep running nor
// report into a newer one. No timeout of its own: the rules' `detect` timer covers a script
// that hangs.
//
// The script honours H2S_LOCK_AUTH_METHODS (the test bed's seam, tests/lock/README.md): it
// is inherited from the shell's environment and read by the script, not here.
//
// Exit status 0 is an answer, any other a failure (LockIoRules.detectionEvent): the script
// exits non-zero when a question could not be answered (fprintd timed out…), after printing
// the lines it could answer, which a failure does not use. What it says on stderr — why it
// failed — is logged as it comes.
Process {
    id: root

    required property int generation

    signal event(var event)
    signal logLine(string level, string message)

    // Set before the object is destroyed for a newer run: nothing more is reported
    property bool cancelled: false

    property var _lines: []
    property bool _exited: false
    property int _exitCode: -1
    property bool _crashed: false
    property bool _reported: false

    command: [Quickshell.shellDir + "/scripts/lock-auth-methods.sh"]

    stdout: SplitParser {
        splitMarker: "\n"
        onRead: line => {
            if (line.trim() !== "")
                root._lines = root._lines.concat([line]);
        }
    }

    // The script's own words (it reads no input, so they hold nothing typed), cut short in
    // case of a flood
    stderr: SplitParser {
        splitMarker: "\n"
        onRead: line => {
            if (line.trim() !== "" && !root.cancelled)
                root.logLine("warning", "methods script: " + line.trim().slice(0, 300));
        }
    }

    onExited: (exitCode, exitStatus) => {
        _exited = true;
        _exitCode = exitCode;
        _crashed = exitStatus !== 0;
    }

    // Becomes false exactly once per run: after `exited` when it ran, without it when the
    // script could not be started at all
    onRunningChanged: {
        if (running || _reported || cancelled)
            return;
        _reported = true;
        root.event(LockIoRules.detectionEvent(generation, {
            started: _exited,
            exitCode: _exitCode,
            crashed: _crashed,
            lines: _lines
        }));
    }

    // Started here, never by a declarative `running: true` (CLAUDE.md)
    Component.onCompleted: running = true
}
