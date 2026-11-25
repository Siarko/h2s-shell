pragma Singleton

import Quickshell
import QtQuick
import qs.singletons.io as Io

// What api/Api.qml works with and keeps out of a module's reach: nothing of it is a member of
// Api, so no module writes it through the singleton every module is handed. Its clock and its
// link opener; and module test mode's seams, set by tests/ModuleTestKit.qml and read by Api
// only while the host is in test mode (outside it they change nothing).
Singleton {
    id: root

    readonly property SystemClock minuteClock: SystemClock {
        precision: SystemClock.Minutes
    }
    readonly property Io.CommandRunner opener: Io.CommandRunner {}
    // Api.notify refused a progress notification once (it is logged once)
    property bool progressRefusedLogged: false

    // ---- Module test mode's seams (tests/ModuleTestKit.qml) ----
    // setNow: the clock behind Api.minuteNow (0: the real clock)
    property real testNow: 0
    // setRemembered: module.privileged.remembered
    property var testRemembered: RememberRules.remembered(null, 5, 0)
    // setSystem: the fields given (null: the made-up defaults)
    property var testSystemGiven: null
    readonly property var testSystemFacts: SystemFactsRules.testFacts(testSystemGiven, SystemFactsRules.testDefaults(Modules.host.testHome)).facts
    // setDistribution: the distribution named (null: not answered)
    property var testDistributionName: null
    // setNetworks: the facts given (null: the defaults — read, none)
    property var testNetworkGiven: null
    readonly property var testNetworkFacts: ModuleRules.testNetworkFacts(testNetworkGiven).facts
    // What Api.openUrl was asked in test mode, oldest first: frozen { url, allowFile }
    property var opened: []
}
