pragma Singleton

import Quickshell
import QtQuick
import qs.singletons.screen

// The monitors and their power: which are connected (by their ids, MonitorRules), whether
// each is on, and turning one off or on. Only the compositor can cut one output's power, so
// it takes a backend (singletons/screen/ScreenPowerBackend.qml picks it): Hyprland's own
// dispatch where the shell runs under Hyprland, elsewhere `wlopm` when it is on PATH;
// without either, `canPowerOff` is false, nothing is read or asked, and `unavailable` says
// why ({ reason, hint }) for the page.
//
// A failed reading or action leaves a monitor's power "unknown", never "off".
Singleton {
    id: root

    readonly property string backend: _backend.backend
    readonly property bool canPowerOff: _backend.canPowerOff
    readonly property var unavailable: _backend.unavailable

    // [{ connector, id, base, make, model, serial, builtIn, power: "on" | "off" | "unknown" }]
    readonly property var monitors: _backend.monitors
    readonly property var twins: _backend.twins
    readonly property bool monitorsRead: _backend.monitorsRead

    signal actionDone(string id, bool on, string problem)

    function read() {
        _backend.read();
    }

    // The monitor with this id off (false) or on (true); answered by actionDone
    function setPower(id, on) {
        _backend.setPower(id, on);
    }

    property ScreenPowerBackend _backend: ScreenPowerBackend {
        onActionDone: (id, on, problem) => root.actionDone(id, on, problem)
    }
}
