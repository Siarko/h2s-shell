pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // Connection state
    property string activeDevice: ""
    property string activeDeviceType: "none"  // "wifi" | "ethernet" | "none"
    property string activeConnection: ""
    property bool isConnected: false
    property bool wifiEnabled: false

    // WiFi-specific
    property bool wifiAvailable: false  // true when any wifi adapter is present
    property int wifiSignal: 0
    property var wifiNetworks: []
    property bool scanning: false       // true while continuous scan loop is running
    property bool scanInProgress: false // true while the nmcli process itself is running

    // Throughput (bytes/sec, updated every 2s)
    property real rxSpeed: 0
    property real txSpeed: 0

    // Internal speed tracking
    property real _rxPrev: -1
    property real _txPrev: -1
    property real _rxCurrent: 0
    property real _txCurrent: 0
    property bool _rxReady: false
    property bool _txReady: false

    // Reset speed state when the active interface changes
    onActiveDeviceChanged: {
        _rxPrev = -1
        _txPrev = -1
        rxSpeed = 0
        txSpeed = 0
    }

    // -------------------------------------------------------------------------
    // Status polling (every 5 s) — device/type/state/connection
    // -------------------------------------------------------------------------
    Timer {
        id: statusTimer
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!statusProcess.running) {
                statusProcess._lines = []
                statusProcess.running = true
            }
        }
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
                if (!wifiRadioProcess.running)
                    wifiRadioProcess.running = true
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
    // WiFi radio state
    // -------------------------------------------------------------------------
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

    // Trigger a passive list (cached results) when WiFi first becomes enabled
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
    // WiFi network scan — active (--rescan yes) or passive (--rescan no)
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
                // If continuous scanning is active, schedule the next round
                if (root.scanning)
                    scanRepeatTimer.start()
            }
        }
    }

    // Delay between consecutive active scans (~5 s idle between each --rescan yes)
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
            // Field order: SSID,SIGNAL,SECURITY,IN-USE
            // Parse from the right so SSIDs containing colons are handled correctly
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
    // Throughput polling (every 2 s)
    // -------------------------------------------------------------------------
    Timer {
        id: speedTimer
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (root.activeDevice !== "") {
                root._rxReady = false
                root._txReady = false
                rxProcess.command = ["cat", "/sys/class/net/" + root.activeDevice + "/statistics/rx_bytes"]
                txProcess.command = ["cat", "/sys/class/net/" + root.activeDevice + "/statistics/tx_bytes"]
                if (!rxProcess.running) rxProcess.running = true
                if (!txProcess.running) txProcess.running = true
            } else {
                root.rxSpeed = 0
                root.txSpeed = 0
            }
        }
    }

    Process {
        id: rxProcess
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                var num = parseFloat(line.trim())
                if (!isNaN(num)) {
                    root._rxCurrent = num
                    root._rxReady = true
                    root._checkSpeed()
                }
            }
        }
    }

    Process {
        id: txProcess
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                var num = parseFloat(line.trim())
                if (!isNaN(num)) {
                    root._txCurrent = num
                    root._txReady = true
                    root._checkSpeed()
                }
            }
        }
    }

    function _checkSpeed() {
        if (!_rxReady || !_txReady) return
        if (_rxPrev < 0) {
            // First read — store baseline, report zero
            _rxPrev = _rxCurrent
            _txPrev = _txCurrent
        } else {
            rxSpeed = Math.max(0, (_rxCurrent - _rxPrev) / 2.0)
            txSpeed = Math.max(0, (_txCurrent - _txPrev) / 2.0)
            _rxPrev = _rxCurrent
            _txPrev = _txCurrent
        }
    }

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------
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

    function disconnect() {
        if (actionProcess.running || root.activeDevice === "") return
        actionProcess.command = ["nmcli", "device", "disconnect", root.activeDevice]
        actionProcess.running = true
    }

    function toggleWifi() {
        if (actionProcess.running) return
        actionProcess.command = ["nmcli", "radio", "wifi", root.wifiEnabled ? "off" : "on"]
        actionProcess.running = true
    }

    function startScan() {
        scanning = true
        _doScan(true)
    }

    function stopScan() {
        scanning = false
        scanRepeatTimer.stop()
        // Let any in-flight process finish; results are still useful
    }

    function formatSpeed(bytesPerSec) {
        if (bytesPerSec >= 1048576)
            return (bytesPerSec / 1048576).toFixed(1) + " MB/s"
        if (bytesPerSec >= 1024)
            return (bytesPerSec / 1024).toFixed(0) + " KB/s"
        return bytesPerSec.toFixed(0) + " B/s"
    }

    // Single process for all mutating actions; refreshes state after completion
    Process {
        id: actionProcess
        onRunningChanged: {
            if (!running)
                postActionTimer.restart()
        }
    }

    // Small delay so the system state settles after an nmcli command
    Timer {
        id: postActionTimer
        interval: 600
        repeat: false
        onTriggered: {
            // Reset speed baseline after a network change
            root._rxPrev = -1
            root._txPrev = -1
            // Re-fetch status and WiFi radio state
            if (!statusProcess.running) {
                statusProcess._lines = []
                statusProcess.running = true
            }
            if (!wifiRadioProcess.running)
                wifiRadioProcess.running = true
        }
    }
}
