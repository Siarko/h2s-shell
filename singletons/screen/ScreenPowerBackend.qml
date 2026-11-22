import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.singletons

// ScreenPower's backend picked and run (the shell's one instance is ScreenPower's; a suite
// makes its own with `hyprland` and `wlopm` set): Hyprland's own dispatch where the shell
// runs under Hyprland (HyprlandScreenPower); elsewhere `wlopm` (WlopmScreenPower) once its
// first reading has found it on PATH; without either, `canPowerOff` is false, nothing is
// asked, and `unavailable` says why for the page.
//
// The monitors are read again when Hyprland adds or removes one, or elsewhere when Qt's
// list of screens changes, and after each action.
QtObject {
    id: root

    property bool hyprland: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? "") !== ""
    property string wlopm: "wlopm"

    readonly property string backend: MonitorRules.backend({ hyprland: hyprland, wlopm: _wlopm?.program === "found" })
    readonly property bool canPowerOff: backend !== "none"
    // { reason, hint }: why monitors cannot be turned off, "" when they can
    readonly property var unavailable: MonitorRules.unavailable(backend)
    readonly property var _active: backend === "hyprland" ? _hyprland : backend === "wlopm" ? _wlopm : null

    readonly property var monitors: _active?.monitors ?? []
    readonly property var twins: _active?.twins ?? []
    readonly property bool monitorsRead: _active?.monitorsRead ?? false

    signal actionDone(string id, bool on, string problem)

    function read() {
        _active?.read();
    }

    // The monitor with this id off (false) or on (true); answered by actionDone
    function setPower(id, on) {
        if (_active === null) {
            actionDone(id, on, "no way to turn monitors off here");
            return;
        }
        _active.setPower(id, on);
    }

    property var _hyprland: null
    property var _wlopm: null

    property Component _hyprlandComponent: Component {
        HyprlandScreenPower {
            onActionDone: (id, on, problem) => root.actionDone(id, on, problem)
        }
    }

    property Component _wlopmComponent: Component {
        WlopmScreenPower {
            onActionDone: (id, on, problem) => root.actionDone(id, on, problem)
        }
    }

    property Connections _events: Connections {
        target: root.backend === "hyprland" ? Hyprland : null
        function onRawEvent(event) {
            if (event.name === "monitoradded" || event.name === "monitoraddedv2"
                    || event.name === "monitorremoved" || event.name === "monitorremovedv2") {
                root._hyprland?.monitorEvent();
                root.read();
            }
        }
    }

    property Connections _screens: Connections {
        target: root.backend === "wlopm" ? Quickshell : null
        function onScreensChanged() {
            root._wlopm?.monitorEvent();
            root.read();
        }
    }

    Component.onCompleted: {
        if (hyprland) {
            _hyprland = _hyprlandComponent.createObject(root);
            _hyprland.read();
        } else {
            // Its first reading says whether wlopm is there
            _wlopm = _wlopmComponent.createObject(root, { wlopm: wlopm });
            _wlopm.read();
        }
    }
}
