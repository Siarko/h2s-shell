import QtQuick
import Quickshell.Io
import qs.singletons

// One run of the settings migrations on config.json and its side files (ConfigFile holds
// one): reads the config (the load phase: the file as it is on disk; the after-seed phase:
// the text it is handed) and the side files the registered migrations name, asks
// MigrationRules.startup what to do, and does it — the backup first (only when something
// changed or a scope was reset; with the side files it overwrites or removes and the list
// of those it creates, readable by the user only), the side files, then the config with the records, each write atomic, and
// only then the side files it removes —; then prunes the config backups to the newest
// automatic ones (MigrationRules.backupsToKeep). Read-only (the test runner): nothing
// written, no backup, nothing pruned; what the migrations made is handed back for the
// readers only. A write that fails leaves the rest unwritten (the records last: the run
// repeats at the next start) and saving blocked for the session.
QtObject {
    id: root

    // config.json (a path or a file:// URL)
    property string configPath: ""
    // The migrations, in order (Migrations.all(); a suite hands its own)
    property var registry: []
    property bool readOnly: false
    property string version: Version.number
    // Where a config migrated in memory only is put for the adapter to read (removed once
    // read): a private folder (the runtime folder); "" for none, and then none is made
    property string viewDir: ""
    // config.json is being replaced (a restore): a run not yet written writes nothing more
    property bool writesHeld: false
    // A run goes on (until `finished`)
    readonly property bool running: _phase !== ""
    readonly property bool busy: running || _pruner.busy

    // A run ended. `result`: { phase, report (MigrationRules.startup's, with `backup`: the
    // backup's path or ""), readOnly (the session stays read-only), written (the config was
    // written), text (the config's content when it changed: written, or in memory only; "" when
    // unchanged), viewPath (a file holding `text` when it was not written; "" otherwise) }
    signal finished(var result)
    // The backups were pruned after a run that wrote one
    signal pruned
    // config.json now holds `text`, written by the run of `phase` (before `finished`: side
    // files may still be removed)
    signal configWritten(string phase, string text)

    property string _phase: ""
    property var _outcome: null
    property string _backup: ""
    property string _diskText: ""
    property var _raw: null
    property var _source: null
    property var _files: ({})
    property var _unreadable: []
    // The side files as read (path → text): what their backups hold
    property var _sideTexts: ({})
    property string _writeError: ""

    readonly property string _file: {
        const plain = configPath.replace(/^file:\/\//, "");
        try {
            return decodeURIComponent(plain);
        } catch (error) {
            return plain;
        }
    }
    readonly property string _dir: _file.substring(0, _file.lastIndexOf("/"))

    property FileView _reader: FileView {
        blockAllReads: true
        printErrors: false
    }

    property FileView _writer: FileView {
        blockWrites: true
        blockAllReads: true
        atomicWrites: true
        printErrors: false
        onSaveFailed: error => root._writeError = FileViewError.toString(error)
    }

    function _read(path) {
        _reader.path = "";
        _reader.path = path;
        _reader.reload();
        return _reader.text() ?? "";
    }

    // setText skips a text equal to the one last read: the file is read first
    function _write(path, text) {
        _writeError = "";
        _writer.path = "";
        _writer.path = path;
        _writer.reload();
        _writer.setText(text);
        return _writeError === "";
    }

    // Starts a run: `phase` "load" reads config.json itself; "afterSeed" calls `source()` for
    // the config as it stands — at the start, and again when the config is written. A run
    // asked for while one goes on is refused (false).
    function start(phase, source) {
        if (_phase !== "" || _file === "")
            return false;
        _phase = phase === "afterSeed" ? "afterSeed" : "load";
        _source = _phase === "afterSeed" && typeof source === "function" ? source : null;
        // A restore cut short (the shell ended mid-swap) is put back before anything is read
        if (_phase === "load" && !readOnly && _swap.recover(_dir, result => {
                if (!result.ok)
                    console.warn("[Migrations] " + result.problem);
                root._begin();
            }))
            return true;
        _begin();
        return true;
    }

    property ConfigSideSwap _swap: ConfigSideSwap {}

    function _begin() {
        _sideTexts = {};
        _written = null;
        _diskText = _read(_file);
        let text = "";
        if (_phase === "load")
            text = _diskText;
        else if (_source !== null)
            text = String(_source() ?? "");
        const source0 = text;
        _raw = null;
        if (source0.trim() !== "") {
            try {
                _raw = JSON.parse(source0);
            } catch (error) {
                _raw = undefined;
            }
        }
        const depth = MigrationRules.sideFileDepth(registry);
        if (depth === 0) {
            _decide({}, []);
            return;
        }
        _lister.command = ["find", _dir, "-mindepth", "1", "-maxdepth", String(depth), "-xtype", "f", "-printf", "%P\\n"];
        _lister.running = true;
    }

    property Process _lister: Process {
        stdout: StdioCollector { id: _listed }
        onExited: code => {
            const names = _listed.text.split("\n").filter(name => name !== "");
            // The folder could not be listed (it is there: the config is in it): every side
            // file is unknown, and a pattern stands for the files it names, so a migration
            // reaching them is not run on a guess
            if (code !== 0 && root._raw !== null)
                root._decide({}, root._patterns());
            else
                root._readSideFiles(MigrationRules.sideFilesIn(root.registry, names));
        }
    }

    function _patterns() {
        const patterns = [];
        for (const migration of registry)
            for (const path of MigrationRules.parseScope(migration?.scope).paths)
                if (path.kind === "file")
                    patterns.push(path.pattern);
        return patterns;
    }

    function _readSideFiles(names) {
        const files = {};
        const texts = {};
        const unreadable = [];
        for (const name of names) {
            const text = _read(_dir + "/" + name);
            Object.defineProperty(texts, name, { value: text, enumerable: true, writable: true, configurable: true });
            try {
                const value = JSON.parse(text);
                Object.defineProperty(files, name, { value: value, enumerable: true, writable: true, configurable: true });
            } catch (error) {
                unreadable.push(name);
            }
        }
        _sideTexts = texts;
        _decide(files, unreadable);
    }

    function _decide(files, unreadable) {
        _files = files;
        _unreadable = unreadable;
        _outcome = MigrationRules.startup(registry, _raw, files, unreadable, _options());
        _backup = "";
        _log(_outcome);
        if (!_outcome.write || readOnly) {
            const shown = _outcome.view ?? (_outcome.write && !_outcome.report.fresh ? _outcome.config : null);
            _finish(_outcome.readOnly, false, shown);
            return;
        }
        // FileView does not create folders; the backup's side files go into a folder named
        // after it (not "config.json…": the config's files get mode 600, a folder could not
        // be entered then), private like the backup
        const folders = [_dir];
        for (const file of Object.keys(_outcome.files))
            folders.push(_parent(_dir + "/" + file));
        if (_outcome.backup) {
            _backup = _dir + "/" + MigrationRules.backupName(new Date().toISOString(), "migration");
            for (const file of _backedUpSideFiles())
                folders.push(_parent(_sideBackup(_backup) + "/" + file));
            if (_createdSideFiles().length > 0)
                folders.push(_sideBackup(_backup));
        }
        _prepare.command = ["sh", "-c", "umask 077 && mkdir -p -- \"$@\"", "sh"].concat(folders);
        _prepare.running = true;
    }

    // The folder holding the side files of the backup at `path`
    function _sideBackup(path) {
        return _pruner.sideFolder(path.substring(path.lastIndexOf("/") + 1));
    }

    function _options() {
        return { phase: _phase, version: version, context: { version: version } };
    }

    function _parent(path) {
        return path.replace(/\/[^\/]*$/, "");
    }

    // The side files the run overwrites or removes that are there now: kept with the backup
    function _backedUpSideFiles() {
        return Object.keys(_outcome.files).concat(_outcome.removed)
            .filter(file => Object.prototype.hasOwnProperty.call(_sideTexts, file));
    }

    // The side files the run writes that are not there now: listed with the backup, so that
    // a restore of it removes them (ConfigRestore)
    function _createdSideFiles() {
        return Object.keys(_outcome.files).filter(file => !Object.prototype.hasOwnProperty.call(_sideTexts, file));
    }

    property Process _prepare: Process {
        onExited: code => {
            if (code !== 0) {
                root._failed("could not create the config's folders");
                return;
            }
            root._writeBackup();
        }
    }

    function _writeBackup() {
        if (_backup === "") {
            _writeSideFiles();
            return;
        }
        // The file as it is on disk: what the run started from
        if (!_write(_backup, _diskText)) {
            const path = _backup;
            _backup = "";
            _failed("could not write the backup " + path + ": " + _writeError);
            return;
        }
        const sideFiles = _backedUpSideFiles();
        for (const file of sideFiles) {
            if (!_write(_sideBackup(_backup) + "/" + file, _sideTexts[file])) {
                _failed("could not back up " + file + ": " + _writeError);
                return;
            }
        }
        const created = _createdSideFiles();
        console.log("[Migrations] Backup of the config before the run:", _backup);
        // It holds the Google tokens: readable by the user only, whatever the folder's mode
        _protect.command = ["chmod", "-R", "go-rwx", "--", _backup].concat(sideFiles.length + created.length > 0 ? [_sideBackup(_backup)] : []);
        _protect.running = true;
    }

    property Process _protect: Process {
        onExited: code => {
            if (code !== 0) {
                root._failed("could not restrict the backup's permissions");
                return;
            }
            root._writeSideFiles();
        }
    }

    function _writeSideFiles() {
        if (writesHeld) {
            _failed("config.json is being replaced: the migrations run again at the next start", true);
            return;
        }
        if (_phase === "afterSeed" && typeof _source === "function" && !_againOnCurrent())
            return;
        // The files it creates listed with the backup before they are written (a restore of it
        // removes them while they are what was written here)
        const created = {};
        for (const file of Object.keys(_outcome.files))
            if (!Object.prototype.hasOwnProperty.call(_sideTexts, file))
                Object.defineProperty(created, file, { value: _sideText(file), enumerable: true });
        if (_backup !== "" && Object.keys(created).length > 0
                && !_write(_sideBackup(_backup) + "/" + ConfigBackupRules.createdFilesName, ConfigBackupRules.createdText(created))) {
            _failed("could not list the side files the run creates: " + _writeError);
            return;
        }
        for (const file of Object.keys(_outcome.files)) {
            if (!_write(_dir + "/" + file, _sideText(file))) {
                _failed("could not write " + _dir + "/" + file + ": " + _writeError);
                return;
            }
        }
        _writeConfig();
    }

    // A side file's text as written (as the theme files are)
    function _sideText(file) {
        return JSON.stringify(_outcome.files[file], null, 2) + "\n";
    }

    // After seeding the config is the adapter's and may have been saved since the run began:
    // the migrations run again, on the content as it stands now (the side files as read), just
    // before anything but the backup is written, so that nothing saved meanwhile is written
    // over. A second run that writes nothing, would write other side files, or needs a backup
    // the first did not take is a failure: nothing more written, nothing applied, saves blocked.
    function _againOnCurrent() {
        let raw = undefined;
        try {
            raw = JSON.parse(_source());
        } catch (error) {}
        const now = MigrationRules.startup(registry, raw, _files, _unreadable, _options());
        const sameFiles = JSON.stringify(Object.keys(now.files).sort()) === JSON.stringify(Object.keys(_outcome.files).sort())
            && JSON.stringify(now.removed.slice().sort()) === JSON.stringify(_outcome.removed.slice().sort());
        if (!now.write || now.readOnly || !sameFiles || (now.backup && _backup === "")) {
            _outcome.report.applied = [];
            _outcome.report.reset = [];
            _failed("the config changed while the migrations ran and could not be migrated again"
                    + (now.report.failure ? " (" + (now.report.failure.id || now.report.failure.error) + ")" : ""), true);
            return false;
        }
        _outcome = now;
        return true;
    }

    function _writeConfig() {
        const config = _outcome.config;
        if (config !== null && !_write(_file, MigrationRules.configText(config))) {
            _failed("could not write " + _file + ": " + _writeError);
            return;
        }
        _written = config;
        if (config !== null)
            configWritten(_phase, MigrationRules.configText(config));
        // Side files removed last, once the records are written (each is in the backup)
        if (_outcome.removed.length > 0) {
            _remover.command = ["rm", "-f", "--"].concat(_outcome.removed.map(file => _dir + "/" + file));
            _remover.running = true;
            return;
        }
        _done();
    }

    property var _written: null

    property Process _remover: Process {
        onExited: code => {
            if (code !== 0)
                console.warn("[Migrations] could not remove " + root._outcome.removed.join(", ") + ": left where they are");
            root._done();
        }
    }

    function _done() {
        const backup = _backup;
        _finish(false, _written !== null, _written);
        if (backup !== "")
            _prune(backup);
    }

    // A write failed: what is written stays (the records are not, so the run repeats), the
    // readers get the migrated config in memory, and nothing is saved this session
    // `keepReaders`: the readers keep what they have (the config as it stands is newer than
    // the run's result)
    function _failed(problem, keepReaders) {
        console.warn("[Migrations] " + problem + ": the config is not saved until the next start");
        _outcome.report.problem = problem;
        _finish(true, false, keepReaders === true ? null : _outcome.config);
    }

    // The view: a config not written, put where only the user can read it — the runtime
    // folder (private by definition), never a shared one; without one the readers get the
    // file as it is
    function _finish(readOnlySession, written, config) {
        const text = config ? MigrationRules.configText(config) : "";
        const report = Object.assign({}, _outcome.report, { backup: _backup });
        _result = { phase: _phase, report: report, readOnly: readOnlySession, written: written, text: text, viewPath: "" };
        if (!written && text !== "" && _phase === "load") {
            if (!viewDir.startsWith("/")) {
                console.warn("[Migrations] no runtime folder for the migrated config: it is read as it is on disk");
                _emit();
                return;
            }
            const viewPath = viewDir + "/h2s-shell-config-view-" + Date.now() + "-" + Math.floor(Math.random() * 1e9) + ".json";
            if (!_write(viewPath, text)) {
                console.warn("[Migrations] could not put the migrated config in " + viewPath + ": " + _writeError);
                _emit();
                return;
            }
            _viewProtect.path = viewPath;
            _viewProtect.command = ["chmod", "600", "--", viewPath];
            _viewProtect.running = true;
            return;
        }
        _emit();
    }

    property var _result: null

    property Process _viewProtect: Process {
        property string path: ""
        onExited: code => {
            if (code === 0) {
                root._result.viewPath = path;
            } else {
                console.warn("[Migrations] could not restrict " + path + ": the migrated config is read as it is on disk");
                root.dropView(path);
            }
            root._emit();
        }
    }

    function _emit() {
        const result = _result;
        _result = null;
        _phase = "";
        _source = null;
        finished(result);
    }

    // Removes a view file once the adapter has read it
    function dropView(path) {
        if (typeof path !== "string" || !path.startsWith(viewDir + "/h2s-shell-config-view-"))
            return;
        _viewRemover.command = ["rm", "-f", "--", path];
        _viewRemover.running = true;
    }

    property Process _viewRemover: Process {}

    function _summary(id) {
        const migration = registry.find(each => each?.migrationId === id);
        return typeof migration?.summary === "string" ? migration.summary : "";
    }

    // Always shown, not only in debug: a one-time change to the user's config
    function _log(outcome) {
        const report = outcome.report;
        if (report.fresh && outcome.write)
            console.log("[Migrations] A new config: " + registry.length + " migration(s) recorded as done");
        for (const id of report.applied)
            console.log("[Migrations] " + id + ": " + _summary(id));
        for (const entry of report.reset) {
            const migration = registry.find(each => each?.migrationId === entry.id);
            console.warn("[Migrations] " + entry.id + " failed (" + entry.error + "): its part was reset to defaults (" + (migration?.scope ?? []).join(", ") + ")");
        }
        for (const entry of report.skipped)
            console.warn("[Migrations] " + entry.id + " not run: it depends on " + entry.after + ", which did not run");
        for (const id of report.held)
            console.log("[Migrations] " + id + " held: the previous settings were restored after it failed under this version");
        if (outcome.readOnly)
            console.warn("[Migrations] " + (report.failure?.id ? report.failure.id + " failed: " : "") + (report.failure?.error ?? report.problem)
                         + ": the config is used unchanged and not saved this session");
    }

    // ---- Pruning ----

    function _prune(backup) {
        _pruner.prune(backup, []);
    }

    property ConfigBackupPruner _pruner: ConfigBackupPruner {
        dir: root._dir
        onPruned: root.pruned()
    }
}
