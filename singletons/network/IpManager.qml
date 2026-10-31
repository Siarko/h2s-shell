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

    // Each device that exists; asked while already running, a query runs once more after
    // (CommandQuery)
    function _poll() {
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
