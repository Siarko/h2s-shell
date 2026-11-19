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

    // Every device's addresses (Nmcli.devices: { device, type, kind, ipv4 [], ipv6 [] }, the
    // addresses with their prefix), for Api.localNetworks; [] while not read
    property var devices: []
    // The last reading of them worked: a failed one (no nmcli, NetworkManager not running)
    // leaves `devices` empty and this false — unknown, never "no network"
    property bool devicesRead: false

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

    // One reading at a time; one asked for meanwhile runs when it ends, so the answer kept is
    // always from a reading started after the last change was reported
    property var _devicesRun: null
    property bool _devicesAgain: false
    property string _devicesProblem: ""

    function _readDevices() {
        if (_devicesRun !== null) {
            _devicesAgain = true
            return
        }
        _devicesRun = _devicesRunner.start(["nmcli", "-t", "-f", "GENERAL.DEVICE,GENERAL.TYPE,IP4.ADDRESS,IP6.ADDRESS", "device", "show"], {
            timeoutMs: 15000,
            maxOutputBytes: 262144,
            done: result => {
                root._devicesRun = null
                const ok = result.ok && !result.truncated
                root.devices = ok ? Nmcli.devices(result.stdout.split("\n")) : []
                root.devicesRead = ok
                // Logged when the outcome changes, not on every reading
                const problem = ok ? "" : (result.failedToStart ? "nmcli could not be started"
                    : result.timedOut ? "nmcli did not answer" : result.truncated ? "too much output"
                    : "nmcli failed (" + result.code + "): " + result.stderr.trim().split("\n")[0].slice(0, 200))
                if (problem !== root._devicesProblem)
                    console.warn("IpManager: the devices' addresses " + (problem === "" ? "are read again" : "could not be read: " + problem))
                root._devicesProblem = problem
                if (root._devicesAgain) {
                    root._devicesAgain = false
                    root._readDevices()
                }
            }
        })
    }

    property CommandRunner _devicesRunner: CommandRunner {}

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
