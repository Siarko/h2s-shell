pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.singletons

Singleton {
    id: root

    property string wifiAddress: ""
    property string wifiDns: ""
    property string ethernetAddress: ""
    property string ethernetDns: ""

    Timer {
        interval: 10000
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

    function _poll() {
        var wifiDev = NetworkManager.wifiDevice
        var ethDev = NetworkManager.ethernetDevice
        if (wifiDev !== "" && !wifiProcess.running) {
            wifiProcess._lines = []
            wifiProcess.command = ["nmcli", "-t", "-f", "IP4.ADDRESS,IP4.DNS", "device", "show", wifiDev]
            wifiProcess.running = true
        }
        if (ethDev !== "" && !ethProcess.running) {
            ethProcess._lines = []
            ethProcess.command = ["nmcli", "-t", "-f", "IP4.ADDRESS,IP4.DNS", "device", "show", ethDev]
            ethProcess.running = true
        }
    }

    Process {
        id: wifiProcess
        property var _lines: []

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => { if (line.trim() !== "") wifiProcess._lines.push(line.trim()) }
        }

        onRunningChanged: {
            if (!running) {
                var result = root._parse(_lines)
                root.wifiAddress = result.address
                root.wifiDns = result.dns
                _lines = []
            }
        }
    }

    Process {
        id: ethProcess
        property var _lines: []

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => { if (line.trim() !== "") ethProcess._lines.push(line.trim()) }
        }

        onRunningChanged: {
            if (!running) {
                var result = root._parse(_lines)
                root.ethernetAddress = result.address
                root.ethernetDns = result.dns
                _lines = []
            }
        }
    }

    function _parse(lines) {
        var address = ""
        var dnsList = []
        for (var i = 0; i < lines.length; i++) {
            var colonIdx = lines[i].indexOf(":")
            if (colonIdx < 0) continue
            var key = lines[i].substring(0, colonIdx)
            var value = lines[i].substring(colonIdx + 1).trim()
            if (value === "" || value === "--") continue
            if (key.startsWith("IP4.ADDRESS") && address === "")
                address = value
            else if (key.startsWith("IP4.DNS"))
                dnsList.push(value)
        }
        return { address: address, dns: dnsList.join(", ") }
    }
}
