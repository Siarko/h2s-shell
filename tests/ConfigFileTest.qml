import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.singletons

// JsonConfigFile, Config's file, on scratch files: a save keeps the top-level keys the loaded
// file held that the adapter does not declare (what a newer shell wrote), takes the declared
// ones from the adapter, and writes a file with no such keys exactly as JsonAdapter alone
// does. Config's own file under the suites: no newer-version warning.
TestCase {
    id: suite
    suiteName: "ConfigFile"

    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-config-file-test-" + Date.now()

    property Component _keeping: Component {
        JsonConfigFile {
            blockLoading: true
            printErrors: false
            adapter: JsonAdapter {
                property string name: ""
                property int count: 0
                property string writtenBy: ""
            }
        }
    }

    // The same adapter on a plain FileView: what JsonAdapter alone writes
    property Component _plain: Component {
        FileView {
            blockLoading: true
            blockWrites: true
            printErrors: false
            adapter: JsonAdapter {
                property string name: ""
                property int count: 0
                property string writtenBy: ""
            }
        }
    }

    property FileView _disk: FileView {
        blockAllReads: true
        blockWrites: true
        printErrors: false
    }

    // setText compares with the text last read: read the file first, or a text equal to the
    // previous file's would not be written
    function _write(path, text) {
        _read(path);
        _disk.setText(text);
    }

    function _read(path) {
        _disk.path = path;
        _disk.reload();
        return _disk.text() ?? "";
    }

    function run() {
        try {
            _keepsUndeclared();
            _normalUnchanged();
        } finally {
            Quickshell.execDetached(["rm", "-rf", "--", _scratch]);
        }
        assert(!Config.newerNotice.shown, "the suites' config: no newer-version warning");
    }

    function _keepsUndeclared() {
        const path = _scratch + "/newer.json";
        const future = { list: [1, 2, { deep: "x" }], flag: true, none: null };
        _write(path, JSON.stringify({ name: "old", count: 3, writtenBy: "9.0.0", futureSection: future, acknowledgedModules: "{\"weather\":{}}" }));
        const file = _keeping.createObject(suite, { path: path });
        try {
            // The first read blocks (blockLoading) until the file is loaded, loaded included
            file.text();
            assertEqual(file.adapter.name, "old", "a config from a newer shell: loaded");
            file.adapter.name = "new";
            file.save();
            const saved = JSON.parse(_read(path));
            assertEqual(JSON.stringify(saved.futureSection), JSON.stringify(future), "saved: a key the adapter does not declare kept as it was");
            assertEqual(saved.acknowledgedModules, "{\"weather\":{}}", "… every such key");
            assert(saved.name === "new" && saved.count === 3 && saved.writtenBy === "9.0.0", "… the declared keys as the adapter holds them");
            file.adapter.count = 4;
            file.save();
            const again = JSON.parse(_read(path));
            assert(JSON.stringify(again.futureSection) === JSON.stringify(future) && again.count === 4, "a second save: still kept");
            assertEqual(file.adapter.name, "new", "… the adapter keeps its values through the writes");
        } finally {
            file.destroy();
        }
    }

    function _normalUnchanged() {
        const text = JSON.stringify({ name: "same", count: 1, writtenBy: "2.1.0" });
        const path = _scratch + "/normal.json";
        const plainPath = _scratch + "/plain.json";
        _write(path, text);
        _write(plainPath, text);
        const file = _keeping.createObject(suite, { path: path });
        const plain = _plain.createObject(suite, { path: plainPath });
        try {
            file.text();
            plain.text();
            assertEqual(file.adapter.name + plain.adapter.name, "samesame", "a config with only declared keys: loaded");
            file.adapter.count = 2;
            plain.adapter.count = 2;
            file.save();
            plain.writeAdapter();
            const saved = _read(path);
            assert(saved.includes("\"count\": 2"), "a config with only declared keys: saved");
            assertEqual(saved, _read(plainPath), "… exactly as JsonAdapter alone writes it");
        } finally {
            file.destroy();
            plain.destroy();
        }
    }
}
