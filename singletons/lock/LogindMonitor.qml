import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

// logind's word, as the rules' events: Lock and Unlock on the shell's own session
// (`loginctl lock-session` / `unlock-session`, a power key or lid set to "lock"), and
// PrepareForSleep(true / false) for the whole machine. Lives for the shell's lifetime.
//
// One `gdbus monitor` on everything login1 emits; LockRules.parseLogind picks the lines
// that mean something, Lock and Unlock only on this session's object path. The path is
// asked of logind once (GetSession with XDG_SESSION_ID): without XDG_SESSION_ID there is no
// session to follow, which is logged once and never retried; a lookup that fails is logged
// once and retried with a growing pause. Sleep is followed either way.
//
// The monitor is restarted when it ends (logind or the bus restarted, no bus at all) with
// a growing pause (LockIoRules.restartDelay), never in a tight loop.
//
// Orphans: a Process's children survive a crash of the shell, and `gdbus monitor` only
// notices a dead reader when it next writes — which may be hours later — so crashed
// shells used to leave them piling up. Here gdbus runs under a small sh that also reads its
// own standard input, a pipe whose only writer is this shell: when the shell goes away, by
// a crash or by destroying the Process, the pipe closes, the read ends, and the sh kills
// gdbus. When gdbus ends on its own, the sh ends with it and the monitor is restarted.
//
// `gdbus` is the one on PATH, or `toolDirectory`/gdbus when the driver names a directory
// (H2S_LOCK_TOOLS, the lock test bed's seam: its stand-in delivers these signals, the real
// system bus being cut off there).
Scope {
    id: root

    signal event(var event)
    signal logLine(string level, string message)
    // logind said, when asked right after the monitor began listening, that it is preparing
    // for sleep (its PrepareForSleep came before anyone here listened: a reload, a start)
    signal preparingForSleep()

    readonly property string sessionId: Quickshell.env("XDG_SESSION_ID") ?? ""
    // This session's object path once known; "" until then, or for none
    property string sessionPath: ""
    // Where `gdbus` is taken from: "" for PATH (see the header)
    property string toolDirectory: ""
    readonly property string _gdbus: toolDirectory !== "" ? toolDirectory + "/gdbus" : "gdbus"

    readonly property var _restartTable: ({ minimum: 5000, maximum: 300000, healthyRun: 60000 })
    readonly property var _lookupTable: ({ minimum: 30000, maximum: 600000, healthyRun: Infinity })

    property double _monitorStartedAt: 0
    property int _monitorDelay: 0
    property int _lookupDelay: 0
    property bool _lookupFailureLogged: false
    // When PreparingForSleep was found true (ms): the monitor's own PrepareForSleep(true)
    // for that same sleep, should it still arrive, is not reported twice
    property double _sleepFoundAt: 0

    function start() {
        if (sessionId === "")
            logLine("warning", "no logind session (XDG_SESSION_ID is unset): logind's Lock and Unlock are not followed, sleep is");
        else
            _lookup.running = true;
        _startMonitor();
    }

    function _startMonitor() {
        _monitorStartedAt = Date.now();
        _monitor.running = true;
    }

    // ---- The session's object path ----

    Process {
        id: _lookup
        property string _output: ""
        command: [root._gdbus, "call", "--system", "--dest", "org.freedesktop.login1",
            "--object-path", "/org/freedesktop/login1",
            "--method", "org.freedesktop.login1.Manager.GetSession", root.sessionId]
        stdout: StdioCollector {
            onStreamFinished: _lookup._output = text
        }
        onRunningChanged: {
            if (running)
                return;
            const path = LockRules.parseSessionPath(_output);
            _output = "";
            if (path !== "") {
                if (root._lookupFailureLogged)
                    root.logLine("info", "logind session found after all: " + path);
                else
                    root.logLine("info", "following logind session " + path);
                root.sessionPath = path;
                root._lookupDelay = 0;
                return;
            }
            if (!root._lookupFailureLogged) {
                root._lookupFailureLogged = true;
                root.logLine("warning", "cannot find logind session " + root.sessionId
                    + ": logind's Lock and Unlock are not followed for now (asked again later)");
            }
            root._lookupDelay = LockIoRules.restartDelay(root._lookupDelay, 0, root._lookupTable);
            _lookupRetry.interval = root._lookupDelay;
            _lookupRetry.start();
        }
    }

    Timer {
        id: _lookupRetry
        repeat: false
        onTriggered: _lookup.running = true
    }

    // ---- The monitor ----

    Process {
        id: _monitor
        stdinEnabled: true
        command: ["sh", "-c",
            "exec 3<&0\n"
            + "\"$0\" monitor --system --dest org.freedesktop.login1 < /dev/null 3<&- &\n"
            + "monitor=$!\n"
            + "{ read -r _ <&3; kill \"$monitor\" 2> /dev/null; } &\n"
            + "watcher=$!\n"
            + "wait \"$monitor\"\n"
            + "status=$?\n"
            + "kill \"$watcher\" 2> /dev/null\n"
            + "exit \"$status\"", root._gdbus]

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                // gdbus monitor's own first lines: it asks for logind's owner after adding its
                // match, so either answer means it is listening from now on
                if (/^The name org\.freedesktop\.login1 (is owned by|does not have an owner)/.test(line)) {
                    _sleepCheck.running = true;
                    return;
                }
                const parsed = LockRules.parseLogind(line, root.sessionPath);
                if (parsed === null)
                    return;
                if (parsed.type === "resumed")
                    root._sleepFoundAt = 0;
                if (parsed.type === "prepareForSleep" && root._sleepFoundAt > 0
                        && Date.now() - root._sleepFoundAt < 10000) {
                    root._sleepFoundAt = 0;
                    root.logLine("info", "logind's PrepareForSleep arrived after all; already acted on (PreparingForSleep)");
                    return;
                }
                root.event(parsed);
            }
        }

        onRunningChanged: {
            if (running)
                return;
            const ran = Date.now() - root._monitorStartedAt;
            root._monitorDelay = LockIoRules.restartDelay(root._monitorDelay, ran, root._restartTable);
            root.logLine("warning", "the logind monitor ended after " + Math.round(ran / 1000)
                + " s: started again in " + Math.round(root._monitorDelay / 1000) + " s");
            _monitorRestart.interval = root._monitorDelay;
            _monitorRestart.start();
        }
    }

    Timer {
        id: _monitorRestart
        repeat: false
        onTriggered: root._startMonitor()
    }

    // ---- A sleep that began before the monitor listened ----
    // A PrepareForSleep sent while no monitor of this shell listened is lost: during a reload
    // (Quickshell builds the new generation with the event loop blocked — the old monitor's
    // lines are never read — then tears the old one down; the new generation's processes
    // start only after that), at a start, after a restart of the monitor. So once the monitor
    // listens, logind is asked whether it is preparing for sleep (its PreparingForSleep
    // property: read-only, no polkit). A sleep signalled from then on reaches the monitor.
    Process {
        id: _sleepCheck
        property string _output: ""
        command: [root._gdbus, "call", "--system", "--dest", "org.freedesktop.login1",
            "--object-path", "/org/freedesktop/login1", "--method", "org.freedesktop.DBus.Properties.Get",
            "org.freedesktop.login1.Manager", "PreparingForSleep"]
        stdout: StdioCollector {
            onStreamFinished: _sleepCheck._output = text
        }
        onRunningChanged: {
            if (running)
                return;
            const output = _output;
            _output = "";
            if (/^\(<\s*true\s*>,?\)/.test(output.trim())) {
                root._sleepFoundAt = Date.now();
                root.logLine("warning", "logind is preparing for sleep (PreparingForSleep is true) as the monitor starts listening");
                root.preparingForSleep();
            } else if (!/^\(<\s*false\s*>,?\)/.test(output.trim())) {
                root.logLine("info", "could not ask logind whether it is preparing for sleep: " + (output.trim().slice(0, 200) || "no answer"));
            }
        }
    }
}
