import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons
import qs.singletons.hardware
import qs.singletons.network

// What the suites of one process share, read for SharedState's check: Config's stored fields
// (the module lists turned on and off and the acknowledgements among them), Profiles'
// profiles, globals, active profiles and what it is told (screen locked, simulated facts,
// open panels), the module lists the core reads (ModuleLists: the host's widget, setting and
// fact lists), the toasts' state, the settings pages a provider added, the Theme switches
// suites flip and Notifier's record mode — and, in a process where a suite names them, the
// network's and the GPUs' state (building those starts their readers, so a process whose
// suites never name them does not build them).
//
// Not read: the module host (Modules) — only suites with a process of their own reach it,
// and they are not checked; building it would start the host everywhere. tests.qml hands
// this to SharedState.
QtObject {
    id: reader

    // The singletons read only where a suite of this process names them: name → its keys
    readonly property var _named: ({
        "WifiManager": () => ({ "WifiManager.wifiNetworks": WifiManager.wifiNetworks,
                                "WifiManager.connecting": WifiManager.connecting,
                                "WifiManager.connectingTo": WifiManager.connectingTo }),
        "NetworkProfiles": () => ({ "NetworkProfiles.profiles": NetworkProfiles.profiles,
                                    "NetworkProfiles.wifi": NetworkProfiles.wifi,
                                    "NetworkProfiles.savesReconnecting": NetworkProfiles.savesReconnecting,
                                    "NetworkProfiles.pendingUndo": NetworkProfiles.pendingUndo }),
        "VpnManager": () => ({ "VpnManager.withNetworks": VpnManager.withNetworks,
                               "VpnManager.fakeProvider": VpnManager._fakeProvider !== null }),
        "VpnLockdown": () => ({ "VpnLockdown.networks": VpnLockdown.networks,
                                "VpnLockdown.extraServers": VpnLockdown.extraServers,
                                "VpnLockdown.state": VpnLockdown.state }),
        "GpuDevices": () => ({ "GpuDevices.cards": GpuDevices.cards })
    })
    // Which of them the suites selected here name (read once, from their files)
    property var _namedHere: null

    function _suitesHere() {
        const names = Quickshell.env("H2S_TEST_SUITES");
        return typeof names === "string" && names !== "" ? names.split(":") : null;
    }

    function _findNamed() {
        const suites = _suitesHere();
        // All suites at once (no selection): every one is read
        if (suites === null)
            return Object.keys(_named);
        const found = new Set();
        for (const suite of suites) {
            _suiteFile.path = Quickshell.shellDir + "/tests/" + suite + ".qml";
            _suiteFile.reload();
            const text = _suiteFile.text();
            for (const name of Object.keys(_named))
                if (new RegExp("\\b" + name + "\\.").test(text))
                    found.add(name);
        }
        return Array.from(found);
    }

    property FileView _suiteFile: FileView {
        blockAllReads: true
        printErrors: false
    }

    // value → text, for comparing: JSON where it can be, else its string (a QObject, a cycle)
    function _text(value) {
        if (typeof value === "function")
            return "function";
        try {
            const text = JSON.stringify(value);
            return text === undefined ? String(value) : text;
        } catch (error) {
            return String(value);
        }
    }

    // An object's properties, as "<prefix>.<name>": every one that is not a function or an
    // underscore's, one level into the objects it holds (Config.gcal and its kind)
    function _properties(object, prefix, into, depth) {
        for (const name of Object.keys(object)) {
            if (name.startsWith("_") || name === "objectName")
                continue;
            let value;
            try {
                value = object[name];
            } catch (error) {
                continue;
            }
            if (typeof value === "function")
                continue;
            if (depth > 0 && value !== null && typeof value === "object" && !Array.isArray(value) && typeof value.objectName === "string")
                _properties(value, prefix + "." + name, into, depth - 1);
            else
                into[prefix + "." + name] = _text(value);
        }
        return into;
    }

    // The shared state now: { key: text }
    function snapshot() {
        const state = _properties(Config, "Config", {}, 1);
        state["Config.acknowledgedModulesText"] = _text(Config.acknowledgedModulesText);
        state["Profiles.profiles"] = _text(Profiles.profiles);
        state["Profiles.globals"] = _text(Profiles.globals);
        state["Profiles.activeProfiles"] = _text(Profiles.activeProfiles);
        state["Profiles.screenLocked"] = _text(Profiles.screenLocked);
        state["Profiles.simulated"] = _text(Profiles.simulated);
        state["Profiles.openPanels"] = _text(Profiles._openPanels);
        for (const name of ["widgetEntries", "settingEntries", "factTypes", "factValues", "settled"])
            state["ModuleLists." + name] = _text(ModuleLists[name]);
        for (const name of ["instantAnimations", "reduceMotion", "nerdFontWarningDismissed"])
            state["Theme." + name] = _text(Theme[name]);
        state["Notifier.recordOnly"] = _text(Notifier.recordOnly);
        state["Toasts.screensOverride"] = _text(Toasts.screensOverride);
        state["Toasts.toastState"] = _text(Toasts.toastState);
        state["Shell.settingsPageIds"] = _text(Shell.settingsPageIds);
        if (_namedHere === null)
            _namedHere = _findNamed();
        for (const name of _namedHere) {
            const values = _named[name]();
            for (const key of Object.keys(values))
                state[key] = _text(values[key]);
        }
        return state;
    }

    // The startup's own writes are made: the config read and the profiles seeded (the private
    // home of the runners has no config file, so Profiles seeds one)
    function startupWritten() {
        return Config.ready && Config.profiles !== "";
    }
}
