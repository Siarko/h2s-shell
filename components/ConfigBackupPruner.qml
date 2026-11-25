import QtQuick
import Quickshell.Io
import qs.singletons

// Prunes the config backups in config.json's folder after one was written: the folder's
// regular files listed (a folder or a link of a backup's name is never a backup),
// MigrationRules.backupsToKeep decides (the newest automatic ones; manual ones and the
// protected never), each deleted backup removed with the folder of side files it holds
// (ConfigBackupRemover: nothing removed through a linked backup-side-files). One
// at a time: a prune asked for while one runs runs again once it is done, with the last
// names it was given.
QtObject {
    id: root

    // config.json's folder
    property string dir: ""
    readonly property bool busy: _lister.running || _remover.running || _listing

    // A prune ended (also when nothing was removed or the folder could not be listed)
    signal pruned

    property bool _again: false
    property string _written: ""
    property var _protect: []

    // The folder holding the side files of the backup named `name`
    function sideFolder(name) {
        return dir + "/backup-side-files/" + name;
    }

    // `written`: the backup just written (its name or path); `protect`: names kept whatever
    // their age (a backup a restore reads)
    function prune(written, protect) {
        _written = String(written ?? "").replace(/^.*\//, "");
        _protect = Array.isArray(protect) ? protect.map(name => String(name).replace(/^.*\//, "")) : [];
        if (busy) {
            _again = true;
            return;
        }
        _again = false;
        if (dir === "") {
            Qt.callLater(_done);
            return;
        }
        _listing = true;
        _lister.command = ["find", "-H", dir, "-mindepth", "1", "-maxdepth", "1", "-type", "f", "-printf", "%f\\n"];
        _lister.running = true;
    }

    property bool _listing: false

    property Process _lister: Process {
        stdout: StdioCollector { id: _names }
        onExited: code => {
            root._listing = false;
            if (code !== 0) {
                console.warn("[Migrations] could not list " + root.dir + ": no backups pruned");
                root._done();
                return;
            }
            const plan = MigrationRules.backupsToKeep(_names.text.split("\n"), { written: root._written, protect: root._protect });
            if (plan.delete.length === 0) {
                root._done();
                return;
            }
            console.log("[Migrations] Older backups removed:", plan.delete.join(", "));
            const started = root._remover.remove(root.dir, plan.delete, result => {
                if (!result.ok)
                    console.warn("[Migrations] pruning backups: " + result.problem);
                root._done();
            });
            if (!started)
                root._done();
        }
    }

    property ConfigBackupRemover _remover: ConfigBackupRemover {}

    function _done() {
        if (_again) {
            prune(_written, _protect);
            return;
        }
        pruned();
    }
}
