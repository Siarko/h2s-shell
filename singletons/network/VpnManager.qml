pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.singletons
import qs.singletons.io
import qs.singletons.network

Singleton {
    id: root

    property var vpnConnections: []
    property string activeVpn: ""
    // Type of the active tunnel ("wireguard" | "vpn" | "openconnect"), so the bar
    // and the panel pick their glyph from the same place
    property string activeVpnType: ""

    // -------------------------------------------------------------------------
    // VPN connection state
    // -------------------------------------------------------------------------
    // Re-queried when NetworkEvents reports a change; the slow timer is only the
    // fallback for changes nmcli monitor does not print
    Connections {
        target: NetworkEvents
        function onChanged() { root._poll() }
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root._poll()
    }

    // Asked while already running, it runs once more after (CommandQuery)
    function _poll() {
        vpnQuery.request()
    }

    CommandQuery {
        id: vpnQuery
        command: ["nmcli", "-t", "-f", "name,type,state", "connection", "show"]
        onDone: lines => root._processVpn(lines)
    }

    function _processVpn(lines) {
        var connections = []
        var active = ""
        var activeType = ""
        for (var i = 0; i < lines.length; i++) {
            // NAME,TYPE,STATE
            var parts = Nmcli.splitTerse(lines[i])
            if (parts.length < 3) continue
            var name  = parts[0]
            var type  = parts[1].trim()
            var state = parts[2].trim()
            var isVpn = type === "wireguard" || type === "vpn" || type === "openconnect"
            if (!isVpn) continue
            connections.push({ name: name, type: type })
            if (state === "activated") {
                active = name
                activeType = type
            }
        }
        root.vpnConnections = connections
        root.activeVpn = active
        root.activeVpnType = activeType
    }

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------
    function connectVpn(name) {
        if (actionProcess.running) return
        actionProcess.command = ["nmcli", "connection", "up", name]
        actionProcess.running = true
    }

    function disconnectVpn() {
        if (actionProcess.running || activeVpn === "") return
        actionProcess.command = ["nmcli", "connection", "down", activeVpn]
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
        onTriggered: {
            root._poll()
            NetworkManager.refresh()
        }
    }
}
