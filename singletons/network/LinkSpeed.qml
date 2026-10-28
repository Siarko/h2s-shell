import QtQuick
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
    property int intervalMs: 2000

    property real rxSpeed: 0
    property real txSpeed: 0

    // Byte counts from the previous tick; -1 means the next read only establishes
    // a baseline. Switching device or going down has to go through that again,
    // otherwise the first delta would be a jump between two unrelated counters.
    property real _rxPrevious: -1
    property real _txPrevious: -1

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

    Timer {
        interval: root.intervalMs
        running: root.device !== "" && root.active
        repeat: true
        triggeredOnStart: true
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

    function _update(rxBytes, txBytes) {
        if (_rxPrevious < 0) {
            _rxPrevious = rxBytes
            _txPrevious = txBytes
            return
        }
        var seconds = intervalMs / 1000.0
        rxSpeed = Math.max(0, (rxBytes - _rxPrevious) / seconds)
        txSpeed = Math.max(0, (txBytes - _txPrevious) / seconds)
        _rxPrevious = rxBytes
        _txPrevious = txBytes
    }
}
