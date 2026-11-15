pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The shell's modules (docs/plans/modules.md): one ModuleHost fed from the environment the
// launcher builds — H2S_SHELL_MODULES, the canonical module directories in search order, and
// H2S_SHELL_SAFE_MODE=1 after the shell died quickly twice (scripts/launch.sh) — loaded as
// soon as this singleton exists. shell.qml touches it before it builds the bars, so the
// modules are known (and the ones without required programs running) before the first frame.
//
// A failure inside the host is caught and leaves the shell without modules (hostError, and a
// line in the log): the host must never be what keeps the bar or the lock screen from coming
// up. No module file is ever imported statically — a broken one would fail the whole config.
//
// Read-only over IPC:
//   qs ipc call modules list     JSON: { api, safeMode, hostError, checkingPrograms,
//                                ignoredEntries, modules: [status…] } (ModuleRules.statusOf)
Singleton {
    id: root

    readonly property ModuleHost host: _host
    readonly property string apiVersion: _host.apiVersion
    readonly property bool safeMode: _host.safeMode
    readonly property string hostError: _host.hostError
    readonly property var statuses: _host.statuses
    readonly property var widgetEntries: _host.widgetEntries
    readonly property var settingsPages: _host.settingsPages
    readonly property var settingEntries: _host.settingEntries
    readonly property var factTypes: _host.factTypes
    readonly property int generation: _host.generation

    function slotContributions(name) {
        return _host.slotContributions(name);
    }

    function status(id) {
        return _host.status(id);
    }

    function setEnabled(id, enabled) {
        return _host.setEnabled(id, enabled);
    }

    function isEnabled(id) {
        return _host.isEnabled(id);
    }

    ModuleHost {
        id: _host
    }

    Component.onCompleted: {
        try {
            const value = Quickshell.env("H2S_SHELL_MODULES");
            const safe = Quickshell.env("H2S_SHELL_SAFE_MODE") === "1";
            _host.load(typeof value === "string" ? value : "", { safeMode: safe });
            if (safe)
                console.warn("[Modules] safe mode (the shell died quickly twice): no module is loaded");
        } catch (error) {
            console.error("[Modules] the module host failed, running without modules:", error);
        }
    }

    IpcHandler {
        target: "modules"

        function list(): string {
            try {
                return JSON.stringify(_host.describe());
            } catch (error) {
                return JSON.stringify({ hostError: String(error), modules: [] });
            }
        }
    }
}
