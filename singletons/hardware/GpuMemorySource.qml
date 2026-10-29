import Quickshell
import QtQuick
import qs.singletons
import qs.singletons.polling
import qs.singletons.io

// Video memory in use on one card. A source of its own rather than a subtitle under the
// load: the two are unrelated, and under one bar they read as if the bar showed the
// memory. On an APU this is the carve-out of system RAM.
Scope {
    id: root

    // An entry of GpuDevices.cards
    required property var card

    readonly property string sourceId: "vram@" + card.slot
    readonly property string label: "VRAM " + card.number + " (" + card.name + ")"
    property string unit: "%"
    property real value: 0
    property real minValue: 0
    property real maxValue: 100
    property bool available: _readable
    property var history: []
    property string subtitle: ""
    property bool showProgressBar: true

    property real usedBytes: 0
    property real totalBytes: 0
    property bool _readable: true
    property bool _checked: false

    function _appendHistory(v) {
        history = History.append(history, v, _poll.interval)
    }

    function formatBytes(bytes) {
        if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + " GB"
        if (bytes >= 1048576)    return (bytes / 1048576).toFixed(0) + " MB"
        return bytes + " B"
    }

    KernelFile {
        id: _used
        path: root.card.path + "/mem_info_vram_used"
    }

    KernelFile {
        id: _total
        path: root.card.path + "/mem_info_vram_total"
    }

    PollTimer {
        id: _poll
        interval: Profiles.value("polling.hardware.interval")
        active: root._readable
        onTriggered: {
            var used  = parseFloat(_used.read())
            var total = parseFloat(_total.read())
            if (!isNaN(used) && total > 0) {
                root.usedBytes  = used
                root.totalBytes = total
                root.value      = Math.round(used / total * 100)
                root.subtitle   = root.formatBytes(used) + " / " + root.formatBytes(total)
                root._appendHistory(root.value)
            } else if (!root._checked) {
                root._readable = false
            }
            root._checked = true
        }
    }
}
