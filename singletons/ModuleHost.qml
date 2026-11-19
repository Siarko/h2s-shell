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
// In module test mode (`testMode`) a module that names testPrograms has its programs looked
// for there instead, as stand-ins, and never on PATH.
// Before a module loads, its data directory is made private (module.dataDirectory, API 1.13:
// "<dataRoot>/<id>", mode 700; in test mode below a private temporary home instead).
// The five checks (the file check, the stores' directory, the start guard, the program
// look-up, the data directories) are runs of the host's one CommandRunner (singletons/io),
// under checkTimeoutMs.
// Turning a module off (setEnabled, stored in Config.disabledModules) destroys its main, drops
// its contributions and facts and turns its handle's `active` off; on again, they come back.
// (API 1.18) A module that `uses` others loads after them and gets their exports objects
// (usesOf); one of them leaving — turned off, failed, the shell reloading — turns it off
// first (missing-module), and it comes back after the provider does.
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
    // (API 1.13) Where the modules' data directories are: "<dataHome>/h2s-shell/module-data"
    // (SystemFactsRules.dataRoot; "" — the suites' default — none: every module.dataDirectory
    // is ""). A module's, "<dataRoot>/<id>", is made before the module loads, again at each
    // load and when it is turned on (SystemFactsRules.makeScript: every folder from the data
    // home down checked, the root and the module's 700). One that cannot be made so leaves
    // the module loading with module.dataDirectory "" and a warning in its status. Nothing
    // there may be run as root: the user can write there. Not used in test mode, where the
    // data directories are below `testHome`
    property string dataRoot: ""
    // In module test mode: the private temporary home the host made (mktemp -d, in
    // XDG_RUNTIME_DIR, else /tmp) before the first module loaded — the data directories are
    // below its .local/share, and Api.system's made-up directories below it too. "" until made
    property string testHome: ""
    // The root the data directories are made in now: dataRoot, or in test mode testHome's
    readonly property string dataRootInUse: testMode ? (testHome !== "" ? SystemFactsRules.dataRoot(testHome + "/.local/share") : "")
        : SystemFactsRules.absolutePath(dataRoot)
    // { <id>: its data directory } for every module whose directory was made private:
    // what the handles' `dataDirectory` show
    property var dataDirectories: ({})
    // Added to the file check's environment (the suites' and the lock bed's seam: a PATH whose
    // `head` hangs, as a mount that answers stat and then blocks on read would)
    property var checkEnvironment: ({})
    // The program look-up's environment: its PATH is the one searched instead of the shell's
    // (the suites' seam: a PATH that holds stand-in programs)
    property var programEnvironment: ({})
    // Module test mode (ModuleRules, "Module test mode"): fixed once, by setTestMode() before
    // modules are loaded — Modules from TestSeams.moduleTestMode (true only in a test tree),
    // tests-modules.qml, a suite that builds a host — and read-only from then on: the first
    // load() that names a module directory fixes it as it is (off unless set). Modules reach
    // this object (their handle's `host`), so the value is held where no property write
    // reaches it, and nothing a module can call after the load changes it. A module that names testPrograms then gets its
    // programs from there (testProgramVerdicts), never from PATH. Told in describe() and to
    // modules as Api.testMode
    readonly property bool testMode: {
        _testModeRevision;
        return _testModeLatch.value();
    }
    // The held value: a frozen object whose state only its own functions see
    readonly property var _testModeLatch: {
        let value = false;
        let fixed = false;
        return Object.freeze({
            value: () => value,
            // → true when this fixed it, false when it was fixed before
            fix: on => {
                if (fixed)
                    return false;
                value = on === true;
                fixed = true;
                return true;
            }
        });
    }
    // Only tells bindings to read testMode again: writing it changes nothing
    property int _testModeRevision: 0
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
    // In test mode, per module that names testPrograms: { <id>: { <name>: verdict } }
    // (ModuleRules.testProgramVerdicts) — what its handle's `programs` show instead
    property var testProgramVerdicts: ({})
    // In test mode, the stand-in pkexec of each module that names testPrograms and pkexec
    // among its programs (ModuleRules.testStandIns), once the look at its stand-ins found it
    // there, inside the module: the only pkexec a module's commands may start
    readonly property var testStandIns: testMode
        ? ModuleRules.testStandIns(_records.filter(record => record.shadowedBy === "" && record.manifest.valid)
                                   .map(record => ({ directory: record.directory, testPrograms: record.manifest.testPrograms })))
              .filter(path => Object.values(testProgramVerdicts).some(verdicts => verdicts.pkexec?.path === path))
        : []
    // Set when the host itself failed: it then holds no module
    property string hostError: ""
    // Counts every change of the statuses and lists
    property int generation: 0
    readonly property bool checkingPrograms: _checkingPrograms || _checkingTestPrograms
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

    // In test mode, the pkexec rule for a call whose JavaScript stack is `stack` (an
    // Error().stack taken where a module's code called the API): "legacy" when only modules
    // written for an API below 1.10 are on it (ModuleRules, the gate removed by slice Z), else
    // "strict"
    function testCallRule(stack) {
        return ModuleRules.testCallRule(ModuleRules.stackDirectories(stack, directories)
            .map(directory => ModuleRules.testPkexecRule(_records.find(record => record.directory === directory)?.manifest?.api)));
    }

    // Fixes module test mode (`testMode`): only once, and only before the first load() that
    // names a module directory — the shell's test entry points call it, nothing later can.
    // → true when this call fixed it
    function setTestMode(on) {
        const fixedNow = _testModeLatch.fix(on === true);
        if (fixedNow)
            _testModeRevision++;
        else if ((on === true) !== testMode)
            console.warn("[Modules] module test mode is fixed (" + testMode + "): setTestMode(" + (on === true) + ") refused");
        return fixedNow;
    }

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
            // Test mode is what it is now, for the host's life: from the first load that names
            // a module directory on — before it, no module's code exists to change it
            if (parsed.directories.length > 0 && _testModeLatch.fix(false))
                _testModeRevision++;
            directories = parsed.directories;
            ignoredEntries = parsed.ignored;
            // Nothing is read here: each module is pending until the file check (a process,
            // under checkTimeoutMs) has handed over its module.json and qmldir
            _records = parsed.directories.map(directory => _newRecord(directory));
            // Each load makes the data directories again: one that failed, or was removed
            _forgetData();
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
        // Dependents before their providers
        for (const record of _teardownOrder())
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
        // since, perhaps), and its data directory made again
        if (enabled) {
            // (not one running now: forgetting its directory would restart it)
            if (disabledIds.includes(id))
                _forgetData(id);
            for (const record of _records.filter(entry => entry.manifest.id === id)) {
                if (record.testVerdicts && Object.keys(record.testVerdicts).some(name => record.testVerdicts[name].path === ""))
                    record.testVerdicts = null;
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

    // The object made from a module's main while it exists (a handle's `main`), or null:
    // set right after it is created, cleared before it is destroyed. `revision`
    // (mainsRevision) only makes a binding follow it
    function mainOf(id, revision) {
        return _record(id)?.main ?? null;
    }

    // Counts every change of a module's main object (mainOf)
    property int mainsRevision: 0

    // The object created from a loaded module's main, or null
    function mainObject(id) {
        const record = _record(id);
        return record?.state === "loaded" ? record.main ?? null : null;
    }

    // (API 1.18) What a module gets of the modules its manifest `uses` (its handle's `uses`):
    // frozen { <id>: that module's exports object }. Set just before the module is turned on
    // (its main made, its views built) and kept, the same object, until it is turned on
    // again: its main and views, while they go, still read what they had — and a provider's
    // main is destroyed only after its dependents' mains are gone (_reap). Empty for a module
    // never turned on. Nothing else of a provider: not its main, not its handle. `revision`
    // (usesRevision) only makes a binding follow
    function usesOf(id, revision) {
        return _uses.get(id) ?? _noUses;
    }

    // Counts every change of a module's `uses` (usesOf)
    property int usesRevision: 0

    readonly property var _noUses: Object.freeze({})
    // id → what usesOf gives; kept, like the handles, for the host's life
    property var _uses: new Map()

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
        // Its identity is fixed here, for good (readonly in the handle)
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
        if (_fromStandIns(record)) {
            // Asked during a look at the same module: looked at again after it
            if (!_testProgramsQueue.includes(record))
                _testProgramsQueue = _testProgramsQueue.concat([record]);
            _checkTestPrograms([]);
            return;
        }
        if (_checkingPrograms) {
            _recheckNames = _recheckNames.concat(names.filter(name => !_recheckNames.includes(name)));
            return;
        }
        _checkPrograms(names);
    }

    // Everything `qs ipc call modules list` tells: plain data, no secrets
    function describe() {
        return { api: apiVersion, safeMode: safeMode, safeModeReason: safeModeReason, hostError: hostError, testMode: testMode,
                 checkingPrograms: checkingPrograms, checkingFiles: checkingFiles, startGuard: guard, dataRoot: dataRootInUse,
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

    // Its programs come from its testPrograms directory (test mode, and it names one)
    function _fromStandIns(record) {
        return ModuleRules.programSource(testMode, record?.manifest?.testPrograms) === "test";
    }

    // A program's verdict for a module: from its stand-ins or from the PATH look-up
    // (undefined: not known yet)
    function _verdictFor(record, program) {
        return _fromStandIns(record) ? record.testVerdicts?.[program] : _programs.get(program);
    }

    // A module not read yet: pending until the file check hands over its module.json
    function _newRecord(directory) {
        return {
            directory: directory, manifest: { valid: false, errors: [], warnings: [] }, manifestRead: false,
            compatible: false, errors: [], warnings: [], deprecations: [],
            shadowedBy: "", qmldirText: "", filesChecked: true, mainFileError: "",
            // Every QML file under its directory, for the import scan: ModuleFileRules.listing's
            // answer ({ files, skipped, more, failed })
            scanListing: null,
            main: null, component: null, mainError: "", state: "", facts: ({}), runtimeErrors: [],
            // (1.18) Its main's exports object while the main lives (null: none), why there is
            // none when it declares exports, and why it does not load for the modules it uses
            exportsObject: null, exportsProblem: "", dependencyReasons: [],
            rootProperties: ({}),
            // Test mode: its stand-ins' verdicts, { <name>: verdict } (null until looked at)
            testVerdicts: null
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
            asked.push({ record: record, file: ModuleFileRules.listKey, stage: "manifest", cap: "list", optional: true });
        }
        let settledAtOnce = false;
        if (asked.length === 0) {
            for (const record of _records) {
                if (record.filesChecked)
                    continue;
                const files = ModuleFileRules.filesToCheck(record.manifest, record.qmldirText);
                const scanned = ModuleFileRules.scanOnly(record.scanListing?.files, files);
                // Nothing to check: settled at once
                if (files.length === 0 && scanned.length === 0) {
                    _filesAnswered(record, {}, {});
                    settledAtOnce = true;
                }
                for (const entry of files)
                    asked.push({ record: record, file: entry.file, stage: "files", cap: ModuleFileRules.maxFileBytes });
                // Only for the import scan: its header, whatever its size
                for (const file of scanned)
                    asked.push({ record: record, file: file, stage: "files", cap: "h" + ModuleRules.maxHeaderBytes, optional: true });
            }
        }
        // Every module's required files first, the listings and the scan's reads after them
        asked.splice(0, asked.length, ...ModuleFileRules.checkOrder(asked));
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
                record.scanListing = ModuleFileRules.listing(answered.answers[ModuleFileRules.listKey], answered.texts[ModuleFileRules.listKey]);
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
        // Capped per file (importWarnings) and per module: added after the loops
        const importLines = [];
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
            const openerWarning = (record.manifest.widgets ?? []).some(widget => widget.popupPanel === name) ? ModuleSourceRules.openerPropertyWarning(name, text) : "";
            if (openerWarning !== "")
                record.warnings.push(openerWarning);
            importLines.push(...ModuleSourceRules.importWarnings(name, text, (record.manifest.tests ?? []).includes(name)));
        }
        // Its other QML files, in subdirectories or built by a Loader, for their imports
        // alone; one that could not be read is not an error (nothing loads it by name), but
        // counted: the status says how many were not checked
        let unread = 0;
        for (const name of record.scanListing?.files ?? []) {
            const text = texts?.[name];
            if (ModuleRules.has(read, name))
                continue;
            if (typeof text !== "string") {
                unread++;
                continue;
            }
            read[name] = text;
            // Under tests/: a suite's helper, which runs under the runner as the suites do
            importLines.push(...ModuleSourceRules.importWarnings(name, text, name.startsWith("tests/")));
        }
        record.warnings.push(...ModuleSourceRules.cappedLines(importLines, ModuleSourceRules.maxImportWarnings));
        const scanWarning = ModuleFileRules.scanWarning(record.scanListing, unread);
        if (scanWarning !== "")
            record.warnings.push(scanWarning);
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

    // ---- The data directories (API 1.13) ----

    // What making the data directories answered: { root (the one they were made in),
    // made: { <id>: true (made) | false (could not be) } }. Forgotten at each load(), and a
    // module's at setEnabled(id, true), so a directory that failed, or was removed since, is
    // made again; an answer for a root that is no longer the one in use counts for nothing
    property var _dataAnswers: ({ root: "", made: {} })
    property bool _makingData: false
    // Raised when the answers are forgotten: a run started before answers for nothing
    property int _dataGeneration: 0

    function _dataDirectoryKnown(id) {
        if (!id)
            return true;
        // No root (the suites' default, or not an absolute path): no data directories
        if (!testMode && SystemFactsRules.absolutePath(dataRoot) === "")
            return true;
        return _dataAnswers.root === dataRootInUse && ModuleRules.has(_dataAnswers.made, id);
    }

    function _dataFailed(id) {
        return _dataAnswers.root === dataRootInUse && ModuleRules.has(_dataAnswers.made, id) && _dataAnswers.made[id] === false;
    }

    function _forgetData(id) {
        _dataGeneration++;
        const made = id === undefined ? {} : Object.assign({}, _dataAnswers.made);
        if (id !== undefined)
            delete made[id];
        _dataAnswers = { root: _dataAnswers.root, made: made };
        _publishDataDirectories();
    }

    // The handles' dataDirectory, from the answers for the root in use
    function _publishDataDirectories() {
        const published = {};
        if (_dataAnswers.root === dataRootInUse) {
            for (const id of Object.keys(_dataAnswers.made)) {
                if (_dataAnswers.made[id] === true)
                    published[id] = SystemFactsRules.dataDirectory(_dataAnswers.root, id);
            }
        }
        if (JSON.stringify(published) !== JSON.stringify(dataDirectories))
            dataDirectories = published;
    }

    function _dataWarning(id) {
        const path = SystemFactsRules.dataDirectory(dataRootInUse, id);
        return "its data directory " + (path || "(none: no place to make it)") + " could not be made private (mode 700): module.dataDirectory is \"\"";
    }

    // One run for the modules waiting; when it answers, _apply asks for any still waiting
    function _makeDataDirectories(ids) {
        if (_makingData)
            return;
        // In test mode before the temporary home exists: "" — the script makes it first
        const where = testMode ? (testHome !== "" ? dataRootInUse : "") : SystemFactsRules.absolutePath(dataRoot);
        const base = SystemFactsRules.baseDirectories({ XDG_RUNTIME_DIR: Quickshell.env("XDG_RUNTIME_DIR") }).runtimeDirectory;
        const generation = _dataGeneration;
        const lines = [];
        _makingData = true;
        _check(["sh", "-c", SystemFactsRules.makeScript, "sh", where, base].concat(ids), {
            onLine: (line, stream) => {
                if (stream === "stdout")
                    lines.push(line);
            },
            done: result => {
                root._makingData = false;
                root._dataAnswered(ids, lines, result.timedOut, where, generation);
            }
        });
    }

    function _dataAnswered(ids, lines, timedOut, where, generation) {
        const answers = SystemFactsRules.makeAnswers(lines, ids);
        if (testMode && testHome === "" && answers.home !== "")
            testHome = answers.home;
        // The root this answer is for: the one asked, or below the temporary home it made
        const answeredRoot = where !== "" ? where : (answers.home !== "" ? SystemFactsRules.dataRoot(answers.home + "/.local/share") : "");
        // Late: the answers were forgotten since, or the root in use is another now — asked
        // again by _apply
        if (generation === _dataGeneration && answeredRoot === dataRootInUse) {
            const made = _dataAnswers.root === answeredRoot ? Object.assign({}, _dataAnswers.made) : {};
            for (const id of ids) {
                made[id] = answers.made[id] === true;
                if (!made[id])
                    console.warn("[Modules] " + id + ": " + _dataWarning(id) + (timedOut ? " (no answer in " + checkTimeoutMs / 1000 + " s)" : ""));
            }
            _dataAnswers = { root: answeredRoot, made: made };
            _publishDataDirectories();
        }
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

    // Brings every module to the state it should be in, then publishes. A module that uses
    // others (API 1.18) is planned after them (ModuleMergeRules.dependencyPlan): what leaves
    // goes first, in the reverse of that order — a dependent's main before its providers' —
    // then what comes is made in that order, a provider's main (and its exports) before its
    // dependents'
    function _apply() {
        const unknownPrograms = [];
        const unknownStandIns = [];
        const unknownData = [];
        // Each module's own state, from its own checks: record → { base (before its main),
        // state (a main that failed counted), facts }
        const own = new Map();
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
                programsKnown: programs.every(program => _verdictFor(record, program) !== undefined),
                missingPrograms: (manifest.programs ?? []).filter(program => _verdictFor(record, program)?.path === ""),
                dataDirectoryKnown: _dataDirectoryKnown(manifest.id),
                mainError: ""
            };
            const base = ModuleMergeRules.stateOf(facts);
            // Waiting for its data directory alone: asked for below
            if (base === "pending" && !facts.dataDirectoryKnown
                    && ModuleMergeRules.stateOf(Object.assign({}, facts, { dataDirectoryKnown: true })) === "loaded")
                unknownData.push(manifest.id);
            // Its main failed before: failed until it is turned off and on, or reloaded
            own.set(record, { base: base, state: base === "loaded" && record.mainError !== "" ? "failed" : base, facts: facts });
            if (base === "pending" && record.filesChecked && _guardKnown && _storeDirectoryKnown && settingsKnown) {
                if (!_fromStandIns(record))
                    unknownPrograms.push(...programs.filter(program => !_programs.has(program) && !unknownPrograms.includes(program)));
                else if (programs.some(program => _verdictFor(record, program) === undefined))
                    unknownStandIns.push(record);
            }
        }
        // The modules that count (not shadowed, with an id) are planned; the others never load
        const counted = _records.filter(record => record.shadowedBy === "" && record.manifest.id);
        const byId = new Map(counted.map(record => [record.manifest.id, record]));
        const planNow = () => ModuleMergeRules.dependencyPlan(counted.map(record => record.manifest), _planStates(counted, own));
        const plan = planNow();
        _order = plan.order.slice();
        const ordered = plan.order.map(id => byId.get(id)).concat(_records.filter(record => !counted.includes(record)));
        const finalState = record => counted.includes(record) ? ModuleMergeRules.planned(plan, record.manifest.id) : { state: own.get(record).state, reasons: [] };

        // What does not stay loaded leaves, dependents first
        for (const record of ordered.slice().reverse()) {
            const entry = finalState(record);
            if (entry.state !== "loaded")
                _settle(record, own.get(record), entry);
        }
        // What is loaded comes, providers first: each checked again against what was made
        // before it (a provider whose main just failed, or gave no exports object)
        for (const record of ordered) {
            let entry = finalState(record);
            if (entry.state !== "loaded")
                continue;
            if (counted.includes(record) && (record.manifest.uses ?? []).length > 0)
                entry = ModuleMergeRules.planned(planNow(), record.manifest.id);
            if (entry.state !== "loaded") {
                _settle(record, own.get(record), entry);
                continue;
            }
            const manifest = record.manifest;
            if (counted.includes(record))
                _giveUses(record);
            _setActive(manifest.id, true);
            if (!record.main && record.mainError === "" && manifest.main !== "")
                _createMain(record);
            if (record.mainError !== "") {
                own.get(record).state = "failed";
                _setActive(manifest.id, false);
                record.state = "failed";
                if (Object.keys(record.facts).length > 0)
                    record.facts = {};
            } else {
                record.state = "loaded";
            }
            // Declared exports and no main to give them: its dependents count it as missing
            record.exportsProblem = manifest.exports && !record.main && record.mainError === "" ? ModuleRules.exportsOf(null).problem : record.exportsProblem;
            record.dependencyReasons = [];
            record.missingPrograms = own.get(record).facts.missingPrograms;
        }
        if (unknownPrograms.length > 0)
            _checkPrograms(unknownPrograms);
        if (unknownStandIns.length > 0)
            _checkTestPrograms(unknownStandIns);
        if (unknownData.length > 0)
            _makeDataDirectories(unknownData);
        _publish();
    }

    // (1.18) A module about to be turned on (or staying on): its `uses`, its providers'
    // exports objects now (their mains made before, in this pass or earlier). A new object
    // only when one of them is another object — never while it stays on, since a provider
    // that goes turns it off first
    function _giveUses(record) {
        const id = record.manifest.id;
        const given = {};
        for (const use of record.manifest.uses ?? []) {
            const provider = _record(use.id);
            if (provider?.exportsObject)
                given[use.id] = provider.exportsObject;
        }
        const before = _uses.get(id);
        const keys = Object.keys(given);
        if (before && Object.keys(before).length === keys.length && keys.every(key => before[key] === given[key]))
            return;
        _uses.set(id, Object.freeze(given));
        usesRevision++;
    }

    // A module brought to a state other than loaded: off, its main destroyed, its facts gone
    function _settle(record, known, entry) {
        if (record.shadowedBy === "")
            _setActive(record.manifest.id, false);
        _destroyMain(record);
        // Off, or waiting: a later start tries the main again (not when its own main failed)
        if (known.base !== "loaded")
            record.mainError = "";
        if (Object.keys(record.facts).length > 0)
            record.facts = {};
        record.state = entry.state;
        record.dependencyReasons = entry.reasons.slice();
        record.missingPrograms = known.facts.missingPrograms;
    }

    // What dependencyPlan is told of each module: its own state, and whether its exports
    // object is there ("" yes, a text no, undefined not known until its main is made)
    function _planStates(counted, own) {
        const states = {};
        for (const record of counted) {
            let exportsKnown;
            if (!record.manifest.exports)
                exportsKnown = "";
            else if (record.main)
                exportsKnown = record.exportsProblem;
            else if (record.manifest.main === "")
                exportsKnown = ModuleRules.exportsOf(null).problem;
            states[record.manifest.id] = { state: own.get(record).state, exports: exportsKnown };
        }
        return states;
    }

    // The ids in the order of the last plan (providers first): unload() destroys in reverse
    property var _order: []

    // The records, dependents before their providers
    function _teardownOrder() {
        const rank = new Map(_order.map((id, index) => [id, index]));
        return _records.slice().sort((a, b) => (rank.get(b.manifest.id) ?? -1) - (rank.get(a.manifest.id) ?? -1));
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
        // Tells the host when this main is really gone (destroy() only asks for it): a child
        // of the main, destroyed with it, after the main's own Component.onDestruction
        _goneWatcher.createObject(object, { gone: () => root._mainGone(object) });
        // (1.18) Its exports object, read once: what its dependents get as module.uses.<id>
        // for as long as this main lives
        if (record.manifest.exports) {
            const offered = ModuleRules.exportsOf(object, [root].concat(Array.from(_handles.values())));
            record.exportsObject = offered.object;
            record.exportsProblem = offered.problem;
        }
        // module.main: set right after the main is made, before _publish builds its views
        mainsRevision++;
    }

    // Takes a module's main away: module.main and its exports cleared now, the object
    // destroyed by _reap — at once, unless it is a provider whose dependents' mains are not
    // gone yet
    function _destroyMain(record) {
        const main = record.main;
        const offered = record.exportsObject;
        // module.main cleared before the main goes
        record.main = null;
        record.component = null;
        record.exportsObject = null;
        record.exportsProblem = "";
        if (!main)
            return;
        mainsRevision++;
        _going.push({ id: record.manifest.id, main: main, offered: offered, uses: _uses.get(record.manifest.id) ?? _noUses, destroying: false });
        _reap();
    }

    // (1.18) The mains asked to go and not gone yet: { id, main, offered (its exports object,
    // or null), uses (what its module.uses held), destroying }
    property var _going: []
    // The host itself is being destroyed: nothing more is done for the mains going with it
    property bool _dying: false

    // Destroys each going main that nothing waits on: a provider's (its exports object) only
    // once no going dependent's main holds it in its module.uses — so a dependent's main, and
    // its views torn down meanwhile, can still use the provider's object while they go
    function _reap() {
        if (_dying)
            return;
        for (const entry of _going) {
            if (entry.destroying)
                continue;
            if (entry.offered && _going.some(other => other !== entry && Object.values(other.uses).includes(entry.offered)))
                continue;
            entry.destroying = true;
            try {
                entry.main.destroy();
            } catch (error) {
                console.error("[Modules] destroying the main of " + entry.id + " threw:", error);
            }
        }
    }

    // A main is gone (its watcher went with it): the providers waiting on it go next, one
    // turn of the event loop later, after what was torn down with it
    function _mainGone(main) {
        if (_dying)
            return;
        const left = _going.filter(entry => entry.main !== main);
        if (left.length === _going.length)
            return;
        _going = left;
        Qt.callLater(root._reap);
    }

    property Component _goneWatcher: Component {
        QtObject {
            property var gone: null
            Component.onDestruction: gone?.()
        }
    }

    // The shell reloading (or a suite) destroys the host: the engine runs every main's
    // Component.onDestruction, newest first — a dependent's main is always newer than its
    // providers' (made after them, and gone before them) — and then deletes them. Nothing is
    // asked of the modules here, and nothing more is scheduled
    Component.onDestruction: _dying = true

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
                errors.push(ModuleRules.missingProgramText(program, _fromStandIns(record) ? "test" : "path", record.manifest.testPrograms,
                                                           _programsTimedOut.includes(program) ? checkTimeoutMs / 1000 : 0));
            if (record.state === "safe-mode" && safeModeReason !== "")
                errors.push(safeModeReason);
            errors.push(...(record.dependencyReasons ?? []));
            if (record.state === "loaded" && record.exportsProblem)
                errors.push("exports: " + record.exportsProblem);
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
            const warnings = record.shadowedBy === "" && _dataFailed(record.manifest.id)
                ? record.warnings.concat([_dataWarning(record.manifest.id)]) : record.warnings;
            return ModuleMergeRules.statusOf({
                manifest: record.manifest, directory: record.directory, state: record.state || "failed",
                enabled: !disabledIds.includes(record.manifest.id), errors: errors, warnings: warnings,
                deprecations: record.deprecations.concat(ModuleRules.testGateDeprecations(testMode, record.manifest.api)),
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
        const standIns = {};
        for (const record of _records) {
            if (record.shadowedBy === "" && record.manifest.id && record.testVerdicts && _fromStandIns(record))
                standIns[record.manifest.id] = record.testVerdicts;
        }
        if (JSON.stringify(standIns) !== JSON.stringify(testProgramVerdicts))
            testProgramVerdicts = standIns;
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
            for (const record of _teardownOrder())
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
        testProgramVerdicts = ({});
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

    // Test mode: each module's programs looked for in its testPrograms directory, never on
    // PATH (ModuleRules.testProgramProbeScript, testProgramVerdicts); one module per run,
    // one run at a time, the others when it has answered. An answer for a record that is
    // gone (a load() since), or that test mode no longer applies to, is dropped. A name the
    // run did not answer (it ran out of time) is "not found"
    property bool _checkingTestPrograms: false
    property var _testProgramsQueue: []
    // The record whose stand-ins are being looked at (not asked for again meanwhile by _apply)
    property var _testProgramsLooking: null

    function _checkTestPrograms(records) {
        _testProgramsQueue = _testProgramsQueue.concat(records.filter(record => !_testProgramsQueue.includes(record) && record !== _testProgramsLooking));
        if (_checkingTestPrograms)
            return;
        const record = _testProgramsQueue[0];
        _testProgramsQueue = _testProgramsQueue.slice(1);
        if (!record)
            return;
        if (!_records.includes(record) || !_fromStandIns(record)) {
            _checkTestPrograms([]);
            return;
        }
        const names = _programNames(record.manifest);
        const directory = ModuleRules.testProgramsDirectory(record.directory, record.manifest.testPrograms);
        const lines = [];
        _checkingTestPrograms = true;
        _testProgramsLooking = record;
        _check([ModuleRules.probeShell, "-c", ModuleRules.testProgramProbeScript, "sh", record.directory, directory].concat(names), {
            environment: { PATH: ModuleRules.probeToolPath },
            onLine: (line, stream) => {
                if (stream === "stdout")
                    lines.push(line);
            },
            done: result => {
                root._checkingTestPrograms = false;
                root._testProgramsLooking = null;
                root._testProgramsAnswered(record, names, directory, lines);
                root._applyGuarded();
                root._checkTestPrograms([]);
            }
        });
    }

    function _testProgramsAnswered(record, names, directory, lines) {
        if (!_records.includes(record) || !_fromStandIns(record))
            return;
        const answered = ModuleRules.testProgramVerdicts(lines, names, directory);
        const verdicts = {};
        for (const name of names)
            verdicts[name] = answered[name] ?? Object.freeze({ path: "", real: "", trusted: false, reason: "the look-up gave no answer", owner: "", mode: "" });
        // One line per change of what its stand-ins are
        if (logStates && JSON.stringify(record.testVerdicts) !== JSON.stringify(verdicts)) {
            const found = names.filter(name => verdicts[name].path !== "");
            console.info("[Modules] " + record.manifest.id + ": test mode, programs from " + directory + ": "
                         + (found.length > 0 ? found.join(", ") : "none") + (found.length < names.length
                            ? "; no stand-in for " + names.filter(name => verdicts[name].path === "").join(", ") : ""));
        }
        record.testVerdicts = verdicts;
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
