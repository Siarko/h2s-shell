pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.singletons

Singleton {
    id: root

    property string sourceId: "disk"
    property string label: "Disk"
    property string unit: "%"
    property real value: 0
    property real minValue: 0
    property real maxValue: 100
    property bool available: true
    property var history: []
    property int maxHistory: 360  // 1h at 10s interval
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

    Timer {
        interval: Profiles.value("polling.disk.interval")
        running: interval > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!_proc.running) _proc.running = true
    }

    Process {
        id: _proc
        command: ["df", "-B1", "/"]
        property var _lines: []

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => { if (line.trim()) _proc._lines.push(line) }
        }

        onRunningChanged: {
            if (!running) {
                if (_proc._lines.length >= 2) {
                    var parts = _proc._lines[1].trim().split(/\s+/)
                    if (parts.length >= 4) {
                        var total = parseInt(parts[1]) || 0
                        var used  = parseInt(parts[2]) || 0
                        root.totalBytes = total
                        root.usedBytes  = used
                        if (total > 0) {
                            root.value    = Math.round(used / total * 100)
                            root.subtitle = root.formatBytes(used) + " / " + root.formatBytes(total)
                        }
                    }
                }
                _proc._lines = []
                root._appendHistory(root.value)
            }
        }
    }
}
