import Quickshell
import QtQuick
import qs.singletons
import qs.singletons.polling
import qs.singletons.io

// One card's temperature (its first hwmon sensor, "edge" on amdgpu). One instance per
// card, created by Hardware.qml.
Scope {
    id: root

    // An entry of GpuDevices.cards
    required property var card

    readonly property string sourceId: "gpuTemp@" + card.slot
    readonly property string label: "GPU " + card.number + " Temp (" + card.name + ")"
    property string unit: "°C"
    property real value: 0
    property real minValue: 0
    property real maxValue: 110
    property bool available: card.tempPath !== "" && _readable
    property var history: []
    property string subtitle: ""
    property bool showProgressBar: false

    property bool _readable: true
    property bool _checked: false

    function _appendHistory(v) {
        history = History.append(history, v, _poll.interval)
    }

    KernelFile {
        id: _sensor
        path: root.card.tempPath
    }

    PollTimer {
        id: _poll
        interval: Profiles.value("polling.temperatures.interval")
        active: root.card.tempPath !== "" && root._readable
        onTriggered: {
            var raw = parseInt(_sensor.read().trim())
            if (!isNaN(raw) && raw > 0) {
                root.value = Math.round(raw / 1000)
                root._appendHistory(root.value)
            } else if (!root._checked) {
                root._readable = false
            }
            root._checked = true
        }
    }
}
