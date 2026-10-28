pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.singletons
import qs.singletons.network

Singleton {
    id: root

    // Throughput of the wifi device, measured independently of ethernet
    readonly property real rxSpeed: _wifiSpeed.rxSpeed
    readonly property real txSpeed: _wifiSpeed.txSpeed

    LinkSpeed {
        id: _wifiSpeed
        device: NetworkManager.wifiDevice
        active: NetworkManager.wifiConnected
    }

    property bool wifiEnabled: false
    property int wifiSignal: 0
    property var wifiNetworks: []
    property bool scanning: false
    property bool scanInProgress: false

    readonly property bool wifiConnected: wifiNetworks.some(n => n.inUse)
    property bool connecting: false
    property string connectingTo: ""
    property bool disconnecting: false
    property bool connectFailed: false
    property string failedSsid: ""

    Timer {
        id: connectTimeoutTimer
        interval: 30000
        repeat: false
        onTriggered: {
            root.connecting = false
            root.connectingTo = ""
        }
    }

    // -------------------------------------------------------------------------
    // WiFi radio polling (every 5s)
    // -------------------------------------------------------------------------
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root._pollRadio()
            root._pollSaved()
        }
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
        property bool _pendingRescan: false

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
                if (_pendingRescan) {
                    root._doScan(true)
                } else if (root.scanning) {
                    scanRepeatTimer.start()
                }
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
        if (wifiScanProcess.running) {
            wifiScanProcess._pendingRescan = forceRescan || wifiScanProcess._pendingRescan
            return
        }
        wifiScanProcess._pendingRescan = false
        wifiScanProcess._lines = []
        wifiScanProcess.command = [
            "nmcli", "-t", "-f", "SSID,SIGNAL,SECURITY,IN-USE,FREQ",
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
            if (parts.length < 5) continue
            var freq = parts[parts.length - 1].trim()
            var inUse = parts[parts.length - 2].trim() === "*"
            var security = parts[parts.length - 3].trim()
            var signal = parseInt(parts[parts.length - 4]) || 0
            var ssid = parts.slice(0, parts.length - 4).join(":")
            if (ssid === "") continue
            var freqNum = parseInt(freq) || 0
            var band = freqNum >= 3000 ? "5G" : (freqNum > 0 ? "2.4G" : "")
            networks.push({ ssid: ssid, signal: signal, security: security, inUse: inUse, band: band })
            if (inUse && signal > bestInUseSignal) {
                bestInUseSignal = signal
                root.wifiSignal = signal
            }
        }
        root.wifiNetworks = networks
        var anyInUse = networks.some(n => n.inUse)
        if (root.connectingTo !== "" && networks.some(n => n.inUse && n.ssid === root.connectingTo)) {
            root.connecting = false
            root.connectingTo = ""
            connectTimeoutTimer.stop()
        }
        if (root.disconnecting && !anyInUse) {
            root.disconnecting = false
        }
    }

    // -------------------------------------------------------------------------
    // Saved connection profiles
    // -------------------------------------------------------------------------
    property var savedSsids: []

    Process {
        id: savedProcess
        command: ["nmcli", "-t", "-f", "name,type", "connection", "show"]
        property var _lines: []

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => { if (line.trim() !== "") savedProcess._lines.push(line) }
        }

        onRunningChanged: {
            if (!running) {
                root._processSaved(_lines)
                _lines = []
            }
        }
    }

    function _pollSaved() {
        if (!savedProcess.running) {
            savedProcess._lines = []
            savedProcess.running = true
        }
    }

    function _processSaved(lines) {
        var ssids = []
        for (var i = 0; i < lines.length; i++) {
            var parts = lines[i].split(":")
            if (parts.length < 2) continue
            var type = parts[parts.length - 1].trim()
            var name = parts.slice(0, parts.length - 1).join(":")
            if (type === "802-11-wireless")
                ssids.push(name)
        }
        root.savedSsids = ssids
    }

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------
    function toggleWifi() {
        if (actionProcess.running) return
        actionProcess.command = ["nmcli", "radio", "wifi", root.wifiEnabled ? "off" : "on"]
        actionProcess.running = true
    }

    function forgetNetwork(ssid) {
        if (actionProcess.running) return
        actionProcess.command = ["nmcli", "connection", "delete", ssid]
        actionProcess.running = true
    }

    function disconnect() {
        var device = NetworkManager.wifiDevice
        if (actionProcess.running || device === "") return
        root.disconnecting = true
        actionProcess.command = ["nmcli", "device", "disconnect", device]
        actionProcess.running = true
    }

    function connectToWifi(ssid, password) {
        if (actionProcess.running) return
        root.connecting = true
        root.connectingTo = ssid
        root.connectFailed = false
        root.failedSsid = ""
        connectTimeoutTimer.restart()
        var cmd = ["nmcli", "device", "wifi", "connect", ssid]
        if (password && password !== "") {
            cmd.push("password")
            cmd.push(password)
        }
        actionProcess.command = cmd
        actionProcess.running = true
    }

    function connectToHiddenWifi(ssid, password) {
        if (actionProcess.running) return
        root.connecting = true
        root.connectingTo = ssid
        root.connectFailed = false
        root.failedSsid = ""
        connectTimeoutTimer.restart()
        var cmd = ["nmcli", "device", "wifi", "connect", ssid, "hidden", "yes"]
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

    function cancelConnect() {
        if (!root.connecting) return
        actionProcess._cancelling = true
        actionProcess.running = false
        root.connecting = false
        root.connectingTo = ""
        connectTimeoutTimer.stop()
        cancelProcess.command = ["nmcli", "device", "disconnect", NetworkManager.wifiDevice]
        cancelProcess.running = true
    }

    Process {
        id: cancelProcess
        onRunningChanged: {
            if (!running) {
                root._pollRadio()
                root._doScan(false)
                NetworkManager.refresh()
            }
        }
    }

    Process {
        id: actionProcess
        property string _output: ""
        property bool _cancelling: false

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                if (line.trim() !== "")
                    actionProcess._output += line + "\n"
            }
        }

        onRunningChanged: {
            if (!running) {
                if (!_cancelling) {
                    if (root.connecting && actionProcess._output.toLowerCase().includes("error")) {
                        root.connectFailed = true
                        root.failedSsid = root.connectingTo
                        root.connecting = false
                        root.connectingTo = ""
                        connectTimeoutTimer.stop()
                    }
                    root._pollRadio()
                    root._doScan(false)
                    postActionTimer.restart()
                }
                _cancelling = false
                actionProcess._output = ""
            }
        }
    }

    Timer {
        id: postActionTimer
        interval: 600
        repeat: false
        onTriggered: {
            root._pollSaved()
            NetworkManager.refresh()
        }
    }
}
