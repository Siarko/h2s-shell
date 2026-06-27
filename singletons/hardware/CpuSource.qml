pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property string sourceId: "cpu"
    property string label: "CPU"
    property string unit: "%"
    property real value: 0
    property real minValue: 0
    property real maxValue: 100
    property bool available: true
    property var history: []
    property int maxHistory: 1800
    property string subtitle: ""
    property bool showProgressBar: true

    property var _prev: null

    function _appendHistory(v) {
        var h = history.slice(-(maxHistory - 1))
        h.push({t: Date.now(), v: v})
        history = h
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!_proc.running) _proc.running = true
    }

    Process {
        id: _proc
        command: ["cat", "/proc/stat"]

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                if (!line.startsWith("cpu ")) return
                var parts   = line.trim().split(/\s+/)
                var user    = parseInt(parts[1])
                var nice    = parseInt(parts[2])
                var system  = parseInt(parts[3])
                var idle    = parseInt(parts[4])
                var iowait  = parseInt(parts[5])
                var irq     = parseInt(parts[6])
                var softirq = parseInt(parts[7])
                var steal   = parseInt(parts[8]) || 0
                var total   = user + nice + system + idle + iowait + irq + softirq + steal
                var idleAll = idle + iowait

                if (root._prev !== null) {
                    var dTotal = total - root._prev.total
                    var dIdle  = idleAll - root._prev.idle
                    if (dTotal > 0) {
                        root.value = Math.max(0, Math.min(100, Math.round((1 - dIdle / dTotal) * 100)))
                        root._appendHistory(root.value)
                    }
                }
                root._prev = {total: total, idle: idleAll}
            }
        }
    }
}
