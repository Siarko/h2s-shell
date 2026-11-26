import QtQuick
import Quickshell.Io
import qs.singletons

// Replaces config.json, keeping what it held: the current file is first copied to a backup
// (config.json.bak-<stamp>-restore, readable by the user only), then the new content is
// written (atomic). A restore of a backup in config.json's folder also puts back the side
// files kept with it (backup-side-files/<name>/: what that migration run overwrote or removed),
// with config.json as one step: everything staged first, the files they replace kept with the
// new backup, then swapped; when any part fails, everything is put back as it was. A linked
// backup-side-files or side folder, a link or a non-regular file among the side files or in
// their places, and a name that is no path inside the folder (ConfigBackupRules.sideFilePlan)
// refuse the whole restore. Two contents: a backup with migrations held (restore(): the settings from
// before a failed update, or any backup from the list, MigrationNoticeRules.restoredConfig),
// or a new config with the defaults (startWithDefaults(): MigrationNoticeRules.defaultsConfig).
// The shell restarts afterwards (the caller's): the migrations run once, before any reader, at
// start. backUp() only copies the current file to a backup (a module version switch's). After
// a backup is written the automatic ones are pruned (ConfigBackupPruner), the one a restore
// reads kept. Read-only (the test runner): nothing written. One at a time.
QtObject {
    id: root

    // config.json (a path or a file:// URL)
    property string configPath: ""
    property bool readOnly: false
    property string version: Version.number
    readonly property bool running: _running
    // Backups its pruning always keeps (names or paths): the failure notice's backup
    property var keep: () => []
    // The backup a restore reads ("" none): kept by pruning, never deleted while it runs
    readonly property string reading: _reading

    property bool _running: false
    property string _reading: ""
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

    // The backup at `backupPath` written back as config.json with `held` held under this
    // version. `done({ ok, problem, backup })` — `backup` the copy of the file replaced.
    // false when it cannot start (read-only, one runs, no backup named)
    function restore(backupPath, held, done) {
        if (_running || readOnly || _file === "" || typeof backupPath !== "string" || backupPath === "")
            return false;
        const plain = backupPath.replace(/^file:\/\//, "");
        _reading = plain;
        const text = _read(plain);
        if (text.trim() === "") {
            _reading = "";
            _later(done, { ok: false, problem: "the backup " + plain + " could not be read", backup: "" });
            return true;
        }
        const restored = MigrationNoticeRules.restoredConfig(text, held, version);
        if (!restored.ok) {
            _reading = "";
            _later(done, { ok: false, problem: restored.problem + ": " + plain, backup: "" });
            return true;
        }
        _start(restored.text, done, ConfigBackupRules.sideBackupName(plain, _dir));
        return true;
    }

    // A new config with the defaults (every registered migration recorded as done) in place
    // of config.json. Same answer as restore()
    function startWithDefaults(registry, done) {
        if (_running || readOnly || _file === "")
            return false;
        _start(MigrationNoticeRules.defaultsConfig(registry, version), done);
        return true;
    }

    // A backup of config.json as it is now with `reason` (ConfigBackupRules.reasons; `module`
    // { id, from, to } for "module"), nothing else written. `done({ ok, problem, backup })`;
    // false when it cannot start (read-only, one runs). No file: nothing to back up (ok)
    function backUp(reason, module, done) {
        if (_running || readOnly || _file === "")
            return false;
        _running = true;
        _onlyBackup = true;
        _done = done;
        _backup = "";
        _reason = reason;
        _module = module ?? null;
        const current = _read(_file);
        if (current === "") {
            _finish(true, "");
            return true;
        }
        _writeBackup(current);
        return true;
    }

    function _later(done, result) {
        Qt.callLater(() => {
            if (typeof done === "function")
                done(result);
        });
    }

    property string _text: ""
    property string _backup: ""
    property var _done: null
    property bool _onlyBackup: false
    property string _reason: "restore"
    property var _module: null
    property string _sideName: ""
    property string _staging: ""

    // `sideName`: the backup whose side files go back with the config ("" none)
    function _start(text, done, sideName) {
        _running = true;
        _sideName = sideName ?? "";
        _onlyBackup = false;
        _reason = "restore";
        _module = null;
        _text = text;
        _done = done;
        _backup = "";
        const current = _read(_file);
        if (current === "") {
            _writeConfig();
            return;
        }
        _writeBackup(current);
    }

    function _writeBackup(current) {
        const backup = _dir + "/" + ConfigBackupRules.name(new Date().toISOString(), _reason, _module);
        if (!_write(backup, current)) {
            _finish(false, "could not write the backup " + backup + ": " + _writeError);
            return;
        }
        _backup = backup;
        // It holds the Google tokens: readable by the user only, whatever the folder's mode
        _protect.command = ["chmod", "go-rwx", "--", backup];
        _protect.running = true;
    }

    property Process _protect: Process {
        onExited: code => {
            if (code !== 0) {
                root._finish(false, "could not restrict the backup's permissions");
                return;
            }
            // Pruned before config.json is written: the shell restarts right after that
            root._pruning = true;
            root._pruner.prune(root._backup, root._protected());
        }
    }

    property bool _pruning: false

    function _protected() {
        let kept = [];
        try {
            kept = Array.from(keep() ?? []).filter(name => typeof name === "string" && name !== "");
        } catch (error) {}
        return _reading !== "" ? kept.concat([_reading]) : kept;
    }

    property ConfigBackupPruner _pruner: ConfigBackupPruner {
        dir: root._dir
        onPruned: {
            if (!root._pruning)
                return;
            root._pruning = false;
            if (root._onlyBackup)
                root._finish(true, "");
            else
                root._writeConfig();
        }
    }

    function _writeConfig() {
        if (_sideName !== "") {
            _sideLister.command = ["sh", "-c", _listScript, "sh", _dir, _sideName];
            _sideLister.running = true;
            return;
        }
        _writeConfigOnly();
    }

    function _writeConfigOnly() {
        if (!_write(_file, _text)) {
            _finish(false, "could not write " + _file + ": " + _writeError);
            return;
        }
        _finish(true, "");
    }

    // ---- The side files of the backup restored ----

    // $1 the folder, $2 the backup's name: the side files kept with it, one path a line
    // (relative to its side folder); none when it has none. A link or anything but files and
    // folders there refuses (one line on stderr, non-zero)
    readonly property string _listScript: "dir=$1; name=$2; side=\"$dir/backup-side-files\"; src=\"$side/$name\"; "
        + "if [ -L \"$side\" ]; then echo \"backup-side-files is a link: nothing restored\" >&2; exit 1; fi; "
        + "[ -e \"$side\" ] || exit 0; "
        + "if [ ! -d \"$side\" ]; then echo \"backup-side-files is not a folder: nothing restored\" >&2; exit 1; fi; "
        + "if [ -L \"$src\" ]; then echo \"the side files of $name are a link: nothing restored\" >&2; exit 1; fi; "
        + "[ -e \"$src\" ] || exit 0; "
        + "if [ ! -d \"$src\" ]; then echo \"the side files of $name are not a folder: nothing restored\" >&2; exit 1; fi; "
        + "odd=$(find \"$src\" -mindepth 1 ! -type f ! -type d -print -quit) || exit 1; "
        + "if [ -n \"$odd\" ]; then echo \"${odd#\"$src\"/} in the side files of $name is a link or not a regular file: nothing restored\" >&2; exit 1; fi; "
        + "find \"$src\" -mindepth 1 -type f -printf '%P\\n'"

    // $1 the folder, $2 the backup's name, the side files after them: a private staging
    // folder in the config's folder (the swap is a rename there) with a copy of each under
    // new/; its path on stdout. Nothing outside it is written
    readonly property string _stageScript: "dir=$1; name=$2; shift 2; src=\"$dir/backup-side-files/$name\"; umask 077; "
        + "stage=$(mktemp -d \"$dir/.config-restore.XXXXXX\") || { echo \"could not make a staging folder in $dir\" >&2; exit 1; }; "
        + "for file in \"$@\"; do "
        + "if [ -L \"$src/$file\" ] || [ ! -f \"$src/$file\" ]; then echo \"$file is no regular file in the side files of $name: nothing restored\" >&2; rm -rf -- \"$stage\"; exit 1; fi; "
        + "mkdir -p -- \"$stage/new/$(dirname -- \"$file\")\" && cp -- \"$src/$file\" \"$stage/new/$file\" "
        + "|| { echo \"could not stage $file: nothing restored\" >&2; rm -rf -- \"$stage\"; exit 1; }; "
        + "done; printf '%s\\n' \"$stage\""

    // $1 the folder, $2 the staging folder (config.json and new/ in it), $3 the backup just
    // made ("" none), then an entry per side file: "w:<path>" put back from new/, "r:<path>"
    // removed (the run created it). Every place checked first (no link, nothing but a file
    // where a file goes), the files replaced or removed copied into the new backup's side
    // folder (with the list of those this creates: a restore of that backup removes them) and
    // kept in the staging folder, then config.json renamed into place and each side file
    // after it (a crash between leaves the old config with newer side files, which the
    // migrations run again on, never a migrated config with old side files, which they would
    // not reach again); a step that fails puts back everything done before it. A folder made
    // for a side file whose folder was gone stays. The staging folder is removed in every case
    readonly property string _swapScript: "dir=$1; stage=$2; keep=$3; shift 3; side=\"$dir/backup-side-files\"; config=\"$dir/config.json\"; umask 077; "
        + "count=0; configMoved=0; keepMade=0; "
        + "rollback() { "
        + "if [ $configMoved = 1 ]; then if [ -e \"$stage/old-config.json\" ]; then mv -f -- \"$stage/old-config.json\" \"$config\"; else rm -f -- \"$config\"; fi; fi; "
        + "i=0; for entry in \"$@\"; do [ $i -lt $count ] || break; i=$((i + 1)); file=${entry#?:}; "
        + "if [ -e \"$stage/old/$file\" ]; then mv -f -- \"$stage/old/$file\" \"$dir/$file\"; else rm -f -- \"$dir/$file\"; fi; done; "
        + "if [ $keepMade = 1 ]; then rm -rf -- \"$side/$keep\"; fi; }; "
        + "fail() { echo \"$1: nothing restored\" >&2; shift; rollback \"$@\"; rm -rf -- \"$stage\"; exit 1; }; "
        + "if [ -L \"$config\" ]; then fail \"config.json is a link\" \"$@\"; fi; "
        + "if [ -e \"$config\" ] && [ ! -f \"$config\" ]; then fail \"config.json is not a regular file\" \"$@\"; fi; "
        + "if [ -L \"$stage/config.json\" ] || [ ! -f \"$stage/config.json\" ]; then fail \"the restored config was not staged\" \"$@\"; fi; "
        + "for entry in \"$@\"; do file=${entry#?:}; "
        + "path=$dir; rest=$file; "
        + "while [ \"${rest#*/}\" != \"$rest\" ]; do path=\"$path/${rest%%/*}\"; rest=${rest#*/}; "
        + "if [ -L \"$path\" ]; then fail \"${path#\"$dir\"/} is a link\" \"$@\"; fi; "
        + "if [ -e \"$path\" ] && [ ! -d \"$path\" ]; then fail \"${path#\"$dir\"/} is not a folder\" \"$@\"; fi; done; "
        + "if [ -L \"$dir/$file\" ]; then fail \"$file is a link\" \"$@\"; fi; "
        + "if [ -e \"$dir/$file\" ] && [ ! -f \"$dir/$file\" ]; then fail \"$file is not a regular file\" \"$@\"; fi; "
        + "case $entry in w:*) if [ -L \"$stage/new/$file\" ] || [ ! -f \"$stage/new/$file\" ]; then fail \"$file was not staged\" \"$@\"; fi;; "
        + "r:*) ;; *) fail \"$entry is no side file entry\" \"$@\";; esac; "
        + "done; "
        + "if [ -n \"$keep\" ]; then "
        + "if [ -L \"$side\" ]; then fail \"backup-side-files is a link\" \"$@\"; fi; "
        + "if [ -e \"$side/$keep\" ] || [ -L \"$side/$keep\" ]; then fail \"the side files of $keep are there already\" \"$@\"; fi; "
        + ": > \"$stage/created\" || fail \"could not list the files created\" \"$@\"; "
        + "for entry in \"$@\"; do file=${entry#?:}; "
        + "if [ -f \"$dir/$file\" ]; then keepMade=1; "
        + "{ mkdir -p -- \"$side/$keep/$(dirname -- \"$file\")\" && cp -- \"$dir/$file\" \"$side/$keep/$file\"; } || fail \"could not back up $file\" \"$@\"; "
        + "else case $entry in w:*) printf '%s\\n' \"$file\" >> \"$stage/created\" || fail \"could not list the files created\" \"$@\";; esac; fi; done; "
        + "if [ -s \"$stage/created\" ]; then keepMade=1; "
        + "{ mkdir -p -- \"$side/$keep\" && cp -- \"$stage/created\" \"$side/$keep/.created-files\"; } || fail \"could not list the files created\" \"$@\"; fi; "
        + "fi; "
        + "for entry in \"$@\"; do file=${entry#?:}; if [ -f \"$dir/$file\" ]; then "
        + "{ mkdir -p -- \"$stage/old/$(dirname -- \"$file\")\" && { ln -- \"$dir/$file\" \"$stage/old/$file\" 2>/dev/null || cp -p -- \"$dir/$file\" \"$stage/old/$file\"; }; } "
        + "|| fail \"could not keep $file\" \"$@\"; "
        + "case $entry in w:*) chmod --reference=\"$dir/$file\" -- \"$stage/new/$file\" || fail \"could not keep the mode of $file\" \"$@\";; esac; fi; done; "
        + "if [ -f \"$config\" ]; then "
        + "{ { ln -- \"$config\" \"$stage/old-config.json\" 2>/dev/null || cp -p -- \"$config\" \"$stage/old-config.json\"; } "
        + "&& chmod --reference=\"$config\" -- \"$stage/config.json\"; } || fail \"could not keep config.json\" \"$@\"; "
        + "else chmod 600 -- \"$stage/config.json\" || fail \"could not restrict config.json\" \"$@\"; fi; "
        + "mv -f -- \"$stage/config.json\" \"$config\" || fail \"could not write config.json\" \"$@\"; configMoved=1; "
        + "for entry in \"$@\"; do file=${entry#?:}; "
        + "case $entry in "
        + "w:*) { mkdir -p -- \"$dir/$(dirname -- \"$file\")\" && mv -f -- \"$stage/new/$file\" \"$dir/$file\"; } || fail \"could not write $file\" \"$@\";; "
        + "r:*) rm -f -- \"$dir/$file\" || fail \"could not remove $file\" \"$@\";; "
        + "esac; count=$((count + 1)); done; "
        + "rm -rf -- \"$stage\"; exit 0"

    // The scripts' own line comes last, after what a command it ran said
    function _sideProblem(text, fallback) {
        const lines = String(text ?? "").trim().split("\n");
        const last = (lines[lines.length - 1] ?? "").slice(0, 200);
        return last !== "" ? last : fallback;
    }

    property Process _sideLister: Process {
        stdout: StdioCollector { id: _sideListed }
        stderr: StdioCollector { id: _sideListErrors }
        onExited: code => {
            if (code !== 0) {
                root._finish(false, root._sideProblem(_sideListErrors.text, "could not list the side files of " + root._sideName));
                return;
            }
            const listed = _sideListed.text;
            const created = listed.split("\n").includes(ConfigBackupRules.createdFilesName)
                ? root._read(root._pruner.sideFolder(root._sideName) + "/" + ConfigBackupRules.createdFilesName) : "";
            const plan = ConfigBackupRules.sideFilePlan(listed, created);
            if (!plan.ok) {
                root._finish(false, plan.problem + ": nothing restored");
                return;
            }
            if (plan.write.length + plan.remove.length === 0) {
                root._writeConfigOnly();
                return;
            }
            root._sideEntries = plan.write.map(file => "w:" + file).concat(plan.remove.map(file => "r:" + file));
            root._stager.command = ["sh", "-c", root._stageScript, "sh", root._dir, root._sideName].concat(plan.write);
            root._stager.running = true;
        }
    }

    // The swap's entries: "w:<path>" put back, "r:<path>" removed
    property var _sideEntries: []

    property Process _stager: Process {
        stdout: StdioCollector { id: _staged }
        stderr: StdioCollector { id: _stageErrors }
        onExited: code => {
            const staging = _staged.text.trim();
            if (code !== 0 || !staging.startsWith(root._dir + "/.config-restore.") || staging.includes("\n")) {
                root._finish(false, root._sideProblem(_stageErrors.text, "could not stage the side files of " + root._sideName));
                return;
            }
            root._staging = staging;
            if (!root._write(staging + "/config.json", root._text)) {
                const problem = "could not stage the restored config: " + root._writeError;
                root._dropStaging();
                root._finish(false, problem);
                return;
            }
            const keep = root._backup !== "" ? root._backup.substring(root._backup.lastIndexOf("/") + 1) : "";
            root._swapper.command = ["sh", "-c", root._swapScript, "sh", root._dir, staging, keep].concat(root._sideEntries);
            root._swapper.running = true;
        }
    }

    property Process _swapper: Process {
        stderr: StdioCollector { id: _swapErrors }
        onExited: code => {
            root._staging = "";
            if (code !== 0) {
                root._finish(false, root._sideProblem(_swapErrors.text, "could not restore the side files of " + root._sideName));
                return;
            }
            root._finish(true, "");
        }
    }

    function _dropStaging() {
        if (_staging === "")
            return;
        _stagingRemover.command = ["rm", "-rf", "--", _staging];
        _stagingRemover.running = true;
        _staging = "";
    }

    property Process _stagingRemover: Process {}

    function _finish(ok, problem) {
        const done = _done;
        const result = { ok: ok, problem: problem, backup: _backup };
        _running = false;
        _reading = "";
        _done = null;
        _text = "";
        _sideName = "";
        _sideEntries = [];
        if (typeof done === "function")
            done(result);
    }
}
