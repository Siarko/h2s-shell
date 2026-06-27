pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property string sourceId: "gpuTemp"
    property string label: "GPU Temp"
    property string unit: "°C"
    property real value: 0
    property real minValue: 0
    property real maxValue: 110
    property bool available: true
    property var history: []
    property int maxHistory: 1800
    property string subtitle: ""
    property bool showProgressBar: false

    property bool _checked: false

    function _appendHistory(v) {
        var h = history.slice(-(maxHistory - 1))
        h.push({t: Date.now(), v: v})
        history = h
    }

    Timer {
        id: _timer
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!_proc.running) _proc.running = true
    }

    Process {
        id: _proc
        // Glob expansion via sh; temperature in millidegrees Celsius
        command: ["sh", "-c",
            "cat /sys/class/drm/card0/device/hwmon/hwmon*/temp1_input 2>/dev/null | head -1"]
        property string _buf: ""

        stdout: SplitParser {
            splitMarker: ""
            onRead: data => { _proc._buf += data }
        }

        onRunningChanged: {
            if (!running) {
                var raw = parseInt(_proc._buf.trim())
                if (!isNaN(raw) && raw > 0) {
                    root.value = Math.round(raw / 1000)
                    root._appendHistory(root.value)
                } else if (!root._checked) {
                    root.available = false
                    _timer.running = false
                }
                root._checked = true
                _proc._buf = ""
            }
        }
    }
}
