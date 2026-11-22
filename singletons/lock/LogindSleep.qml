import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

// logind and sleep, for Idle: what it allows — CanSuspend ("yes", "no", "challenge", "na")
// — and does by itself — its IdleAction and IdleActionUSec properties (logind.conf) —, read
// by refresh(); and the sleep itself, suspend(): Manager.Suspend(false), non-interactive, so
// logind never asks for a password (a polkit rule that wants one makes it fail: such a
// system answers CanSuspend "challenge", and Idle never asks then). Reads only, apart from
// the one call Idle makes when its rules say so.
//
// A failed or timed-out read is "unknown" (no sleep by the shell), never "yes"; a read that
// has not answered after `watchdog` ms is ended. One read and one call at a time.
//
// `gdbus` is the one on PATH, or `toolDirectory`/gdbus (H2S_LOCK_TOOLS, the lock test bed's
// seam: its stand-in answers from the test's files, the real system bus being cut off
// there). The path reaches the shell as `$0`, never inside the script's text.
Scope {
    id: root

    // After each read, with its outcome (also in `support`)
    signal read(var support)
    // After each suspend(): whether logind took it, and gdbus's error line when not
    signal suspended(bool ok, string error)

    property string toolDirectory: ""
    property int watchdog: 7000
    // { canSuspend: "yes" | "no" | "challenge" | "na" | "unknown", idleAction: { action,
    // after (s) } | null (not read) } — LockParseRules.sleepSupport
    property var support: ({ canSuspend: "unknown", idleAction: null })
    property int reads: 0
    readonly property bool running: _query.running
    readonly property bool suspending: _suspend.running

    readonly property string _gdbus: toolDirectory !== "" ? toolDirectory + "/gdbus" : "gdbus"
    readonly property string _call: "call --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1 --timeout 5 --method"

    function refresh() {
        if (_query.running)
            return;
        _query._timedOut = false;
        _query.running = true;
        _watchdog.restart();
    }

    function suspend() {
        if (_suspend.running)
            return false;
        _suspend.running = true;
        return true;
    }

    Timer {
        id: _watchdog
        interval: root.watchdog
        repeat: false
        onTriggered: {
            if (!_query.running)
                return;
            _query._timedOut = true;
            _query.running = false;
        }
    }

    Process {
        id: _query
        property string _output: ""
        property bool _timedOut: false
        // Each answer under its header; a call that fails prints nothing on stdout
        command: ["sh", "-c",
            "echo '[CanSuspend]'; \"$0\" " + root._call + " org.freedesktop.login1.Manager.CanSuspend; "
            + "echo '[IdleAction]'; \"$0\" " + root._call + " org.freedesktop.DBus.Properties.Get org.freedesktop.login1.Manager IdleAction; "
            + "echo '[IdleActionUSec]'; \"$0\" " + root._call + " org.freedesktop.DBus.Properties.Get org.freedesktop.login1.Manager IdleActionUSec; "
            + "true", root._gdbus]
        stdout: StdioCollector {
            onStreamFinished: _query._output = text
        }
        onRunningChanged: {
            if (running)
                return;
            _watchdog.stop();
            const outcome = _timedOut ? LockParseRules.sleepSupport("") : LockParseRules.sleepSupport(_output);
            _output = "";
            root.support = outcome;
            root.reads++;
            root.read(outcome);
        }
    }

    Process {
        id: _suspend
        property string _output: ""
        // false: non-interactive — logind fails the call rather than ask for a password.
        // gdbus's answer or error, then its status, all on stdout (one stream, read at the end)
        command: ["sh", "-c", "out=$(\"$0\" " + root._call + " org.freedesktop.login1.Manager.Suspend false 2>&1); "
            + "code=$?; printf '%s\\n[exit %s]\\n' \"$out\" \"$code\"", root._gdbus]
        stdout: StdioCollector {
            onStreamFinished: _suspend._output = text
        }
        onRunningChanged: {
            if (running)
                return;
            const outcome = LockParseRules.suspendOutcome(_output);
            _output = "";
            root.suspended(outcome.ok, outcome.error);
        }
    }
}
