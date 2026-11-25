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
// shell restarted — refused while a run goes on or the shell cannot restart).
QtObject {
    id: root

    // config.json (a path or a file:// URL)
    property string configPath: ""
    property string version: Version.number
    // The migrations (Migrations.all())
    property var registry: []
    // MigrationFailureNotice: its restoreBackup carries Apply out
    property var notice: null

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
        _lister.command = ["ls", "-1A", "--", dir];
        _lister.running = true;
    }

    property bool _again: false

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
            for (const name of _names.text.split("\n")) {
                if (!ConfigBackupRules.parseName(name).ok)
                    continue;
                const text = root._read(root.dir + "/" + name);
                entries.push({ name: name, text: text });
            }
            root.rows = ConfigBackupRules.rows(entries, root.version, root.registry);
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
        if (path === "")
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
