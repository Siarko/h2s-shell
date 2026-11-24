import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

// config.json read and written (Config holds one; a suite one on a scratch file): what the
// file says about itself once read — whether it could be read, whether it held the
// acknowledgements, the version that wrote it, and whether that was a newer shell
// (MigrationRules.newerConfig, newerNotice) —, and a save that stamps this version and keeps
// the keys this version does not declare (JsonConfigFile). `adapter` is a ConfigAdapter.
JsonConfigFile {
    id: root

    // The file is there but could not be read or is not a JSON object
    // (ProfileRules.configReadFailed)
    property bool loadFailed: false
    // Whether the file held acknowledgedModules, and the version that wrote it ("" for none)
    property bool acknowledgedModulesInFile: false
    property string writtenByAtLoad: ""
    // Why the file could not be read ("" when it was, or is missing)
    property string readError: ""
    // Written by a newer shell: the banner's and the log line's text (MigrationRules.newerNotice)
    property var newerNotice: MigrationRules.newerNotice(null, Version.number)
    // The version stamped on each save (a suite gives another)
    property string version: Version.number

    // The file was read (or found missing, or unreadable) and the properties above say what
    // it holds
    signal read

    // ---- The settings migrations (ConfigMigration) ----

    // config.json, for load(): the migrations run on it before it is read (a file:// URL or a
    // path); "" when `path` is set directly
    property string configPath: ""
    // The migrations (Migrations.all(); a suite hands its own)
    property var registry: Migrations.all()
    // Nothing written: no migration result, no backup (the test runner)
    property bool readOnly: false
    // Where a config migrated in memory only is put for a moment, for the adapter to read
    property string viewDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp")
    // The last runs' reports, { load, afterSeed } (ConfigMigration's result.report; null for a
    // phase not run): what the failure notice tells
    property var migrationReports: ({ load: null, afterSeed: null })
    // A run could not be written, or could not be made at all: the session must not save
    property bool migrationReadOnly: false
    readonly property bool migrationBusy: _migration.busy
    property bool _afterSeedStarted: false
    property string _viewPath: ""

    // A run ended (its report in migrationReports), before its result is read
    signal migrated(var result)
    // The backups were pruned after a run that wrote one
    signal backupsPruned

    // The load phase: the pending migrations run on configPath, then the file (or, when the
    // result was not written, the migrated content in memory) is read — `read` comes after it
    function load() {
        if (configPath === "" || !_migration.start("load", "")) {
            if (configPath !== "")
                path = configPath;
        }
    }

    // The after-seed phase, once per run, once the profiles exist: the content as it stands
    // is migrated, written, and put into the adapter. false while it cannot run yet.
    function runAfterSeed() {
        if (_afterSeedStarted || configPath === "" || _migration.running || !adapter || adapter.profiles === "")
            return false;
        _afterSeedStarted = true;
        if (!_migration.start("afterSeed", currentText()))
            _afterSeedStarted = false;
        return _afterSeedStarted;
    }

    property ConfigMigration _migration: ConfigMigration {
        configPath: root.configPath
        registry: root.registry
        readOnly: root.readOnly
        version: root.version
        viewDir: root.viewDir
        onPruned: root.backupsPruned()
        onFinished: result => {
            const reports = Object.assign({}, root.migrationReports);
            reports[result.phase] = result.report;
            root.migrationReports = reports;
            if (result.readOnly)
                root.migrationReadOnly = true;
            root.migrated(result);
            if (result.phase === "load") {
                root._viewPath = result.viewPath;
                root.path = result.viewPath !== "" ? result.viewPath : root.configPath;
                return;
            }
            if (result.text === "")
                return;
            if (result.written)
                root.written(result.text);
            root.apply(JSON.parse(result.text));
        }
    }


    onLoaded: {
        // A migrated config shown in memory only: its file is not needed once read
        if (_viewPath !== "" && path === _viewPath) {
            _migration.dropView(_viewPath);
            _viewPath = "";
        }
        const content = text();
        loadFailed = ProfileRules.configReadFailed("", content);
        readError = "";
        let data = null;
        try {
            data = JSON.parse(content);
        } catch (error) {
            data = null;
        }
        acknowledgedModulesInFile = data !== null && typeof data === "object" && Object.prototype.hasOwnProperty.call(data, "acknowledgedModules");
        writtenByAtLoad = typeof data?.writtenBy === "string" ? data.writtenBy : "";
        newerNotice = MigrationRules.newerNotice(MigrationRules.newerConfig(data?.writtenBy, data?.migratedKeys, version, Migrations.all()), version);
        read();
    }
    onLoadFailed: error => {
        loadFailed = ProfileRules.configReadFailed(error === FileViewError.FileNotFound ? "missing" : "error", "");
        readError = loadFailed ? FileViewError.toString(error) : "";
        acknowledgedModulesInFile = false;
        writtenByAtLoad = "";
        newerNotice = MigrationRules.newerNotice(null, version);
        read();
    }

    // Writes the adapter's content, stamped with this version
    function saveStamped() {
        adapter.writtenBy = version;
        save();
    }
}
