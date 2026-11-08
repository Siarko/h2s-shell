pragma Singleton

import Quickshell
import Quickshell.Bluetooth
import QtQuick

// Keeps Bluetooth on or off across restarts. BlueZ does not remember the adapter's power:
// with AutoEnable (on by default) it powers the adapter on whenever bluetoothd starts, so
// switching it off lasted only until the next boot. Here the last state the adapter was
// seen in is kept in Config and put back when an adapter appears — at the shell's start,
// and again if bluetoothd restarts or the adapter comes back after a resume.
//
// Until the shell runs, Bluetooth is whatever BlueZ made it (on, by default). Blocking the
// radio with rfkill would hold from boot, but was not chosen (2026-11-08).
Singleton {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter

    // The adapter the remembered state was put back on. Until then its state is BlueZ's,
    // not the user's, and is not recorded.
    property var _appliedTo: null

    function setEnabled(enabled: bool) {
        if (root.adapter)
            root.adapter.enabled = enabled;
    }

    function _apply() {
        if (!Config.ready || !root.adapter || root._appliedTo === root.adapter)
            return;
        root._appliedTo = root.adapter;
        if (Config.bluetooth.powered === "")
            return;
        root.adapter.enabled = Config.bluetooth.powered === "on";
        _settling.restart();
    }

    onAdapterChanged: root._apply()
    Component.onCompleted: root._apply()

    Connections {
        target: Config
        function onReadyChanged() {
            root._apply();
        }
    }

    Connections {
        target: root.adapter
        function onEnabledChanged() {
            if (root._appliedTo !== root.adapter)
                return;
            const remembered = root.adapter.enabled ? "on" : "off";
            // A change right after putting the state back is BlueZ still powering the
            // adapter up on its own (AutoEnable racing the shell), not the user: undo it
            if (_settling.running && remembered !== Config.bluetooth.powered) {
                root.adapter.enabled = Config.bluetooth.powered === "on";
                return;
            }
            Config.bluetooth.powered = remembered;
        }
    }

    Timer {
        id: _settling
        interval: 3000
    }
}
