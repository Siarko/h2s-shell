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
// hideCountdown). Started with the shell (shell.qml), so that the lock's revoke is never
// missed. In a test tree it asks the lock bed's stand-in gdbus (TestSeams.lockTools), or
// nothing at all: never the real bus.
Singleton {
    id: root

    readonly property var installed: _reader.installed
    readonly property string system: _reader.system
    readonly property var kept: _reader.kept
    readonly property real keptUntilMs: _reader.keptUntilMs
    readonly property real revokeAtMs: _reader.revokeAtMs
    readonly property string forgetOutcome: _reader.forgetOutcome
    readonly property string forgetReason: _reader.forgetReason
    readonly property real forgetAtMs: _reader.forgetAtMs
    readonly property int minutes: Profiles.value("system.rememberAdminMinutes") ?? 5

    // In a test tree without the lock bed's tools: nothing is run
    readonly property bool _inert: TestSeams.active && TestSeams.lockTools === ""

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

    RememberedAdminReader {
        id: _reader
        locked: !root._inert && Profiles.screenLocked
        minutes: root.minutes
        pid: Quickshell.processId
        user: SystemFacts.facts.userName
        timeout: CommandTools.timeout
        gdbusCommand: [TestSeams.lockTools !== "" ? TestSeams.lockTools + "/gdbus" : "gdbus"]
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

    Component.onCompleted: refresh()
}
