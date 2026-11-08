pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// Whether an on-screen keyboard is on screen. It is another program's layer surface
// (oskbd, squeekboard — namespace "osk"), which Wayland lets no client see; Hyprland tells
// on its event socket (`openlayer>>osk`, `closelayer>>osk`), and `hyprctl layers` says
// at start. A popup opened by touch must not close when the keyboard is tapped
// (Popup, its focus grab) — docs/plans/touch.md.
Singleton {
    id: root

    // The layer namespace on-screen keyboards use (oskbd took squeekboard's)
    readonly property string namespace: "osk"
    property bool visible: false

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.data !== root.namespace)
                return;
            if (event.name === "openlayer")
                root.visible = true;
            else if (event.name === "closelayer")
                root.visible = false;
        }
    }

    Component.onCompleted: _query.running = true

    // Already on screen when the shell starts: no event comes for it
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
            try {
                root.visible = _output.includes('"namespace": "' + root.namespace + '"');
            } catch (error) {
                root.visible = false;
            }
            _output = "";
        }
    }
}
