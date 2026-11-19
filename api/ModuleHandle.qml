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

    // Set by the host when it makes the handle, read-only from then on: a module cannot
    // turn another's handle into its own. `host` is the shell's and deprecated for modules
    // (API 1.19): a module's code reading `module.host` has it listed in its `deprecations`
    // (ModuleSourceRules.codeDeprecations); it becomes `_host` with the shell's next tightening
    readonly property string moduleId: ""
    readonly property var host: null

    // ---- Who it is ---- (moduleId above: its id; QML reserves the name `id`)
    // Its status (Modules.status: state, errors, warnings, …), as `qs ipc call modules list`
    readonly property var status: host ? (host.statuses.find(entry => entry.id === moduleId && entry.state !== "duplicate") ?? null) : null
    // True while the module is enabled and loaded: everything that acts follows this
    readonly property bool active: host ? host.activeIds.includes(moduleId) : false
    // (API 1.15) The object made from its manifest's `main` while the module is active: null
    // while it is off, before the main exists and while the main itself is being built, and
    // for a module without one. Set by the host right after the main is created, so before
    // any of its widgets, popups or pages are built; cleared before the main is destroyed, so
    // views read through it allowing null (`module.main?.client`). Turned on again, it is a
    // new object. The host's to set (ModuleHost.mainOf): not writable through the handle.
    readonly property var main: host ? host.mainOf(moduleId, host.mainsRevision) : null

    // (API 1.18) The modules its manifest `uses`, each as the object that module offers
    // (its main's `exports`), frozen: { <id>: exports object } — `module.uses.tailscale`. Set
    // just before the module is turned on (before its main is made and its views built) and
    // kept, the same object, until it is turned on again: a provider turned off or reloaded
    // first turns this module off (missing-module), and its main is destroyed only after this
    // module's main is gone, so what this module's main and views read — bindings, their
    // Component.onDestruction — is there for as long as they live. Empty for a module never
    // turned on. Nothing else of a provider is given. The host's to set (ModuleHost.usesOf):
    // not writable through the handle.
    readonly property var uses: host ? host.usesOf(moduleId, host.usesRevision) : Object.freeze({})

    // (API 1.2) The machine woke from sleep (logind's PrepareForSleep(false)), told only while
    // the module is active: re-read what may have changed while it slept, restart what a
    // long sleep broke — instead of a clock that watches for jumps
    signal resumed()
    readonly property string directory: status?.directory ?? ""
    readonly property string version: status?.version ?? ""
    readonly property string name: status?.name ?? ""
    // (1.26) Its icon as the shell draws it, frozen: { kind: "glyph" | "svg" | "image", glyph,
    // url (the file's file:// URL, "" for a glyph), colors: "theme" | "own" }, or null — none
    // in the manifest, a wrong one, or one that could not be drawn (the error is in its
    // status). The shell draws it itself (components/ModuleIcon.qml): the first letter of the
    // name where there is none
    readonly property var icon: {
        const shown = host && ModuleRules.has(host.icons ?? {}, moduleId) ? host.icons[moduleId] : null;
        return shown ? Object.freeze(Object.assign({}, shown)) : null;
    }
    // Its manifest as the shell read and checked it (a frozen copy)
    readonly property var manifest: {
        const read = host && directory !== "" ? host.manifestOf(directory) : null;
        try {
            return read ? Object.freeze(JSON.parse(JSON.stringify(read))) : null;
        } catch (error) {
            return null;
        }
    }

    // ---- Its programs (API 1.9) ----
    // Every program its manifest names (requires.programs, optionalPrograms), as the shell
    // found it on PATH and judged it (ModuleRules.programVerdict), frozen:
    //   { <name>: { path: the absolute path ("" — not found), trusted, reason } }
    // `trusted`: only root can change what runs (the path walked as the kernel resolves it:
    // every directory passed, the directory of each link met and the real file root's and
    // writable by root alone; a root-owned, daemon-run Nix store counts as root's). A read
    // that failed is untrusted. A new object only when something in it changed.
    // (API 1.10) In module test mode, when its manifest names testPrograms: every program is
    // taken from that directory — { path: "<directory>/<testPrograms>/<name>", trusted: true,
    // reason: "test stand-in" }, or path "" when it is not there — and never from PATH.
    readonly property var _verdicts: ModuleRules.programSource(host?.testMode === true, manifest?.testPrograms) === "test"
        ? (host?.testProgramVerdicts?.[moduleId] ?? {}) : (host?.programVerdicts ?? {})
    readonly property string _programsText: {
        const verdicts = _verdicts;
        const own = {};
        for (const name of _programNames) {
            const verdict = verdicts[name];
            if (verdict)
                own[name] = { path: verdict.path, trusted: verdict.trusted === true, reason: verdict.reason };
        }
        return JSON.stringify(own);
    }
    readonly property var programs: {
        const parsed = JSON.parse(_programsText);
        for (const name of Object.keys(parsed))
            Object.freeze(parsed[name]);
        return Object.freeze(parsed);
    }
    // Every program it names has a verdict (the module loads only once they have)
    readonly property bool programsReady: manifest !== null && _programNames.every(name => _verdicts[name] !== undefined)

    // Looks its programs up again (installed or changed since): at most once every 2 s — a
    // call sooner is done when the 2 s are over. The verdicts stay until the new ones come.
    // The shell does this itself after the machine wakes, before `resumed()`.
    function recheckPrograms() {
        const wait = ModuleRules.recheckDelay(_lastRecheck, Date.now(), ModuleRules.recheckMinMs);
        if (wait === 0) {
            _recheckNow();
        } else if (!_recheckTimer.running) {
            _recheckTimer.interval = wait;
            _recheckTimer.start();
        }
    }

    readonly property var _programNames: (manifest?.programs ?? []).concat(manifest?.optionalPrograms ?? [])
    property real _lastRecheck: 0

    function _recheckNow() {
        _lastRecheck = Date.now();
        host?.recheckPrograms(moduleId);
    }

    property Timer _recheckTimer: Timer {
        onTriggered: root._recheckNow()
    }

    // ---- Running as administrator (API 1.11) ----
    // `privileged.start(argv, options)` runs a command as root through pkexec, in
    // the shell's one queue (singletons/PrivilegedRuns.qml; Api.qml says what it does). The
    // shell knows the module by this handle: it is not told.
    readonly property QtObject privileged: QtObject {
        // pkexec and a trusted `timeout` found: { available, reason, pkexec, timeout }
        readonly property var _tools: PrivilegedRules.availability({
            testMode: root.host?.testMode === true,
            standIn: root.host?.testProgramVerdicts?.[root.moduleId]?.pkexec?.path ?? "",
            pkexecKnown: PrivilegedRuns.known, pkexec: PrivilegedRuns.pkexec, pkexecReason: PrivilegedRuns.pkexecReason,
            timeoutKnown: CommandTools.known, timeout: CommandTools.timeout
        })
        readonly property bool available: _tools.available
        readonly property string unavailableReason: _tools.reason

        function start(argv, options) {
            if (root._privilegedKey === "")
                root._privilegedKey = PrivilegedRuns.newOwnerKey();
            // argv is read once, inside: the words judged are the ones that run
            return PrivilegedRuns.start(root, argv, options, {
                testMode: root.host?.testMode === true, tools: _tools
            });
        }
    }

    // What PrivilegedRuns knows its runs by ("" until the first)
    property string _privilegedKey: ""
    // Turned off: its runs leave the queue, the started ones are cancelled, nothing is called
    onActiveChanged: {
        if (!active && _privilegedKey !== "")
            PrivilegedRuns.ownerGone(_privilegedKey);
        if (!active) {
            _logWritten.clear();
            FileChooser.ownerGone(root);
        }
    }

    // ---- The file chooser (API 1.17) ----
    // `chooseFiles(options, done)` asks the user for files or a folder in the system's dialog,
    // hosted by the shell (singletons/FileChooser.qml; Api.qml says what it does). Closed, and
    // `done` dropped, when the module is turned off.
    function chooseFiles(options, done) {
        return FileChooser.choose(root, options, done, Api.system.home);
    }

    // ---- Its data directory (API 1.13) ----
    // "<dataHome>/h2s-shell/module-data/<id>", made private (700) by the shell before the
    // module loads; "" when it could not be (a warning in its status says so) — or, in module
    // test mode, the same below the shell's private temporary home. The user can write it:
    // nothing in it may be run as root
    readonly property string dataDirectory: ModuleRules.has(host?.dataDirectories ?? {}, moduleId) ? String(host.dataDirectories[moduleId]) : ""

    // A file of the module as a URL ("icons/x.svg" → file:///…/icons/x.svg)
    function url(relative) {
        return directory === "" ? "" : ModuleFileRules.fileUrl(directory, String(relative ?? ""));
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

    // ---- Its bar widgets' presets (API 1.3; WidgetPresets, the shared library) ----
    // A bar widget gets the name of its entry's preset as `preset`, its settings pane as
    // `presetName`; these read and write a key of such a preset. Its own widget types only
    // (a type its manifest's `widgets` declares). A convention between cooperating modules, not a
    // security boundary: a module runs in the shell's process.

    // True when `type` is one of its loaded widget types
    function _ownWidgetType(type) {
        return moduleId !== "" && WidgetRegistry.moduleOf(String(type ?? "")) === moduleId;
    }

    // A key of a preset, or the manifest's presetDefaults when the preset does not set it (or
    // the entry has none: preset ""). Undefined for another module's or the core's type. Call
    // it in a binding: it follows edits.
    function presetValue(type, preset, key) {
        return _ownWidgetType(type) ? WidgetPresets.value(String(type), String(preset ?? ""), String(key ?? "")) : undefined;
    }

    // Writes a key of one of its existing presets (plain JSON; undefined removes it, back to the
    // default). It never creates a preset (the section editor does). The preset as it would be
    // after the write is checked as a whole: names as keys, at most 50 keys and 16 KiB.
    // → "" when written, else why not (another's type, no such preset, a bad key or value)
    function setPresetValue(type, preset, key, newValue) {
        if (!_ownWidgetType(type))
            return "\"" + type + "\" is not one of " + moduleId + "'s widget types";
        const name = String(preset ?? "");
        if (!WidgetPresets.validName(name))
            return "no preset to write to";
        if (!WidgetPresets.exists(String(type), name))
            return "no preset \"" + name + "\" of " + type;
        const keyName = String(key ?? "");
        if (!/^[A-Za-z_][A-Za-z0-9_]{0,63}$/.test(keyName) || keyName === "__proto__")
            return "the key " + JSON.stringify(keyName) + " is not a name";
        const merged = WidgetPresets.stored(String(type), name);
        if (newValue === undefined)
            delete merged[keyName];
        else
            merged[keyName] = newValue;
        const problem = ModuleManifestRules.presetDefaultsProblem(merged);
        if (problem !== "")
            return problem;
        WidgetPresets.set(String(type), name, keyName, newValue);
        return "";
    }

    // ---- Facts (its own: <id>.*, declared in its manifest) ----

    // Sets one of its facts ("ready" or "<id>.ready") for profile conditions, checked against
    // its declared type; null: not known. Only while active. → "" when set, else why not.
    // Facts are for slow-changing state (connected, on a network): every change re-resolves
    // the profiles and re-evaluates every setting binding in the shell, so set one when its
    // value changes, never on a clock. Setting the value it already has does nothing.
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

    // A notification under the module's name (Notifier.send's options; API 1.12: format
    // "plain" for text from outside, Api.qml says what it does)
    function notify(summary, options) {
        Notifier.send(String(summary), Object.assign({ appName: name || moduleId }, ModuleRules.moduleNotifyOptions(options)));
    }

    // (API 1.12) A line in the shell's log, "[<id>] <text>": level "debug" (written only
    // with the shell's debug setting on), "info", "warn" or "error" (another word: "info");
    // the text on one line, cut at 1000 characters. With `key` (any short text naming what
    // the line is about) the line is written only when its level or text differs from the
    // one last written for that key — a failure logged once, again when its reason changes,
    // and its recovery — instead of once per attempt. → true when it was written (a debug
    // line while the setting is off is not, and is not remembered for its key). The keys are
    // forgotten when the module is turned off; at most 256 are kept.
    function log(level, text, key) {
        const entry = ModuleRules.logEntry(moduleId, level, text, key, _logWritten, Profiles.value("general.debug") === true);
        if (!entry.write)
            return false;
        if (entry.key !== "") {
            // Re-set at the end, so the oldest written goes first
            _logWritten.delete(entry.key);
            _logWritten.set(entry.key, entry.memo);
            if (_logWritten.size > ModuleRules.maxLogKeys)
                _logWritten.delete(_logWritten.keys().next().value);
        }
        if (entry.level === "error")
            console.error(entry.line);
        else if (entry.level === "warn")
            console.warn(entry.line);
        else if (entry.level === "info")
            console.info(entry.line);
        else
            console.log(entry.line);
        return true;
    }

    // Each log key → the level and text it wrote last (ModuleRules.logEntry's memo)
    property var _logWritten: new Map()

    // Opens one of its settings pages: "" its page "<id>", "<name>" → "<id>.<name>"
    function openSettings(page) {
        const pageId = !page ? moduleId : String(page).startsWith(moduleId) ? String(page) : moduleId + "." + page;
        Shell.openSettings(pageId);
    }

    // (1.27) Marks an item's card: the card shows the module's icon at the end of its name's
    // line, closed and open, with `label` as the icon's accessible name and tooltip, shown as
    // "<module's name>: <label>" (plain text, one line, at most 40 characters). `path` a card's
    // path whose row takes marks (Api.anchors' `marks`: the saved Wi-Fi networks' and the
    // wired profiles' cards), `itemId` the item's id as in the card's context (`networkId`).
    // → true when kept; false while the module is off, and for a path that takes no marks,
    // an id that is not a text or a label that is not one, or the 201st mark on a path —
    // then a warning in its status, one line per kind of refusal. Set again for the same item, the label is replaced. A
    // card shows the first three modules' marks, in module id order. A mark does nothing on
    // a click. The shell does not store marks: they go when the module goes off, and it sets
    // them again when it starts
    function setMark(path, itemId, label) {
        return host ? host.setMark(moduleId, path, itemId, label) === true : false;
    }

    // (1.27) Takes the module's mark off an item's card
    function clearMark(path, itemId) {
        host?.clearMark(moduleId, path, itemId);
    }

    // Something that failed at run time, shown among its status's errors (Settings → Modules)
    function reportError(text) {
        host?.reportError(moduleId, text);
    }
}
