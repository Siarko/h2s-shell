pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    property var workspaces: Hyprland.workspaces
    property var focused: Hyprland.focusedWorkspace

    // monitorName -> active special workspace name ("" when none)
    property var _activeSpecials: ({})

    function isSpecial(workspace) {
        return workspace.id < 0
    }

    function isSpecialVisible(workspace) {
        for (var monitor in _activeSpecials)
            if (_activeSpecials[monitor] === workspace.name)
                return true
        return false
    }

    function activate(workspace) {
        workspace.activate()
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "activespecial") return
            var args = event.parse(2)
            var specials = Object.assign({}, _activeSpecials)
            specials[args[1]] = args[0]
            _activeSpecials = specials
        }
    }
}
