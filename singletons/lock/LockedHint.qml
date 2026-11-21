import QtQuick
import Quickshell
import Quickshell.Io

// logind's LockedHint for the shell's session: `SetLockedHint` on the session's object path,
// which the session's owner may call without polkit. Programs that lock themselves when the
// session locks (password managers) follow it. LockRules decides when (reportLockedHint).
//
// One `gdbus call` at a time, and the latest wish wins: a lock and an unlock in quick
// succession end with the unlock's value, never with a call that finished late. A call that
// fails is logged once, on a change of outcome, and not retried — the next lock or unlock
// calls again. Without a session path (no logind session, or not known yet) nothing is
// called; the latest wish is sent when the path becomes known.
//
// `gdbus` is the one on PATH, or `toolDirectory`/gdbus (H2S_LOCK_TOOLS, the lock test bed's
// seam: its stand-in records the call).
Scope {
    id: root

    signal logLine(string level, string message)

    property string sessionPath: ""
    property string toolDirectory: ""
    readonly property string _gdbus: toolDirectory !== "" ? toolDirectory + "/gdbus" : "gdbus"

    // The value to report, the one the running call sends, the last call's outcome
    property var _wanted: null
    property var _sending: null
    property string _lastOutcome: ""
    property string _error: ""

    onSessionPathChanged: _next()

    function report(locked) {
        _wanted = locked === true;
        _next();
    }

    function _next() {
        // Without the session's path yet (logind still asked) the wish waits for it
        if (_call.running || _wanted === null || sessionPath === "")
            return;
        _sending = _wanted;
        _wanted = null;
        _error = "";
        _call.command = [_gdbus, "call", "--system", "--dest", "org.freedesktop.login1",
                         "--object-path", sessionPath, "--method", "org.freedesktop.login1.Session.SetLockedHint",
                         _sending ? "true" : "false"];
        _call.running = true;
    }

    function _finished(code) {
        const outcome = code === 0 ? "ok" : "failed";
        if (outcome !== _lastOutcome) {
            if (outcome === "failed")
                logLine("warning", "could not report the lock to logind (SetLockedHint " + _sending + "): exit " + code
                        + (_error !== "" ? ", " + _error : "") + "; told again at the next lock or unlock");
            else if (_lastOutcome !== "")
                logLine("info", "the lock is reported to logind again (SetLockedHint)");
            _lastOutcome = outcome;
        }
        _sending = null;
        _next();
    }

    Process {
        id: _call
        stderr: SplitParser {
            splitMarker: "\n"
            // One line kept for the log, capped: what gdbus says is outside text
            onRead: line => {
                if (root._error === "")
                    root._error = line.slice(0, 200);
            }
        }
        onExited: code => root._finished(code)
    }
}
