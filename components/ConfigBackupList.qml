import QtQuick
import Quickshell.Io
import qs.singletons

// The config backups in config.json's folder, read for the Settings list and IPC
// (MigrationNotice holds the shell's one; a suite one on a scratch folder): refresh() lists
// the folder and reads each backup (ConfigBackupRules.rows: newest first, the reason from the
// name, the version that wrote it, a newer writer, an unreadable one kept as such);
// preview(name) runs a backup's pending migrations in memory (ConfigBackupRules.preview);
// apply(name, held) restores it through the failure notice's restore
// (MigrationFailureNotice.restoreBackup: the current config backed up, saving held, the
// shell restarted — refused while a run goes on or the shell cannot restart);
// makeBackup() writes a manual backup (never pruned); deleteBackup(name) removes one backup,
// never the one a restore reads or the failure notice's restore needs.
QtObject {
    id: root

    // config.json (a path or a file:// URL)
    property string configPath: ""
    property string version: Version.number
    // The migrations (Migrations.all())
    property var registry: []
    // MigrationFailureNotice: its restoreBackup carries Apply out
    property var notice: null
    // The modules there now, { id: display name } (a module switch's row names it)
    property var moduleNames: () => ({})

    // The rows (ConfigBackupRules.rows), and whether the folder was read once
    property var rows: []
    property bool known: false
    readonly property bool listing: _lister.running

    readonly property string _file: {
        const plain = configPath.replace(/^file:\/\//, "");
        try {
            return decodeURIComponent(plain);
        } catch (error) {
            return plain;
        }
    }
    readonly property string dir: _file.substring(0, _file.lastIndexOf("/"))

    property FileView _reader: FileView {
        blockAllReads: true
        printErrors: false
    }

    function _read(path) {
        _reader.path = "";
        _reader.path = path;
        _reader.reload();
        return _reader.text() ?? "";
    }

    // Lists the folder again; a listing asked for while one runs follows it
    function refresh() {
        if (dir === "")
            return;
        if (_lister.running) {
            _again = true;
            return;
        }
        _again = false;
        // Each file with its size (one too large is not read), then each folder in
        // backup-side-files (none when it is a link)
        _lister.command = ["sh", "-c", "find -H \"$1\" -mindepth 1 -maxdepth 1 -type f -printf 'f %s\\t%f\\n' || exit 1; side=\"$1/backup-side-files\"; "
            + "if [ -d \"$side\" ] && [ ! -L \"$side\" ]; then find \"$side\" -mindepth 1 -maxdepth 1 -type d -printf 'd %f\\n' 2>/dev/null; fi; exit 0", "sh", dir];
        _lister.running = true;
    }

    property bool _again: false
    // The sizes the last listing found, by name
    property var _sizes: ({})

    property Process _lister: Process {
        stdout: StdioCollector { id: _names }
        onExited: code => {
            if (root._again) {
                root.refresh();
                return;
            }
            if (code !== 0) {
                // A folder that cannot be listed shows no backups, and says it was not read
                root.rows = [];
                root.known = false;
                return;
            }
            const entries = [];
            const sizes = {};
            const lines = _names.text.split("\n");
            const sideFolders = lines.filter(line => line.startsWith("d ")).map(line => line.slice(2));
            for (const listed of lines) {
                if (!listed.startsWith("f "))
                    continue;
                const line = listed.slice(2);
                const tab = line.indexOf("\t");
                const name = line.slice(tab + 1);
                if (tab < 0 || !ConfigBackupRules.parseName(name).ok)
                    continue;
                const size = Number(line.slice(0, tab));
                Object.defineProperty(sizes, name, { value: size, enumerable: true });
                if (!(size <= ConfigBackupRules.maxBackupBytes)) {
                    entries.push({ name: name, text: "", tooLarge: true });
                    continue;
                }
                entries.push({ name: name, text: root._read(root.dir + "/" + name) });
            }
            root._sizes = sizes;
            let names = {};
            try {
                names = root.moduleNames() ?? {};
            } catch (error) {}
            root.rows = ConfigBackupRules.rows(entries, root.version, root.registry, names, sideFolders);
            root.known = true;
        }
    }

    // A name that is a backup in the folder: a bare name of the pattern
    function _path(name) {
        if (typeof name !== "string" || name.includes("/") || !ConfigBackupRules.parseName(name).ok || dir === "")
            return "";
        return dir + "/" + name;
    }

    // What Apply would do with backup `name` (ConfigBackupRules.preview), read now
    function preview(name) {
        const path = _path(name);
        if (path === "" || _sizes[name] > ConfigBackupRules.maxBackupBytes)
            return ConfigBackupRules.preview(registry, "", version);
        return ConfigBackupRules.preview(registry, _read(path), version);
    }

    // Apply backup `name` with `held` held (the question's subject). → "" started, else why not
    function apply(name, held) {
        const path = _path(name);
        if (path === "")
            return "Not a backup: " + String(name ?? "").slice(0, 80);
        if (!notice)
            return "Could not start";
        return notice.restoreBackup(path, held);
    }

    // Make a backup now: config.json as it is now, as a manual backup
    // (MigrationFailureNotice.backUpNow), the list read again once it is written.
    // `done({ ok, problem, name })` — `name` the backup made ("" none). → "" started, else why not
    function makeBackup(done) {
        if (!notice)
            return "Could not start";
        return notice.backUpNow(result => {
            const name = String(result?.backup ?? "").replace(/^.*\//, "");
            const problem = !result?.ok ? String(result?.problem ?? "") : name === "" ? "No settings file to back up yet" : "";
            root.refresh();
            if (typeof done === "function")
                done({ ok: problem === "", problem: problem, name: name });
        });
    }

    // Why backup `name` cannot be deleted now ("" it can): not while a restore reads it or the
    // failure notice's restore needs it (ConfigBackupRules.deleteRefusal)
    function deleteRefusal(name) {
        if (!notice)
            return "Could not start";
        return ConfigBackupRules.deleteRefusal(name, {
            testRunner: notice.testRunner, deleting: deleting, reading: notice.restoring,
            needed: notice.current?.backup ? [notice.current.backup] : []
        });
    }

    // Deletes backup `name`: that file, and the side files a migration run kept with it
    // (backup-side-files/<name>), nothing else (ConfigBackupRemover: a folder of the name is
    // refused, nothing is removed through a link); the list read again. `done({ ok, problem })`.
    // → "" started, else why not
    function deleteBackup(name, done) {
        const refusal = deleteRefusal(name);
        if (refusal !== "")
            return refusal;
        if (_path(name) === "")
            return "Not a backup: " + String(name ?? "").slice(0, 80);
        _deleteRunning = true;
        const started = _remover.remove(dir, [name], result => {
            if (result.ok)
                console.info("[Migrations] backup deleted: " + root.dir + "/" + name);
            root._deleted(result.ok, result.ok ? "" : "Could not delete: " + result.problem, done);
        });
        if (!started) {
            _deleteRunning = false;
            return "Could not start";
        }
        return "";
    }

    // A delete runs (set at once: a Process says it runs only once it started)
    readonly property bool deleting: _deleteRunning
    property bool _deleteRunning: false

    property ConfigBackupRemover _remover: ConfigBackupRemover {}

    function _deleted(ok, problem, done) {
        _deleteRunning = false;
        refresh();
        if (typeof done === "function")
            done({ ok: ok, problem: problem });
    }

    // Apply backup `name` with what its preview holds now (IPC). → "" started, else why not
    function applyNow(name) {
        if (_path(name) === "")
            return "Not a backup: " + String(name ?? "").slice(0, 80);
        const seen = preview(name);
        if (!seen.ok)
            return "The backup can't be read";
        return apply(name, seen.held);
    }
}
