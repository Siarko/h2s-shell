pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.singletons

Singleton {
    id: root

    property bool wifiEnabled: false
    property int wifiSignal: 0
    property var wifiNetworks: []
    property bool scanning: false
    property bool scanInProgress: false

    // -------------------------------------------------------------------------
    // WiFi radio polling (every 5s)
    // -------------------------------------------------------------------------
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root._pollRadio()
    }

    function _pollRadio() {
        if (!wifiRadioProcess.running) {
            wifiRadioProcess._output = ""
            wifiRadioProcess.running = true
        }
    }

    Process {
        id: wifiRadioProcess
        command: ["nmcli", "radio", "wifi"]
        property string _output: ""

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                if (line.trim() !== "")
                    wifiRadioProcess._output = line.trim()
            }
        }

        onRunningChanged: {
            if (!running) {
                root.wifiEnabled = (_output === "enabled")
                _output = ""
            }
        }
    }

    onWifiEnabledChanged: {
        if (wifiEnabled) {
            _doScan(false)
        } else {
            wifiNetworks = []
            wifiSignal = 0
            scanning = false
            scanRepeatTimer.stop()
        }
    }

    // -------------------------------------------------------------------------
    // WiFi network scan
    // -------------------------------------------------------------------------
    Process {
        id: wifiScanProcess
        property var _lines: []

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                if (line.trim() !== "")
                    wifiScanProcess._lines.push(line)
            }
        }

        onRunningChanged: {
            root.scanInProgress = running
            if (!running) {
                root._processWifiList(_lines)
                _lines = []
                if (root.scanning)
                    scanRepeatTimer.start()
            }
        }
    }

    Timer {
        id: scanRepeatTimer
        interval: 5000
        repeat: false
        onTriggered: {
            if (root.scanning)
                root._doScan(true)
        }
    }

    function _doScan(forceRescan) {
        if (wifiScanProcess.running) return
        wifiScanProcess._lines = []
        wifiScanProcess.command = [
            "nmcli", "-t", "-f", "SSID,SIGNAL,SECURITY,IN-USE",
            "device", "wifi", "list",
            "--rescan", forceRescan ? "yes" : "no"
        ]
        wifiScanProcess.running = true
    }

    function _processWifiList(lines) {
        var networks = []
        var bestInUseSignal = -1
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (line === "") continue
            var parts = line.split(":")
            if (parts.length < 4) continue
            var inUse = parts[parts.length - 1].trim() === "*"
            var security = parts[parts.length - 2].trim()
            var signal = parseInt(parts[parts.length - 3]) || 0
            var ssid = parts.slice(0, parts.length - 3).join(":")
            if (ssid === "") continue
            networks.push({ ssid: ssid, signal: signal, security: security, inUse: inUse })
            if (inUse && signal > bestInUseSignal) {
                bestInUseSignal = signal
                root.wifiSignal = signal
            }
        }
        root.wifiNetworks = networks
    }

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------
    function toggleWifi() {
        if (actionProcess.running) return
        actionProcess.command = ["nmcli", "radio", "wifi", root.wifiEnabled ? "off" : "on"]
        actionProcess.running = true
    }

    function connectToWifi(ssid, password) {
        if (actionProcess.running) return
        var cmd = ["nmcli", "device", "wifi", "connect", ssid]
        if (password && password !== "") {
            cmd.push("password")
            cmd.push(password)
        }
        actionProcess.command = cmd
        actionProcess.running = true
    }

    function startScan() {
        scanning = true
        _doScan(true)
    }

    function stopScan() {
        scanning = false
        scanRepeatTimer.stop()
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
            root._pollRadio()
            NetworkManager.refresh()
        }
    }
}
