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

    // The card serves a hotspot (NetworkProfiles.activeHotspot): it joins no network, and
    // its list of networks is the one from before — a rescan does nothing in that mode
    readonly property var hotspot: NetworkProfiles.activeHotspot
    // Joined to a network — not serving a hotspot, whose own SSID the list marks in use
    readonly property bool wifiConnected: hotspot === null && wifiNetworks.some(network => network.inUse)
    // The Wi-Fi in one word, for what shows it (the popup, the bar): "off", "hotspot"
    // (serving one), "connected" (joined to a network) or "disconnected". The device's own
    // state (NetworkManager.wifiConnected) is "connected" in both of the middle two.
    readonly property string mode: !wifiEnabled ? "off" : hotspot !== null ? "hotspot" : wifiConnected ? "connected" : "disconnected"

    // Turning a hotspot on takes the Wi-Fi off the network it is on; without a cable or a
    // modem up, the devices that join get no internet — so turning one on asks this first
    // ("" when nothing would be lost)
    readonly property string hotspotQuestion: wifiConnected && !NetworkManager.otherLinkConnected
        ? "Leaves " + (wifiNetworks.find(network => network.inUse)?.ssid ?? "the network") + ": no internet to share. Turn on?" : ""
    property bool connecting: false
    property string connectingTo: ""
    property bool disconnecting: false
    property bool connectFailed: false
    property string failedSsid: ""
    // Why it failed: Nmcli.errorKind ("password", "auth", "notFound", "missing", "other")
    // and nmcli's own words
    property string failedKind: ""
    property string failedMessage: ""

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
        if (root.hotspot !== null)
            forceRescan = false
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
        var anyInUse = networks.some(network => network.inUse)
        if (root.connectingTo !== "" && networks.some(network => network.inUse && network.ssid === root.connectingTo)) {
            root.connecting = false
            root.connectingTo = ""
            connectTimeoutTimer.stop()
        }
        if (root.disconnecting && !anyInUse) {
            root.disconnecting = false
        }
    }

    // -------------------------------------------------------------------------
    // Saved connection profiles: by SSID, from NetworkProfiles (a profile's name may
    // differ from its network's, so names are never matched)
    // -------------------------------------------------------------------------
    readonly property var savedSsids: NetworkProfiles.savedSsids

    function _pollSaved() {
        NetworkProfiles.refresh()
    }

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------
    function toggleWifi() {
        if (actionProcess.running) return
        actionProcess.what = root.wifiEnabled ? "Turning Wi-Fi off" : "Turning Wi-Fi on"
        actionProcess.command = ["nmcli", "radio", "wifi", root.wifiEnabled ? "off" : "on"]
        actionProcess.running = true
    }

    // Every profile saved for the network, by UUID
    function forgetNetwork(ssid) {
        if (actionProcess.running) return
        const profiles = NetworkProfiles.profilesForSsid(ssid)
        if (profiles.length === 0) return
        const command = ["nmcli", "connection", "delete"]
        for (const profile of profiles)
            command.push("uuid", profile.uuid)
        actionProcess.what = "Forgetting " + ssid
        actionProcess.command = command
        actionProcess.running = true
    }

    function disconnect() {
        var device = NetworkManager.wifiDevice
        if (actionProcess.running || device === "") return
        root.disconnecting = true
        actionProcess.what = "Disconnecting Wi-Fi"
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
        root.failedKind = ""
        root.failedMessage = ""
        connectTimeoutTimer.restart()
        const command = ["nmcli", "device", "wifi", "connect", ssid]
        if (hidden)
            command.push("hidden", "yes")
        if (password && password !== "")
            command.push("password", password)
        actionProcess.command = command
        actionProcess.running = true
    }

    // Scanning while something shows the networks in range: the popup, the Wi-Fi settings
    // page. Counted, so one closing does not stop the other's list.
    property int _scanHolders: 0

    function holdScan() {
        _scanHolders++
        startScan()
    }

    function releaseScan() {
        _scanHolders = Math.max(0, _scanHolders - 1)
        if (_scanHolders === 0)
            stopScan()
    }

    // The popup's Scan / Stop button: resumes or pauses the scan while held
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

    // nmcli writes its errors to stderr ("Error: … Secrets were required…") and exits with
    // a code other than 0: both are read. Reading stdout for "error" never matched, so a
    // wrong password waited out the 30 s timeout.
    Process {
        id: actionProcess
        property string _errors: ""
        property bool _cancelling: false
        // What the action was, for a message when one other than connecting fails
        property string what: ""

        stderr: SplitParser {
            splitMarker: ""
            onRead: data => actionProcess._errors += data
        }

        onExited: exitCode => {
            if (!_cancelling) {
                const failed = exitCode !== 0
                if (root.connecting && failed) {
                    root.connectFailed = true
                    root.failedSsid = root.connectingTo
                    root.failedKind = Nmcli.errorKind(actionProcess._errors)
                    root.failedMessage = Nmcli.errorMessage(actionProcess._errors)
                    root.connecting = false
                    root.connectingTo = ""
                    connectTimeoutTimer.stop()
                } else if (failed) {
                    const action = actionProcess.what !== "" ? actionProcess.what : "A Wi-Fi action"
                    if (Nmcli.errorKind(actionProcess._errors) === "auth")
                        Authentication.reportDenied(action)
                    else
                        Notifier.send(action + " failed", { body: Nmcli.errorMessage(actionProcess._errors) })
                }
                root._pollRadio()
                root._doScan(false)
                postActionTimer.restart()
            }
            _cancelling = false
            actionProcess._errors = ""
            actionProcess.what = ""
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
