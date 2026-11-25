import QtQuick
import Quickshell.Io
import qs.singletons

// Prunes the config backups in config.json's folder after one was written: the folder listed,
// MigrationRules.backupsToKeep decides (the newest automatic ones; manual ones and the
// protected never), each deleted backup removed with the folder of side files it holds. One
// at a time: a prune asked for while one runs runs again once it is done, with the last
// names it was given.
QtObject {
    id: root

    // config.json's folder
    property string dir: ""
    readonly property bool busy: _lister.running || _remover.running

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
        _lister.command = ["ls", "-1A", "--", dir];
        _lister.running = true;
    }

    property Process _lister: Process {
        stdout: StdioCollector { id: _names }
        onExited: code => {
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
            const paths = [];
            for (const name of plan.delete)
                paths.push(root.dir + "/" + name, root.sideFolder(name));
            root._remover.command = ["rm", "-rf", "--"].concat(paths);
            root._remover.running = true;
        }
    }

    property Process _remover: Process {
        onExited: root._done()
    }

    function _done() {
        if (_again) {
            prune(_written, _protect);
            return;
        }
        pruned();
    }
}
