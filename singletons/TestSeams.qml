pragma Singleton

import Quickshell
import QtQuick

// The one reader of the test seams: the environment variables by which the test beds
// (tests/lock, tests/headless.sh's runs) change the shell's timings, tools, directories and
// stand-ins — TestSeamRules lists them, with what each is for, and decides what each says.
// Nothing else in the shell reads one: Lockscreen, CapsLockLed, Modules and VpnManager
// read them here. Read once, at the first use; when any is in force, one line in the log
// names them (`[TestSeams] test bed: …`), and `qs ipc call modules list` and the lock
// screen's `state` carry the list.
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
    // The names of the seams in force, and whether there is any
    readonly property var inForce: _read.inForce
    readonly property bool active: inForce.length > 0

    Component.onCompleted: {
        if (active)
            console.warn("[TestSeams] test bed: " + inForce.join(", "));
        if (_read.ignored.length > 0)
            console.warn("[TestSeams] set, but not used (a value the shell cannot use): " + _read.ignored.join(", "));
    }
}
