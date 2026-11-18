import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.singletons.io

// The module host (notes/plans/modules.md): given the module directories, it reads NOTHING on
// the GUI thread before its check — each module.json and qmldir, and then the text of every
// file the module names (for the import check and the properties a root object declares), come
// out of one process, the file check (ModuleFileRules.fileCheckScript: resolved inside the module's
// directory, a regular file, not too large), under checkTimeoutMs; a module whose files did
// not answer in time is failed, with the reason, and the shell goes on. It checks the manifest
// with ModuleRules, counts the start (the start guard, below), looks up and judges the
// programs the modules name (a process; ModuleRules.programVerdict: found on PATH, trusted or
// not), creates each enabled, compatible module's `main` by URL inside a guard, and keeps
// every module's status, its handle (api/ModuleHandle.qml), its facts and the merged
// contributions as plain reactive lists. A module is "pending" until all of that has answered.
// The four checks (the file check, the stores' directory, the start guard, the program
// look-up) are runs of the host's one CommandRunner (singletons/io), under checkTimeoutMs.
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
    // (ModuleFileRules.startGuardScript); cleared after guardClearMs; ModuleFileRules.guardLimit
    // relaunches in a row → safe mode
    property string guardFile: ""
    // The identity the guard counts under ("<pid>:<crash>"; "" — the process's own): the
    // suites' seam
    property string guardIdentity: ""
    property int guardClearMs: ModuleFileRules.guardClearMs
    // How long the file and program checks may take before what they did not answer counts
    // as failed (a hung directory on PATH must not leave a module pending for good)
    property int checkTimeoutMs: 5000
    // The modules' stores' directory (api/ModuleStore.qml; "" — the suites' default — none):
    // made private (mode 700, and its parent if it has to be made) at the first load(), before
    // any module is created, so no store ever lands in a directory others can read
    property string storeDirectory: ""
    // Added to the file check's environment (the suites' and the lock bed's seam: a PATH whose
    // `head` hangs, as a mount that answers stat and then blocks on read would)
    property var checkEnvironment: ({})
    // The program look-up's environment: its PATH is the one searched instead of the shell's
    // (the suites' seam: a PATH that holds stand-in programs)
    property var programEnvironment: ({})
    // Module test mode: set by Modules from TestSeams.moduleTestMode (true only in a test
    // tree), or by a suite that builds a host. Told in describe(); the modules' API does not
    // show it
    property bool testMode: false
    property bool _storeDirectoryKnown: true

    // The canonical module directories given to load(), in search order, and the entries
    // that were not absolute paths
    property var directories: []
    property var ignoredEntries: []
    // One status per directory, in search order (ModuleMergeRules.statusOf):
    // { id, name, version, api, description, directory, state, enabled, errors, warnings,
    //   deprecations, missingPrograms, setupHints, shadowedBy }
    property var statuses: []
    // The loaded modules' contributions, merged (ModuleMergeRules.merge): what the core's
    // registries read. Every file an absolute file:// URL; every entry has `module`.
    property var widgetEntries: []
    property var settingsPages: []
    property var settingEntries: []
    property var factTypes: []
    property var slots: ({})
    // The loaded modules' facts, { "<id>.<name>": plain value } (setFact; checked against
    // the declared type): what Profiles adds to its facts
    property var factValues: ({})
    // What the program look-up found, { <name>: { path, real, trusted, reason, owner, mode } }
    // (ModuleRules.programVerdict), for every program a module names, required or optional:
    // what the handles' `programs` show. A new object only when something in it changed
    property var programVerdicts: ({})
    // Set when the host itself failed: it then holds no module
    property string hostError: ""
    // Counts every change of the statuses and lists
    property int generation: 0
    readonly property bool checkingPrograms: _checkingPrograms
    readonly property bool checkingFiles: _checkingFiles
    // load() has been called and every module has settled (none pending, no check running):
    // its facts are as known as they will get
    readonly property bool settled: _loadCalled && !_checkingFiles && !statuses.some(status => status.state === "pending")
    property bool _loadCalled: false
    // The ids of the modules loaded now (their handles' `active`): set before a main is
    // created, so the main sees itself active while it is built
    property var activeIds: []
    // The start guard's answer: { count, reason } (null before, or without a guard)
    property var guard: null
    // Each module's change of state goes to the log (the shell's host; the suites' are quiet)
    property bool logStates: true

    signal modulesChanged

    // Internal, per directory: { directory, manifest, compatible, errors (from the
    // manifest, API and files), warnings, deprecations, shadowedBy, qmldirText, filesChecked,
    // mainFileError, main, component, mainError, state, facts, runtimeErrors }
    property var _records: []
    // What the program look-up found: name → verdict (ModuleRules.programVerdict); the ones
    // it did not answer in time; the ones a module asked to look up again while it ran
    property var _programs: new Map()
    property var _programsTimedOut: []
    property var _recheckNames: []
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
            const parsed = ModuleFileRules.moduleDirectories(directoryList);
            directories = parsed.directories;
            ignoredEntries = parsed.ignored;
            // Nothing is read here: each module is pending until the file check (a process,
            // under checkTimeoutMs) has handed over its module.json and qmldir
            _records = parsed.directories.map(directory => _newRecord(directory));
            _loadCalled = true;
            _startGuard();
            _makeStoreDirectory();
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
                for (const program of _programNames(record.manifest)) {
                    if (_programs.get(program)?.path === "") {
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
        return ModuleMergeRules.slotContributions(slots, name);
    }

    // The object created from a loaded module's main, or null
    function mainObject(id) {
        const record = _record(id);
        return record?.state === "loaded" ? record.main ?? null : null;
    }

    // The checked manifest (ModuleManifestRules.parseManifest, less what the file check dropped)
    // read from a directory, or null
    function manifestOf(directory) {
        return _records.find(record => record.directory === ModuleFileRules.canonicalPath(directory))?.manifest ?? null;
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
        const index = ModuleFileRules.directoryIndexOf(directories, url);
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
        // Unchanged (null and never set are both "not known"): nothing is published, so no
        // setting binding is re-evaluated for it
        if ((record.facts[fact] ?? null) === checked.value)
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
        const index = ModuleFileRules.directoryIndexOf(directories, url);
        if (index < 0)
            return {};
        const record = _records.find(entry => entry.directory === directories[index]);
        let path = String(url).replace(/^file:\/\//, "");
        try {
            path = decodeURIComponent(path);
        } catch (error) {
            return {};
        }
        const relative = ModuleFileRules.canonicalPath(path).slice(directories[index].length + 1);
        return ModuleSourceRules.initialProperties(record?.rootProperties[relative], wanted);
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

    // Looks up the programs a module names again (its handle's recheckPrograms(), which
    // keeps it to one look every ModuleRules.recheckMinMs). The verdicts known stay until the
    // new ones answer
    function recheckPrograms(id) {
        const record = _record(id);
        const names = record ? _programNames(record.manifest) : [];
        if (names.length === 0)
            return;
        if (_checkingPrograms) {
            _recheckNames = _recheckNames.concat(names.filter(name => !_recheckNames.includes(name)));
            return;
        }
        _checkPrograms(names);
    }

    // Everything `qs ipc call modules list` tells: plain data, no secrets
    function describe() {
        return { api: apiVersion, safeMode: safeMode, safeModeReason: safeModeReason, hostError: hostError, testMode: testMode,
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

    // Every program a manifest names: the required ones, then the optional ones
    function _programNames(manifest) {
        return (manifest?.programs ?? []).concat((manifest?.optionalPrograms ?? []).filter(name => !(manifest?.programs ?? []).includes(name)));
    }

    // A module not read yet: pending until the file check hands over its module.json
    function _newRecord(directory) {
        return {
            directory: directory, manifest: { valid: false, errors: [], warnings: [] }, manifestRead: false,
            compatible: false, errors: [], warnings: [], deprecations: [],
            shadowedBy: "", qmldirText: "", filesChecked: true, mainFileError: "",
            main: null, component: null, mainError: "", state: "", facts: ({}), runtimeErrors: [],
            rootProperties: ({})
        };
    }

    // The file check answered for a module's module.json and qmldir (`answers`: { file: "ok"
    // | why not }, `texts`: { file: text })
    function _manifestAnswered(record, answers, texts) {
        record.manifestRead = true;
        const read = answers["module.json"] === "ok";
        const manifest = ModuleManifestRules.parseManifest(read ? texts["module.json"] : null);
        if (!read)
            manifest.errors = ["module.json cannot be read: " + (answers["module.json"] ?? "it could not be read within " + checkTimeoutMs / 1000 + " s")];
        record.manifest = manifest;
        record.errors = manifest.errors.slice();
        record.warnings = manifest.warnings.slice();
        if (!manifest.valid)
            return;
        const compatibility = ModuleRules.apiCompatibility(manifest.api, apiVersion);
        record.compatible = compatibility.compatible;
        if (!compatibility.compatible) {
            record.errors.push(compatibility.reason);
            return;
        }
        record.warnings.push(...ModuleMergeRules.unknownSlotWarnings(manifest));
        const qmldir = answers["qmldir"];
        if (qmldir === "ok") {
            record.qmldirText = texts["qmldir"] ?? "";
        } else if (qmldir !== "does not exist") {
            // A qmldir that is there but cannot be read (a FIFO, a link out, too large, a
            // read that did not answer): every file of the module imports its directory
            record.mainFileError = "qmldir " + (qmldir ?? "could not be read within " + checkTimeoutMs / 1000 + " s");
            return;
        }
        // Its files are checked (the same process) before any is loaded
        record.filesChecked = false;
    }

    // ---- The file check ----

    // The texts it reads: module.json and qmldir at most maxManifestBytes, every other file
    // at most maxFileBytes
    function _checkFiles() {
        // One run at a time: a load() while one runs asks again when it has answered (its
        // answer is for records that are gone, and ignored)
        if (_checkingFiles)
            return;
        const asked = [];
        // First every manifest not read yet (precedence needs them all); their files in the
        // next run
        for (const record of _records) {
            if (record.manifestRead)
                continue;
            for (const file of ["module.json", "qmldir"])
                asked.push({ record: record, file: file, stage: "manifest", cap: ModuleRules.maxManifestBytes });
        }
        let settledAtOnce = false;
        if (asked.length === 0) {
            for (const record of _records) {
                if (record.filesChecked)
                    continue;
                const files = ModuleFileRules.filesToCheck(record.manifest, record.qmldirText);
                // Nothing to check: settled at once
                if (files.length === 0) {
                    _filesAnswered(record, {}, {});
                    settledAtOnce = true;
                }
                for (const entry of files)
                    asked.push({ record: record, file: entry.file, stage: "files", cap: ModuleFileRules.maxFileBytes });
            }
        }
        if (asked.length === 0) {
            // No run follows whose answer would apply what was just settled: applied here
            if (settledAtOnce)
                _applyGuarded();
            return;
        }
        const lines = [];
        _checkingFiles = true;
        _check(["sh", "-c", ModuleFileRules.fileCheckScript, "sh"]
                   .concat(...asked.map(entry => [String(entry.cap), entry.record.directory, entry.file])), {
            environment: checkEnvironment ?? {},
            // A line is a line of a file with its index in front: never cut below a whole file
            maxOutputBytes: ModuleFileRules.maxFileBytes + 64,
            onLine: (line, stream) => {
                if (stream === "stdout")
                    lines.push(line);
            },
            done: result => {
                root._checkingFiles = false;
                // What it did not answer, for whatever reason, counts as failed
                root._fileCheckDone(asked, lines);
                // The next stage (the files of the manifests just read), or what a load()
                // during this run asked for; nothing when nothing is left to check
                root._checkFiles();
            }
        });
    }

    // The check answered (or ran out of time: what it did not answer counts as failed)
    function _fileCheckDone(asked, lines) {
        const answers = ModuleFileRules.parseFileCheck(lines);
        const texts = ModuleFileRules.fileTexts(lines);
        const byRecord = new Map();
        asked.forEach((entry, index) => {
            if (!_records.includes(entry.record))
                return;
            if (!byRecord.has(entry.record))
                byRecord.set(entry.record, { stage: entry.stage, answers: {}, texts: {} });
            const answer = answers[String(index)];
            byRecord.get(entry.record).answers[entry.file] = answer ?? "could not be checked within " + checkTimeoutMs / 1000 + " s";
            if (texts[String(index)] !== undefined)
                byRecord.get(entry.record).texts[entry.file] = texts[String(index)];
        });
        let manifests = false;
        for (const [record, answered] of byRecord) {
            if (answered.stage === "manifest" && !record.manifestRead) {
                _manifestAnswered(record, answered.answers, answered.texts);
                manifests = true;
            } else if (answered.stage === "files" && !record.filesChecked) {
                const bad = {};
                for (const file of Object.keys(answered.answers)) {
                    if (answered.answers[file] !== "ok")
                        bad[file] = answered.answers[file];
                }
                _filesAnswered(record, bad, answered.texts);
            }
        }
        if (manifests) {
            const order = ModuleMergeRules.precedence(_records.map(record => ({ directory: record.directory, id: record.manifest.id })));
            _records.forEach((record, index) => record.shadowedBy = order[index].shadowedBy);
            // Reassigned so that what reads them in a binding (handleAt: Api.moduleAt in a
            // module's singleton) sees the ids now known
            _records = _records.slice();
        }
        _applyGuarded();
    }

    // Drops the entries whose files failed, then takes the rest's texts (from the check) for
    // the import check and the properties their root objects declare
    function _filesAnswered(record, bad, texts) {
        const checked = ModuleFileRules.withoutBadFiles(record.manifest, bad, record.qmldirText);
        record.manifest = Object.assign(checked.manifest);
        record.errors.push(...checked.errors);
        record.mainFileError = checked.fatal;
        record.filesChecked = true;
        if (checked.fatal !== "")
            return;
        const files = ModuleFileRules.manifestFiles(record.manifest);
        for (const listed of ModuleFileRules.qmldirFiles(record.qmldirText)) {
            if (!files.includes(listed))
                files.push(listed);
        }
        const read = {};
        for (const name of files.concat(record.manifest.tests ?? [])) {
            const text = texts?.[name];
            if (typeof text !== "string") {
                record.errors.push(name + " cannot be read");
                continue;
            }
            read[name] = text;
            record.rootProperties[name] = ModuleSourceRules.rootProperties(text);
            // Only the files the core builds and hands `module` (main, the entries' components);
            // a singleton finding its handle with Api.moduleAt in a readonly property is fine
            const moduleWarning = ModuleFileRules.manifestFiles(record.manifest).includes(name) ? ModuleSourceRules.modulePropertyWarning(name, text) : "";
            if (moduleWarning !== "")
                record.warnings.push(moduleWarning);
            record.warnings.push(...ModuleSourceRules.importWarnings(name, text, (record.manifest.tests ?? []).includes(name)));
        }
        // The old ways its files still use: listed in its status, the module loads as before
        record.deprecations = ModuleSourceRules.importDeprecations(read);
    }

    // ---- The stores' directory ----

    // Once per host: mkdir -p under umask 077 (a parent it has to make is 700 too), then
    // chmod 700 — a directory made earlier by anything else is closed as well. Modules wait
    // for it (as for the start guard), at most checkTimeoutMs
    property bool _storeDirectoryMade: false

    function _makeStoreDirectory() {
        if (storeDirectory === "" || _storeDirectoryMade || _makingStoreDirectory)
            return;
        _storeDirectoryKnown = false;
        _makingStoreDirectory = true;
        _check(["sh", "-c", "umask 077; mkdir -p -- \"$1\" && chmod 700 -- \"$1\"", "sh", storeDirectory], {
            done: result => {
                root._makingStoreDirectory = false;
                root._storeDirectoryAnswered(result.ok);
            }
        });
    }

    function _storeDirectoryAnswered(ok) {
        if (_storeDirectoryKnown)
            return;
        _storeDirectoryKnown = true;
        _storeDirectoryMade = ok;
        if (!ok)
            console.warn("[Modules] the modules' store directory " + storeDirectory + " could not be made private (mode 700)");
        _applyGuarded();
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
        if (_checkingGuard)
            return;
        let output = "";
        _checkingGuard = true;
        // The shell's pid is handed over: the script's own parent is the runner's `timeout`
        _check(["sh", "-c", ModuleFileRules.startGuardScript, "sh", guardFile, guardIdentity, String(Quickshell.processId)], {
            onLine: (line, stream) => {
                if (stream === "stdout")
                    output += line;
            },
            done: result => {
                root._checkingGuard = false;
                root._guardAnswered(output);
            }
        });
    }

    function _guardAnswered(output) {
        if (_guardKnown)
            return;
        _guardKnown = true;
        const decision = ModuleFileRules.startGuard(output);
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
        Quickshell.execDetached(["sh", "-c", ModuleFileRules.guardClearScript, "sh", guardFile, guard.identity]);
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
            // Every one is looked up before the module loads; only a required one missing
            // stops it
            const programs = _programNames(manifest);
            const facts = {
                valid: manifest.valid, compatible: record.compatible, duplicate: record.shadowedBy !== "",
                manifestRead: record.manifestRead,
                filesChecked: record.filesChecked, mainFileError: record.mainFileError, guardKnown: _guardKnown && _storeDirectoryKnown,
                safeMode: safeMode, settingsKnown: settingsKnown, enabled: !disabledIds.includes(manifest.id),
                programsKnown: programs.every(program => _programs.has(program)),
                missingPrograms: (manifest.programs ?? []).filter(program => _programs.get(program)?.path === ""),
                mainError: ""
            };
            let state = ModuleMergeRules.stateOf(facts);
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
                if (state === "pending" && record.filesChecked && _guardKnown && _storeDirectoryKnown && settingsKnown)
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
        const url = ModuleFileRules.fileUrl(record.directory, record.manifest.main);
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
            if (ModuleMergeRules.contributes(record.state))
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
            return ModuleMergeRules.statusOf({
                manifest: record.manifest, directory: record.directory, state: record.state || "failed",
                enabled: !disabledIds.includes(record.manifest.id), errors: errors, warnings: record.warnings,
                deprecations: record.deprecations,
                missingPrograms: record.missingPrograms, shadowedBy: record.shadowedBy
            });
        });
        const merged = ModuleMergeRules.merge(loaded);
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

    // ---- Programs ----

    // Looks each name up on PATH as an executable file (not `command -v`, which also finds
    // shell builtins) and judges what it finds (ModuleRules.programProbeScript,
    // programVerdict); re-applies when it answers. A name the look-up did not answer in time
    // is "not found" the first time; a verdict known before keeps its path, untrusted.
    function _checkPrograms(names) {
        // One at a time: when it answers, _apply asks again for what is still unknown, and
        // the rechecks asked for meanwhile run
        if (_checkingPrograms)
            return;
        const lines = [];
        _checkingPrograms = true;
        // The PATH searched is the shell's (or the suites' seam); the probe's own tools come
        // from the system's directories, never from the PATH it judges
        const searched = programEnvironment?.PATH ?? Quickshell.env("PATH") ?? "";
        _check([ModuleRules.probeShell, "-c", ModuleRules.programProbeScript, "sh", "first", String(searched)].concat(names), {
            environment: { PATH: ModuleRules.probeToolPath },
            onLine: (line, stream) => {
                if (stream === "stdout")
                    lines.push(line);
            },
            done: result => {
                root._checkingPrograms = false;
                root._programsAnswered(names, lines, result.timedOut);
                root._applyGuarded();
                if (!root._checkingPrograms && root._recheckNames.length > 0) {
                    const again = root._recheckNames;
                    root._recheckNames = [];
                    root._checkPrograms(again);
                }
            }
        });
    }

    function _programsAnswered(names, lines, timedOut) {
        const verdicts = ModuleRules.programVerdicts(lines, names);
        for (const program of names) {
            const before = _programs.get(program);
            let verdict = verdicts[program];
            if (!verdict) {
                const reason = timedOut ? "the look-up did not answer within " + checkTimeoutMs / 1000 + " s" : "the look-up gave no answer";
                verdict = before && before.path !== ""
                    ? Object.freeze(Object.assign({}, before, { trusted: false, reason: reason }))
                    : Object.freeze({ path: "", real: "", trusted: false, reason: reason, owner: "", mode: "" });
                if (timedOut && verdict.path === "" && !_programsTimedOut.includes(program))
                    _programsTimedOut = _programsTimedOut.concat([program]);
            } else if (_programsTimedOut.includes(program)) {
                _programsTimedOut = _programsTimedOut.filter(name => name !== program);
            }
            _programs.set(program, verdict);
            // One line per change of what a name runs, or of its verdict
            if (logStates && JSON.stringify(before ?? null) !== JSON.stringify(verdict)) {
                const line = "[Modules] program " + program + ": " + (verdict.path === "" ? verdict.reason
                    : verdict.path + " (real file " + (verdict.real || "?") + (verdict.owner !== "" ? ", owner " + verdict.owner + ", mode " + verdict.mode : "") + "): "
                      + (verdict.trusted ? "trusted, " : "not trusted, ") + verdict.reason);
                if (verdict.path !== "" && verdict.trusted)
                    console.info(line);
                else
                    console.warn(line);
            }
        }
        const published = {};
        for (const [program, verdict] of _programs)
            published[program] = verdict;
        if (JSON.stringify(published) !== JSON.stringify(programVerdicts))
            programVerdicts = published;
    }

    // The machine woke (SystemSleep, neutral: the lock screen reports it there): each active
    // module's programs are looked up again (1.9) and its handle says so (module API 1.2,
    // `module.resumed()`)
    function forwardResumed() {
        for (const [id, made] of _handles) {
            if (!activeIds.includes(id))
                continue;
            made.recheckPrograms();
            try {
                made.resumed();
            } catch (error) {
                console.warn("[Modules] " + id + ": its resumed() handler threw:", error);
            }
        }
    }

    Connections {
        target: SystemSleep
        function onResumed() {
            root.forwardResumed();
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

    // ---- The checks' processes ----
    //
    // The file check, the stores' directory, the start guard and the program look-up each
    // run one command through this runner, one at a time per check, under checkTimeoutMs:
    // a check that takes longer is ended (TERM, KILL a second later) and answered with
    // what it had said until then.
    property bool _checkingFiles: false
    property bool _checkingPrograms: false
    property bool _checkingGuard: false
    property bool _makingStoreDirectory: false

    function _check(argv, options) {
        const done = options.done;
        return _runner.start(argv, Object.assign({ timeoutMs: Math.max(1, checkTimeoutMs), killAfterMs: 1000, keepOutput: false }, options, {
            done: result => {
                // Answered all the same, as a check that said nothing
                if (result.error !== "")
                    console.warn("[Modules] a check could not be run: " + result.error);
                done(result);
            }
        }));
    }

    CommandRunner {
        id: _runner
    }

    // The shell has lived long enough: whatever kills it now is not a start-up crash loop
    Timer {
        id: _guardClear
        onTriggered: root._clearGuard()
    }
}
