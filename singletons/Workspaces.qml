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
        return workspace.id < 0;
    }

    function isSpecialVisible(workspace) {
        for (var monitor in _activeSpecials)
            if (_activeSpecials[monitor] === workspace.name)
                return true;
        return false;
    }

    function activate(workspace) {
        workspace.activate();
    }

    // Hyprland with a Lua config (hyprland.lua, 0.5x) takes a Lua expression as the
    // dispatch, through the hl.dsp.* API — scripts/logout.sh relies on it too. A classic
    // hyprland.conf setup would need the old "togglespecialworkspace <name>" form instead.
    function toggleSpecial(workspace) {
        Hyprland.dispatch("hl.dsp.workspace.toggle_special(" + luaString(workspace.name.replace(/^special:/, "")) + ")");
    }

    // A Lua string literal: the name goes into Lua code, so a quote or backslash in it
    // must not end the string or change the expression
    function luaString(text) {
        return "\"" + text.replace(/\\/g, "\\\\").replace(/"/g, "\\\"").replace(/\n/g, "\\n") + "\"";
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "activespecial")
                return;
            var args = event.parse(2);
            var specials = Object.assign({}, _activeSpecials);
            specials[args[1]] = args[0];
            _activeSpecials = specials;
        }
    }
}
