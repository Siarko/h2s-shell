import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

// One run of scripts/lock-auth-methods.sh for the rules' detectMethods effect, reported
// once, as methodsDetected or methodsFailed, with the generation it was asked under. One
// object per run: the lock's scope destroys the previous run when a newer one is asked for,
// and destroying a Process kills it (SIGKILL), so an older run can neither keep running nor
// report into a newer one. No timeout of its own: the rules' `detect` timer covers a script
// that hangs (plan, section 7).
//
// The script honours H2S_LOCK_AUTH_METHODS (the test bed's seam, tests/lock/README.md): it
// is inherited from the shell's environment and read by the script, not here.
Process {
    id: root

    required property int generation

    signal event(var event)

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
