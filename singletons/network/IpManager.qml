pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.singletons
import qs.singletons.io

Singleton {
    id: root

    property string wifiAddress: ""
    property string wifiDns: ""
    property string ethernetAddress: ""
    property string ethernetDns: ""

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

    Connections {
        target: NetworkManager
        function onWifiDeviceChanged() { root._poll() }
        function onEthernetDeviceChanged() { root._poll() }
    }

    // Every device's addresses (Nmcli.devices: { device, ipIface, type, kind, ipv4 [], ipv6 [] },
    // the addresses with their prefix), for Api.localNetworks; [] while not read
    property var devices: []
    // The last reading of them worked: a failed one (no nmcli, NetworkManager not running)
    // leaves `devices` empty and this false — unknown, never "no network"
    property bool devicesRead: false
    // The IPv6 addresses' flags (NetworkRules.ipv6AddressFlags), read after the devices, or
    // null when `ip` could not tell them: every global address is kept then
    property var ipv6Flags: null

    // Each device that exists; asked while already running, a query runs once more after
    // (CommandQuery)
    function _poll() {
        _readDevices()
        if (NetworkManager.wifiDevice !== "")
            wifiQuery.request()
        if (NetworkManager.ethernetDevice !== "")
            ethernetQuery.request()
    }

    CommandQuery {
        id: wifiQuery
        command: ["nmcli", "-t", "-f", "IP4.ADDRESS,IP4.DNS", "device", "show", NetworkManager.wifiDevice]
        onDone: lines => {
            const result = root._parse(lines)
            root.wifiAddress = result.address
            root.wifiDns = result.dns
        }
    }

    CommandQuery {
        id: ethernetQuery
        command: ["nmcli", "-t", "-f", "IP4.ADDRESS,IP4.DNS", "device", "show", NetworkManager.ethernetDevice]
        onDone: lines => {
            const result = root._parse(lines)
            root.ethernetAddress = result.address
            root.ethernetDns = result.dns
        }
    }

    // A reading is the devices (nmcli), then their IPv6 addresses' flags (ip). One asked for
    // while it runs drops the answer under way and starts again (LatestQuery), so what is
    // published is always from a reading started after the last change was reported
    property var _rejectedFields: []
    property var _pendingDevices: []
    property string _devicesProblem: ""
    property string _flagsProblem: ""

    function _readDevices() {
        _devicesQuery.command = ["nmcli", "-t", "-f", NetworkRules.deviceAddressFields(_rejectedFields).join(","), "device", "show"]
        _devicesQuery.request()
    }

    LatestQuery {
        id: _devicesQuery
        timeoutMs: 15000
        onAnswered: (lines, result) => {
            const problem = NetworkRules.readProblem(result, "nmcli")
            const refused = problem === "" ? "" : NetworkRules.rejectedField(result.stderr)
            if (refused !== "" && NetworkRules.deviceAddressOptionalFields.includes(refused) && !root._rejectedFields.includes(refused)) {
                console.warn("IpManager: this nmcli does not know " + refused + ": the devices are read without it")
                root._rejectedFields = root._rejectedFields.concat([refused])
                root._readDevices()
                return
            }
            // Logged when the outcome changes, not on every reading
            if (problem !== root._devicesProblem)
                console.warn("IpManager: the devices' addresses " + (problem === "" ? "are read again" : "could not be read: " + problem))
            root._devicesProblem = problem
            if (problem !== "") {
                root.devices = []
                root.devicesRead = false
                return
            }
            root._pendingDevices = Nmcli.devices(lines)
            root._flagsQuery.request()
        }
    }

    LatestQuery {
        id: _flagsQuery
        command: ["ip", "-j", "-6", "address", "show"]
        timeoutMs: 15000
        onAnswered: (lines, result) => {
            // A newer reading of the devices is under way: it asks for the flags again
            if (root._devicesQuery.running)
                return
            const problem = NetworkRules.readProblem(result, "ip")
            const flags = problem === "" ? NetworkRules.ipv6AddressFlags(lines.join("\n")) : null
            const flagsProblem = problem !== "" ? problem : flags === null ? "ip gave no readable answer" : ""
            if (flagsProblem !== root._flagsProblem)
                console.warn("IpManager: the IPv6 addresses' flags " + (flagsProblem === "" ? "are read again" : "could not be read, every address kept: " + flagsProblem))
            root._flagsProblem = flagsProblem
            root.ipv6Flags = flags
            root.devices = root._pendingDevices
            root.devicesRead = true
        }
    }

    function _parse(lines) {
        var address = ""
        var dnsList = []
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            var colonIdx = line.indexOf(":")
            if (colonIdx < 0) continue
            var key = line.substring(0, colonIdx)
            var value = line.substring(colonIdx + 1).trim()
            if (value === "" || value === "--") continue
            if (key.startsWith("IP4.ADDRESS") && address === "")
                address = value
            else if (key.startsWith("IP4.DNS"))
                dnsList.push(value)
        }
        return { address: address, dns: dnsList.join(", ") }
    }
}
