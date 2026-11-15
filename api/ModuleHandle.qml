import QtQuick
import qs.singletons

// A module's handle (module API 1.0): what the shell gives a module of itself. One per
// module for the shell's life, made by the host. A module's file gets it
//   - as its `module` property, when it declares one (`property var module`): the host sets
//     it on the main, and the core on every object it builds from the module's manifest —
//     bar widgets, popup panels, widget settings panes, settings pages, slot contributions —
//     before their Component.onCompleted;
//   - anywhere else (its singletons, objects it makes itself): Api.moduleAt(Qt.resolvedUrl(".")),
//     the handle of the module whose directory holds the file.
//
// THE CONTRACT FOR TURNING A MODULE OFF: while it is off (Settings → Modules, `modules
// setEnabled`), nothing of it may act. The host destroys its main and everything the core built
// from its manifest; what the module's singletons hold survives (QML cannot unload them). So
// everything that acts — an IpcHandler, a Process, a Timer, a VPN provider, a registration
// anywhere — lives under the main object, or binds to `module.active` (a singleton's Timer:
// `running: module.active && …`). Turned on again, a new main is made next to the singletons'
// old state: a singleton resets what it needs on `activeChanged`.
//
// A module's IpcHandler targets are "<id>" or "<id>.<name>" (the core's are reserved ids).
QtObject {
    id: root

    // Set by the host
    property string moduleId: ""
    property var host: null

    // ---- Who it is ---- (moduleId above: its id; QML reserves the name `id`)
    // Its status (Modules.status: state, errors, warnings, …), as `qs ipc call modules list`
    readonly property var status: host ? (host.statuses.find(entry => entry.id === moduleId && entry.state !== "duplicate") ?? null) : null
    // True while the module is enabled and loaded: everything that acts follows this
    readonly property bool active: host ? host.activeIds.includes(moduleId) : false
    readonly property string directory: status?.directory ?? ""
    readonly property string version: status?.version ?? ""
    readonly property string name: status?.name ?? ""
    // Its manifest as the shell read and checked it (a frozen copy)
    readonly property var manifest: {
        const read = host && directory !== "" ? host.manifestOf(directory) : null;
        try {
            return read ? Object.freeze(JSON.parse(JSON.stringify(read))) : null;
        } catch (error) {
            return null;
        }
    }

    // A file of the module as a URL ("icons/x.svg" → file:///…/icons/x.svg)
    function url(relative) {
        return directory === "" ? "" : ModuleRules.fileUrl(directory, String(relative ?? ""));
    }

    // ---- Settings (its own: mod.<id>.*, declared in its manifest) ----

    // The full key of one of its settings ("greeting" → "mod.<id>.greeting"); "" when not its
    function settingKey(key) {
        return ModuleRules.ownSettingKey(moduleId, key);
    }

    // A setting's value, as the profiles in effect have it (Profiles.value). Its own keys
    // only ("greeting" or "mod.<id>.greeting"); undefined otherwise, and while it is off
    function value(key) {
        const full = settingKey(key);
        return full !== "" ? Profiles.value(full) : undefined;
    }

    // Writes one of its settings the way the shell writes from outside a settings page
    // (Profiles.writeInEffect: the global value if pinned, else the profile it comes from now,
    // else Full), checked against its declaration. → "" when written, else why not
    function setValue(key, newValue) {
        const full = settingKey(key);
        if (full === "")
            return "\"" + key + "\" is not one of " + moduleId + "'s settings";
        const entry = SettingsSchema.entry(full);
        if (!entry)
            return full + " is not declared (or the module is off)";
        const problem = ModuleRules.settingValueProblem(entry, newValue);
        if (problem !== "")
            return full + ": " + problem;
        return Profiles.writeInEffect(full, newValue) === false ? full + ": no profile in effect to write it to" : "";
    }

    // ---- Facts (its own: <id>.*, declared in its manifest) ----

    // Sets one of its facts ("ready" or "<id>.ready") for profile conditions, checked against
    // its declared type; null: not known. Only while active. → "" when set, else why not
    function setFact(name, newValue) {
        return host ? host.setFact(moduleId, name, newValue) : "no host";
    }

    // Its facts as the profiles see them now
    readonly property var facts: {
        const all = host?.factValues ?? {};
        const own = {};
        for (const key of Object.keys(all)) {
            if (key.startsWith(moduleId + "."))
                own[key] = all[key];
        }
        return own;
    }

    // ---- Its store (data, not preferences: api/ModuleStore.qml) ----
    readonly property ModuleStore store: ModuleStore {
        moduleId: root.moduleId
    }

    // ---- The shell ----

    // A notification under the module's name (Notifier.send's options)
    function notify(summary, options) {
        Notifier.send(String(summary), Object.assign({ appName: name || moduleId }, options ?? {}));
    }

    // Opens one of its settings pages: "" its page "<id>", "<name>" → "<id>.<name>"
    function openSettings(page) {
        const pageId = !page ? moduleId : String(page).startsWith(moduleId) ? String(page) : moduleId + "." + page;
        Shell.openSettings(pageId);
    }

    // Something that failed at run time, shown among its status's errors (Settings → Modules)
    function reportError(text) {
        host?.reportError(moduleId, text);
    }
}
