import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.singletons

// Config's file on scratch files only: JsonConfigFile keeps the keys the loaded file held that
// the adapter does not declare (top-level, and inside a declared JsonObject), in one write,
// takes the declared ones from the adapter, forgets a key once another writer removed it, and
// writes a file with no such keys exactly as JsonAdapter alone does; its serialization is
// JsonAdapter's. ConfigFile with ConfigAdapter (what Config holds): a config from a newer
// shell warns, nothing refused, and a save stamps the version and keeps what it does not know.
TestCase {
    id: suite
    suiteName: "ConfigFile"

    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-config-file-test-" + Date.now()

    // Writes are synchronous here so that a save's writes can be counted and read back at once
    property Component _keeping: Component {
        JsonConfigFile {
            property int writes: 0
            blockLoading: true
            blockWrites: true
            printErrors: false
            onSaved: writes++
            adapter: JsonAdapter {
                property string name: ""
                property int count: 0
                property real big: 0
                property list<string> tags: []
                property string writtenBy: ""
                property JsonObject inner: JsonObject {
                    property string mode: "a"
                    property list<string> items: []
                }
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
                property real big: 0
                property list<string> tags: []
                property string writtenBy: ""
                property JsonObject inner: JsonObject {
                    property string mode: "a"
                    property list<string> items: []
                }
            }
        }
    }

    property Component _config: Component {
        ConfigFile {
            blockLoading: true
            blockWrites: true
            printErrors: false
            adapter: ConfigAdapter {}
        }
    }

    property Component _plainConfig: Component {
        FileView {
            blockLoading: true
            blockWrites: true
            printErrors: false
            adapter: ConfigAdapter {}
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

    // The first read blocks (blockLoading) until the file is loaded, loaded and read included
    function _open(component, path) {
        const file = component.createObject(suite, { path: path });
        file.text();
        return file;
    }

    function run() {
        try {
            _keepsUndeclared();
            _anotherWriter();
            _normalUnchanged();
            _serializedAsJsonAdapter();
            _configNewer();
            _configNormal();
        } finally {
            Quickshell.execDetached(["rm", "-rf", "--", _scratch]);
        }
    }

    function _keepsUndeclared() {
        const path = _scratch + "/newer.json";
        const future = { list: [1, 2, { deep: "x" }], flag: true, none: null };
        _write(path, JSON.stringify({ name: "old", count: 3, writtenBy: "9.0.0", futureSection: future, acknowledgedModules: "{\"weather\":{}}",
                                      inner: { mode: "b", items: ["x"], futureField: { on: 1 } } }));
        const file = _open(_keeping, path);
        try {
            assertEqual(file.adapter.name, "old", "a config from a newer shell: loaded");
            file.adapter.name = "new";
            const before = file.writes;
            file.save();
            assertEqual(file.writes - before, 1, "saved: in one write");
            const text = _read(path);
            const saved = JSON.parse(text);
            assertEqual(JSON.stringify(saved.futureSection), JSON.stringify(future), "saved: a top-level key the adapter does not declare kept as it was");
            assertEqual(saved.acknowledgedModules, "{\"weather\":{}}", "… every such key");
            assertEqual(JSON.stringify(saved.inner.futureField), JSON.stringify({ on: 1 }), "… and one inside a declared JsonObject");
            assert(saved.inner.mode === "b" && saved.inner.items.join() === "x", "… beside that object's declared keys");
            assert(saved.name === "new" && saved.count === 3 && saved.writtenBy === "9.0.0", "… the declared keys as the adapter holds them");
            assertEqual(file.loadedText, text, "… what was written is what the next save keeps keys from");
            file.adapter.count = 4;
            file.save();
            const again = JSON.parse(_read(path));
            assert(JSON.stringify(again.futureSection) === JSON.stringify(future) && again.count === 4, "a second save: still kept");
            assertEqual(file.adapter.name, "new", "… the adapter keeps its values through the writes");
        } finally {
            file.destroy();
        }
    }

    // A migration or a restore writes the file without this view: a key it removed stays removed
    function _anotherWriter() {
        const path = _scratch + "/other-writer.json";
        _write(path, JSON.stringify({ name: "a", futureSection: { x: 1 }, gone: true }));
        const file = _open(_keeping, path);
        try {
            const rewritten = JSON.stringify({ name: "a", futureSection: { x: 2 } });
            _write(path, rewritten);
            file.written(rewritten);
            file.adapter.name = "b";
            file.save();
            const saved = JSON.parse(_read(path));
            assert(!("gone" in saved), "another writer removed a key: a save does not bring it back");
            assertEqual(saved.futureSection?.x, 2, "… the keys it kept, as it wrote them");
        } finally {
            file.destroy();
        }
    }

    function _normalUnchanged() {
        const text = JSON.stringify({ name: "same", count: 1, writtenBy: "2.1.0", inner: { mode: "a", items: [] } });
        const path = _scratch + "/normal.json";
        const plainPath = _scratch + "/plain.json";
        _write(path, text);
        _write(plainPath, text);
        const file = _open(_keeping, path);
        const plain = _open(_plain, plainPath);
        try {
            assertEqual(file.adapter.name + plain.adapter.name, "samesame", "a config with only declared keys: loaded");
            file.adapter.count = 2;
            plain.adapter.count = 2;
            const before = file.writes;
            file.save();
            plain.writeAdapter();
            const saved = _read(path);
            assert(saved.includes("\"count\": 2") && file.writes - before === 1, "a config with only declared keys: saved, once");
            assertEqual(saved, _read(plainPath), "… exactly as JsonAdapter alone writes it");
        } finally {
            file.destroy();
            plain.destroy();
        }
    }

    // What save() writes for the declared keys is what JsonAdapter would: the test adapter and
    // Config's own, every kind of value they hold
    function _serializedAsJsonAdapter() {
        const cases = [
            { name: "a test adapter", keeping: _keeping, plain: _plain,
              content: { name: "n \"q\" ü", count: -7, big: 1732000000123.5, tags: ["a", "b"], writtenBy: "2.1.0", inner: { mode: "z", items: ["1"] } } },
            { name: "Config's adapter", keeping: _config, plain: _plainConfig,
              content: { profiles: "[{\"name\":\"Full\"}]", globals: "{\"a\":1}", widgetPresets: "{}", migratedKeys: ["bar.height", "theme.barLayout"],
                         disabledModules: ["x"], enabledModules: [], acknowledgedModules: "{}", sleepLockNotice: "", moduleUpdates: "{\"failures\":2}",
                         screensOff: ["DP-1"], writtenBy: "2.1.0", audio: { appVolumes: "{\"firefox\":0.5}" }, bluetooth: { powered: "on" },
                         network: { vpnMemory: "{}", lockdown: "{\"boot\":\"b\"}" },
                         nixos: { folder: "/etc/nixos-alt", host: "h", homeWarningAcknowledged: ["/home/u/nixos"] },
                         gcal: { viewMode: "week", clientId: "c", clientSecret: "s", accessToken: "t", refreshToken: "r", tokenExpiry: 1732000000123, enabledCalendarIds: ["p", "q"] } } }
        ];
        for (const each of cases) {
            const path = _scratch + "/serialized-" + cases.indexOf(each) + ".json";
            const plainPath = _scratch + "/serialized-plain-" + cases.indexOf(each) + ".json";
            _write(path, JSON.stringify(each.content));
            _write(plainPath, JSON.stringify(each.content));
            const file = _open(each.keeping, path);
            const plain = _open(each.plain, plainPath);
            try {
                plain.writeAdapter();
                const byAdapter = JSON.parse(_read(plainPath));
                assertEqual(JSON.stringify(file.serialized()), JSON.stringify(byAdapter), each.name + ": serialized as JsonAdapter writes it");
                assertEqual(MigrationRules.canonical(byAdapter), MigrationRules.canonical(each.content), each.name + ": … every key of the fixture declared");
            } finally {
                file.destroy();
                plain.destroy();
            }
        }
    }

    // ConfigFile, as Config holds it, on a config a newer shell wrote
    function _configNewer() {
        const path = _scratch + "/config-newer.json";
        _write(path, JSON.stringify({ writtenBy: "99.0.0", profiles: "[]", futureSection: { kept: [1] }, gcal: { viewMode: "week", futureToken: "f" },
                                      migratedKeys: ["2099-01-01-future"] }));
        const file = _open(_config, path);
        try {
            assert(!file.loadFailed && file.writtenByAtLoad === "99.0.0", "a config from a newer shell: read, not refused");
            assert(file.newerNotice.shown, "… the newer-version warning");
            assertEqual(file.newerNotice.title, "Settings written by h2s-shell 99.0.0", "… naming the version that wrote it");
            assert(file.newerNotice.log.includes("settings updates it does not know: 2099-01-01-future"), "… the log line names the unknown records");
            file.adapter.profiles = "[{\"name\":\"Full\"}]";
            file.saveStamped();
            const saved = JSON.parse(_read(path));
            assertEqual(saved.writtenBy, Version.number, "saved: stamped with this version");
            assertEqual(saved.profiles, "[{\"name\":\"Full\"}]", "… the change saved");
            assertEqual(JSON.stringify(saved.futureSection), JSON.stringify({ kept: [1] }), "… a key this version does not know kept");
            assert(saved.gcal.futureToken === "f" && saved.gcal.viewMode === "week", "… also inside a declared object");
            assertEqual(saved.migratedKeys.join(), "2099-01-01-future", "… the records it does not know kept");
        } finally {
            file.destroy();
        }
    }

    function _configNormal() {
        const path = _scratch + "/config-normal.json";
        _write(path, JSON.stringify({ writtenBy: Version.number, profiles: "[]", migratedKeys: ["bar.height", "theme.barLayout"] }));
        const file = _open(_config, path);
        try {
            assert(!file.loadFailed && !file.newerNotice.shown, "a config of this version: no warning");
        } finally {
            file.destroy();
        }
        const missing = _open(_config, _scratch + "/none.json");
        try {
            assert(!missing.loadFailed && !missing.newerNotice.shown && missing.readError === "", "no config file: no warning, not a failure");
        } finally {
            missing.destroy();
        }
        const broken = _scratch + "/config-broken.json";
        _write(broken, "{\"writtenBy\": \"99.0.0\"");
        const unreadable = _open(_config, broken);
        try {
            assert(unreadable.loadFailed && !unreadable.newerNotice.shown, "a config that is not JSON: failed, no newer warning");
        } finally {
            unreadable.destroy();
        }
    }
}
