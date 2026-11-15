import QtQuick
import QtCore
import Quickshell
import Quickshell.Io
import qs.singletons

// A module's own store (its handle's `store`): data that is not a preference — tokens,
// remembered state — as one JSON object in a file of its own,
// ~/.config/h2s_shell/modules/<id>.json. A module's preferences are settings (mod.<id>.*),
// never here.
//
//   data          the object, read-only (a frozen copy); bind to it
//   ready         the file has been read (or found missing, or refused)
//   get(key, fallback)   a value, or `fallback` (before `ready`: what was set since, else
//                        `fallback` — read it in a binding on `data`, or after `ready`)
//   set(key, value)      plain JSON (undefined removes the key); false when refused (not
//                        plain JSON, or the store would pass ModuleRules.maxStoreBytes)
//   remove(key)
//   flush()       writes what is waiting, now: synchronously, before it returns
//
// How it is kept (API 1.2):
//   - The directory is private (700) before anything is written: the module host makes
//     ~/.config/h2s_shell/modules (and its parent, should the shell's config directory not
//     exist yet) with mode 700 at its start, before any module is loaded, as Config keeps its
//     own directory (ModuleHost.storeDirectory).
//   - Each write is atomic (a new file renamed over the old) and synchronous, a second after
//     the last change or at flush(); the file is then made 600, like Config's file. A store
//     being destroyed — its module turned off, the shell reloading — writes what is waiting
//     first. (An orderly quit runs no JavaScript at all: Quickshell stops it before tearing
//     down, so the last second of changes before a quit is lost, as for Config.)
//   - The read is a process (never the GUI thread), capped: a file larger than
//     ModuleRules.maxStoreBytes is refused — the store stays empty and is NOT written for the
//     rest of the session (so the file is not overwritten), the reason in the module's
//     status. Sets made before the read answers are kept on top of what it read.
//   - Never written while Config.readOnly (the test runners), unless `writable` says so.
//   - Two shells (two sessions, or a stray second instance) share the file: the last writer
//     wins, whole-file — nothing merges.
QtObject {
    id: root

    property string moduleId: ""
    // The file; the suites may point it elsewhere
    property string path: moduleId === "" ? ""
        : String(StandardPaths.writableLocation(StandardPaths.GenericConfigLocation)).replace(/^file:\/\//, "")
          + "/h2s_shell/modules/" + moduleId + ".json"
    // Whether it writes at all (the suites' seam: the runners' Config is read-only)
    property bool writable: !Config.readOnly

    readonly property var data: _data
    readonly property bool ready: _ready
    // Why the file was not taken ("" when it was, or is missing)
    readonly property string refusedReason: _refused

    property var _data: Object.freeze({})
    property bool _ready: false
    property bool _dirty: false
    property string _refused: ""
    // Keys set before the read answered: kept over what it reads
    property var _early: ({})
    property bool _protected: false

    function get(key, fallback) {
        return Object.prototype.hasOwnProperty.call(_data, key) ? _data[key] : fallback;
    }

    function set(key, value) {
        if (typeof key !== "string" || key === "" || key === "__proto__")
            return false;
        const next = Object.assign({}, _data);
        if (value === undefined)
            delete next[key];
        else
            next[key] = value;
        const text = ModuleRules.storeText(next);
        if (text === null)
            return false;
        _data = Object.freeze(JSON.parse(text));
        if (!_ready)
            _early = Object.assign({}, _early, { [key]: value });
        _dirty = true;
        _saveTimer.restart();
        return true;
    }

    function remove(key) {
        return set(key, undefined);
    }

    function flush() {
        _saveTimer.stop();
        // Not before the read (it would overwrite the file with only the early sets), never
        // over a refused file
        if (!_dirty || !_ready || _refused !== "" || !writable || path === "")
            return;
        const text = ModuleRules.storeText(_data);
        if (text === null)
            return;
        _dirty = false;
        _file.path = path;
        _file.setText(text);
        if (!_protected) {
            _protected = true;
            Quickshell.execDetached(["chmod", "600", "--", path]);
        }
    }

    onPathChanged: if (_completed) _load()
    Component.onCompleted: {
        _completed = true;
        _load();
    }
    Component.onDestruction: flush()

    property bool _completed: false
    // The path changed while a read ran: read again when it ends (its answer is for the old path)
    property bool _again: false

    function _load() {
        if (_reader.running) {
            _again = true;
            return;
        }
        _ready = false;
        _refused = "";
        _data = Object.freeze({});
        _early = {};
        if (path === "")
            return;
        _reader.output = "";
        // A missing file is an empty store (exit 3); anything but a regular file (exit 4) or a
        // file over the cap (exit 5) is refused, unread; else at most the cap is read
        _reader.command = ["sh", "-c", "[ -e \"$1\" ] || exit 3; [ -f \"$1\" ] || exit 4; "
                           + "size=$(stat -c %s -- \"$1\") || exit 4; [ \"$size\" -le \"$2\" ] || exit 5; head -c \"$2\" -- \"$1\"",
                           "sh", path, String(ModuleRules.maxStoreBytes)];
        _reader.running = true;
    }

    function _read(code, text) {
        let read = {};
        if (code === 4) {
            _refused = "its store " + path + " is not a regular file: not read, not written";
        } else if (code === 5) {
            _refused = "its store " + path + " is larger than " + ModuleRules.maxStoreBytes + " bytes: not read, not written";
        } else if (code === 0) {
            read = ModuleRules.parseStore(text);
        } else if (code !== 3) {
            _refused = "its store " + path + " could not be read (exit " + code + "): not written";
        }
        if (_refused !== "") {
            console.warn("[Modules] " + moduleId + ": " + _refused);
            Modules.reportError(moduleId, _refused);
        }
        const merged = Object.assign({}, read);
        for (const key of Object.keys(_early)) {
            if (_early[key] === undefined)
                delete merged[key];
            else
                merged[key] = _early[key];
        }
        _early = {};
        _data = Object.freeze(merged);
        _ready = true;
        if (_dirty)
            _saveTimer.restart();
    }

    property Timer _saveTimer: Timer {
        interval: 1000
        onTriggered: root.flush()
    }

    property FileView _file: FileView {
        preload: false
        blockWrites: true
        atomicWrites: true
        printErrors: false
    }

    property Process _reader: Process {
        property string output: ""
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => root._reader.output += data
        }
        onExited: (exitCode, exitStatus) => {
            if (root._again) {
                root._again = false;
                Qt.callLater(root._load);
                return;
            }
            root._read(exitCode, root._reader.output);
        }
    }
}
