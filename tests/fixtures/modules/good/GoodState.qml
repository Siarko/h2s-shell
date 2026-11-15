pragma Singleton

import QtQuick
import Quickshell
import qs.api

// The fixture module's own singleton: one instance for all its files (its qmldir). It
// outlives the module's main, so — the module API's contract for turning a module off —
// what acts here follows `module.active`: its timer stops while the module is off.
Singleton {
    id: root

    // Its handle, found from its own file (a singleton gets no `module` property)
    readonly property var module: Api.moduleAt(Qt.resolvedUrl("."))

    // Mains alive now, and ever created
    property int mains: 0
    property int started: 0
    // Ticks of a timer that runs only while the module is active
    property int ticks: 0
    readonly property bool ticking: _ticker.running
    // Registrations alive (made by the main's objects: a stand-in for a VPN provider)
    property var registrations: []
    // The last main had its handle, active, by its Component.onCompleted
    property bool mainSawHandle: false
    // The bar's widget had its handle by its Component.onCompleted (the core injects it)
    property bool widgetSawHandle: false

    function greet(name) {
        return "hello, " + name;
    }

    function register(object) {
        registrations = registrations.concat([object]);
    }

    function unregister(object) {
        registrations = registrations.filter(entry => entry !== object);
    }

    property Timer _ticker: Timer {
        interval: 50
        repeat: true
        running: root.module?.active ?? false
        onTriggered: root.ticks += 1
    }
}
