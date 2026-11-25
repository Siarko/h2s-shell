import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.singletons

// The failed settings update told and answered (MigrationFailureNotice, ConfigRestore), on
// scratch config folders with test-only registries and a stand-in notifier: a successful run
// sends nothing; a run with a reset part sends one critical notification without timeout,
// plain, with Keep defaults and Restore previous settings and a click that opens Settings;
// Keep defaults withdraws it; Restore backs up the current file, writes the backup from
// before the run with the failed and skipped migrations held under this version and
// restarts — the next start under the same version holds them (the old values kept), under
// another runs them; a session that saves nothing ("*" failure) offers Start with default
// settings, which backs up the file and writes the new-config baseline; a backup gone
// leaves everything and saves again; nothing is written while a run goes on or while the
// shell cannot restart (the session locked); a restart refused after the write keeps saving
// held and brings the entry back with the problem and Restart shell; a migration run whose
// config is being replaced writes nothing; the test runner sends and writes nothing.
TestCase {
    id: suite
    suiteName: "MigrationRestore"
    asynchronous: true

    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-migration-restore-test-" + Date.now() + "-" + Math.floor(Math.random() * 1e6)

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
            blockWrites: true
            printErrors: false
            onRead: reads++
            adapter: ConfigAdapter {}
        }
    }

    // The notifier's stand-in: what was sent, each with a handle whose close() is counted
    property Component _handleComponent: Component {
        QtObject {
            property bool open: true
            property int closes: 0
            function close() {
                open = false;
                closes++;
            }
        }
    }

    property Component _notice: Component {
        MigrationFailureNotice {
            property var sent: []
            property int opens: 0
            property int holds: 0
            property int releases: 0
            property int restarts: 0
            property bool restartWorks: true
            property bool restartAllowed: true
            property var askedFor: []
            logging: false
            settleMs: 50
            version: "2.2.0"
            notifier: QtObject {
                property var owner: null
                function send(summary, options) {
                    const handle = suite._handleComponent.createObject(suite);
                    owner.sent = owner.sent.concat([{ summary: summary, options: options, handle: handle }]);
                    return handle;
                }
            }
            onAsked: what => askedFor = askedFor.concat([what])
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

    function _list(dir) {
        const process = _lister.createObject(suite, { command: ["ls", "-1A", "--", dir] });
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

    function _open(dir, registry, version) {
        const config = _config.createObject(suite, { configPath: dir + "/config.json", viewDir: dir + "-view", version: version ?? "2.2.0" });
        config.registry = registry;
        return config;
    }

    // A notice on `config`'s runs, its seams counted
    function _newNotice(config, registry, extra) {
        const notice = _notice.createObject(suite, Object.assign({ configPath: config.configPath }, extra ?? {}));
        notice.notifier.owner = notice;
        notice.registry = registry;
        notice.reports = Qt.binding(() => config.migrationReports);
        notice.saveBlocked = Qt.binding(() => config.migrationReadOnly);
        notice.openSettings = () => notice.opens++;
        notice.holdSaves = () => notice.holds++;
        notice.releaseSaves = () => notice.releases++;
        notice.restartShell = () => {
            notice.restarts++;
            return notice.restartWorks;
        };
        notice.canRestart = () => notice.restartAllowed;
        return notice;
    }

    function _migration(id, scope, migrate, extra) {
        return Object.assign({ migrationId: id, since: "2.2.0", summary: "test " + id, scope: scope, migrate: migrate }, extra ?? {});
    }

    readonly property var _rename: _migration("2026-11-25-testonly-rename", ["setting:testonly.*"],
                                              doc => MigrationHelpers.renameKey(doc, "testonly.old", "testonly.new"))
    // Broken under any version: its part reset
    readonly property var _broken: _migration("2026-11-25-x-music-popup", ["preset:music"], doc => { throw new Error("broken"); },
                                              { scopeLabel: "music widget presets" })
    // Overlaps the broken one: skipped after it
    readonly property var _dependent: _migration("2026-11-25-y-music-more", ["preset:music"], doc => doc)
    readonly property var _whole: _migration("2026-11-25-w-everything", ["*"], doc => { throw new Error("broken whole"); },
                                             { wholeScopeReason: "a test" })

    readonly property string _oldText: '{"profiles": "[{\\"name\\":\\"Full\\",\\"enabled\\":true,\\"when\\":{},\\"set\\":{\\"testonly.old\\":\\"a\\"}}]",\n'
        + ' "widgetPresets": "{\\"music\\":{\\"Default\\":{\\"popupMode\\":\\"click\\"}},\\"clock\\":{\\"Default\\":{\\"format\\":\\"hh:mm\\"}}}",\n'
        + ' "migratedKeys": ["bar.height"], "writtenBy": "2.1.0"}\n'

    function runAsync() {
        _success();
        _failedAndRestored();
        _keepDefaults();
        _backupGone();
        _cannotRestart();
        _writesHeld();
        _readOnlySession();
        _testRunner();
        _clock.start();
    }

    // ---- A successful run: nothing said ----
    function _success() {
        const dir = _scratch + "/success";
        let config = null;
        let notice = null;
        _then("the success case's folder", () => true, () => {
            _write(dir + "/config.json", _oldText);
            config = _open(dir, [_rename]);
            notice = _newNotice(config, [_rename]);
            config.load();
        });
        _then("the success case read and settled", () => config.reads === 1 && !config.migrationBusy && notice._settled, () => {
            assertEqual(config.migrationReports.load?.applied?.length, 1, "success: the migration applied");
            assertEqual(notice.current.kind, "", "success: no failure");
        });
        // Settled: any notification would have been sent at once (a turn of the event loop)
        _then("the success case's evaluation", () => true, () => {
            assertEqual(notice.sent.length, 0, "success: no notification");
            assert(!notice.entryShown, "success: no entry");
        });
    }

    // ---- A reset part: told, then restored ----
    function _failedAndRestored() {
        const dir = _scratch + "/restore";
        const registry = [_rename, _broken, _dependent];
        let config = null;
        let notice = null;
        let backup = "";
        let migrated = "";
        let listing = null;
        let again = null;
        let other = null;
        _then("the restore case's folder", () => true, () => {
            _write(dir + "/config.json", _oldText);
            config = _open(dir, registry);
            notice = _newNotice(config, registry);
            config.load();
        });
        _then("the restore case told", () => notice !== null && notice.sent.length > 0, () => {
            assertEqual(notice.sent.length, 1, "told: one notification");
            const sent = notice.sent[0];
            assertEqual(sent.summary, "Updating settings to 2.2.0 failed", "told: the summary");
            assertEqual(sent.options.body, "Defaults are used where possible. See Settings for details.", "told: the body");
            assertEqual(sent.options.urgency + "|" + sent.options.expireTime + "|" + sent.options.format, "critical|0|plain", "told: critical, no timeout, plain");
            assertEqual(sent.options.actions.map(action => action.id + ":" + action.label).join("|"),
                        "default:Open Settings|keep:Keep defaults|restore:Restore previous settings", "told: its click and its two buttons");
            assertEqual(notice.current.parts.join(","), "music widget presets", "told: the part reset, in words");
            assert(notice.entryShown, "told: the entry shown");
            sent.options.actions[0].onTriggered();
            assertEqual(notice.opens, 1, "click: Settings opened");
            sent.options.actions[2].onTriggered();
            assertEqual(notice.opens, 2, "restore button: Settings opened …");
            backup = notice.current.backup;
            migrated = _read(dir + "/config.json");
            assertEqual(_read(backup), _oldText, "the backup from before the run is the old file");
        });
        _then("the restore button asks on the entry", () => notice.askedFor.length > 0, () => {
            assertEqual(notice.askedFor.join(","), "restore", "restore button: … and the question asked there, nothing restored yet");
            assertEqual(notice.holds + notice.restarts, 0, "restore button: nothing written before the answer");
            assertEqual(notice.restore("an old key"), "The failure asked about is not the current one", "restore: an answer to another failure refused");
            notice.busy = true;
            assertEqual(notice.restore(""), "The settings update is still running", "restore: refused while a run goes on");
            notice.busy = false;
            assertEqual(notice.holds, 0, "restore: … nothing held"); 
            assertEqual(notice.restore(notice.current.key), "", "restore: started");
            assertEqual(notice.holds, 1, "restore: saving held first");
            assert(!notice.entryShown, "restore: the entry gone");
            assertEqual(notice.sent[0].handle.closes, 1, "restore: the notification withdrawn");
        });
        _then("the restore written and the shell restarted", () => notice.restarts > 0, () => {
            const written = _json(_read(dir + "/config.json"));
            assertEqual((written?.migratedKeys ?? []).join(","), "bar.height,held:2026-11-25-x-music-popup@2.2.0,held:2026-11-25-y-music-more@2.2.0",
                        "restored: the old records, the failed and the skipped one held under this version");
            assertEqual(_json(written?.widgetPresets ?? "")?.music?.Default?.popupMode, "click", "restored: the old values back");
            assertEqual(notice.restarts, 1, "restored: one restart");
            assertEqual(notice.releases, 0, "restored: saving stays held until the restart");
            listing = _list(dir);
        });
        _then("the restore case's folder listed", () => listing.names !== null, () => {
            const restoreBackups = listing.names.filter(name => /^config\.json\.bak-.*Z-restore$/.test(name));
            assertEqual(restoreBackups.length, 1, "restored: one backup of the file replaced");
            assertEqual(_read(dir + "/" + restoreBackups[0]), migrated, "restored: it holds the file as it was (nothing set since is lost)");
            again = _open(dir, registry);
            again.load();
        });
        _then("the next start under the same version", () => again.reads === 1 && !again.migrationBusy, () => {
            const report = again.migrationReports.load;
            assertEqual(report.held.join(","), "2026-11-25-x-music-popup,2026-11-25-y-music-more", "same version: the held ones not run");
            assertEqual(report.reset.length, 0, "same version: nothing reset again");
            assertEqual(report.applied.join(","), "2026-11-25-testonly-rename", "same version: the one that worked runs again");
            const written = _json(_read(dir + "/config.json"));
            assertEqual(_json(written?.widgetPresets ?? "")?.music?.Default?.popupMode, "click", "same version: the old values kept");
            assert((written?.migratedKeys ?? []).includes("held:2026-11-25-x-music-popup@2.2.0"), "same version: the hold kept");
            other = _open(dir, registry, "2.3.0");
            other.load();
        });
        _then("the next start under another version", () => other.reads === 1 && !other.migrationBusy, () => {
            const report = other.migrationReports.load;
            assertEqual(report.held.length, 0, "another version: nothing held");
            assertEqual(report.reset.map(entry => entry.id).join(","), "2026-11-25-x-music-popup", "another version: the held one runs (and fails again here)");
        });
    }

    // ---- Keep defaults ----
    function _keepDefaults() {
        const dir = _scratch + "/keep";
        const registry = [_broken];
        let config = null;
        let notice = null;
        _then("the keep case's folder", () => true, () => {
            _write(dir + "/config.json", _oldText);
            config = _open(dir, registry);
            notice = _newNotice(config, registry);
            config.load();
        });
        _then("the keep case told", () => notice !== null && notice.sent.length > 0, () => {
            const before = _read(dir + "/config.json");
            assert(!notice.keepDefaults("an old key"), "keep: an answer to another failure refused");
            notice.sent[0].options.actions[1].onTriggered();
            assertEqual(notice.sent[0].handle.closes, 1, "keep: the notification withdrawn");
            assert(!notice.entryShown, "keep: the entry gone");
            assertEqual(_read(dir + "/config.json"), before, "keep: nothing written");
            assertEqual(notice.holds + notice.restarts, 0, "keep: nothing restored");
        });
        _then("the keep case after a turn", () => true, () => {
            assertEqual(notice.sent.length, 1, "keep: not told again");
        });
    }

    // ---- The backup gone: nothing replaced ----
    function _backupGone() {
        const dir = _scratch + "/gone";
        const registry = [_broken];
        let config = null;
        let notice = null;
        let before = "";
        _then("the gone case's folder", () => true, () => {
            _write(dir + "/config.json", _oldText);
            config = _open(dir, registry);
            notice = _newNotice(config, registry);
            config.load();
        });
        _then("the gone case told", () => notice !== null && notice.sent.length > 0, () => {
            before = _read(dir + "/config.json");
            Quickshell.execDetached(["rm", "-f", "--", notice.current.backup]);
        });
        _then("the gone case's backup removed", () => _read(notice.current.backup) === "", () => {
            assertEqual(notice.restore(""), "", "gone: started");
        });
        _then("the gone case answered", () => notice.problem !== "", () => {
            assert(notice.problem.includes("could not be read"), "gone: the problem said: " + notice.problem);
            assertEqual(notice.releases, 1, "gone: saving again");
            assertEqual(notice.restarts, 0, "gone: no restart");
            assertEqual(_read(dir + "/config.json"), before, "gone: the file left as it was");
            assert(notice.entryShown, "gone: the entry stays");
        });
    }

    // ---- The shell cannot restart: nothing written; refused after the write: finished later ----
    function _cannotRestart() {
        const dir = _scratch + "/locked";
        const registry = [_broken];
        let config = null;
        let notice = null;
        let before = "";
        _then("the locked case's folder", () => true, () => {
            _write(dir + "/config.json", _oldText);
            config = _open(dir, registry);
            notice = _newNotice(config, registry);
            config.load();
        });
        _then("the locked case told", () => notice !== null && notice.sent.length > 0, () => {
            before = _read(dir + "/config.json");
            notice.restartAllowed = false;
            assertEqual(notice.restore(""), "The shell cannot restart now", "locked: restore refused before anything is written");
            assertEqual(notice.holds + notice.restarts, 0, "locked: nothing held, no restart");
            assert(notice.entryShown, "locked: the entry stays");
            notice.restartAllowed = true;
            notice.restartWorks = false;
            assertEqual(notice.restore(""), "", "refused restart: started");
        });
        _then("the refused restart answered", () => notice.restarts > 0, () => {
            assert(_read(dir + "/config.json") !== before, "refused restart: the restore written");
            assert(notice.restartPending && notice.entryShown, "refused restart: the entry back");
            assertEqual(notice.problem, "Restart the shell to finish. Changes are not saved until then.", "refused restart: the problem said");
            assertEqual(notice.holds + "|" + notice.releases, "1|0", "refused restart: saving stays held (the running settings would undo the restore)");
            assertEqual(notice.restore(""), "Already under way", "refused restart: no second restore");
            notice.restartAllowed = false;
            assertEqual(notice.retryRestart(), "The shell cannot restart now", "refused restart: Restart shell refused while locked");
            notice.restartAllowed = true;
            notice.restartWorks = true;
            assertEqual(notice.retryRestart(), "", "refused restart: Restart shell");
            assertEqual(notice.restarts + "|" + notice.problem, "2|", "refused restart: restarted, the problem gone");
        });
    }

    // ---- A run whose config is being replaced writes nothing ----
    function _writesHeld() {
        const dir = _scratch + "/held";
        let config = null;
        _then("the held case's folder", () => true, () => {
            _write(dir + "/config.json", _oldText);
            config = _open(dir, [_rename]);
            config.writesHeld = true;
            config.load();
        });
        _then("the held case read", () => config.reads === 1 && !config.migrationBusy, () => {
            assertEqual(_read(dir + "/config.json"), _oldText, "writes held: the run writes nothing over the file");
            assert(String(config.migrationReports.load?.problem).includes("being replaced"), "writes held: the report says why");
        });
    }

    // ---- A session that saves nothing: Start with default settings ----
    function _readOnlySession() {
        const dir = _scratch + "/readonly";
        const registry = [_rename, _whole];
        let config = null;
        let notice = null;
        let listing = null;
        _then("the read-only case's folder", () => true, () => {
            _write(dir + "/config.json", _oldText);
            config = _open(dir, registry);
            notice = _newNotice(config, registry);
            config.load();
        });
        _then("the read-only case told", () => notice !== null && notice.sent.length > 0, () => {
            const sent = notice.sent[0];
            assertEqual(sent.options.body, "Changes are not saved. See Settings for details.", "read-only: the body");
            assertEqual(sent.options.actions.map(action => action.id).join(","), "default,defaults", "read-only: its click and Start with default settings");
            assertEqual(notice.restore(""), "No failed settings update to restore from", "read-only: no restore");
            sent.options.actions[1].onTriggered();
        });
        _then("the defaults button asks on the entry", () => notice.askedFor.length > 0, () => {
            assertEqual(notice.askedFor.join(","), "defaults", "read-only: the question asked on the entry");
            assertEqual(notice.startWithDefaults(""), "", "read-only: started");
        });
        _then("the defaults written", () => notice.restarts > 0, () => {
            assertEqual(_read(dir + "/config.json"), MigrationNoticeRules.defaultsConfig(registry, "2.2.0"), "defaults: the new-config baseline");
            listing = _list(dir);
        });
        _then("the read-only case's folder listed", () => listing.names !== null, () => {
            const kept = listing.names.filter(name => /^config\.json\.bak-.*Z-restore$/.test(name));
            assertEqual(kept.length, 1, "defaults: the old file kept as a backup");
            assertEqual(_read(dir + "/" + kept[0]), _oldText, "defaults: byte-identical");
        });
    }

    // ---- The test runner: nothing sent, nothing written ----
    function _testRunner() {
        const dir = _scratch + "/runner";
        const registry = [_broken];
        let config = null;
        let notice = null;
        _then("the runner case's folder", () => true, () => {
            _write(dir + "/config.json", _oldText);
            config = _open(dir, registry);
            config.readOnly = true;
            notice = _newNotice(config, registry, { testRunner: true });
            config.load();
        });
        _then("the runner case settled", () => config.reads === 1 && !config.migrationBusy && notice._settled, () => {
            assertEqual(notice.current.kind, "reset", "runner: the failure known");
        });
        _then("the runner case after a turn", () => true, () => {
            assertEqual(notice.sent.length, 0, "runner: nothing sent");
            assertEqual(notice.restore(""), "No backup from before the update", "runner: no restore");
            assertEqual(_read(dir + "/config.json"), _oldText, "runner: nothing written");
        });
    }
}
