pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.components

// Tells the network managers when NetworkManager's state changed, so they re-query it
// then instead of polling nmcli every few seconds.
//
// One long-running `nmcli monitor` prints a line for every device state change, VPN
// up/down, profile added or removed, and connectivity change. A burst of lines from one
// change (a connect prints several) becomes a single `changed()`. If the monitor dies it
// is restarted, with a growing delay so a stopped NetworkManager is not hammered, and
// `changed()` fires once it is back, since anything may have happened meanwhile.
//
// Not every change prints a line — a DHCP renewal that only changes the address does
// not — so the managers keep a slow fallback poll as well.
Singleton {
    id: root

    signal changed

    // Restart delays, doubling from the first to the last
    readonly property int _minRestartDelay: 1000
    readonly property int _maxRestartDelay: 60000
    property int _restartDelay: _minRestartDelay
    property double _startedAt: 0

    Component.onCompleted: _start()

    Logger {
        id: _log
        prefix: "[NetworkEvents]"
    }

    function _start() {
        _startedAt = Date.now();
        _monitor.running = true;
    }

    Process {
        id: _monitor
        command: ["nmcli", "monitor"]

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: _debounce.restart()
        }

        onRunningChanged: {
            if (running) {
                _debounce.restart();
                return;
            }
            // A monitor that ran for a while was healthy: start the backoff afresh
            if (Date.now() - root._startedAt > root._maxRestartDelay)
                root._restartDelay = root._minRestartDelay;
            // Always logged, not only in debug: the shell goes back to slow polling
            _log.error("nmcli monitor exited, restarting in", root._restartDelay, "ms");
            _restart.interval = root._restartDelay;
            _restart.start();
            root._restartDelay = Math.min(root._restartDelay * 2, root._maxRestartDelay);
        }
    }

    Timer {
        id: _restart
        onTriggered: root._start()
    }

    Timer {
        id: _debounce
        interval: 300
        onTriggered: root.changed()
    }
}
