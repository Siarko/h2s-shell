import QtQuick
import Quickshell.Io
import qs.singletons

// One run of the settings migrations on config.json and its side files (ConfigFile holds
// one): reads the config (the load phase: the file as it is on disk; the after-seed phase:
// the text it is handed) and the side files the registered migrations name, asks
// MigrationRules.startup what to do, and does it — the backup first (only when something
// changed or a scope was reset), the side files, then the config with the records, each
// write atomic —; then prunes the config backups to the newest automatic ones
// (MigrationRules.backupsToKeep). Read-only (the test runner): nothing written, no backup,
// nothing pruned; what the migrations made is handed back for the readers only. A write that
// fails leaves the rest unwritten (the records last: the run repeats at the next start) and
// the session read-only.
QtObject {
    id: root

    // config.json (a path or a file:// URL)
    property string configPath: ""
    // The migrations, in order (Migrations.all(); a suite hands its own)
    property var registry: []
    property bool readOnly: false
    property string version: Version.number
    // Where a config migrated in memory only is put for the adapter to read (removed once read)
    property string viewDir: "/tmp"
    // A run goes on (until `finished`)
    readonly property bool running: _phase !== ""
    readonly property bool busy: running || _pruneLister.running || _pruneRemover.running

    // A run ended. `result`: { phase, report (MigrationRules.startup's, with `backup`: the
    // backup's path or ""), readOnly (the session stays read-only), written (the config was
    // written), text (the config's content when it changed: written, or in memory only; "" when
    // unchanged), viewPath (a file holding `text` when it was not written; "" otherwise) }
    signal finished(var result)
    // The backups were pruned after a run that wrote one
    signal pruned

    property string _phase: ""
    property var _outcome: null
    property string _backup: ""
    property string _diskText: ""
    property var _raw: null
    property bool _pruneAgain: false
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

    // Starts a run: `phase` "load" reads config.json itself, "afterSeed" takes `text`, the
    // config as it stands. A run asked for while one goes on is refused (false).
    function start(phase, text) {
        if (_phase !== "" || _file === "")
            return false;
        _phase = phase === "afterSeed" ? "afterSeed" : "load";
        _diskText = _read(_file);
        const source = _phase === "load" ? _diskText : (typeof text === "string" ? text : "");
        _raw = null;
        if (source.trim() !== "") {
            try {
                _raw = JSON.parse(source);
            } catch (error) {
                _raw = undefined;
            }
        }
        const depth = MigrationRules.sideFileDepth(registry);
        if (depth === 0) {
            _decide({}, []);
            return true;
        }
        _lister.command = ["find", _dir, "-mindepth", "1", "-maxdepth", String(depth), "-xtype", "f", "-printf", "%P\\n"];
        _lister.running = true;
        return true;
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
        const unreadable = [];
        for (const name of names) {
            const text = _read(_dir + "/" + name);
            try {
                const value = JSON.parse(text);
                Object.defineProperty(files, name, { value: value, enumerable: true, writable: true, configurable: true });
            } catch (error) {
                unreadable.push(name);
            }
        }
        _decide(files, unreadable);
    }

    function _decide(files, unreadable) {
        _outcome = MigrationRules.startup(registry, _raw, files, unreadable, { phase: _phase, version: version, context: { version: version } });
        _backup = "";
        _log(_outcome);
        if (!_outcome.write || readOnly) {
            const shown = _outcome.view ?? (_outcome.write ? _outcome.config : null);
            _finish(_outcome.readOnly, false, shown);
            return;
        }
        if (_outcome.backup) {
            const name = MigrationRules.backupName(new Date().toISOString(), "migration");
            // The file as it is on disk: what the run started from
            if (!_write(_dir + "/" + name, _diskText)) {
                _failed("could not write the backup " + _dir + "/" + name + ": " + _writeError);
                return;
            }
            _backup = _dir + "/" + name;
            console.log("[Migrations] Backup of the config before the run:", _backup);
        }
        // FileView does not create folders
        const folders = [_dir];
        for (const file of Object.keys(_outcome.files))
            folders.push((_dir + "/" + file).replace(/\/[^\/]*$/, ""));
        _mkdir.command = ["mkdir", "-p", "--"].concat(folders);
        _mkdir.running = true;
    }

    property Process _mkdir: Process {
        onExited: code => {
            if (code !== 0) {
                root._failed("could not create the config's folders");
                return;
            }
            root._writeSideFiles();
        }
    }

    function _writeSideFiles() {
        for (const file of Object.keys(_outcome.files)) {
            // As the theme files are written
            if (!_write(_dir + "/" + file, JSON.stringify(_outcome.files[file], null, 2) + "\n")) {
                _failed("could not write " + _dir + "/" + file + ": " + _writeError);
                return;
            }
        }
        if (_outcome.removed.length > 0) {
            _remover.command = ["rm", "-f", "--"].concat(_outcome.removed.map(file => _dir + "/" + file));
            _remover.running = true;
            return;
        }
        _writeConfig();
    }

    property Process _remover: Process {
        onExited: code => {
            if (code !== 0)
                root._failed("could not remove " + root._outcome.removed.join(", "));
            else
                root._writeConfig();
        }
    }

    function _writeConfig() {
        if (!_write(_file, MigrationRules.configText(_outcome.config))) {
            _failed("could not write " + _file + ": " + _writeError);
            return;
        }
        _finish(false, true, _outcome.config);
        if (_backup !== "")
            _prune();
    }

    // A write failed: what is written stays (the records are not, so the run repeats), the
    // readers get the migrated config in memory, and nothing is saved this session
    function _failed(problem) {
        console.warn("[Migrations] " + problem + ": the config is not saved until the next start");
        _outcome.report.problem = problem;
        _finish(true, false, _outcome.config);
    }

    function _finish(readOnlySession, written, config) {
        const text = config ? MigrationRules.configText(config) : "";
        let viewPath = "";
        if (!written && text !== "" && _phase === "load") {
            viewPath = viewDir + "/h2s-shell-config-view-" + Date.now() + "-" + Math.floor(Math.random() * 1e9) + ".json";
            if (!_write(viewPath, text)) {
                console.warn("[Migrations] could not put the migrated config in " + viewPath + ": " + _writeError);
                viewPath = "";
            }
        }
        const report = Object.assign({}, _outcome.report, { backup: _backup });
        const result = { phase: _phase, report: report, readOnly: readOnlySession, written: written, text: text, viewPath: viewPath };
        _phase = "";
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

    function _prune() {
        if (_pruneLister.running || _pruneRemover.running) {
            _pruneAgain = true;
            return;
        }
        _pruneAgain = false;
        _pruneLister.written = _backup.substring(_backup.lastIndexOf("/") + 1);
        _pruneLister.command = ["ls", "-1A", "--", _dir];
        _pruneLister.running = true;
    }

    property Process _pruneLister: Process {
        property string written: ""
        stdout: StdioCollector { id: _backupNames }
        onExited: code => {
            if (code !== 0) {
                console.warn("[Migrations] could not list " + root._dir + ": no backups pruned");
                root._prunedOne();
                return;
            }
            const plan = MigrationRules.backupsToKeep(_backupNames.text.split("\n"), { written: written });
            if (plan.delete.length === 0) {
                root._prunedOne();
                return;
            }
            console.log("[Migrations] Older backups removed:", plan.delete.join(", "));
            root._pruneRemover.command = ["rm", "-f", "--"].concat(plan.delete.map(name => root._dir + "/" + name));
            root._pruneRemover.running = true;
        }
    }

    property Process _pruneRemover: Process {
        onExited: root._prunedOne()
    }

    function _prunedOne() {
        if (_pruneAgain) {
            _prune();
            return;
        }
        pruned();
    }
}
