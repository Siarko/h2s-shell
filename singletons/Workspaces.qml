pragma Singleton

import Quickshell
import Quickshell.Hyprland

Singleton {
    property var workspaces: Hyprland.workspaces
    property var focused: Hyprland.focusedWorkspace

    function isSpecial(workspace) {
        return workspace.id < 0
    }

    function activate(workspace) {
        workspace.activate()
    }
}
