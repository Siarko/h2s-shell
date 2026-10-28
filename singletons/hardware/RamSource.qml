pragma Singleton

import Quickshell
import QtQuick
import qs.singletons.io

Singleton {
    id: root

    property string sourceId: "ram"
    property string label: "RAM"
    property string unit: "%"
    property real value: 0
    property real minValue: 0
    property real maxValue: 100
    property bool available: true
    property var history: []
    property int maxHistory: 1800
    property string subtitle: ""
    property bool showProgressBar: true

    property real usedBytes: 0
    property real totalBytes: 0

    function _appendHistory(v) {
        var h = history.slice(-(maxHistory - 1))
        h.push({t: Date.now(), v: v})
        history = h
    }

    function formatBytes(bytes) {
        if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + " GB"
        if (bytes >= 1048576)    return (bytes / 1048576).toFixed(0) + " MB"
        return bytes + " B"
    }

    KernelFile {
        id: _meminfo
        path: "/proc/meminfo"
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            var data = {}
            for (const line of _meminfo.read().split("\n")) {
                var m = line.match(/^(\w+):\s+(\d+)/)
                if (m) data[m[1]] = parseInt(m[2]) * 1024
            }
            var total = data["MemTotal"] || 0
            var avail = data["MemAvailable"] || 0
            root.totalBytes = total
            root.usedBytes  = total - avail
            root.value      = total > 0 ? Math.round((total - avail) / total * 100) : 0
            root.subtitle   = root.formatBytes(root.usedBytes) + " / " + root.formatBytes(root.totalBytes)
            root._appendHistory(root.value)
        }
    }
}
