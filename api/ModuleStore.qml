import QtQuick
import QtCore
import Quickshell
import Quickshell.Io
import qs.singletons

// A module's own store (its handle's `store`): data that is not a preference — tokens,
// remembered state — as one JSON object in a file of its own,
// ~/.config/h2s_shell/modules/<id>.json (the shell's config directory, which Config keeps
// private: 700). Written as Config writes: a second after the last change, never while
// Config.readOnly (the test runners). A module's preferences are settings (mod.<id>.*),
// never here.
//
//   data          the object, read-only (a frozen copy); bind to it
//   ready         the file has been read (or found missing)
//   get(key, fallback)   a value, or `fallback`
//   set(key, value)      plain JSON (undefined removes the key); false when refused (not
//                        plain JSON, or the store would pass ModuleRules.maxStoreBytes)
//   remove(key)
//   flush()       writes now what is waiting
QtObject {
    id: root

    property string moduleId: ""
    // The file; the suites may point it elsewhere
    property string path: moduleId === "" ? ""
        : String(StandardPaths.writableLocation(StandardPaths.GenericConfigLocation)).replace(/^file:\/\//, "")
          + "/h2s_shell/modules/" + moduleId + ".json"

    readonly property var data: _data
    readonly property bool ready: _ready

    property var _data: Object.freeze({})
    property bool _ready: false
    property bool _dirty: false

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
        _dirty = true;
        _saveTimer.restart();
        return true;
    }

    function remove(key) {
        return set(key, undefined);
    }

    function flush() {
        if (!_dirty || Config.readOnly || path === "")
            return;
        _dirty = false;
        _saveTimer.stop();
        const text = ModuleRules.storeText(_data);
        if (text === null)
            return;
        // The directory first (a FileView does not make it), then the file
        _mkdir.command = ["mkdir", "-p", "--", path.substring(0, path.lastIndexOf("/"))];
        _mkdir.pending = text;
        _mkdir.running = true;
    }

    onPathChanged: _load()
    Component.onCompleted: _load()
    Component.onDestruction: flush()

    function _load() {
        _ready = false;
        _data = Object.freeze({});
        if (path === "")
            return;
        _file.path = path;
        // Missing: an empty store (FileView reports the failure, quietly)
        _data = Object.freeze(ModuleRules.parseStore(_file.text()));
        _ready = true;
    }

    property Timer _saveTimer: Timer {
        interval: 1000
        onTriggered: root.flush()
    }

    property FileView _file: FileView {
        blockAllReads: true
        printErrors: false
        atomicWrites: true
    }

    property Process _mkdir: Process {
        property string pending: ""
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0)
                root._file.setText(pending);
            else
                console.warn("[Modules] " + root.moduleId + ": its store's directory could not be made");
            pending = "";
        }
    }
}
