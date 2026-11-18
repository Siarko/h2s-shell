pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The test tree's TestSeams: copied over singletons/TestSeams.qml (whose properties are
// constants) when a test tree is assembled — the lock bed's copy of the checkout
// (tests/lock/run.sh). Only such a tree reads
// the test seams: the environment variables by which the tests change the shell's timings,
// tools, directories and stand-ins. TestSeamRules (copied beside it) lists them, with what
// each is for, and decides what each says. Lockscreen, CapsLockLed, Modules and VpnManager
// read them here, by the same property names as the production file's — TestSeamsShapeTest
// checks the two files agree. Read once, at the first use; when any is in force, one line
// in the log names them (`[TestSeams] test bed: …`), and `qs ipc call modules list` and
// the lock screen's `state` carry the list. And the `locktest` IPC lives here, below.
//
// Used by the lock screen: it imports nothing of the module system, and nothing that
// would wait.
Singleton {
    id: root

    readonly property var _read: {
        const environment = {};
        for (const name of TestSeamRules.names)
            environment[name] = Quickshell.env(name) ?? "";
        return TestSeamRules.read(environment);
    }

    readonly property string lockTools: _read.lockTools
    readonly property string systemPamDirectory: _read.systemPamDirectory
    readonly property string lockSystem: _read.lockSystem
    readonly property string ledsDirectory: _read.ledsDirectory
    readonly property var timings: _read.timings
    readonly property string timingsProblem: _read.timingsProblem
    readonly property bool reloadIpc: _read.reloadIpc
    readonly property int moduleGuardMs: _read.moduleGuardMs
    readonly property string moduleCheckPath: _read.moduleCheckPath
    readonly property int moduleCheckMs: _read.moduleCheckMs
    readonly property bool fakeVpnProvider: _read.fakeVpnProvider
    // Module test mode (ModuleHost.testMode): on in every test tree, whatever the
    // environment holds — it is the tree, not a variable, that makes a run a test
    readonly property bool moduleTestMode: true
    // The names of the seams in force, and whether there is any
    readonly property var inForce: _read.inForce
    readonly property bool active: inForce.length > 0

    Component.onCompleted: {
        if (active)
            console.warn("[TestSeams] test bed: " + inForce.join(", "));
        if (_read.ignored.length > 0)
            console.warn("[TestSeams] set, but not used (a value the shell cannot use): " + _read.ignored.join(", "));
    }

    // A reload while locked, for the lock bed (tests/lock/tests/reload-*.sh): nothing in the
    // shell calls Quickshell.reload(), and file changes do not reload while locked, so the
    // test asks for one here. Only with H2S_LOCK_TEST_RELOAD=1 (stack_start --reload-seam).
    // Built when the lock screen first reads a seam, which is at its start.
    IpcHandler {
        target: "locktest"
        enabled: root.reloadIpc

        function reload(hard: bool): string {
            Qt.callLater(() => Quickshell.reload(hard));
            return hard ? "hard reload" : "reload";
        }
    }
}
