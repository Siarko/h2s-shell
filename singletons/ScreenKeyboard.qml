pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// Whether an on-screen keyboard is on screen, on which screen and where its top edge is —
// so popups keep clear of it (Popup). It is another program's layer surface (oskbd,
// squeekboard — namespace "osk"), which Wayland lets no client see; Hyprland tells on its
// event socket (`openlayer>>osk`, `closelayer>>osk`), and `hyprctl layers` says where it is
// (asked when it opens, and once at start).
Singleton {
    id: root

    // The layer namespace on-screen keyboards use (oskbd took squeekboard's)
    readonly property string namespace: "osk"
    property bool visible: false
    // Its screen's name ("eDP-1") and its top edge in the compositor's (global) logical
    // pixels — a screen's own y to be taken off
    property string screenName: ""
    property real top: 0

    function _where() {
        _query.running = true;
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.data !== root.namespace)
                return;
            if (event.name === "openlayer") {
                root.visible = true;
                // Its place is known once it has mapped
                _settle.restart();
            } else if (event.name === "closelayer") {
                root.visible = false;
            }
        }
    }

    Timer {
        id: _settle
        interval: 150
        onTriggered: root._where()
    }

    Component.onCompleted: _where()

    // { "eDP-1": { "levels": { "3": [{ x, y, w, h, namespace }, …] } }, … }
    Process {
        id: _query
        command: ["hyprctl", "layers", "-j"]
        property string _output: ""
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => _query._output += data
        }
        onRunningChanged: {
            if (running)
                return;
            let found = null;
            try {
                const monitors = JSON.parse(_output);
                for (const name in monitors) {
                    for (const level of Object.values(monitors[name].levels ?? {})) {
                        const layer = level.find(surface => surface.namespace === root.namespace);
                        if (layer)
                            found = { screen: name, top: layer.y };
                    }
                }
            } catch (error) {
                found = null;
            }
            _output = "";
            root.visible = found !== null;
            if (found) {
                root.screenName = found.screen;
                root.top = found.top;
            }
        }
    }
}
