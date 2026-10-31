pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.singletons
import qs.singletons.io
import qs.singletons.network

// Wi-Fi through nmcli: the radio, the networks in range, the saved profiles, and
// connecting, disconnecting and forgetting. The device and its state are NetworkManager's.
Singleton {
    id: root

    // Throughput of the wifi device, measured independently of ethernet
    readonly property real rxSpeed: _wifiSpeed.rxSpeed
    readonly property real txSpeed: _wifiSpeed.txSpeed
    readonly property var rxHistory: _wifiSpeed.rxHistory
    readonly property var txHistory: _wifiSpeed.txHistory

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
    // WiFi radio and saved profiles
    // -------------------------------------------------------------------------
    // Re-queried when NetworkEvents reports a change; the slow timer is only the
    // fallback for changes nmcli monitor does not print
    Connections {
        target: NetworkEvents
        function onChanged() {
            root._pollRadio()
            root._pollSaved()
            // Which network is in use comes from the network list, so it has to follow
            // the change too — after the radio comes on, the card connects seconds after
            // the list was first read. NM's cached list, no rescan: it is instant.
            if (root.wifiEnabled)
                root._doScan(false)
        }
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root._pollRadio()
            root._pollSaved()
        }
    }

    // Asked while already running, a query runs once more after (CommandQuery)
    function _pollRadio() {
        radioQuery.request()
    }

    CommandQuery {
        id: radioQuery
        command: ["nmcli", "radio", "wifi"]
        onDone: lines => root.wifiEnabled = lines.length > 0 && lines[lines.length - 1].trim() === "enabled"
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
        const result = Nmcli.wifiNetworks(lines)
        const networks = result.networks
        if (result.signalInUse >= 0)
            root.wifiSignal = result.signalInUse
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

    CommandQuery {
        id: savedQuery
        command: ["nmcli", "-t", "-f", "name,type", "connection", "show"]
        onDone: lines => root._processSaved(lines)
    }

    function _pollSaved() {
        savedQuery.request()
    }

    function _processSaved(lines) {
        root.savedSsids = Nmcli.savedWifi(lines)
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
        _connect(ssid, password, false)
    }

    function connectToHiddenWifi(ssid, password) {
        _connect(ssid, password, true)
    }

    // A network not broadcasting its name has to be asked for by it ("hidden yes")
    function _connect(ssid, password, hidden) {
        if (actionProcess.running) return
        root.connecting = true
        root.connectingTo = ssid
        root.connectFailed = false
        root.failedSsid = ""
        connectTimeoutTimer.restart()
        const command = ["nmcli", "device", "wifi", "connect", ssid]
        if (hidden)
            command.push("hidden", "yes")
        if (password && password !== "")
            command.push("password", password)
        actionProcess.command = command
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
