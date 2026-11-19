pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import QtCore

// The shell's modules (notes/plans/modules.md): one ModuleHost fed from the environment the
// launcher builds — H2S_SHELL_MODULES, the canonical module directories in search order, and
// H2S_SHELL_SAFE_MODE=1 after the shell died quickly twice (scripts/launch.sh) — loaded as
// soon as this singleton exists (load() only starts processes: nothing is read here). shell.qml
// touches it before it builds the bars. The registries the lock screen's settings go through
// (WidgetRegistry, SettingsSchema, ProfileRules.factTypes, Profiles' facts) read ModuleLists,
// which this feeds — never this singleton; the settings window's pages, ModuleSlot and the VPN
// slots read it here.
//
// The start guard (ModuleHost.guardFile, ModuleFileRules.startGuardScript):
// $XDG_RUNTIME_DIR/h2s-shell-module-starts counts Quickshell's relaunches of this process after
// a crash — what the launcher cannot see — before any module loads; a start that lives 30 s
// (the launcher's quick-death window; H2S_SHELL_TEST_MODULE_GUARD_MS shortens it) sets it
// back to 0; two in a row → safe mode, its reason in `modules list` (safeModeReason, as for
// the launcher's own safe mode). Not under the test runners (Config.readOnly): they never write it.
//
// A failure inside the host is caught and leaves the shell without modules (hostError, and a
// line in the log): the host must never be what keeps the bar or the lock screen from coming
// up. No module file is ever imported statically — a broken one would fail the whole config.
//
// Over IPC:
//   qs ipc call modules list                 JSON: { api, safeMode, safeModeReason, hostError,
//                                            testMode, checkingPrograms, checkingFiles, startGuard,
//                                            ignoredEntries, modules: [status…] }
//   qs ipc call modules setEnabled <id> <on> turns a module on or off, as Settings → Modules
//                                            will (Config.disabledModules); "" or why not
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
    readonly property var factValues: _host.factValues
    readonly property var activeIds: _host.activeIds
    readonly property var slots: _host.slots
    readonly property int generation: _host.generation

    function slotContributions(name) {
        return _host.slotContributions(name);
    }

    // For a core place that takes one Component (or one URL) per module instead of a
    // ModuleSlot — the VPN slots after the merge (notes/plans/modules.md, "Module API 1.0")
    function slotComponent(slot, id) {
        return _host.slotComponent(slot, id);
    }

    function slotUrl(slot, id) {
        return _host.slotUrl(slot, id);
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

    function handle(id) {
        return _host.handle(id);
    }

    function handleAt(url) {
        return _host.handleAt(url);
    }

    function reportError(id, text) {
        _host.reportError(id, text);
    }

    // The initial properties to give a Loader for a module's file: `module` (the handle of the
    // module whose file it is) and `extra`, of them the ones its root object declares
    function initialProperties(url, extra) {
        const owner = _host.handleAt(url);
        return owner ? _host.initialProperties(url, Object.assign({}, extra ?? {}, { module: owner })) : {};
    }

    ModuleHost {
        id: _host
    }

    // The plain lists the core's registries read (ModuleLists: they never touch this
    // singleton, so nothing the lock screen needs constructs or waits for the host)
    Binding { target: ModuleLists; property: "widgetEntries"; value: _host.widgetEntries }
    Binding { target: ModuleLists; property: "settingEntries"; value: _host.settingEntries }
    Binding { target: ModuleLists; property: "factTypes"; value: _host.factTypes }
    Binding { target: ModuleLists; property: "factValues"; value: _host.factValues }
    Binding { target: ModuleLists; property: "settled"; value: _host.settled }
    // Module test mode: notifications are recorded, never sent (Notifier.recorded) — except
    // in a test tree that asks for them on its private bus (TestSeams.moduleNotify)
    Binding { target: Notifier; property: "recordOnly"; value: _host.testMode && !TestSeams.moduleNotify }

    // Entering safe mode, once: a notification says so (`modules list` says why)
    property bool _safeModeNotified: false
    readonly property bool _inSafeMode: _host.safeMode
    on_InSafeModeChanged: _notifySafeMode()

    function _notifySafeMode() {
        if (!_host.safeMode || _safeModeNotified || Config.readOnly)
            return;
        _safeModeNotified = true;
        Notifier.send("Started without modules: " + (_host.safeModeReason || "safe mode"),
                      { body: "qs ipc call modules list tells more", urgency: "normal" });
    }

    Component.onCompleted: {
        try {
            const value = Quickshell.env("H2S_SHELL_MODULES");
            const safe = Quickshell.env("H2S_SHELL_SAFE_MODE") === "1";
            const runtime = Quickshell.env("XDG_RUNTIME_DIR");
            if (!Config.readOnly && typeof runtime === "string" && runtime.startsWith("/"))
                _host.guardFile = runtime + "/h2s-shell-module-starts";
            // The stores' directory, private before any module runs (api/ModuleStore.qml)
            if (!Config.readOnly)
                _host.storeDirectory = String(StandardPaths.writableLocation(StandardPaths.GenericConfigLocation)).replace(/^file:\/\//, "") + "/h2s_shell/modules";
            // The modules' data directories (module.dataDirectory): below the data home
            // (XDG_DATA_HOME, else ~/.local/share); in module test mode the host's own
            // temporary one instead
            if (!Config.readOnly)
                _host.dataRoot = SystemFactsRules.dataRoot(SystemFacts.dataHome);
            // Test seams (TestSeams): the guard's window, shortened by the lock test bed; a
            // directory put first on the file check's PATH (a `head` that hangs) and the
            // checks' deadline (tests/lock/tests/modules-hung.sh)
            if (TestSeams.moduleGuardMs > 0)
                _host.guardClearMs = TestSeams.moduleGuardMs;
            if (TestSeams.moduleCheckPath !== "")
                _host.checkEnvironment = { PATH: TestSeams.moduleCheckPath + ":" + (Quickshell.env("PATH") ?? "") };
            if (TestSeams.moduleCheckMs > 0)
                _host.checkTimeoutMs = TestSeams.moduleCheckMs;
            // Module test mode: on in a test tree only (TestSeams). Off is fixed by the load
            // itself; set here only when on, so tests-modules.qml can still turn it on for its
            // own load (this one names no module there)
            if (TestSeams.moduleTestMode)
                _host.setTestMode(true);
            _host.load(typeof value === "string" ? value : "", {
                safeMode: safe,
                safeModeReason: "the launcher started the shell in safe mode (H2S_SHELL_SAFE_MODE=1): it died within 30 s of starting twice in a row"
            });
            if (safe)
                console.warn("[Modules] safe mode (the shell died quickly twice): no module is loaded");
            _notifySafeMode();
        } catch (error) {
            console.error("[Modules] the module host failed, running without modules:", error);
        }
    }

    IpcHandler {
        target: "modules"

        function list(): string {
            try {
                return JSON.stringify(Object.assign(_host.describe(), { testSeams: TestSeams.inForce.slice() }));
            } catch (error) {
                return JSON.stringify({ hostError: String(error), modules: [] });
            }
        }

        function setEnabled(id: string, on: bool): string {
            if (!_host.statuses.some(status => status.id === id))
                return "No module \"" + id + "\"";
            _host.setEnabled(id, on);
            return "";
        }
    }
}
