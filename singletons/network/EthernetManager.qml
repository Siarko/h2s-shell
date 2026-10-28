pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.singletons
import qs.singletons.network

Singleton {
    id: root

    // Read from the per-device state: with ethernet and wifi both up, the old
    // activeDeviceType check reported ethernet as down whenever nmcli happened
    // to list the wifi device first.
    readonly property bool ethernetConnected: NetworkManager.ethernetConnected

    // Throughput of the ethernet device itself, not of whichever link happens
    // to be the shell's "active" one.
    readonly property real rxSpeed: _ethernetSpeed.rxSpeed
    readonly property real txSpeed: _ethernetSpeed.txSpeed
    readonly property var rxHistory: _ethernetSpeed.rxHistory
    readonly property var txHistory: _ethernetSpeed.txHistory

    LinkSpeed {
        id: _ethernetSpeed
        device: NetworkManager.ethernetDevice
        active: root.ethernetConnected
    }

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------
    function connect() {
        var device = NetworkManager.ethernetDevice
        if (actionProcess.running || device === "") return
        actionProcess.command = ["nmcli", "device", "connect", device]
        actionProcess.running = true
    }

    function disconnect() {
        var device = NetworkManager.ethernetDevice
        if (actionProcess.running || device === "") return
        actionProcess.command = ["nmcli", "device", "disconnect", device]
        actionProcess.running = true
    }

    Process {
        id: actionProcess
        onRunningChanged: {
            if (!running)
                postActionTimer.restart()
        }
    }

    Timer {
        id: postActionTimer
        interval: 600
        repeat: false
        onTriggered: NetworkManager.refresh()
    }
}
