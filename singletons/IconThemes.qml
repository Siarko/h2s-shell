pragma Singleton

import QtQuick
import Quickshell
import qs.singletons.io

// The icon theme setting (`appearance.iconTheme`) and what it takes to apply it.
//
// Quickshell sets the icon theme once, at launch, from QS_ICON_THEME; the shell is started
// through scripts/launch.sh, which reads the setting and sets it. So a changed setting
// applies on a restart, through the same script (restart()). The script alone decides
// which themes count and what "Automatic" (an empty setting) picks; this asks it.
Singleton {
    id: root

    // The installed icon themes, as the script lists them; read by refresh()
    property var installed: []
    // The theme the shell runs with; empty when it was started without the script
    readonly property string current: Quickshell.env("QS_ICON_THEME") ?? ""
    // Whether the shell was started through scripts/launch.sh, which marks it so: without
    // it the setting cannot apply, and the HUD shows a banner saying why (Hud.qml, StartupWarning)
    readonly property bool launchedByScript: Quickshell.env("H2S_SHELL_LAUNCHER") === "1"
    // The banner closed, for this run of the shell
    property bool launchWarningDismissed: false

    readonly property string setting: Profiles.value("appearance.iconTheme") ?? ""
    // The setting as it was when the shell started — what `current` came from
    property string _settingAtStart: ""
    property bool _startKnown: false
    readonly property bool _configReady: Config.ready
    on_ConfigReadyChanged: _noteStart()
    Component.onCompleted: _noteStart()
    function _noteStart() {
        if (_startKnown || !Config.ready)
            return;
        _settingAtStart = setting;
        _startKnown = true;
    }

    // The setting is not what the shell runs with: it applies on a restart. A theme that
    // is installed is compared with the one in use; "Automatic", or a name not installed,
    // with the setting the shell started with (what the script made of it is `current`)
    readonly property bool restartNeeded: {
        if (setting !== "" && installed.includes(setting))
            return setting !== current;
        return _startKnown && setting !== _settingAtStart;
    }

    readonly property string _script: Quickshell.shellDir + "/scripts/launch.sh"

    function refresh() {
        _list.request();
    }

    function restart() {
        Quickshell.execDetached(["bash", _script, "--restart"]);
    }

    // Sample icons by theme, { theme: [{ name, file }] }, filled by preview(): the running
    // shell can only load its own theme's icons, so the files are found by the script and
    // shown as images
    property var previews: ({})
    property string _previewing: ""
    property var _previewQueue: []

    function preview(theme) {
        if (theme === "" || theme in previews || theme === _previewing || _previewQueue.includes(theme))
            return;
        _previewQueue = _previewQueue.concat([theme]);
        _nextPreview();
    }

    function _nextPreview() {
        if (_previewing !== "" || _previewQueue.length === 0)
            return;
        _previewing = _previewQueue[0];
        _previewQueue = _previewQueue.slice(1);
        _preview.command = ["bash", _script, "--preview", _previewing];
        _preview.request();
    }

    CommandQuery {
        id: _preview
        onDone: lines => {
            const icons = lines.map(line => line.split("\t"))
                .filter(parts => parts.length === 2)
                .map(parts => ({ name: parts[0], file: parts[1] }))
                .sort((a, b) => a.name.localeCompare(b.name));
            const previews = Object.assign({}, root.previews);
            previews[root._previewing] = icons;
            root.previews = previews;
            root._previewing = "";
            root._nextPreview();
        }
    }

    CommandQuery {
        id: _list
        command: ["bash", root._script, "--list"]
        onDone: lines => root.installed = lines.map(line => line.trim())
    }
}
