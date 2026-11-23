pragma Singleton

import Quickshell
import QtQuick

// The test seams, as the shell has them: none. Every property is a constant — what the
// test tree's reader says when no seam is set — so the lock screen's tools, PAM directory
// and LEDs, its timings, the module host's checks and the VPN providers are the real ones
// whatever the environment holds. Lockscreen, CapsLockLed, Modules and VpnManager read
// them here, Distribution its system; an empty directory means their own default (/etc/pam.d, /sys/class/leds,
// gdbus from PATH).
//
// A test tree — the lock bed's copy of the checkout (tests/lock/run.sh) — has
// tests/lock/seams/TestSeams.qml in this file's place, which reads the seams from the
// environment (tests/lock/README.md, "The test tree"). The two files have the same
// properties; TestSeamsShapeTest checks that, and that no file of the shell reads a seam
// itself. A new seam is added to both.
Singleton {
    readonly property string lockTools: ""
    readonly property string systemPamDirectory: ""
    readonly property string ledsDirectory: ""
    readonly property var timings: Object.freeze({})
    readonly property string timingsProblem: ""
    readonly property bool reloadIpc: false
    readonly property int moduleGuardMs: 0
    readonly property string moduleCheckPath: ""
    readonly property int moduleCheckMs: 0
    readonly property bool moduleNotify: false
    readonly property bool fakeVpnProvider: false
    // The distribution the shell takes itself to be on (Distribution): "" — it detects it
    readonly property string distribution: ""
    // Module test mode (ModuleHost.testMode): off
    readonly property bool moduleTestMode: false
    // The names of the seams in force, and whether there is any
    readonly property var inForce: Object.freeze([])
    readonly property bool active: false
}
