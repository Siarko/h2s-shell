pragma Singleton

import Quickshell
import Quickshell.Hyprland

Singleton {
    property var workspaces: Hyprland.workspaces
    property var focused: Hyprland.focusedWorkspace

    function activate(workspace) {
        workspace.activate();
    }
}
