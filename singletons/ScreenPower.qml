pragma Singleton

import Quickshell
import Quickshell.Hyprland
import QtQuick
import qs.singletons.screen

// The monitors and their power: which are connected (by their ids, MonitorRules), whether
// each is on, and turning one off or on. Only the compositor can cut one output's power, so
// it takes a backend (MonitorRules.backend): Hyprland's own dispatch where the shell runs
// under Hyprland; without one, `canPowerOff` is false and nothing is read or asked.
//
// A failed reading or action leaves a monitor's power "unknown", never "off". The monitors
// are read again when Hyprland adds or removes one, and after each action.
Singleton {
    id: root

    readonly property string backend: MonitorRules.backend({ hyprland: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? "") !== "" })
    readonly property bool canPowerOff: backend !== "none"

    // [{ connector, id, make, model, serial, builtIn, power: "on" | "off" | "unknown" }]
    readonly property var monitors: _hyprland?.monitors ?? []
    readonly property var twins: _hyprland?.twins ?? []
    readonly property bool monitorsRead: _hyprland?.monitorsRead ?? false

    signal actionDone(string id, bool on, string problem)

    function read() {
        _hyprland?.read();
    }

    // The monitor with this id off (false) or on (true); answered by actionDone
    function setPower(id, on) {
        if (_hyprland === null) {
            actionDone(id, on, "no way to turn monitors off here");
            return;
        }
        _hyprland.setPower(id, on);
    }

    property HyprlandScreenPower _hyprland: null

    property Component _hyprlandComponent: Component {
        HyprlandScreenPower {
            onActionDone: (id, on, problem) => root.actionDone(id, on, problem)
        }
    }

    property Connections _events: Connections {
        target: root.backend === "hyprland" ? Hyprland : null
        function onRawEvent(event) {
            if (event.name === "monitoradded" || event.name === "monitoraddedv2"
                    || event.name === "monitorremoved" || event.name === "monitorremovedv2")
                root.read();
        }
    }

    Component.onCompleted: {
        if (backend === "hyprland") {
            _hyprland = _hyprlandComponent.createObject(root);
            _hyprland.read();
        }
    }
}
