pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // "Active" = the first connected device nmcli lists. Kept for callers that
    // need one primary link; it says nothing about the other one, so anything
    // per-device must use the ethernet*/wifi* properties below.
    property string activeDevice: ""
    property string activeDeviceType: "none"  // "wifi" | "ethernet" | "none"
    property string activeConnection: ""
    property bool isConnected: false

    property bool wifiAvailable: false
    property string ethernetDevice: ""  // chosen ethernet device, connected or not
    property string wifiDevice: ""      // chosen wifi device, connected or not
    property string ethernetConnection: ""  // profile name on the ethernet device

    // Raw nmcli device state of the chosen devices: "connected", "disconnected",
    // "unavailable" (no cable / radio off), "connecting (...)", or "" when the
    // machine has no such device. Callers decide what to render for each.
    property string ethernetState: ""
    property string wifiState: ""

    // Ethernet and wifi are independent links and can both be up at once, which
    // is exactly what activeDeviceType cannot express.
    readonly property bool ethernetConnected: ethernetState.startsWith("connected")
    readonly property bool wifiConnected: wifiState.startsWith("connected")

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
        var hasWifiAdapter = false
        var ethernetDeviceName = ""
        var ethernetDeviceState = ""
        var ethernetProfile = ""
        var wifiDeviceName = ""
        var wifiDeviceState = ""
        for (var i = 0; i < lines.length; i++) {
            var parts = lines[i].trim().split(":")
            if (parts.length < 3) continue
            var device = parts[0].trim()
            var type = parts[1].trim()
            var state = parts[2].trim()
            var connection = parts.slice(3).join(":")
            // Containers and VMs add plenty of type "ethernet" interfaces (veth
            // pairs, taps). NetworkManager reports them as unmanaged, which is
            // what keeps them from being mistaken for the real port.
            if (state === "unmanaged") continue
            var connectedNow = state.startsWith("connected")
            if (type === "wifi") {
                hasWifiAdapter = true
                // Prefer a radio that is actually up over whichever is listed first
                if (wifiDeviceName === "" || (connectedNow && !wifiDeviceState.startsWith("connected"))) {
                    wifiDeviceName = device
                    wifiDeviceState = state
                }
            }
            if (type === "ethernet") {
                if (ethernetDeviceName === "" || (connectedNow && !ethernetDeviceState.startsWith("connected"))) {
                    ethernetDeviceName = device
                    ethernetDeviceState = state
                    ethernetProfile = connection
                }
            }
            if (!found && connectedNow && (type === "ethernet" || type === "wifi")) {
                root.activeDevice = device
                root.activeDeviceType = type
                root.activeConnection = connection
                root.isConnected = true
                found = true
            }
        }
        root.wifiAvailable = hasWifiAdapter
        root.ethernetDevice = ethernetDeviceName
        root.ethernetState = ethernetDeviceState
        root.ethernetConnection = ethernetProfile
        root.wifiDevice = wifiDeviceName
        root.wifiState = wifiDeviceState
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
