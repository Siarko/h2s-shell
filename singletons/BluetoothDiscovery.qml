pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Looking for Bluetooth devices, through bluetoothctl — Quickshell exposes the adapter's
// `discovering` read-only. BlueZ keeps discovering only while the client that asked is
// connected, and `bluetoothctl scan on` on its own exits at once (BlueZ 5.87): so it runs
// with --timeout, staying for the 30 s a scan lasts. Stopping it ends the scan; the panel
// stops it when it closes. Whether discovery is on is the adapter's to say.
Singleton {
    id: root

    readonly property bool scanning: _scan.running

    function start() {
        _scan.running = true;
    }

    function stop() {
        _scan.running = false;
    }

    function toggle() {
        if (_scan.running)
            stop();
        else
            start();
    }

    Process {
        id: _scan
        command: ["bluetoothctl", "--timeout", "30", "scan", "on"]
    }
}
