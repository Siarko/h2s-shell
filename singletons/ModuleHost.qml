import QtQuick
import Quickshell
import Quickshell.Io
import qs.components

// The module host (docs/plans/modules.md): given the module directories, it reads each
// manifest at once (a blocking read of a regular file — FileView refuses anything else), checks
// it with ModuleRules, checks every file the module names (a process: resolved inside the
// module's directory, a regular file, not too large — before anything of the module is read or
// loaded), counts the start (the start guard, below), checks the programs the modules require
// (a process), creates each enabled, compatible module's `main` by URL inside a guard, and keeps
// every module's status, its handle (api/ModuleHandle.qml), its facts and the merged
// contributions as plain reactive lists. A module is "pending" until all of that has answered.
// Turning a module off (setEnabled, stored in Config.disabledModules) destroys its main, drops
// its contributions and facts and turns its handle's `active` off; on again, they come back.
//
// The shell's one instance is in Modules (the singleton, fed from the environment); the
// suites make their own (tests/ModulesTest.qml), so this takes its directories through load()
// and its start counter through `guardFile`, never from the environment.
//
// What the guard can and cannot contain (QML has no sandbox): a module file that does not
// compile, imports something missing or names a missing file → its Component is in Error,
// the module is "failed" with the error text; createObject returning null or throwing →
// "failed"; a file that is a link out of the module, a FIFO, a device or huge → never opened
// (the entry dropped, or the module failed for its main or qmldir). Not containable, and not
// even visible to the host: an exception thrown in a module's signal handler —
// Component.onCompleted included — or binding (the engine prints it and carries on: the
// module counts as loaded); anything a module's singletons do later (the API contract: what
// acts lives under the main or follows `module.active`); a module that blocks the event loop
// or crashes the process (the launcher's safe mode and the start guard are for that).
Scope {
    id: root

    // The module API this shell offers ("major.minor"; Api.version, ModuleRules.apiVersion)
    readonly property string apiVersion: ModuleRules.apiVersion
    // In safe mode: manifests are read, nothing is loaded. Asked for by load() (the
    // launcher's H2S_SHELL_SAFE_MODE=1) or decided by the start guard
    property bool safeMode: false
    // Why, when the start guard decided it ("" otherwise)
    property string safeModeReason: ""
    // The ids turned off (Config.disabledModules); a module is on unless listed
    readonly property var disabledIds: _plainList(Config.disabledModules)
    // Until the config is read the host cannot know which modules are off: none is
    // created before (one turned off because it misbehaves must not run even briefly)
    readonly property bool settingsKnown: Config.ready

    // The start guard's counter file ("" — the suites' default — no guard): before loading,
    // the host counts Quickshell's relaunches of this process after a crash in it
    // (ModuleRules.startGuardScript); cleared after guardClearMs; ModuleRules.guardLimit
    // relaunches in a row → safe mode
    property string guardFile: ""
    // The identity the guard counts under ("<pid>:<crash>"; "" — the process's own): the
    // suites' seam
    property string guardIdentity: ""
    property int guardClearMs: ModuleRules.guardClearMs
    // How long the file and program checks may take before what they did not answer counts
    // as failed (a hung directory on PATH must not leave a module pending for good)
    property int checkTimeoutMs: 5000

    // The canonical module directories given to load(), in search order, and the entries
    // that were not absolute paths
    property var directories: []
    property var ignoredEntries: []
    // One status per directory, in search order (ModuleRules.statusOf):
    // { id, name, version, api, description, directory, state, enabled, errors, warnings,
    //   missingPrograms, setupHints, shadowedBy }
    property var statuses: []
    // The loaded modules' contributions, merged (ModuleRules.merge): what the core's
    // registries read. Every file an absolute file:// URL; every entry has `module`.
    property var widgetEntries: []
    property var settingsPages: []
    property var settingEntries: []
    property var factTypes: []
    property var slots: ({})
    // The loaded modules' facts, { "<id>.<name>": plain value } (setFact; checked against
    // the declared type): what Profiles adds to its facts
    property var factValues: ({})
    // Set when the host itself failed: it then holds no module
    property string hostError: ""
    // Counts every change of the statuses and lists
    property int generation: 0
    readonly property bool checkingPrograms: _programCheck.running
    readonly property bool checkingFiles: _fileCheck.running
    // The ids of the modules loaded now (their handles' `active`): set before a main is
    // created, so the main sees itself active while it is built
    property var activeIds: []
    // The start guard's answer: { count, reason } (null before, or without a guard)
    property var guard: null
    // Each module's change of state goes to the log (the shell's host; the suites' are quiet)
    property bool logStates: true

    signal modulesChanged

    // Internal, per directory: { directory, manifest, compatible, errors (from the
    // manifest, API and files), warnings, shadowedBy, qmldirText, filesChecked,
    // mainFileError, main, component, mainError, state, facts, runtimeErrors }
    property var _records: []
    // What the program check found: name → true / false; and the ones it did not answer
    property var _programs: new Map()
    property var _programsTimedOut: []
    property bool _guardKnown: true
    property bool _askedSafeMode: false
    // id → handle (api/ModuleHandle.qml), made on first use, kept for the host's life
    property var _handles: new Map()
    // "slot|module|url" → a holder of the Component that slotComponent() hands out
    property var _slotHolders: new Map()

    // ---- Public ----

    // (Re)loads from `directoryList` (an array, or a colon-separated string as in
    // H2S_SHELL_MODULES). `options`: { safeMode }. Never throws: a failure of the host
    // itself unloads everything and is kept in hostError.
    function load(directoryList, options) {
        try {
            unload();
            hostError = "";
            _askedSafeMode = options?.safeMode === true;
            safeMode = _askedSafeMode;
            safeModeReason = _askedSafeMode ? (options?.safeModeReason ?? "asked for (H2S_SHELL_SAFE_MODE=1)") : "";
            const parsed = ModuleRules.moduleDirectories(directoryList);
            directories = parsed.directories;
            ignoredEntries = parsed.ignored;
            const records = parsed.directories.map(directory => _readModule(directory));
            const order = ModuleRules.precedence(records.map(record => ({ directory: record.directory, id: record.manifest.id })));
            records.forEach((record, index) => record.shadowedBy = order[index].shadowedBy);
            _records = records;
            _startGuard();
            _checkFiles();
            _apply();
        } catch (error) {
            _hostFailed(error);
        }
    }

    // Destroys every module's main and forgets them all
    function unload() {
        for (const record of _records)
            _destroyMain(record);
        _records = [];
        directories = [];
        ignoredEntries = [];
        activeIds = [];
        _publish();
    }

    // Turns a module on or off (Config.disabledModules; written to the config file unless
    // Config.readOnly). → true when the id is a module id
    function setEnabled(id, enabled) {
        if (typeof id !== "string" || !ModuleRules.idPattern.test(id))
            return false;
        const list = _plainList(Config.disabledModules).filter(entry => entry !== id);
        if (!enabled)
            list.push(id);
        // Turned on again: programs found missing before are looked for again (installed
        // since, perhaps)
        if (enabled) {
            for (const record of _records.filter(entry => entry.manifest.id === id)) {
                for (const program of record.manifest.programs ?? []) {
                    if (_programs.get(program) === false) {
                        _programs.delete(program);
                        _programsTimedOut = _programsTimedOut.filter(name => name !== program);
                    }
                }
            }
        }
        Config.disabledModules = list;
        _applyGuarded();
        return true;
    }

    function isEnabled(id) {
        return !disabledIds.includes(id);
    }

    // The status of the module with this id that counts (not one shadowed by it), or null
    function status(id) {
        return statuses.find(entry => entry.id === id && entry.state !== "duplicate") ?? null;
    }

    // The contributions to one slot: [{ module, slot, component }]
    function slotContributions(name) {
        return ModuleRules.slotContributions(slots, name);
    }

    // The object created from a loaded module's main, or null
    function mainObject(id) {
        const record = _record(id);
        return record?.state === "loaded" ? record.main ?? null : null;
    }

    // The checked manifest (ModuleRules.parseManifest, less what the file check dropped)
    // read from a directory, or null
    function manifestOf(directory) {
        return _records.find(record => record.directory === ModuleRules.canonicalPath(directory))?.manifest ?? null;
    }

    // The module's handle (api/ModuleHandle.qml: what the module API gives a module of
    // itself), or null for an id no module here has. One per id for the host's life, so a
    // handle kept across a disable and enable stays good (its `active` follows).
    function handle(id) {
        if (typeof id !== "string" || !_record(id))
            return null;
        if (_handles.has(id))
            return _handles.get(id);
        const component = Qt.createComponent(Qt.resolvedUrl("../api/ModuleHandle.qml"), Component.PreferSynchronous);
        if (component.status !== Component.Ready) {
            console.error("[Modules] the module handle does not load:", component.errorString());
            return null;
        }
        const made = component.createObject(root, { moduleId: id, host: root });
        if (made)
            _handles.set(id, made);
        return made;
    }

    // The handle of the module whose directory holds `url` (a file of the module:
    // Qt.resolvedUrl(".") in any of its files), or null
    function handleAt(url) {
        const index = ModuleRules.directoryIndexOf(directories, url);
        if (index < 0)
            return null;
        const record = _records.find(entry => entry.directory === directories[index]);
        return record && record.shadowedBy === "" && record.manifest.id ? handle(record.manifest.id) : null;
    }

    // A module's fact (declared in its manifest's facts; `name` "<name>" or "<id>.<name>"),
    // checked against its type. null or undefined: not known. Only while the module is
    // loaded. → "" when set, else why not
    function setFact(id, name, value) {
        const record = _record(id);
        // Active, not merely "loaded": its main sets facts while it is being built
        if (!record || !activeIds.includes(id))
            return "the module is not active";
        const fact = ModuleRules.ownFactName(id, name);
        const declared = (record.manifest.facts ?? []).find(entry => entry.fact === fact);
        if (!declared)
            return "\"" + name + "\" is not a fact the module declares";
        const checked = ModuleRules.factValue(declared.type, value, declared.options);
        if (!checked.ok)
            return fact + ": " + checked.error;
        if (record.facts[fact] === checked.value)
            return "";
        record.facts = Object.assign({}, record.facts, { [fact]: checked.value });
        _publishFacts();
        return "";
    }

    // Something of a module that failed at run time (a slot contribution, a widget that did
    // not load): shown among its status's errors; the module stays loaded. Each text once,
    // at most 20.
    function reportError(id, text) {
        const record = _record(id);
        if (!record)
            return;
        const line = String(text).trim().slice(0, 500);
        if (line === "" || record.runtimeErrors.includes(line))
            return;
        record.runtimeErrors = record.runtimeErrors.concat([line]).slice(-20);
        console.warn("[Modules] " + id + ": " + line);
        Qt.callLater(_publish);
    }

    // Of `wanted` ({ module, context, … }), the initial properties the root object of the
    // module file at `url` declares — what a Loader may be given without a warning (an
    // object made by createObject ignores the others quietly). {} for a file of no module.
    function initialProperties(url, wanted) {
        const index = ModuleRules.directoryIndexOf(directories, url);
        if (index < 0)
            return {};
        const record = _records.find(entry => entry.directory === directories[index]);
        let path = String(url).replace(/^file:\/\//, "");
        try {
            path = decodeURIComponent(path);
        } catch (error) {
            return {};
        }
        const relative = ModuleRules.canonicalPath(path).slice(directories[index].length + 1);
        return ModuleRules.initialProperties(record?.rootProperties[relative], wanted);
    }

    // The URL of a module's contribution to a slot ("" for none): its first, by manifest
    // order. For a slot the core loads by URL itself (VpnManager.pageOf after the merge).
    function slotUrl(slot, id) {
        return slotContributions(slot).find(entry => entry.module === id)?.component ?? "";
    }

    // A Component for a module's contribution to a slot (its first), or null: a
    // ModuleContribution — the guard ModuleSlot uses: built inside its own Loader, given the
    // module's handle, a failure recorded in the module's status — that forwards the
    // `context` set on it. For a core place that takes one Component per module rather than
    // a ModuleSlot (VpnManager.extrasFor after the merge). The same Component while the
    // contribution stays.
    function slotComponent(slot, id) {
        const url = slotUrl(slot, id);
        if (url === "")
            return null;
        const key = slot + "|" + id + "|" + url;
        if (!_slotHolders.has(key)) {
            const holder = _slotHolder.createObject(root, { slot: slot, moduleId: id, url: url });
            if (!holder)
                return null;
            _slotHolders.set(key, holder);
        }
        return _slotHolders.get(key).component;
    }

    // Everything `qs ipc call modules list` tells: plain data, no secrets
    function describe() {
        return { api: apiVersion, safeMode: safeMode, safeModeReason: safeModeReason, hostError: hostError,
                 checkingPrograms: checkingPrograms, checkingFiles: checkingFiles, startGuard: guard,
                 ignoredEntries: ignoredEntries, modules: statuses };
    }

    onDisabledIdsChanged: _applyGuarded()
    onSettingsKnownChanged: _applyGuarded()

    // ---- Reading ----

    function _record(id) {
        return _records.find(entry => entry.manifest.id === id && entry.shadowedBy === "") ?? null;
    }

    // A list-like value (a QML list<string>) as a plain array of strings
    function _plainList(value) {
        const list = [];
        const length = value?.length ?? 0;
        for (let i = 0; i < length; i++) {
            if (typeof value[i] === "string")
                list.push(value[i]);
        }
        return list;
    }

    // A file's text, read at once: { text } or { error }. FileView reads only a regular file
    // (a FIFO or a device is refused, never opened)
    function _readFile(path) {
        const view = _reader.createObject(root);
        if (!view)
            return { error: "cannot be read" };
        let failure = "";
        view.loadFailed.connect(error => failure = FileViewError.toString(error));
        view.path = path;
        const text = view.text();
        view.destroy();
        return failure !== "" ? { error: failure } : { text: text };
    }

    function _readModule(directory) {
        const file = _readFile(directory + "/module.json");
        const manifest = ModuleRules.parseManifest(file.error === undefined ? file.text : null);
        if (file.error !== undefined)
            manifest.errors = ["module.json cannot be read: " + file.error];
        const record = {
            directory: directory, manifest: manifest, compatible: false,
            errors: manifest.errors.slice(), warnings: manifest.warnings.slice(),
            shadowedBy: "", qmldirText: "", filesChecked: true, mainFileError: "",
            main: null, component: null, mainError: "", state: "", facts: ({}), runtimeErrors: [],
            rootProperties: ({})
        };
        if (!manifest.valid)
            return record;
        const compatibility = ModuleRules.apiCompatibility(manifest.api, apiVersion);
        record.compatible = compatibility.compatible;
        if (!compatibility.compatible) {
            record.errors.push(compatibility.reason);
            return record;
        }
        record.warnings.push(...ModuleRules.unknownSlotWarnings(manifest));
        record.qmldirText = _readFile(directory + "/qmldir").text ?? "";
        // Its files are checked (a process) before any is read or loaded
        record.filesChecked = false;
        return record;
    }

    // ---- The file check ----

    function _checkFiles() {
        // One run at a time: a load() while one runs asks again when it has answered (its
        // answer is for records that are gone, and ignored)
        if (_fileCheck.running) {
            _fileCheck.again = true;
            return;
        }
        const asked = [];
        for (const record of _records) {
            if (record.filesChecked)
                continue;
            const files = ModuleRules.filesToCheck(record.manifest, record.qmldirText);
            // Nothing to check: settled at once
            if (files.length === 0)
                _filesAnswered(record, {});
            for (const entry of files)
                asked.push({ record: record, file: entry.file });
        }
        if (asked.length === 0)
            return;
        _fileCheck.asked = asked;
        _fileCheck.lines = [];
        _fileCheck.command = ["sh", "-c", ModuleRules.fileCheckScript, "sh", String(ModuleRules.maxFileBytes)]
            .concat(...asked.map(entry => [entry.record.directory, entry.file]));
        _fileCheck.running = true;
        _fileCheckDeadline.restart();
    }

    // The check answered (or ran out of time: what it did not answer counts as failed)
    function _fileCheckDone(asked, lines) {
        const answers = ModuleRules.parseFileCheck(lines);
        const bad = new Map();
        asked.forEach((entry, index) => {
            if (!_records.includes(entry.record))
                return;
            if (!bad.has(entry.record))
                bad.set(entry.record, {});
            const answer = answers[String(index)];
            if (answer !== "ok")
                bad.get(entry.record)[entry.file] = answer ?? "could not be checked in time";
        });
        for (const [record, files] of bad) {
            if (!record.filesChecked)
                _filesAnswered(record, files);
        }
        _applyGuarded();
    }

    // Drops the entries whose files failed, then reads the rest for the import check
    function _filesAnswered(record, bad) {
        const checked = ModuleRules.withoutBadFiles(record.manifest, bad, record.qmldirText);
        record.manifest = Object.assign(checked.manifest);
        record.errors.push(...checked.errors);
        record.mainFileError = checked.fatal;
        record.filesChecked = true;
        if (checked.fatal !== "")
            return;
        const files = ModuleRules.manifestFiles(record.manifest);
        for (const listed of ModuleRules.qmldirFiles(record.qmldirText)) {
            if (!files.includes(listed))
                files.push(listed);
        }
        for (const name of files.concat(record.manifest.tests ?? [])) {
            const content = _readFile(record.directory + "/" + name);
            if (content.error !== undefined) {
                record.errors.push(name + " cannot be read: " + content.error);
                continue;
            }
            record.rootProperties[name] = ModuleRules.rootProperties(content.text);
            record.warnings.push(...ModuleRules.importWarnings(name, content.text, (record.manifest.tests ?? []).includes(name)));
        }
    }

    // ---- The start guard ----

    function _startGuard() {
        guard = null;
        // Run in the launcher's safe mode too: its count is then not acted on, but the start
        // is counted and cleared like any other, so a stale count never outlives it
        if (guardFile === "") {
            _guardKnown = true;
            return;
        }
        _guardKnown = false;
        // A load() while it runs: its answer stands for this load too (counted once)
        if (_guardCheck.running)
            return;
        _guardCheck.output = "";
        _guardCheck.command = ["sh", "-c", ModuleRules.startGuardScript, "sh", guardFile, guardIdentity];
        _guardCheck.running = true;
        _guardDeadline.restart();
    }

    function _guardAnswered(output) {
        if (_guardKnown)
            return;
        _guardKnown = true;
        const decision = ModuleRules.startGuard(output);
        guard = { count: decision.count, identity: decision.identity, reason: decision.reason };
        if (decision.safeMode && !_askedSafeMode) {
            safeMode = true;
            safeModeReason = decision.reason;
            console.warn("[Modules] " + decision.reason);
        } else if (decision.reason !== "") {
            console.warn("[Modules] start guard: " + decision.reason);
        }
        _guardClear.interval = guardClearMs;
        _guardClear.restart();
        _applyGuarded();
    }

    // Lived guardClearMs: its count back to 0
    function _clearGuard() {
        if (guardFile === "" || guard === null || guard.count === 0 || guard.identity === "")
            return;
        Quickshell.execDetached(["sh", "-c", ModuleRules.guardClearScript, "sh", guardFile, guard.identity]);
        guard = Object.assign({}, guard, { count: 0, cleared: true });
    }

    // ---- Applying ----

    function _applyGuarded() {
        try {
            _apply();
        } catch (error) {
            _hostFailed(error);
        }
    }

    // Brings every module to the state it should be in, then publishes
    function _apply() {
        const unknownPrograms = [];
        for (const record of _records) {
            const manifest = record.manifest;
            const programs = manifest.programs ?? [];
            const facts = {
                valid: manifest.valid, compatible: record.compatible, duplicate: record.shadowedBy !== "",
                filesChecked: record.filesChecked, mainFileError: record.mainFileError, guardKnown: _guardKnown,
                safeMode: safeMode, settingsKnown: settingsKnown, enabled: !disabledIds.includes(manifest.id),
                programsKnown: programs.every(program => _programs.has(program)),
                missingPrograms: programs.filter(program => _programs.get(program) === false),
                mainError: ""
            };
            let state = ModuleRules.stateOf(facts);
            if (state === "loaded") {
                _setActive(manifest.id, true);
                if (!record.main && record.mainError === "" && manifest.main !== "")
                    _createMain(record);
                if (record.mainError !== "") {
                    state = "failed";
                    _setActive(manifest.id, false);
                }
            } else {
                if (record.shadowedBy === "")
                    _setActive(manifest.id, false);
                _destroyMain(record);
                // Off, or waiting: a later start tries the main again
                record.mainError = "";
                if (state === "pending" && record.filesChecked && _guardKnown && settingsKnown)
                    unknownPrograms.push(...programs.filter(program => !_programs.has(program) && !unknownPrograms.includes(program)));
            }
            if (state !== "loaded" && Object.keys(record.facts).length > 0)
                record.facts = {};
            record.state = state;
            record.missingPrograms = facts.missingPrograms;
        }
        if (unknownPrograms.length > 0)
            _checkPrograms(unknownPrograms);
        _publish();
    }

    function _setActive(id, active) {
        if (!id || activeIds.includes(id) === active)
            return;
        activeIds = active ? activeIds.concat([id]) : activeIds.filter(entry => entry !== id);
    }

    function _createMain(record) {
        const url = ModuleRules.fileUrl(record.directory, record.manifest.main);
        let component = null;
        try {
            component = Qt.createComponent(url, Component.PreferSynchronous);
        } catch (error) {
            record.mainError = record.manifest.main + ": " + error;
            return;
        }
        if (!component || component.status === Component.Error) {
            record.mainError = (component ? component.errorString().trim() : record.manifest.main + ": cannot be loaded");
            return;
        }
        if (component.status !== Component.Ready) {
            record.mainError = record.manifest.main + ": did not load at once (status " + component.status + ")";
            return;
        }
        let object = null;
        try {
            // `module`: its handle, set before its Component.onCompleted (ignored when the
            // main declares no such property)
            object = component.createObject(root, { module: handle(record.manifest.id) });
        } catch (error) {
            record.mainError = record.manifest.main + ": threw while being created: " + error;
        }
        if (!object) {
            if (record.mainError === "")
                record.mainError = record.manifest.main + ": could not be created" + (component.errorString() ? ": " + component.errorString().trim() : "");
            return;
        }
        record.component = component;
        record.main = object;
    }

    function _destroyMain(record) {
        if (record.main) {
            try {
                record.main.destroy();
            } catch (error) {
                console.error("[Modules] destroying the main of " + record.manifest.id + " threw:", error);
            }
        }
        record.main = null;
        record.component = null;
    }

    function _publish() {
        const loaded = [];
        statuses = _records.map(record => {
            const errors = record.errors.slice();
            if (record.state === "failed" && record.mainFileError !== "")
                errors.push(record.mainFileError);
            if (record.state === "failed" && record.mainError !== "")
                errors.push(record.mainError);
            if (record.state === "duplicate")
                errors.push("the id " + record.manifest.id + " is already taken by " + record.shadowedBy);
            for (const program of record.missingPrograms ?? [])
                errors.push("needs the program " + program + ", which is not on PATH"
                            + (_programsTimedOut.includes(program) ? " (the look-up did not answer within " + checkTimeoutMs / 1000 + " s)" : ""));
            if (record.state === "safe-mode" && safeModeReason !== "")
                errors.push(safeModeReason);
            errors.push(...record.runtimeErrors);
            if (ModuleRules.contributes(record.state))
                loaded.push({ id: record.manifest.id, directory: record.directory, manifest: record.manifest });
            // One line per change of state, in the shell's log
            if (logStates && record.state !== record.loggedState && record.state !== "pending" && record.state !== "") {
                record.loggedState = record.state;
                const what = "[Modules] " + (record.manifest.id || record.directory) + " " + record.state
                    + (record.manifest.version ? " (" + record.manifest.version + ", " + record.directory + ")" : "");
                if (record.state === "loaded" || record.state === "disabled" || record.state === "safe-mode")
                    console.info(what + (record.warnings.length > 0 ? ": " + record.warnings.join("; ") : ""));
                else
                    console.warn(what + ": " + errors.join("; "));
            }
            return ModuleRules.statusOf({
                manifest: record.manifest, directory: record.directory, state: record.state || "failed",
                enabled: !disabledIds.includes(record.manifest.id), errors: errors, warnings: record.warnings,
                missingPrograms: record.missingPrograms, shadowedBy: record.shadowedBy
            });
        });
        const merged = ModuleRules.merge(loaded);
        // Assigned only when they changed, so that the registries (and the bars, the settings
        // window) are not rebuilt for a status line
        if (JSON.stringify(merged.widgetEntries) !== JSON.stringify(widgetEntries))
            widgetEntries = merged.widgetEntries;
        if (JSON.stringify(merged.settingsPages) !== JSON.stringify(settingsPages))
            settingsPages = merged.settingsPages;
        if (JSON.stringify(merged.settingEntries) !== JSON.stringify(settingEntries))
            settingEntries = merged.settingEntries;
        if (JSON.stringify(merged.factTypes) !== JSON.stringify(factTypes))
            factTypes = merged.factTypes;
        if (JSON.stringify(merged.slots) !== JSON.stringify(slots))
            slots = merged.slots;
        _publishFacts();
        generation++;
        modulesChanged();
    }

    function _publishFacts() {
        const values = {};
        for (const record of _records) {
            if (record.shadowedBy === "" && activeIds.includes(record.manifest.id))
                Object.assign(values, record.facts);
        }
        if (JSON.stringify(values) !== JSON.stringify(factValues))
            factValues = values;
    }

    function _hostFailed(error) {
        console.error("[Modules] the module host failed, running without modules:", error);
        try {
            for (const record of _records)
                _destroyMain(record);
        } catch (ignored) {}
        _records = [];
        hostError = String(error);
        activeIds = [];
        statuses = [];
        widgetEntries = [];
        settingsPages = [];
        settingEntries = [];
        factTypes = [];
        slots = ({});
        factValues = ({});
        generation++;
        modulesChanged();
    }

    // ---- Required programs ----

    // Looks each name up on PATH as an executable file (not `command -v`, which also finds
    // shell builtins); re-applies when it answers
    function _checkPrograms(names) {
        // One at a time: when it answers, _apply asks again for what is still unknown
        if (_programCheck.running)
            return;
        _programCheck.asked = names;
        _programCheck.found = [];
        _programCheck.timedOut = false;
        _programCheck.command = ["sh", "-c",
            "set -f; for program; do (IFS=:; for dir in $PATH; do "
            + "if [ -f \"${dir:-.}/$program\" ] && [ -x \"${dir:-.}/$program\" ]; then printf '%s\\n' \"$program\"; break; fi; "
            + "done); done", "sh"].concat(names);
        _programCheck.running = true;
        _programDeadline.restart();
    }

    property Component _reader: Component {
        FileView {
            preload: false
            blockAllReads: true
            printErrors: false
        }
    }

    // What slotComponent() hands out: a Component bound to this holder's module and URL
    property Component _slotHolder: Component {
        QtObject {
            id: _holder
            property string slot: ""
            property string moduleId: ""
            property string url: ""
            property Component component: Component {
                ModuleContribution {
                    host: root
                    moduleId: _holder.moduleId
                    url: _holder.url
                    slot: _holder.slot
                }
            }
        }
    }

    Process {
        id: _fileCheck
        property var asked: []
        property var lines: []
        property bool again: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => _fileCheck.lines.push(line)
        }
        onRunningChanged: {
            if (running)
                return;
            _fileCheckDeadline.stop();
            const asked = _fileCheck.asked;
            const lines = _fileCheck.lines;
            _fileCheck.asked = [];
            _fileCheck.lines = [];
            if (asked.length > 0)
                root._fileCheckDone(asked, lines);
            if (_fileCheck.again) {
                _fileCheck.again = false;
                root._checkFiles();
            }
        }
    }

    Timer {
        id: _fileCheckDeadline
        interval: root.checkTimeoutMs
        onTriggered: _fileCheck.running = false
    }

    Process {
        id: _guardCheck
        property string output: ""
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => _guardCheck.output += line
        }
        onRunningChanged: {
            if (running)
                return;
            _guardDeadline.stop();
            root._guardAnswered(_guardCheck.output);
        }
    }

    Timer {
        id: _guardDeadline
        interval: root.checkTimeoutMs
        onTriggered: {
            _guardCheck.running = false;
            root._guardAnswered("");
        }
    }

    // The shell has lived long enough: whatever kills it now is not a start-up crash loop
    Timer {
        id: _guardClear
        onTriggered: root._clearGuard()
    }

    Process {
        id: _programCheck
        property var asked: []
        property var found: []
        property bool timedOut: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => _programCheck.found.push(line.trim())
        }
        onRunningChanged: {
            if (running)
                return;
            _programDeadline.stop();
            for (const program of asked) {
                const present = found.includes(program);
                root._programs.set(program, present);
                if (!present && timedOut && !root._programsTimedOut.includes(program))
                    root._programsTimedOut = root._programsTimedOut.concat([program]);
            }
            asked = [];
            root._applyGuarded();
        }
    }

    Timer {
        id: _programDeadline
        interval: root.checkTimeoutMs
        onTriggered: {
            _programCheck.timedOut = true;
            _programCheck.running = false;
        }
    }
}
