pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.singletons

Singleton {
    id: root

    property var vpnConnections: []
    property string activeVpn: ""

    // -------------------------------------------------------------------------
    // VPN connection polling (every 5s)
    // -------------------------------------------------------------------------
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root._poll()
    }

    function _poll() {
        if (!vpnProcess.running) {
            vpnProcess._lines = []
            vpnProcess.running = true
        }
    }

    Process {
        id: vpnProcess
        command: ["nmcli", "-t", "-f", "name,type,state", "connection", "show"]
        property var _lines: []

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => { if (line.trim() !== "") vpnProcess._lines.push(line) }
        }

        onRunningChanged: {
            if (!running) {
                root._processVpn(_lines)
                _lines = []
            }
        }
    }

    function _processVpn(lines) {
        var connections = []
        var active = ""
        for (var i = 0; i < lines.length; i++) {
            var parts = lines[i].split(":")
            if (parts.length < 2) continue
            var state = parts[parts.length - 1].trim()
            var type  = parts[parts.length - 2].trim()
            var name  = parts.slice(0, parts.length - 2).join(":")
            var isVpn = type === "wireguard" || type === "vpn" || type === "openconnect"
            if (!isVpn) continue
            connections.push({ name: name, type: type })
            if (state === "activated") active = name
        }
        root.vpnConnections = connections
        root.activeVpn = active
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
