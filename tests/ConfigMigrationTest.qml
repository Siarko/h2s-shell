import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.singletons

// The settings migrations at start (ConfigFile.load, ConfigMigration), on scratch config
// folders only, with test-only registries: an empty registry leaves a config byte-identical
// and creates none; a new config records every id, nothing run; a pending migration is
// applied once — its side files and the config written, the records, one backup of the file
// as it was — and not again at the next start; a failing one has its part reset with
// reset:<id> recorded, its backup kept; a failing "*" one leaves the file byte-identical,
// no backup, the session read-only and the migrated content in memory only; the backups
// are pruned to the newest ten automatic ones, the manual ones and the one just written
// kept, nothing else in the folder touched; the after-seed phase runs once the profiles
// exist; read-only (the test runner) writes nothing.
TestCase {
    id: suite
    suiteName: "ConfigMigration"
    asynchronous: true

    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-config-migration-test-" + Date.now() + "-" + Math.floor(Math.random() * 1e6)

    property var _steps: []

    function _then(description, condition, action) {
        _steps.push({ description: description, condition: condition, action: action });
    }

    property Timer _clock: Timer {
        interval: 20
        repeat: true
        property int waited: 0
        onTriggered: {
            const step = suite._steps[0];
            if (!step) {
                stop();
                Quickshell.execDetached(["rm", "-rf", "--", suite._scratch]);
                suite.finish();
                return;
            }
            waited += interval;
            let ready = false;
            try {
                ready = step.condition();
            } catch (error) {}
            if (!ready && waited < 15000)
                return;
            waited = 0;
            suite._steps.shift();
            if (!ready)
                suite.fail("timed out waiting: " + step.description);
            try {
                step.action();
            } catch (error) {
                suite.fail("threw in \"" + step.description + "\": " + error);
            }
        }
    }

    property Component _config: Component {
        ConfigFile {
            property int reads: 0
            property int prunes: 0
            blockWrites: true
            printErrors: false
            onRead: reads++
            onBackupsPruned: prunes++
            adapter: ConfigAdapter {}
        }
    }

    property Component _lister: Component {
        Process {
            property var names: null
            stdout: StdioCollector { id: _out }
            onExited: names = _out.text.split("\n").filter(name => name !== "")
        }
    }

    property FileView _disk: FileView {
        blockAllReads: true
        blockWrites: true
        printErrors: false
    }

    function _read(path) {
        _disk.path = "";
        _disk.path = path;
        _disk.reload();
        return _disk.text() ?? "";
    }

    function _write(path, text) {
        _read(path);
        _disk.setText(text);
    }

    // A folder listed: an object whose `names` is null until `ls` answered
    function _list(dir) {
        const process = _lister.createObject(suite, { command: ["ls", "-1A", "--", dir] });
        process.running = true;
        return process;
    }

    // A condition: `dir` holds nothing (listed again until it does, or the deadline)
    function _emptied(dir) {
        let listing = null;
        return () => {
            if (listing === null || (listing.names !== null && listing.names.length > 0))
                listing = _list(dir);
            return listing.names !== null && listing.names.length === 0;
        };
    }

    // The registry is assigned, not handed to createObject: its properties argument turns a
    // list into a QVariantList, which is no Array
    function _open(dir, registry, extra) {
        const config = _config.createObject(suite, Object.assign({ configPath: dir + "/config.json", viewDir: dir + "-view" }, extra ?? {}));
        config.registry = registry;
        return config;
    }

    function _migration(id, scope, migrate, extra) {
        return Object.assign({ migrationId: id, since: "2.2.0", summary: "test " + id, scope: scope, migrate: migrate }, extra ?? {});
    }

    readonly property var _rename: _migration("2026-11-25-testonly-rename", ["setting:testonly.*"],
                                              doc => MigrationHelpers.renameKey(doc, "testonly.old", "testonly.new"))
    readonly property var _theme: _migration("2026-11-25-testonly-theme", ["file:themes/*"], doc => {
        for (const path of Object.keys(doc.files)) {
            const theme = doc.files[path];
            if (theme.height !== undefined && theme.barHeight === undefined) {
                theme.barHeight = theme.height;
                delete theme.height;
            }
        }
        return doc;
    })
    readonly property var _broken: _migration("2026-11-25-x-music-popup", ["preset:music"], doc => { throw new Error("broken"); })
    readonly property var _independent: _migration("2026-11-25-z-battery-warn", ["setting:battery.*"],
                                                   doc => MigrationHelpers.mapValue(doc, "battery.warn", value => Math.max(value, 25)))
    readonly property var _whole: _migration("2026-11-25-w-everything", ["*"], doc => { throw new Error("broken whole"); },
                                             { wholeScopeReason: "a test" })
    readonly property var _afterSeed: _migration("1.0.0-testonly-legacy", ["raw:oldSection", "setting:legacy.*"], doc => {
        if (doc.raw.oldSection !== undefined) {
            if (doc.globals["legacy.value"] === undefined)
                doc.globals["legacy.value"] = doc.raw.oldSection.value;
            delete doc.raw.oldSection;
        }
        return doc;
    }, { phase: "afterSeed" })

    // An old config, written by hand (its spacing is not what a save writes, so a rewrite shows)
    readonly property string _oldText: '{"profiles": "[{\\"name\\":\\"Full\\",\\"enabled\\":true,\\"when\\":{},\\"set\\":{\\"testonly.old\\":\\"a\\",\\"battery.warn\\":20}}]",\n'
        + ' "globals": "{\\"testonly.old\\":\\"g\\"}",\n'
        + ' "widgetPresets": "{\\"music\\":{\\"Default\\":{\\"popupMode\\":\\"click\\"}},\\"clock\\":{\\"Default\\":{\\"format\\":\\"hh:mm\\"}}}",\n'
        + ' "migratedKeys": ["bar.height"], "writtenBy": "2.1.0", "futureSection": {"kept": true}}\n'

    function _json(text) {
        try {
            return JSON.parse(text);
        } catch (error) {
            return null;
        }
    }

    function _backups(names) {
        return (names ?? []).filter(name => name.startsWith("config.json.bak-"));
    }

    function runAsync() {
        _emptyRegistry();
        _newConfig();
        _appliedOnce();
        _failing();
        _wholeScope();
        _unreadableSideFile();
        _pruning();
        _afterSeedPhase();
        _readOnly();
        _clock.start();
    }

    // ---- An empty registry: nothing changes ----
    function _emptyRegistry() {
        const dir = _scratch + "/empty";
        const missing = _scratch + "/empty-missing";
        let config = null;
        let fresh = null;
        let listing = null;
        _then("scratch folders", () => true, () => {
            _write(dir + "/config.json", _oldText);
            config = _open(dir, []);
            config.load();
            fresh = _open(missing, []);
            fresh.load();
        });
        _then("the empty-registry configs read", () => config.reads === 1 && fresh.reads === 1, () => {
            assertEqual(_read(dir + "/config.json"), _oldText, "empty registry: the config byte-identical");
            assert(config.adapter.profiles.includes("testonly.old"), "empty registry: the config read as it is");
            assert(!config.migrationReadOnly, "empty registry: not read-only");
            assertEqual(config.migrationReports.load?.applied.length, 0, "empty registry: nothing applied");
            listing = [_list(dir), _list(missing)];
        });
        _then("the empty-registry folders listed", () => listing.every(each => each.names !== null), () => {
            assertEqual(listing[0].names.join(","), "config.json", "empty registry: no backup");
            assertEqual(listing[1].names.length, 0, "empty registry: no config created for a new one");
        });
    }

    // ---- A new config: every id recorded, none run ----
    function _newConfig() {
        const dir = _scratch + "/new";
        let config = null;
        let listing = null;
        _then("the new config's folder", () => true, () => {
            config = _open(dir, [_rename, _broken, _afterSeed]);
            config.load();
        });
        _then("the new config read", () => config.reads === 1, () => {
            const written = _json(_read(dir + "/config.json"));
            assertEqual((written?.migratedKeys ?? []).join(","), [_rename, _broken, _afterSeed].map(m => m.migrationId).join(","),
                        "new config: every registered id recorded, the after-seed one too");
            assert(config.migrationReports.load?.fresh === true && config.migrationReports.load.applied.length === 0, "new config: none run");
            assertEqual(config.adapter.migratedKeys.length, 3, "new config: the records read");
            listing = _list(dir);
        });
        _then("the new config's folder listed", () => listing.names !== null, () => {
            assertEqual(_backups(listing.names).length, 0, "new config: no backup");
        });
    }

    // ---- Applied once, with its side files; not again ----
    function _appliedOnce() {
        const dir = _scratch + "/applied";
        const registry = [_rename, _theme];
        let first = null;
        let second = null;
        let afterFirst = "";
        let listing = null;
        _then("the applied case's folder", () => true, () => {
            _write(dir + "/config.json", _oldText);
            _write(dir + "/themes/dark.json", JSON.stringify({ accent: "#88c0d0", height: 30 }));
            _write(dir + "/other/broken.txt", "not a theme");
            first = _open(dir, registry);
            first.load();
        });
        _then("the migrated config read", () => first.reads === 1 && !first.migrationBusy, () => {
            afterFirst = _read(dir + "/config.json");
            const written = _json(afterFirst);
            const profiles = _json(written?.profiles ?? "");
            assertEqual(profiles?.[0]?.set?.["testonly.new"], "a", "applied: the profile migrated");
            assert(profiles?.[0]?.set?.["testonly.old"] === undefined, "applied: the old key gone");
            assertEqual(_json(written?.globals ?? "")?.["testonly.new"], "g", "applied: the globals migrated");
            assertEqual((written?.migratedKeys ?? []).join(","), "bar.height,2026-11-25-testonly-rename,2026-11-25-testonly-theme",
                        "applied: the records written after the old markers, in order");
            assertEqual(written?.writtenBy, "2.1.0", "applied: writtenBy left for the next save");
            assert(written?.futureSection?.kept === true, "applied: a key this version does not declare kept");
            assertEqual(JSON.stringify(_json(_read(dir + "/themes/dark.json"))), JSON.stringify({ accent: "#88c0d0", barHeight: 30 }), "applied: the side file written");
            assertEqual(_read(dir + "/other/broken.txt"), "not a theme", "applied: a file no scope names untouched");
            assert(first.adapter.profiles.includes("testonly.new") && !first.adapter.profiles.includes("testonly.old"), "applied: the reader sees the migrated config");
            const backup = first.migrationReports.load?.backup ?? "";
            assert(/\/config\.json\.bak-[0-9T-]+Z-migration$/.test(backup), "applied: one backup, its reason in its name: " + backup);
            assertEqual(_read(backup), _oldText, "applied: the backup holds the file as it was");
            assertEqual(first.migrationReports.load.applied.join(","), "2026-11-25-testonly-rename,2026-11-25-testonly-theme", "applied: the report names both");
            second = _open(dir, registry);
            second.load();
        });
        _then("the second start read", () => second.reads === 1 && !second.migrationBusy, () => {
            assertEqual(_read(dir + "/config.json"), afterFirst, "applied once: the next start leaves the file byte-identical");
            assertEqual(second.migrationReports.load?.applied.length, 0, "applied once: nothing run again");
            listing = _list(dir);
        });
        _then("the applied case's folder listed", () => listing.names !== null, () => {
            assertEqual(_backups(listing.names).length, 1, "applied once: one backup in all");
        });
    }

    // ---- A failing migration: its part reset, the others applied ----
    function _failing() {
        const dir = _scratch + "/failing";
        let config = null;
        _then("the failing case's folder", () => true, () => {
            _write(dir + "/config.json", _oldText);
            config = _open(dir, [_rename, _broken, _independent]);
            config.load();
        });
        _then("the failing case read", () => config.reads === 1 && !config.migrationBusy, () => {
            const written = _json(_read(dir + "/config.json"));
            const presets = _json(written?.widgetPresets ?? "");
            assert(presets !== null && presets.music === undefined, "failing: its part (the music presets) reset to defaults");
            assertEqual(presets?.clock?.Default?.format, "hh:mm", "failing: other presets kept");
            assertEqual((written?.migratedKeys ?? []).join(","), "bar.height,2026-11-25-testonly-rename,reset:2026-11-25-x-music-popup,2026-11-25-z-battery-warn",
                        "failing: reset:<id> recorded, the independent ones applied");
            assertEqual(_json(written?.profiles ?? "")?.[0]?.set?.["battery.warn"], 25, "failing: the one after it ran");
            const report = config.migrationReports.load;
            assertEqual(report?.reset?.[0]?.id, "2026-11-25-x-music-popup", "failing: the report names it");
            assert(String(report?.reset?.[0]?.error).includes("broken"), "failing: … with its error");
            assertEqual(_read(report?.backup ?? ""), _oldText, "failing: the backup kept, with the old values");
            assert(!config.migrationReadOnly, "failing: the session saves as normal");
        });
    }

    // ---- A failing "*" migration: nothing written, read-only ----
    function _wholeScope() {
        const dir = _scratch + "/whole";
        let config = null;
        let listing = null;
        _then("the whole-scope case's folder", () => true, () => {
            _write(dir + "/config.json", _oldText);
            config = _open(dir, [_rename, _whole, _independent]);
            config.load();
        });
        _then("the whole-scope case read", () => config.reads === 1 && !config.migrationBusy, () => {
            assertEqual(_read(dir + "/config.json"), _oldText, "\"*\" failure: config.json byte-identical");
            assert(config.migrationReadOnly, "\"*\" failure: the session read-only");
            assertEqual(config.migrationReports.load?.failure?.id, "2026-11-25-w-everything", "\"*\" failure: the report names it");
            assert(config.adapter.profiles.includes("testonly.new"), "\"*\" failure: the readers see the migrations before it, in memory");
            assert(config.adapter.profiles.includes("\"battery.warn\":20"), "\"*\" failure: none after it run");
            assertEqual(config.adapter.migratedKeys.join(","), "bar.height", "\"*\" failure: no record added");
            listing = _list(dir);
        });
        _then("the whole-scope folder listed", () => listing.names !== null, () => {
            assertEqual(listing.names.join(","), "config.json", "\"*\" failure: no backup");
        });
        _then("\"*\" failure: the in-memory copy removed once read", _emptied(dir + "-view"), () => {});
    }

    // ---- A side file in a pending migration's scope that does not parse: not migrated on a guess ----
    function _unreadableSideFile() {
        const dir = _scratch + "/unreadable";
        let config = null;
        _then("the unreadable side file's folder", () => true, () => {
            _write(dir + "/config.json", _oldText);
            _write(dir + "/themes/dark.json", "{ not json");
            config = _open(dir, [_rename, _theme]);
            config.load();
        });
        _then("the unreadable side file case read", () => config.reads === 1 && !config.migrationBusy, () => {
            assertEqual(_read(dir + "/config.json"), _oldText, "unreadable side file: config.json byte-identical");
            assertEqual(_read(dir + "/themes/dark.json"), "{ not json", "unreadable side file: left as it is");
            assert(config.migrationReadOnly, "unreadable side file: the session read-only");
            assert(String(config.migrationReports.load?.problem).includes("themes/dark.json"), "unreadable side file: the report names it");
        });
    }

    // ---- Pruning: the newest ten automatic, every manual one, the one just written ----
    function _pruning() {
        const dir = _scratch + "/pruning";
        const old = [];
        let config = null;
        let listing = null;
        _then("the pruning case's folder", () => true, () => {
            _write(dir + "/config.json", _oldText);
            for (let day = 1; day <= 12; day++)
                old.push("config.json.bak-2026-10-" + String(day).padStart(2, "0") + "T10-00-00-000Z" + (day % 2 === 0 ? "-migration" : ""));
            old.push("config.json.bak-2026-09-01T10-00-00-000Z-manual", "config.json.bak-2026-09-02T10-00-00-000Z-manual", "config.json.bak-notes");
            for (const name of old)
                _write(dir + "/" + name, "{}");
            config = _open(dir, [_rename]);
            config.load();
        });
        _then("the pruning case pruned", () => config.reads === 1 && config.prunes === 1 && !config.migrationBusy, () => {
            listing = _list(dir);
        });
        _then("the pruning case's folder listed", () => listing.names !== null, () => {
            const written = config.migrationReports.load.backup.replace(/^.*\//, "");
            const names = listing.names;
            assert(names.includes(written), "pruning: the backup just written kept");
            const automatic = _backups(names).filter(name => !name.endsWith("-manual") && name !== "config.json.bak-notes");
            assertEqual(automatic.length, 10, "pruning: ten automatic backups kept, the new one among them");
            assert(!names.includes(old[0]) && !names.includes(old[1]) && !names.includes(old[2]) && names.includes(old[3]), "pruning: the oldest automatic ones deleted");
            assert(names.includes("config.json.bak-2026-09-01T10-00-00-000Z-manual") && names.includes("config.json.bak-2026-09-02T10-00-00-000Z-manual"),
                   "pruning: manual backups never pruned, however old");
            assert(names.includes("config.json.bak-notes") && names.includes("config.json"), "pruning: nothing else in the folder touched");
        });
    }

    // ---- The after-seed phase ----
    function _afterSeedPhase() {
        const dir = _scratch + "/after-seed";
        let config = null;
        _then("the after-seed case's folder", () => true, () => {
            _write(dir + "/config.json", JSON.stringify({ oldSection: { value: 7 }, migratedKeys: [], writtenBy: "0.9.0" }));
            config = _open(dir, [_rename, _afterSeed]);
            config.load();
        });
        _then("the after-seed case read", () => config.reads === 1 && !config.migrationBusy, () => {
            assertEqual(_json(_read(dir + "/config.json"))?.oldSection?.value, 7, "after-seed: not run in the load phase");
            assert(!config.runAfterSeed(), "after-seed: not before the profiles exist");
            config.adapter.profiles = JSON.stringify([{ name: "Full", enabled: true, when: {}, set: {} }]);
            assert(config.runAfterSeed(), "after-seed: run once the profiles exist");
        });
        _then("the after-seed run ended", () => config.migrationReports.afterSeed !== null && !config.migrationBusy, () => {
            const written = _json(_read(dir + "/config.json"));
            assert(written !== null && written.oldSection === undefined, "after-seed: its result written");
            assertEqual(_json(written?.globals ?? "")?.["legacy.value"], 7, "after-seed: … the value moved");
            assertEqual(_json(written?.profiles ?? "")?.[0]?.name, "Full", "after-seed: … with the profiles as they stand");
            assertEqual((written?.migratedKeys ?? []).join(","), "2026-11-25-testonly-rename,1.0.0-testonly-legacy", "after-seed: recorded after the load phase's");
            assertEqual(_json(config.adapter.globals)?.["legacy.value"], 7, "after-seed: the reader sees it");
            assertEqual(config.adapter.migratedKeys.join(","), "2026-11-25-testonly-rename,1.0.0-testonly-legacy", "after-seed: the records in the adapter");
            assertEqual(_json(_read(config.migrationReports.afterSeed.backup))?.oldSection?.value, 7, "after-seed: a backup of the file before it");
            assert(!config.runAfterSeed(), "after-seed: once per run");
        });
    }

    // ---- Read-only (the test runner): nothing written ----
    function _readOnly() {
        const dir = _scratch + "/read-only";
        let config = null;
        let listing = null;
        _then("the read-only case's folder", () => true, () => {
            _write(dir + "/config.json", _oldText);
            config = _open(dir, [_rename], { readOnly: true });
            config.load();
        });
        _then("the read-only case read", () => config.reads === 1 && !config.migrationBusy, () => {
            assertEqual(_read(dir + "/config.json"), _oldText, "read-only: nothing written");
            assert(config.adapter.profiles.includes("testonly.new"), "read-only: the migrated config in memory");
            listing = _list(dir);
        });
        _then("the read-only folder listed", () => listing.names !== null, () => {
            assertEqual(listing.names.join(","), "config.json", "read-only: no backup");
        });
        _then("read-only: the in-memory copy removed once read", _emptied(dir + "-view"), () => {});
    }
}
