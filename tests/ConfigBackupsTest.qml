import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.singletons

// The config backups listed and applied (ConfigBackupList, MigrationFailureNotice's restore,
// ConfigRestore), on scratch config folders with a test-only registry and stand-in restarts:
// the list (automatic, manual and kept, a module switch's, an older one with no reason, a
// newer writer, an unreadable file and one that is no settings file shown, other files left
// out; newest first); Apply refused while the shell cannot restart (the session locked),
// while a migration run goes on and under the test runner, nothing written; an older backup
// applied — the current file backed up ("-restore"), the backup written with the migrations
// its preview found failing held under this version, the shell restarted, the backup
// protected from the pruning that follows — and the next start running its pending
// migrations; a newer backup applied with its unknown records and keys kept, no migration run
// backwards; a module switch's config backup (ConfigRestore.backUp).
TestCase {
    id: suite
    suiteName: "ConfigBackups"
    asynchronous: true

    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-config-backups-test-" + Date.now() + "-" + Math.floor(Math.random() * 1e6)

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
                Quickshell.execDetached(["sh", "-c", "chmod -R u+rwX -- \"$1\" && rm -rf -- \"$1\"", "sh", suite._scratch]);
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
            blockWrites: true
            printErrors: false
            onRead: reads++
            adapter: ConfigAdapter {}
        }
    }

    property Component _notice: Component {
        MigrationFailureNotice {
            property int holds: 0
            property int releases: 0
            property int restarts: 0
            property bool restartAllowed: true
            property bool restartWorks: true
            property bool moduleJob: false
            logging: false
            settleMs: 50
            version: "2.2.0"
            notifier: QtObject {
                function send(summary, options) {
                    return null;
                }
            }
        }
    }

    property Component _list: Component {
        ConfigBackupList {
            version: "2.2.0"
        }
    }

    property Component _restore: Component {
        ConfigRestore {
            version: "2.2.0"
        }
    }

    property Component _process: Component {
        Process {
            property var names: null
            property int code: -1
            stdout: StdioCollector { id: _out }
            onExited: exitCode => {
                names = _out.text.split("\n").filter(name => name !== "");
                code = exitCode;
            }
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

    function _run(command) {
        const process = _process.createObject(suite, { command: command });
        process.running = true;
        return process;
    }

    function _json(text) {
        try {
            return JSON.parse(text);
        } catch (error) {
            return null;
        }
    }

    function _migration(id, scope, migrate, extra) {
        return Object.assign({ migrationId: id, since: "2.2.0", summary: "test " + id, scope: scope, migrate: migrate }, extra ?? {});
    }

    readonly property var _rename: _migration("2026-11-25-testonly-rename", ["setting:testonly.*"],
                                              doc => MigrationHelpers.renameKey(doc, "testonly.old", "testonly.new"))
    readonly property var _broken: _migration("2026-11-25-x-music-popup", ["preset:music"], doc => { throw new Error("broken"); },
                                              { scopeLabel: "music widget presets" })
    readonly property var _dependent: _migration("2026-11-25-y-music-more", ["preset:music"], doc => doc)
    readonly property var _registry: [_rename, _broken, _dependent]

    function _configText(records, writtenBy, extra) {
        return JSON.stringify(Object.assign({
            profiles: JSON.stringify([{ name: "Full", enabled: true, when: {}, set: { "testonly.old": "a" } }]),
            widgetPresets: JSON.stringify({ music: { Default: { popupMode: "click" } } }),
            migratedKeys: records, writtenBy: writtenBy
        }, extra ?? {}), null, 2) + "\n";
    }

    readonly property string _currentText: _configText(["2026-11-25-testonly-rename", "2026-11-25-x-music-popup", "2026-11-25-y-music-more"], "2.2.0",
                                                       { profiles: JSON.stringify([{ name: "Now", enabled: true, when: {}, set: {} }]) })

    function _stamp(month, day) {
        return "config.json.bak-2025-" + String(month).padStart(2, "0") + "-" + String(day).padStart(2, "0") + "T10-00-00-000Z";
    }

    // A notice settled on runs that changed nothing, its seams counted
    function _newNotice(dir, extra) {
        const notice = _notice.createObject(suite, Object.assign({ configPath: dir + "/config.json" }, extra ?? {}));
        notice.registry = _registry;
        notice.holdSaves = () => notice.holds++;
        notice.releaseSaves = () => notice.releases++;
        notice.restartShell = () => {
            notice.restarts++;
            return notice.restartWorks;
        };
        notice.canRestart = () => notice.restartAllowed;
        notice.moduleBusy = () => notice.moduleJob;
        const quiet = { phase: "load", fresh: false, records: [], applied: [], reset: [], skipped: [], held: [], failure: null, problem: "", backup: "" };
        notice.reports = { load: quiet, afterSeed: Object.assign({}, quiet, { phase: "afterSeed" }) };
        return notice;
    }

    function _newList(dir, notice) {
        const list = _list.createObject(suite, { configPath: dir + "/config.json", notice: notice });
        list.registry = _registry;
        return list;
    }

    function runAsync() {
        _listAndApply();
        _newer();
        _moduleBackup();
        _guards();
        _clock.start();
    }

    // ---- The list; refusals; an older backup applied; the next start ----
    function _listAndApply() {
        const dir = _scratch + "/list";
        const older = _stamp(1, 1) + "-migration";
        let notice = null;
        let list = null;
        let chmod = null;
        let listing = null;
        let again = null;
        _then("the list's folder", () => true, () => {
            _write(dir + "/config.json", _currentText);
            _write(dir + "/" + older, _configText(["bar.height"], "2.1.0", { futureKey: "kept" }));
            // Ten more automatic ones: the pruning after a restore would take the oldest
            for (let day = 2; day <= 11; day++)
                _write(dir + "/" + _stamp(2, day) + "-migration", _configText([], "2.1.0"));
            _write(dir + "/" + _stamp(3, 1) + "-manual", _configText([], "2.2.0"));
            _write(dir + "/" + _stamp(3, 2) + "-module~kappa~1.0.0~1.1.0", _currentText);
            _write(dir + "/" + _stamp(3, 3), _configText([], ""));
            _write(dir + "/" + _stamp(3, 4) + "-migration", _configText([], "2.3.0"));
            _write(dir + "/" + _stamp(3, 5) + "-restore", "{ not json");
            _write(dir + "/" + _stamp(3, 6) + "-restore", _currentText);
            _write(dir + "/notes.txt", "notes");
            chmod = _run(["chmod", "000", "--", dir + "/" + _stamp(3, 6) + "-restore"]);
        });
        _then("one made unreadable", () => chmod.code !== -1, () => {
            assertEqual(chmod.code, 0, "the unreadable one made");
            notice = _newNotice(dir);
            list = _newList(dir, notice);
            assert(!list.known, "list: not read before refresh");
            list.refresh();
        });
        _then("the list read", () => list.known && !list.listing, () => {
            const rows = list.rows;
            assertEqual(rows.length, 17, "list: every backup, the unreadable ones too, other files left out");
            assertEqual(rows[0].name, _stamp(3, 6) + "-restore", "list: newest first");
            assertEqual(rows[rows.length - 1].name, older, "list: the oldest last");
            const by = name => rows.find(row => row.name === name);
            assert(!by(_stamp(3, 6) + "-restore").readable, "list: a file that cannot be read shown as such");
            assert(!by(_stamp(3, 5) + "-restore").readable, "list: a file that is no settings file shown as such");
            assertEqual(by(_stamp(3, 4) + "-migration").newerLine, "Written by shell 2.3.0 (newer than current) — may be incompatible, expect odd behaviour",
                        "list: a newer writer marked");
            assertEqual(by(_stamp(3, 3)).reasonText + "|" + by(_stamp(3, 3)).versionText, "Older backup, reason not recorded|version unknown",
                        "list: an older one with no reason or version");
            assertEqual(by(_stamp(3, 2) + "-module~kappa~1.0.0~1.1.0").reasonText, "Before updating kappa 1.0.0 → 1.1.0", "list: a module switch's");
            assert(by(_stamp(3, 1) + "-manual").kept, "list: a manual one kept");
            assertEqual(by(older).reasonText + "|" + by(older).writtenBy, "Before a settings update|2.1.0", "list: the reason and version");

            const preview = list.preview(older);
            assertEqual(preview.updates + "|" + preview.held.join(","), "3|2026-11-25-x-music-popup,2026-11-25-y-music-more",
                        "preview: the pending updates, the failing one and its dependent held");
            assert(!list.preview(_stamp(3, 6) + "-restore").ok, "preview: an unreadable backup");
            assert(!list.preview("../config.json").ok, "preview: not a backup's name");

            notice.restartAllowed = false;
            assertEqual(list.apply(older, preview.held), "The shell cannot restart now", "refused: the shell cannot restart (the session locked)");
            notice.restartAllowed = true;
            notice.busy = true;
            assertEqual(list.apply(older, preview.held), "The settings update is still running", "refused: a migration run goes on");
            notice.busy = false;
            notice.moduleJob = true;
            assertEqual(list.apply(older, preview.held), "A module update is running", "refused: a module job runs (a restart would cut it in half)");
            notice.moduleJob = false;
            assertEqual(list.apply("../config.json", []), "Not a backup: ../config.json", "refused: not a backup's name");
            assertEqual(list.apply("notes.txt", []), "Not a backup: notes.txt", "refused: another file");
            assertEqual(notice.holds + notice.restarts, 0, "refused: nothing held, nothing restarted");
            assertEqual(_read(dir + "/config.json"), _currentText, "refused: nothing written");

            assertEqual(list.apply(older, preview.held), "", "apply: started");
            assertEqual(notice.restoring, dir + "/" + older, "apply: the backup it reads known (protected)");
            assertEqual(notice.holds, 1, "apply: saving held first");
            assertEqual(list.apply(older, preview.held), "Already under way", "apply: one at a time");
        });
        _then("applied and restarted", () => notice.restarts > 0, () => {
            const written = _json(_read(dir + "/config.json"));
            assertEqual((written?.migratedKeys ?? []).join(","), "bar.height,held:2026-11-25-x-music-popup@2.2.0,held:2026-11-25-y-music-more@2.2.0",
                        "applied: the backup's records, the failing ones held under this version");
            assertEqual(written?.futureKey, "kept", "applied: keys this version does not know kept");
            assertEqual(written?.writtenBy, "2.1.0", "applied: the backup as it was written");
            assertEqual(notice.restoring, "", "applied: no backup read any more");
            listing = _run(["ls", "-1A", "--", dir]);
        });
        _then("the folder after the restore", () => listing.names !== null, () => {
            const restoreBackups = listing.names.filter(name => /^config\.json\.bak-2[0-9]{3}-.*Z-restore$/.test(name) && !name.startsWith("config.json.bak-2025"));
            assertEqual(restoreBackups.length, 1, "applied: the file replaced backed up first");
            assertEqual(_read(dir + "/" + restoreBackups[0]), _currentText, "applied: … as it was");
            assert(listing.names.includes(older), "applied: the backup applied protected from pruning, the oldest though it is");
            assert(listing.names.includes(_stamp(3, 1) + "-manual"), "applied: a manual one never pruned");
            const automatic = listing.names.filter(name => ConfigBackupRules.parseName(name).ok && ConfigBackupRules.parseName(name).reason !== "manual");
            assertEqual(automatic.length, 11, "applied: the automatic ones pruned to ten, and the one protected");
            assert(!listing.names.includes(_stamp(2, 2) + "-migration"), "applied: the oldest unprotected one pruned");
            assert(listing.names.includes("notes.txt"), "applied: other files left alone");
            again = _config.createObject(suite, { configPath: dir + "/config.json", viewDir: dir + "-view", version: "2.2.0" });
            again.registry = _registry;
            again.load();
        });
        _then("the next start", () => again.reads === 1 && !again.migrationBusy, () => {
            const report = again.migrationReports.load;
            assertEqual(report.applied.join(","), "2026-11-25-testonly-rename", "next start: the pending migration runs");
            assertEqual(report.held.join(","), "2026-11-25-x-music-popup,2026-11-25-y-music-more", "next start: the failing ones held");
            assertEqual(report.reset.length, 0, "next start: nothing reset");
            assert(report.backup !== "", "next start: the run backed up first");
        });
    }

    // ---- A newer backup applied: nothing converted back ----
    function _newer() {
        const dir = _scratch + "/newer";
        const name = _stamp(4, 1) + "-migration";
        const newerText = _configText(["2026-11-25-testonly-rename", "2026-11-25-x-music-popup", "2026-11-25-y-music-more", "2026-12-24-from-the-future"],
                                      "2.3.0", { futureKey: { deep: 1 } });
        let notice = null;
        let list = null;
        let runner = null;
        _then("the newer case's folder", () => true, () => {
            _write(dir + "/config.json", _currentText);
            _write(dir + "/" + name, newerText);
            notice = _newNotice(dir);
            list = _newList(dir, notice);
            runner = _newNotice(dir, { testRunner: true });
            list.refresh();
        });
        _then("the newer case listed", () => list.known && !list.listing, () => {
            assert(list.rows[0]?.newer, "newer: marked");
            const preview = list.preview(name);
            assert(preview.newer && preview.updates === 0 && preview.held.length === 0, "newer: no update runs");
            const question = ConfigBackupRules.applyQuestion(list.rows[0], preview, "2.2.0");
            assertEqual(question.title, "Load a backup from a newer shell?", "newer: asked as such, never refused");
            assertEqual(runner.restoreBackup(dir + "/" + name, []), "Not under the test runner", "test runner: refused");
            assertEqual(_read(dir + "/config.json"), _currentText, "test runner: nothing written");
            notice.restartWorks = false;
            assert(!notice.entryShown, "newer: no entry before");
            assertEqual(list.applyNow(name), "", "newer: applied (IPC: the preview's holds)");
        });
        _then("the newer case applied", () => notice.restarts > 0, () => {
            const written = _json(_read(dir + "/config.json"));
            assertEqual((written?.migratedKeys ?? []).join(","), "2026-11-25-testonly-rename,2026-11-25-x-music-popup,2026-11-25-y-music-more,2026-12-24-from-the-future",
                        "newer: its records kept as written, unknown ones too");
            assertEqual(JSON.stringify(written?.futureKey), "{\"deep\":1}", "newer: unknown keys kept");
            assertEqual(written?.writtenBy, "2.3.0", "newer: as written");
            assert(notice.restartPending && notice.entryShown, "restart refused: the entry shows it, no failure behind it");
            assertEqual(notice.releases, 0, "restart refused: saving stays held");
        });
    }

    // ---- A module switch's config backup ----
    function _moduleBackup() {
        const dir = _scratch + "/module";
        let restore = null;
        let result = null;
        let listing = null;
        _then("the module case's folder", () => true, () => {
            _write(dir + "/config.json", _currentText);
            restore = _restore.createObject(suite, { configPath: dir + "/config.json" });
            const readOnly = _restore.createObject(suite, { configPath: dir + "/config.json", readOnly: true });
            assert(!readOnly.backUp("module", { id: "kappa", from: "1.0.0", to: "1.1.0" }, () => {}), "module: nothing under the test runner");
            assert(restore.backUp("module", { id: "kappa", from: "1.0.0", to: "1.1.0" }, answer => result = answer), "module: started");
            assert(!restore.backUp("module", { id: "kappa", from: "1.0.0", to: "1.1.0" }, () => {}), "module: one at a time");
        });
        _then("the module backup taken", () => result !== null, () => {
            assert(result.ok, "module: done");
            assert(/\/config\.json\.bak-[0-9T-]+Z-module~kappa~1\.0\.0~1\.1\.0$/.test(result.backup), "module: named with the module and both versions");
            assertEqual(_read(result.backup), _currentText, "module: the config as it is");
            assertEqual(_read(dir + "/config.json"), _currentText, "module: config.json untouched");
            listing = _run(["stat", "-c", "%a", "--", result.backup]);
        });
        _then("the module backup's mode", () => listing.names !== null, () => {
            assertEqual(listing.names.join(""), "600", "module: readable by the user only");
        });
    }

    // ---- One pruning entry point keeps what a restore needs; a file too large is not read ----
    function _guards() {
        const dir = _scratch + "/guards";
        const failureBackup = _stamp(5, 1) + "-migration";
        let notice = null;
        let list = null;
        let result = null;
        let made = null;
        let listing = null;
        _then("the guards' folder", () => true, () => {
            _write(dir + "/config.json", _currentText);
            _write(dir + "/" + failureBackup, _configText([], "2.1.0"));
            for (let day = 2; day <= 12; day++)
                _write(dir + "/" + _stamp(5, day) + "-migration", _configText([], "2.1.0"));
            // A settings file all the same: only its size keeps it from being read
            _write(dir + "/" + _stamp(6, 1) + "-restore", JSON.stringify({ writtenBy: "2.2.0", pad: "x".repeat(ConfigBackupRules.maxBackupBytes) }));
            made = _run(["true"]);
            notice = _newNotice(dir);
            notice.reports = { load: { phase: "load", reset: [{ id: "2026-11-25-x-music-popup", error: "x" }], skipped: [], held: [], applied: [],
                                       backup: dir + "/" + failureBackup },
                               afterSeed: { phase: "afterSeed", reset: [], skipped: [], held: [], applied: [] } };
        });
        _then("the failure known", () => made.code !== -1 && notice.current.backup !== "", () => {
            assertEqual(made.code, 0, "a file too large made");
            assert(notice.backUp("module", { id: "kappa", from: "1.1.0", to: "1.0.0" }, answer => result = answer), "a module switch's backup through the notice");
        });
        _then("the module backup taken", () => result !== null, () => {
            assert(result.ok, "taken");
            listing = _run(["ls", "-1A", "--", dir]);
        });
        _then("the folder after its pruning", () => listing.names !== null, () => {
            assert(listing.names.includes(failureBackup), "pruning keeps the failure notice's backup, the oldest though it is");
            assert(!listing.names.includes(_stamp(5, 2) + "-migration"), "pruning takes the oldest other one");
            notice.restartAllowed = true;
            assertEqual(notice.restore(""), "", "a restore started");
            list = _newList(dir, notice);
            list.moduleNames = () => ({ kappa: "Kappa Weather" });
            list.refresh();
        });
        _then("the guards listed", () => list.known && !list.listing && notice.restarts > 0, () => {
            const large = list.rows.find(row => row.name === _stamp(6, 1) + "-restore");
            assert(large && !large.readable && large.versionText === "too large", "a file too large: shown, not read");
            assert(!list.preview(_stamp(6, 1) + "-restore").ok, "a file too large: no preview");
            assert(!notice.backUp("module", { id: "kappa", from: "1.0.0", to: "1.1.0" }, () => {}), "no module backup once a restore wrote the config");
            const module = list.rows.find(row => row.reason === "module");
            assertEqual(module?.reasonText, "Before going back: Kappa Weather 1.1.0 → 1.0.0", "a module's display name; to an older version a way back");
        });
    }
}
