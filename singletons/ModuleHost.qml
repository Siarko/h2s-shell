import QtQuick
import Quickshell
import Quickshell.Io
import qs.api

// The module host (docs/plans/modules.md): given the module directories, it reads each
// manifest at once (a blocking read: the modules are known before the first frame), checks it
// with ModuleRules, checks the programs the modules require (a process: their state is
// "pending" until it answers), creates each enabled, compatible module's `main` by URL inside
// a guard, and keeps every module's status and the merged contributions as plain reactive
// lists. Turning a module off (setEnabled, stored in Config.disabledModules) destroys its main
// and drops its contributions; on again, they come back.
//
// The shell's one instance is in Modules (the singleton, fed from the environment); the
// suites make their own (tests/ModulesTest.qml) and tests/run-modules.sh another, so this
// takes its directories through load(), never from the environment.
//
// What the guard can and cannot contain (QML has no sandbox): a module file that does not
// compile, imports something missing or names a missing file → its Component is in Error,
// the module is "failed" with the error text; createObject returning null or throwing →
// "failed". Not containable, and not even visible to the host: an exception thrown in a
// module's signal handler — Component.onCompleted included — or binding (the engine prints
// it and carries on: the module counts as loaded); anything a module's singletons do later;
// a module that blocks the event loop or crashes the process (the launcher's safe mode is
// for that: after two quick deaths the shell starts without modules).
Scope {
    id: root

    // The module API this shell offers ("major.minor", Api.version)
    readonly property string apiVersion: Api.version
    // Started in safe mode (H2S_SHELL_SAFE_MODE=1, set by the launcher after two quick
    // deaths): manifests are read, nothing is loaded
    property bool safeMode: false
    // The ids turned off (Config.disabledModules); a module is on unless listed
    readonly property var disabledIds: _plainList(Config.disabledModules)
    // Until the config is read the host cannot know which modules are off: none is
    // created before (one turned off because it misbehaves must not run even briefly)
    readonly property bool settingsKnown: Config.ready

    // The canonical module directories given to load(), in search order, and the entries
    // that were not absolute paths
    property var directories: []
    property var ignoredEntries: []
    // One status per directory, in search order (ModuleRules.statusOf):
    // { id, name, version, api, description, directory, state, enabled, errors, warnings,
    //   missingPrograms, setupHints, shadowedBy }
    property var statuses: []
    // The loaded modules' contributions, merged (ModuleRules.merge): what the core's
    // registries will read. Every file an absolute file:// URL; every entry has `module`.
    property var widgetEntries: []
    property var settingsPages: []
    property var settingEntries: []
    property var factTypes: []
    property var slots: ({})
    // Set when the host itself failed: it then holds no module
    property string hostError: ""
    // Counts every change of the statuses and lists
    property int generation: 0
    readonly property bool checkingPrograms: _programCheck.running
    // Each module's change of state goes to the log (the shell's host; the suites' are quiet)
    property bool logStates: true

    signal modulesChanged

    // Internal, per directory: { directory, manifest, compatible, errors (from the
    // manifest, API and files), warnings, shadowedBy, main, component, mainError, state }
    property var _records: []
    // What the program check found: name → true / false
    property var _programs: new Map()

    // ---- Public ----

    // (Re)loads from `directoryList` (an array, or a colon-separated string as in
    // H2S_SHELL_MODULES). `options`: { safeMode }. Never throws: a failure of the host
    // itself unloads everything and is kept in hostError.
    function load(directoryList, options) {
        try {
            unload();
            hostError = "";
            safeMode = options?.safeMode === true;
            const parsed = ModuleRules.moduleDirectories(directoryList);
            directories = parsed.directories;
            ignoredEntries = parsed.ignored;
            const records = parsed.directories.map(directory => _readModule(directory));
            const order = ModuleRules.precedence(records.map(record => ({ directory: record.directory, id: record.manifest.id })));
            records.forEach((record, index) => record.shadowedBy = order[index].shadowedBy);
            _records = records;
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
                    if (_programs.get(program) === false)
                        _programs.delete(program);
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
        const record = _records.find(entry => entry.manifest.id === id && entry.state === "loaded");
        return record?.main ?? null;
    }

    // The checked manifest (ModuleRules.parseManifest) read from a directory, or null
    function manifestOf(directory) {
        return _records.find(record => record.directory === ModuleRules.canonicalPath(directory))?.manifest ?? null;
    }

    // Everything `qs ipc call modules list` tells: plain data, no secrets
    function describe() {
        return { api: apiVersion, safeMode: safeMode, hostError: hostError, checkingPrograms: checkingPrograms,
                 ignoredEntries: ignoredEntries, modules: statuses };
    }

    onDisabledIdsChanged: _applyGuarded()
    onSettingsKnownChanged: _applyGuarded()

    // ---- Reading ----

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

    // A file's text, read at once: { text } or { error }
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
            shadowedBy: "", main: null, component: null, mainError: "", state: ""
        };
        if (!manifest.valid)
            return record;
        const compatibility = ModuleRules.apiCompatibility(manifest.api, apiVersion);
        record.compatible = compatibility.compatible;
        if (!compatibility.compatible) {
            record.errors.push(compatibility.reason);
            return record;
        }
        // The import check: the files the manifest names and those its qmldir lists
        const qmldir = _readFile(directory + "/qmldir");
        const files = ModuleRules.manifestFiles(manifest);
        for (const listed of ModuleRules.qmldirFiles(qmldir.text ?? "")) {
            if (!files.includes(listed))
                files.push(listed);
        }
        for (const name of files) {
            const content = _readFile(directory + "/" + name);
            if (content.error !== undefined)
                record.errors.push(name + " cannot be read: " + content.error);
            else
                record.warnings.push(...ModuleRules.importWarnings(name, content.text));
        }
        return record;
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
                safeMode: safeMode, settingsKnown: settingsKnown, enabled: !disabledIds.includes(manifest.id),
                programsKnown: programs.every(program => _programs.has(program)),
                missingPrograms: programs.filter(program => _programs.get(program) === false),
                mainError: ""
            };
            let state = ModuleRules.stateOf(facts);
            if (state === "loaded") {
                if (!record.main && record.mainError === "" && manifest.main !== "")
                    _createMain(record);
                if (record.mainError !== "")
                    state = "failed";
            } else {
                _destroyMain(record);
                // Off, or waiting: a later start tries the main again
                record.mainError = "";
                if (state === "pending")
                    unknownPrograms.push(...programs.filter(program => !_programs.has(program) && !unknownPrograms.includes(program)));
            }
            record.state = state;
            record.missingPrograms = facts.missingPrograms;
        }
        if (unknownPrograms.length > 0)
            _checkPrograms(unknownPrograms);
        _publish();
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
            object = component.createObject(root);
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
            if (record.state === "failed" && record.mainError !== "")
                errors.push(record.mainError);
            if (record.state === "duplicate")
                errors.push("the id " + record.manifest.id + " is already taken by " + record.shadowedBy);
            for (const program of record.missingPrograms ?? [])
                errors.push("needs the program " + program + ", which is not on PATH");
            if (ModuleRules.contributes(record.state))
                loaded.push({ id: record.manifest.id, directory: record.directory, manifest: record.manifest });
            // One line per change of state, in the shell's log
            if (logStates && record.state !== record.loggedState && record.state !== "pending") {
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
        widgetEntries = merged.widgetEntries;
        settingsPages = merged.settingsPages;
        settingEntries = merged.settingEntries;
        factTypes = merged.factTypes;
        slots = merged.slots;
        generation++;
        modulesChanged();
    }

    function _hostFailed(error) {
        console.error("[Modules] the module host failed, running without modules:", error);
        try {
            for (const record of _records)
                _destroyMain(record);
        } catch (ignored) {}
        _records = [];
        hostError = String(error);
        statuses = [];
        widgetEntries = [];
        settingsPages = [];
        settingEntries = [];
        factTypes = [];
        slots = ({});
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
        _programCheck.command = ["sh", "-c",
            "set -f; for program; do (IFS=:; for dir in $PATH; do "
            + "if [ -f \"${dir:-.}/$program\" ] && [ -x \"${dir:-.}/$program\" ]; then printf '%s\\n' \"$program\"; break; fi; "
            + "done); done", "sh"].concat(names);
        _programCheck.running = true;
    }

    property Component _reader: Component {
        FileView {
            preload: false
            blockAllReads: true
            printErrors: false
        }
    }

    Process {
        id: _programCheck
        property var asked: []
        property var found: []
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => _programCheck.found.push(line.trim())
        }
        onRunningChanged: {
            if (running)
                return;
            for (const program of asked)
                root._programs.set(program, found.includes(program));
            asked = [];
            root._applyGuarded();
        }
    }
}
