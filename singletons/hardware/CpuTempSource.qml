pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property string sourceId: "cpuTemp"
    property string label: "CPU Temp"
    property string unit: "°C"
    property real value: 0
    property real minValue: 0
    property real maxValue: 110
    property bool available: true
    property var history: []
    property int maxHistory: 720  // 1h at 5s interval
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
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!_proc.running) _proc.running = true
    }

    Process {
        id: _proc
        // Search hwmon for k10temp (AMD Ryzen), zenpower, or coretemp (Intel).
        // Falls back to ACPI thermal_zone0 as a last resort.
        command: ["sh", "-c",
            "for d in /sys/class/hwmon/hwmon*; do" +
            " n=$(cat \"$d/name\" 2>/dev/null);" +
            " if [ \"$n\" = \"k10temp\" ] || [ \"$n\" = \"zenpower\" ] || [ \"$n\" = \"coretemp\" ]; then" +
            " cat \"$d/temp1_input\" 2>/dev/null && exit 0; fi; done;" +
            " cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null"]
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
