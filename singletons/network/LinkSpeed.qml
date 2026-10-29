import QtQuick
import qs.singletons
import qs.singletons.polling
import qs.singletons.io

// Throughput of one network interface, read from its sysfs byte counters.
//
// Not a singleton: one instance per link, so ethernet and wifi each report
// their own numbers. Reading the shell's single "active device" instead made
// both panel sections show the same figures, and with two links up one of them
// belonged to the other interface.
Item {
    id: root

    // Interface name, e.g. "enp5s0". Empty stops polling and zeroes the rates.
    property string device: ""
    // Gate for polling — false while the link is down, so counters that cannot move
    // are not read.
    property bool active: true
    property int intervalMs: Profiles.value("polling.network.interval")

    property real rxSpeed: 0
    property real txSpeed: 0

    // History.append samples in bytes/s, one per tick while the link is up, for the graph
    property var rxHistory: []
    property var txHistory: []

    // Byte counts from the previous tick; -1 means the next read only establishes
    // a baseline. Switching device or going down has to go through that again,
    // otherwise the first delta would be a jump between two unrelated counters.
    property real _rxPrevious: -1
    property real _txPrevious: -1
    property double _previousTime: 0

    onDeviceChanged: _reset()
    onActiveChanged: if (!active) _reset()

    function _reset() {
        _rxPrevious = -1
        _txPrevious = -1
        rxSpeed = 0
        txSpeed = 0
    }

    KernelFile {
        id: _rxFile
        path: root.device ? "/sys/class/net/" + root.device + "/statistics/rx_bytes" : ""
    }

    KernelFile {
        id: _txFile
        path: root.device ? "/sys/class/net/" + root.device + "/statistics/tx_bytes" : ""
    }

    PollTimer {
        id: _poll
        interval: root.intervalMs
        active: root.device !== "" && root.active
        // Bytes counted during a pause would show up as one spike
        onPaused: root._reset()
        onTriggered: {
            // Both reads are synchronous, so the two counters come from the same tick
            var rxBytes = parseFloat(_rxFile.read())
            var txBytes = parseFloat(_txFile.read())
            // Unreadable means the interface went away between ticks
            if (isNaN(rxBytes) || isNaN(txBytes))
                root._reset()
            else
                root._update(rxBytes, txBytes)
        }
    }

    // Divides by the time actually elapsed, not by intervalMs: a profile can change the
    // rate between two reads. `now` is a parameter for the tests.
    function _update(rxBytes, txBytes, now = Date.now()) {
        if (_rxPrevious < 0 || now <= _previousTime) {
            _rxPrevious = rxBytes
            _txPrevious = txBytes
            _previousTime = now
            return
        }
        var seconds = (now - _previousTime) / 1000.0
        rxSpeed = Math.max(0, (rxBytes - _rxPrevious) / seconds)
        txSpeed = Math.max(0, (txBytes - _txPrevious) / seconds)
        rxHistory = History.append(rxHistory, rxSpeed, intervalMs, now)
        txHistory = History.append(txHistory, txSpeed, intervalMs, now)
        _rxPrevious = rxBytes
        _txPrevious = txBytes
        _previousTime = now
    }
}
