pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.singletons.hardware

Singleton {
    id: root

    property string sourceId: "gpu"
    property string label: "GPU"
    property string unit: "%"
    property real value: 0
    property real minValue: 0
    property real maxValue: 100
    // Unavailable when no amdgpu node exists at all, or when the chosen one
    // turned out not to expose the counters we need.
    property bool available: GpuDevice.available && _readable
    property var history: []
    property int maxHistory: 1800
    property string subtitle: ""
    property bool showProgressBar: true

    property real vramUsedBytes: 0
    property real vramTotalBytes: 0
    property bool _readable: true
    property bool _checked: false

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
        id: _timer
        interval: 2000
        // Idle until GpuDevice has settled on a card, otherwise the first tick
        // would read nothing and latch this source as unavailable.
        running: GpuDevice.path !== "" && root._readable
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!_proc.running) _proc.running = true
    }

    Process {
        id: _proc
        // AMD amdgpu sysfs: GPU busy %, VRAM used, VRAM total — one per line
        command: ["sh", "-c",
            "d='" + GpuDevice.path + "';" +
            "cat \"$d/gpu_busy_percent\";" +
            "cat \"$d/mem_info_vram_used\";" +
            "cat \"$d/mem_info_vram_total\""]
        property var _lines: []

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => { if (line.trim()) _proc._lines.push(line.trim()) }
        }

        onRunningChanged: {
            if (!running) {
                if (_proc._lines.length >= 3) {
                    root.value          = parseInt(_proc._lines[0]) || 0
                    root.vramUsedBytes  = parseFloat(_proc._lines[1]) || 0
                    root.vramTotalBytes = parseFloat(_proc._lines[2]) || 0
                    if (root.vramTotalBytes > 0)
                        root.subtitle = root.formatBytes(root.vramUsedBytes) + " / " + root.formatBytes(root.vramTotalBytes) + " VRAM"
                    root._appendHistory(root.value)
                } else if (!root._checked) {
                    root._readable = false
                }
                root._checked = true
                _proc._lines = []
            }
        }
    }
}
