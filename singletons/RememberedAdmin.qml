pragma Singleton

import Quickshell
import QtQuick
import qs.singletons.io

// The remembered administrator authorization: what is installed and what polkit keeps for
// the shell's process now, read by the shell's one RememberedAdminReader and decided by
// RememberRules. It forgets — session-wide, as polkit revokes — at lock (unless the rule is
// known not to be installed), on forget() ("Forget now"), when the setting
// `system.rememberAdminMinutes` is shorter than what polkit keeps, and at once when polkit
// keeps longer than its conf file says. The list is read after each run of the privileged
// queue, after unlock, and once a second while a view counts down (showCountdown /
// hideCountdown). Started with the shell (shell.qml calls start()), so that the lock's
// revoke is never missed; until then nothing is run, so that a suite reaching it through the
// module API (module.privileged.remembered) never reads or revokes the real polkit's. gdbus and readlink are looked for once on PATH, trusted matches only (as
// CommandTools finds timeout); nothing runs until they are found. In a test tree it asks the
// lock bed's stand-in gdbus (TestSeams.lockTools), or nothing at all: never the real bus.
Singleton {
    id: root

    readonly property var installed: _reader.installed
    readonly property string system: _reader.system
    // What the last reading read: the facts { user, timeout, program } and the texts { rule,
    // confs } a request to RememberInstall is built from; null before the first reading
    readonly property var facts: _reader.facts
    readonly property var files: _reader.files
    readonly property var kept: _reader.kept
    readonly property real keptUntilMs: _reader.keptUntilMs
    readonly property real revokeAtMs: _reader.revokeAtMs
    // What a privileged mark is told (RememberRules.remembered): frozen { kept, untilMs },
    // a new object only when it changes, turned back when what is kept runs out
    readonly property var remembered: _reader.remembered
    readonly property string forgetOutcome: _reader.forgetOutcome
    readonly property string forgetReason: _reader.forgetReason
    readonly property real forgetAtMs: _reader.forgetAtMs
    readonly property real lastObtainedMs: _reader.lastObtainedMs
    readonly property int minutes: Profiles.value("system.rememberAdminMinutes") ?? 5

    // In a test tree without the lock bed's tools, or before the tools are found: nothing is run
    readonly property bool _inert: (TestSeams.active && TestSeams.lockTools === "") || _gdbus === "" || _readlink === ""
    property string _gdbus: ""
    property string _readlink: ""

    function refresh() {
        if (_inert)
            return;
        _reader.refresh();
        _reader.readKept();
    }

    function forget() {
        if (!_inert)
            _reader.forget();
    }

    function showCountdown() {
        _reader.viewers += 1;
    }

    function hideCountdown() {
        _reader.viewers = Math.max(0, _reader.viewers - 1);
    }

    // Install, Remove and Undo as Settings asks for them, and what the last run left
    readonly property RememberActions actions: RememberActions {
        admin: root
        installer: RememberInstall {}
    }

    RememberedAdminReader {
        id: _reader
        locked: !root._inert && Profiles.screenLocked
        minutes: root.minutes
        pid: Quickshell.processId
        user: SystemFacts.facts.userName
        timeout: CommandTools.timeout
        gdbusCommand: [TestSeams.lockTools !== "" ? TestSeams.lockTools + "/gdbus" : root._gdbus]
        resolveCommand: [root._readlink, "-f", "--"]
    }

    // gdbus and readlink: the first trusted match of each on the shell's PATH (only root can
    // change it), as the probe's own tools come from the system's directories
    property CommandRunner _lookup: CommandRunner {}

    function _lookUp() {
        const lines = [];
        _lookup.start([ModuleRules.probeShell, "-c", ModuleRules.programProbeScript, "sh", "all", Quickshell.env("PATH") ?? "", "gdbus", "readlink"], {
            timeoutMs: 5000,
            keepOutput: false,
            environment: { PATH: ModuleRules.probeToolPath },
            onLine: (line, stream) => {
                if (stream === "stdout")
                    lines.push(line);
            },
            done: () => {
                const gdbus = ModuleRules.trustedPrograms(lines, "gdbus")[0] ?? "";
                const readlink = ModuleRules.trustedPrograms(lines, "readlink")[0] ?? "";
                if (gdbus === "" || readlink === "")
                    console.warn("[RememberedAdmin] no trusted " + (gdbus === "" ? "gdbus" : "readlink")
                                 + " on PATH: what is remembered is not read, and not forgotten at lock");
                root._readlink = readlink;
                root._gdbus = gdbus;
                root.refresh();
            }
        });
    }

    // A run of the queue ended: it may have obtained, used or installed something
    property int _runs: PrivilegedRuns.count
    on_RunsChanged: {
        if (_runs < _lastRuns)
            refresh();
        _lastRuns = _runs;
    }
    property int _lastRuns: 0

    // The user and the timeout are known a moment after the start
    readonly property string _factsKey: SystemFacts.facts.userName + "\n" + CommandTools.timeout
    on_FactsKeyChanged: Qt.callLater(root.refresh)

    // Once, by the shell at its start
    function start() {
        if (_started)
            return;
        _started = true;
        _lookUp();
    }
    property bool _started: false
}
