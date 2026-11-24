import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

// logind and sleep, for Idle: what it allows — CanSuspend, CanHibernate,
// CanSuspendThenHibernate ("yes", "no", "challenge", "na") — and does by itself — its
// IdleAction and IdleActionUSec properties (logind.conf) —, and what explains a hibernation
// it does not allow or tells its delay — /proc/swaps, /proc/meminfo, the kernel's lockdown,
// its resume device and command line, sleep.conf with its drop-ins (`systemd-analyze
// cat-config`) — read by refresh(); and the sleep itself, suspend(method):
// Manager.Suspend, SuspendThenHibernate or Hibernate, with `false`: non-interactive, so
// logind never asks for a password (a polkit rule that wants one makes it fail: such a
// system answers "challenge", and Idle never asks then). Reads only, apart from the one call
// Idle makes when its rules say so.
//
// A failed or timed-out read is "unknown" (no sleep by the shell), never "yes"; a read that
// has not answered after `watchdog` ms (its five calls take up to 5 s each) is ended. A call
// that has not answered after `suspendWatchdog` ms is ended and reported as not taken. One
// read and one call at a time.
//
// `gdbus` and `systemd-analyze` are the ones on PATH, or in `toolDirectory` (H2S_LOCK_TOOLS,
// the lock test bed's seam: its stand-ins answer from the test's files, the real system bus
// being cut off there); the files are read under `fileRoot` ("" the system's; a reading
// suite's scratch directory). The paths reach the shell as arguments, never inside the
// script's text.
Scope {
    id: root

    // After each read, with its outcome (also in `support`)
    signal read(var support)
    // After each suspend(method): whether logind took it, gdbus's error line when not, and
    // the method asked
    signal suspended(bool ok, string error, string method)

    property string toolDirectory: ""
    property string fileRoot: ""
    property int watchdog: 32000
    property int suspendWatchdog: 30000
    // { canSuspend, canHibernate, canSuspendThenHibernate: "yes" | "no" | "challenge" | "na" |
    // "unknown", idleAction: { action, after (s) } | null (not read), hibernation: { swaps,
    // memoryInUse, lockdown, resume, delay } } — LockParseRules.sleepSupport
    property var support: LockParseRules.sleepSupportUnread()
    property int reads: 0
    readonly property bool running: _query.running
    readonly property bool suspending: _suspend.running

    readonly property string _gdbus: toolDirectory !== "" ? toolDirectory + "/gdbus" : "gdbus"
    readonly property string _analyze: toolDirectory !== "" ? toolDirectory + "/systemd-analyze" : "systemd-analyze"
    readonly property string _call: "call --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1 --timeout 5 --method"

    // One read at a time: asked while one runs, another follows it (an Apply's result, the
    // page opening, are never answered by a read begun before them)
    function refresh() {
        if (_query.running) {
            _query._again = true;
            return;
        }
        _query._again = false;
        _query._timedOut = false;
        _query.running = true;
        _watchdog.restart();
    }

    // The calls suspend() makes, by name
    readonly property var methods: ["Suspend", "SuspendThenHibernate", "Hibernate"]

    // `method`: one of `methods` (Suspend when not given); false for another, or while a call runs
    function suspend(method) {
        const name = method === undefined ? "Suspend" : method;
        if (_suspend.running || !methods.includes(name))
            return false;
        _suspend._method = name;
        _suspend._timedOut = false;
        _suspend.running = true;
        _suspendWatchdog.restart();
        return true;
    }

    Timer {
        id: _suspendWatchdog
        interval: root.suspendWatchdog
        repeat: false
        onTriggered: {
            if (!_suspend.running)
                return;
            _suspend._timedOut = true;
            _suspend.running = false;
        }
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
        property bool _again: false
        // Each answer under its header; a call that fails prints nothing on stdout
        // Ended (the watchdog), the call under way is ended with it: no gdbus left behind
        command: ["sh", "-c",
            "trap 'kill $call 2> /dev/null; exit 143' TERM; ask() { echo \"[$1]\"; shift; \"$gdbus\" " + root._call + " \"$@\" & call=$!; wait $call; }; "
            + "show() { echo \"[$1]\"; cat -- \"$root$2\" 2> /dev/null; }; "
            + "gdbus=$0; analyze=$1; root=$2; ask CanSuspend org.freedesktop.login1.Manager.CanSuspend; "
            + "ask CanHibernate org.freedesktop.login1.Manager.CanHibernate; "
            + "ask CanSuspendThenHibernate org.freedesktop.login1.Manager.CanSuspendThenHibernate; "
            + "ask IdleAction org.freedesktop.DBus.Properties.Get org.freedesktop.login1.Manager IdleAction; "
            + "ask IdleActionUSec org.freedesktop.DBus.Properties.Get org.freedesktop.login1.Manager IdleActionUSec; "
            + "show Swaps /proc/swaps; show Meminfo /proc/meminfo; show Lockdown /sys/kernel/security/lockdown; "
            + "show Resume /sys/power/resume; show Cmdline /proc/cmdline; "
            + "echo '[SleepConf]'; \"$analyze\" --no-pager cat-config systemd/sleep.conf 2> /dev/null & call=$!; wait $call; "
            + "true", root._gdbus, root._analyze, root.fileRoot]
        stdout: StdioCollector {
            onStreamFinished: _query._output = text
        }
        onRunningChanged: {
            if (running)
                return;
            _watchdog.stop();
            const outcome = _timedOut ? LockParseRules.sleepSupportUnread() : LockParseRules.sleepSupport(_output);
            _output = "";
            root.support = outcome;
            root.reads++;
            root.read(outcome);
            if (_again)
                Qt.callLater(root.refresh);
        }
    }

    Process {
        id: _suspend
        property string _output: ""
        property bool _timedOut: false
        property string _method: "Suspend"
        // false: non-interactive — logind fails the call rather than ask for a password.
        // gdbus's answer or error, then its status, all on stdout (one stream, read at the end);
        // ended by the watchdog, the call is ended with it
        command: ["sh", "-c", "trap 'kill $call 2> /dev/null; exit 143' TERM; "
            + "\"$0\" " + root._call + " \"org.freedesktop.login1.Manager.$1\" false 2>&1 & call=$!; "
            + "wait $call; echo \"[exit $?]\"", root._gdbus, _method]
        stdout: StdioCollector {
            onStreamFinished: _suspend._output = text
        }
        onRunningChanged: {
            if (running)
                return;
            _suspendWatchdog.stop();
            const outcome = _timedOut ? { ok: false, error: "logind did not answer within " + root.suspendWatchdog + " ms" }
                                      : LockParseRules.suspendOutcome(_output);
            _output = "";
            root.suspended(outcome.ok, outcome.error, _method);
        }
    }
}
