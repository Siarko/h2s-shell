pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.singletons
import qs.singletons.polling
import qs.singletons.io

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
    property string subtitle: ""
    property bool showProgressBar: false

    property bool _checked: false

    function _appendHistory(v) {
        history = History.append(history, v, _poll.interval)
    }

    // The sensor file, found once at startup; hwmon numbering only changes across boots
    property string _sensorPath: ""

    Component.onCompleted: _findSensor.running = true

    Process {
        id: _findSensor
        // hwmon for k10temp (AMD Ryzen), zenpower, or coretemp (Intel); ACPI
        // thermal_zone0 as a last resort
        command: ["sh", "-c",
            "for d in /sys/class/hwmon/hwmon*; do" +
            " case $(cat \"$d/name\" 2>/dev/null) in k10temp|zenpower|coretemp)" +
            " [ -r \"$d/temp1_input\" ] && echo \"$d/temp1_input\" && exit 0;; esac; done;" +
            " [ -r /sys/class/thermal/thermal_zone0/temp ] && echo /sys/class/thermal/thermal_zone0/temp"]
        property string _buf: ""

        stdout: SplitParser {
            splitMarker: ""
            onRead: data => { _findSensor._buf += data }
        }

        onRunningChanged: {
            if (running) return
            root._sensorPath = _buf.trim()
            if (root._sensorPath === "")
                root.available = false
            _buf = ""
        }
    }

    KernelFile {
        id: _sensor
        path: root._sensorPath
    }

    PollTimer {
        id: _poll
        interval: Profiles.value("polling.temperatures.interval")
        active: root._sensorPath !== "" && root.available
        onTriggered: {
            var raw = parseInt(_sensor.read().trim())
            if (!isNaN(raw) && raw > 0) {
                root.value = Math.round(raw / 1000)
                root._appendHistory(root.value)
            } else if (!root._checked) {
                root.available = false
            }
            root._checked = true
        }
    }
}
