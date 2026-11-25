import QtQuick
import Quickshell.Io
import qs.singletons

// Removes config backups from config.json's folder, each with the folder of side files a
// migration run kept with it (backup-side-files/<name>): the deleting of the backups list and
// of the pruning. A backup that is a folder is refused, not emptied; a link of a backup's name
// is removed itself, never what it points to; when backup-side-files is a link, nothing is
// removed at all (its side files would be deleted wherever it points) and it is said.
// The names are the caller's, checked against the backup pattern (ConfigBackupRules.parseName);
// they reach the fixed script as arguments. One removal at a time.
QtObject {
    id: root

    readonly property bool running: _process.running || _running

    property bool _running: false
    property var _done: null

    // The script: $1 the folder, the names after it. Each problem one line on stderr, the
    // status non-zero when there was one
    readonly property string _script: "dir=$1; shift; side=\"$dir/backup-side-files\"; status=0; "
        + "if [ -L \"$side\" ]; then echo \"backup-side-files is a link: nothing deleted\" >&2; exit 1; fi; "
        + "for name in \"$@\"; do "
        + "if [ -d \"$dir/$name\" ] && [ ! -L \"$dir/$name\" ]; then echo \"$name is a folder, not a backup\" >&2; status=1; continue; fi; "
        + "rm -f -- \"$dir/$name\" || { status=1; continue; }; "
        + "if [ -d \"$side\" ] && { [ -e \"$side/$name\" ] || [ -L \"$side/$name\" ]; }; then rm -rf -- \"$side/$name\" || status=1; fi; "
        + "done; exit $status"

    // Removes the backups `names` (bare names of the pattern) from `dir`. `done({ ok, problem })`
    // — `problem` the first line of what went wrong. false when it cannot start (one runs, no
    // folder, a name that is no backup)
    function remove(dir, names, done) {
        const list = Array.isArray(names) ? names : [];
        if (running || typeof dir !== "string" || dir === "" || list.length === 0
                || list.some(name => typeof name !== "string" || name.includes("/") || !ConfigBackupRules.parseName(name).ok))
            return false;
        _running = true;
        _done = done ?? null;
        _process.command = ["sh", "-c", _script, "sh", dir].concat(list);
        _process.running = true;
        return true;
    }

    property Process _process: Process {
        stderr: StdioCollector { id: _errors }
        onExited: code => {
            const done = root._done;
            root._done = null;
            root._running = false;
            const first = (_errors.text.trim().split("\n")[0] ?? "").slice(0, 200);
            if (typeof done === "function")
                done({ ok: code === 0, problem: code === 0 ? "" : first !== "" ? first : "could not delete" });
        }
    }
}
