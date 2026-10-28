import Quickshell
import QtQuick
import qs.singletons.io

// How busy one card's cores are. One instance per card, created by Hardware.qml.
Scope {
    id: root

    // An entry of GpuDevices.cards
    required property var card

    readonly property string sourceId: "gpu@" + card.slot
    readonly property string label: "GPU " + card.number + " (" + card.name + ")"
    property string unit: "%"
    property real value: 0
    property real minValue: 0
    property real maxValue: 100
    property bool available: _readable
    property var history: []
    property int maxHistory: 1800
    property string subtitle: ""
    property bool showProgressBar: true

    property bool _readable: true
    property bool _checked: false

    // gpu_busy_percent is an instantaneous reading that swings between 0 and its real
    // level within a fraction of a second; one sample per 2 s tick mostly caught the 0.
    // It is sampled often and the tick publishes the average, like CPU usage is an
    // average over the whole tick.
    property real _busySum: 0
    property int _busySamples: 0

    function _appendHistory(v) {
        var h = history.slice(-(maxHistory - 1))
        h.push({t: Date.now(), v: v})
        history = h
    }

    KernelFile {
        id: _busy
        path: root.card.path + "/gpu_busy_percent"
    }

    Timer {
        id: _timer
        interval: 2000
        running: root._readable
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            // The first tick runs before any sample, so it reads one itself
            var busy = root._busySamples > 0 ? root._busySum / root._busySamples : parseInt(_busy.read())
            root._busySum = 0
            root._busySamples = 0
            if (!isNaN(busy)) {
                root.value = Math.round(busy)
                root._appendHistory(root.value)
            } else if (!root._checked) {
                root._readable = false
            }
            root._checked = true
        }
    }

    Timer {
        interval: 200
        running: _timer.running
        repeat: true
        onTriggered: {
            var busy = parseInt(_busy.read())
            if (isNaN(busy)) return
            root._busySum += busy
            root._busySamples++
        }
    }
}
