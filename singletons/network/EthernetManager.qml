pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.singletons

Singleton {
    id: root

    property real rxSpeed: 0
    property real txSpeed: 0

    property real _rxPrev: -1
    property real _txPrev: -1
    property real _rxCurrent: 0
    property real _txCurrent: 0
    property bool _rxReady: false
    property bool _txReady: false

    Connections {
        target: NetworkManager
        function onActiveDeviceChanged() { root._resetBaseline() }
    }

    function _resetBaseline() {
        _rxPrev = -1
        _txPrev = -1
        rxSpeed = 0
        txSpeed = 0
    }

    // -------------------------------------------------------------------------
    // Throughput polling (every 2s)
    // -------------------------------------------------------------------------
    Timer {
        id: speedTimer
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            var device = NetworkManager.activeDevice
            if (device !== "") {
                root._rxReady = false
                root._txReady = false
                rxProcess.command = ["cat", "/sys/class/net/" + device + "/statistics/rx_bytes"]
                txProcess.command = ["cat", "/sys/class/net/" + device + "/statistics/tx_bytes"]
                if (!rxProcess.running) rxProcess.running = true
                if (!txProcess.running) txProcess.running = true
            } else {
                root.rxSpeed = 0
                root.txSpeed = 0
            }
        }
    }

    Process {
        id: rxProcess
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                var num = parseFloat(line.trim())
                if (!isNaN(num)) {
                    root._rxCurrent = num
                    root._rxReady = true
                    root._checkSpeed()
                }
            }
        }
    }

    Process {
        id: txProcess
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                var num = parseFloat(line.trim())
                if (!isNaN(num)) {
                    root._txCurrent = num
                    root._txReady = true
                    root._checkSpeed()
                }
            }
        }
    }

    function _checkSpeed() {
        if (!_rxReady || !_txReady) return
        if (_rxPrev < 0) {
            _rxPrev = _rxCurrent
            _txPrev = _txCurrent
        } else {
            rxSpeed = Math.max(0, (_rxCurrent - _rxPrev) / 2.0)
            txSpeed = Math.max(0, (_txCurrent - _txPrev) / 2.0)
            _rxPrev = _rxCurrent
            _txPrev = _txCurrent
        }
    }

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------
    function disconnect() {
        var device = NetworkManager.activeDevice
        if (actionProcess.running || device === "") return
        actionProcess.command = ["nmcli", "device", "disconnect", device]
        actionProcess.running = true
    }

    Process {
        id: actionProcess
        onRunningChanged: {
            if (!running)
                postActionTimer.restart()
        }
    }

    Timer {
        id: postActionTimer
        interval: 600
        repeat: false
        onTriggered: NetworkManager.refresh()
    }
}
