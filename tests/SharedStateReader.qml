import QtQuick
import qs.singletons

// What the suites of one process share, read for SharedState's check: Config's stored fields
// (the module lists turned on and off and the acknowledgements among them), Profiles'
// profiles, globals, active profiles and what it is told (screen locked, simulated facts,
// open panels), the module lists the core reads (ModuleLists: the host's widget, setting and
// fact lists), the Theme switches suites flip and Notifier's record mode. The Modules
// singleton is never read: building it would start the module host in processes that never
// use it. tests.qml hands this to SharedState.
QtObject {
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
        return state;
    }

    // The startup's own writes are made: the config read and the profiles seeded (the private
    // home of the runners has no config file, so Profiles seeds one)
    function startupWritten() {
        return Config.ready && Config.profiles !== "";
    }
}
