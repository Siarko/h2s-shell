pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property string activeDevice: ""
    property string activeDeviceType: "none"  // "wifi" | "ethernet" | "none"
    property string activeConnection: ""
    property bool isConnected: false
    property bool wifiAvailable: false

    // -------------------------------------------------------------------------
    // Status polling (every 5s) — device/type/state/connection
    // -------------------------------------------------------------------------
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: statusProcess
        command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"]
        property var _lines: []

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                if (line.trim() !== "")
                    statusProcess._lines.push(line)
            }
        }

        onRunningChanged: {
            if (!running) {
                root._processStatus(_lines)
                _lines = []
            }
        }
    }

    function _processStatus(lines) {
        var found = false
        var hasWifi = false
        for (var i = 0; i < lines.length; i++) {
            var parts = lines[i].trim().split(":")
            if (parts.length < 3) continue
            var device = parts[0].trim()
            var type = parts[1].trim()
            var state = parts[2].trim()
            var connection = parts.slice(3).join(":")
            if (type === "wifi")
                hasWifi = true
            if (state === "connected" && !found) {
                root.activeDevice = device
                root.activeDeviceType = (type === "ethernet") ? "ethernet" : "wifi"
                root.activeConnection = connection
                root.isConnected = true
                found = true
            }
        }
        root.wifiAvailable = hasWifi
        if (!found) {
            root.activeDevice = ""
            root.activeDeviceType = "none"
            root.activeConnection = ""
            root.isConnected = false
        }
    }

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------
    function refresh() {
        if (!statusProcess.running) {
            statusProcess._lines = []
            statusProcess.running = true
        }
    }

    function formatSpeed(bytesPerSec) {
        if (bytesPerSec >= 1048576)
            return (bytesPerSec / 1048576).toFixed(1) + " MB/s"
        if (bytesPerSec >= 1024)
            return (bytesPerSec / 1024).toFixed(0) + " KB/s"
        return bytesPerSec.toFixed(0) + " B/s"
    }
}
