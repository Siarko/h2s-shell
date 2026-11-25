import QtQuick
import Quickshell.Io
import qs.singletons

// Replaces config.json, keeping what it held: the current file is first copied to a backup
// (config.json.bak-<stamp>-restore, readable by the user only), then the new content is
// written (atomic). Two contents: a backup with migrations held (restore(): the settings from
// before a failed update, MigrationNoticeRules.restoredConfig), or a new config with the
// defaults (startWithDefaults(): MigrationNoticeRules.defaultsConfig). The shell restarts
// afterwards (the caller's): the migrations run once, before any reader, at start.
// Read-only (the test runner): nothing written. One at a time.
QtObject {
    id: root

    // config.json (a path or a file:// URL)
    property string configPath: ""
    property bool readOnly: false
    property string version: Version.number
    readonly property bool running: _running

    property bool _running: false
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
        const text = _read(plain);
        if (text.trim() === "") {
            _later(done, { ok: false, problem: "the backup " + plain + " could not be read", backup: "" });
            return true;
        }
        const restored = MigrationNoticeRules.restoredConfig(text, held, version);
        if (!restored.ok) {
            _later(done, { ok: false, problem: restored.problem + ": " + plain, backup: "" });
            return true;
        }
        _start(restored.text, done);
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

    function _later(done, result) {
        Qt.callLater(() => {
            if (typeof done === "function")
                done(result);
        });
    }

    property string _text: ""
    property string _backup: ""
    property var _done: null

    function _start(text, done) {
        _running = true;
        _text = text;
        _done = done;
        _backup = "";
        const current = _read(_file);
        if (current === "") {
            _writeConfig();
            return;
        }
        const backup = _dir + "/" + MigrationRules.backupName(new Date().toISOString(), "restore");
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
            root._writeConfig();
        }
    }

    function _writeConfig() {
        if (!_write(_file, _text)) {
            _finish(false, "could not write " + _file + ": " + _writeError);
            return;
        }
        _finish(true, "");
    }

    function _finish(ok, problem) {
        const done = _done;
        const result = { ok: ok, problem: problem, backup: _backup };
        _running = false;
        _done = null;
        _text = "";
        if (typeof done === "function")
            done(result);
    }
}
