import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.panels.settings
import qs.singletons
import qs.singletons.io

// A module's failed settings migration told (components/ModuleMigrationNotices.qml,
// ModuleMigrationNotice.qml) on the fixture module migrating (tests/fixtures/modules), whose
// migration "broken" throws, run by a module host with its store and a backup taker in a
// private temporary directory: one critical notification naming the module by its display
// name and its parts, the Settings entry (MigrationFailureEntry) naming the same; beside a
// failed core update (MigrationFailureNotice on a stand-in report), each told and shown on
// its own; Restore asks the module's steps and restores the backup taken before the run
// through the installer (a stand-in) with the failed and skipped ones held under the
// module's version; a failed restore brings the entry back with the problem, a restore
// done withdraws it; Keep defaults withdraws it; a module gone is named by its id. Changes
// the profiles, the records and the modules turned off through Config: in a process of its own.
TestCase {
    id: suite
    suiteName: "ModuleMigrationNotice"
    asynchronous: true
    timeLimitMs: 120000
    ownProcess: true

    readonly property string fixtures: Quickshell.shellDir + "/tests/fixtures/modules"

    property ModuleHost host: ModuleHost {
        logStates: false
    }
    property ModuleBackups backups: ModuleBackups {}
    property CommandRunner runner: CommandRunner {}

    property string temp: ""
    property var _out: null
    property var _steps: []
    property bool _saved: false
    property string _savedProfiles: ""
    property string _savedGlobals: ""
    property var _savedMigrated: []
    property var _savedDisabled: []

    // Every notification sent, by either notice
    property var sent: []
    property Component _handleComponent: Component {
        QtObject {
            property bool open: true
            function close() {
                open = false;
            }
        }
    }
    property QtObject notifier: QtObject {
        function send(summary, options) {
            const handle = suite._handleComponent.createObject(suite);
            suite.sent = suite.sent.concat([{ summary: summary, options: options, handle: handle }]);
            return handle;
        }
    }

    // The installer's stand-in: what was asked of it; finished() as the real one's
    property QtObject installer: QtObject {
        property var calls: []
        signal finished(var result)
        function restore(id, name, options) {
            calls = calls.concat([{ id: id, name: name, options: options }]);
            return "";
        }
    }

    property var names: ({ migrating: "Migrating fixture" })

    property ModuleMigrationNotices modules: ModuleMigrationNotices {
        reports: suite.host.migrationReports
        names: suite.names
        notifier: suite.notifier
        installer: suite.installer
        logging: false
    }

    readonly property var _registry: [{ migrationId: "2026-11-25-x-music-popup", scopeLabel: "music widget presets" }]
    property MigrationFailureNotice core: MigrationFailureNotice {
        logging: false
        settleMs: 50
        version: "2.2.0"
        registry: suite._registry
        notifier: suite.notifier
    }

    property QtObject modalHost: QtObject {
        property var spec: null
        property var onAnswer: null
        function ask(spec, onAnswer) {
            this.spec = spec;
            this.onAnswer = onAnswer;
            return "";
        }
    }

    property var _window: PanelWindow {
        anchors { top: true; left: true }
        implicitWidth: 620
        implicitHeight: 400
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "h2s-tests"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    }
    property Component _entryComponent: Component {
        MigrationFailureEntry {
            width: 600
        }
    }
    property var _coreEntry: null
    property var _moduleEntry: null

    // ---- The scheduler: each step waits for its condition (or its deadline), then runs ----

    function _then(description, condition, action, timeoutMs) {
        _steps.push({ description: description, condition: condition, action: action, deadline: timeoutMs ?? 30000 });
    }

    property Timer _clock: Timer {
        interval: 25
        repeat: true
        property int waited: 0
        onTriggered: {
            const step = suite._steps[0];
            if (!step) {
                stop();
                suite._end();
                return;
            }
            waited += interval;
            let ready = false;
            try {
                ready = step.condition();
            } catch (error) {
                ready = false;
            }
            if (!ready && waited < step.deadline)
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

    function _end() {
        for (const entry of [_coreEntry, _moduleEntry])
            if (entry)
                entry.destroy();
        host.unload();
        if (_saved) {
            Config.profiles = _savedProfiles;
            Config.globals = _savedGlobals;
            Config.migratedKeys = _savedMigrated;
            Config.disabledModules = _savedDisabled;
        }
        if (temp.startsWith("/") && temp.includes("h2s-migration-notice.")) {
            runner.start(["rm", "-rf", "--", temp], { timeoutMs: 30000, done: () => suite.finish() });
            return;
        }
        finish();
    }

    function _sh(script, args) {
        _out = null;
        runner.start(["sh", "-c", script, "sh"].concat(args ?? []), {
            timeoutMs: 30000,
            done: result => suite._out = { ok: result.ok, lines: result.stdout === "" ? [] : result.stdout.split("\n") }
        });
    }

    function _settled() {
        return host.statuses.length > 0 && !host.statuses.some(status => status.state === "pending") && !host.checkingPrograms;
    }

    function _named(item, name) {
        let found = [];
        for (const child of item?.children ?? []) {
            if (child.objectName === name)
                found.push(child);
            found = found.concat(_named(child, name));
        }
        return found;
    }

    function _parts(entry) {
        return _named(entry, "migrationFailurePart").map(part => part.text).join("|");
    }

    function _moduleNotice() {
        return modules.notices.find(each => each.moduleId === "migrating") ?? null;
    }

    function _sentFor(fragment) {
        return sent.filter(each => each.summary.includes(fragment));
    }

    function runAsync() {
        _then("the config is read", () => Config.ready, () => {
            _savedProfiles = Config.profiles;
            _savedGlobals = Config.globals;
            _savedMigrated = host._plainList(Config.migratedKeys);
            _savedDisabled = host._plainList(Config.disabledModules);
            _saved = true;
            Config.disabledModules = [];
            Config.migratedKeys = [];
            Config.profiles = JSON.stringify([{ name: "Full", enabled: true, when: {}, set: { "mod.migrating.town": "Oslo", "mod.migrating.broken.level": 3 } }]);
            Config.globals = JSON.stringify({});
            _sh("T=$(mktemp -d -p \"${XDG_RUNTIME_DIR:-/tmp}\" h2s-migration-notice.XXXXXX) && mkdir -p \"$T/config/h2s_shell/modules\" \"$T/data\" "
                + "&& printf '%s' '{\"folders\":\"a:b\"}' > \"$T/config/h2s_shell/modules/migrating.json\" && echo \"$T\"");
        });
        _then("the stand-ins are made", () => _out !== null, () => {
            assert(_out.ok, "the temporary homes and the store are made");
            temp = _out.ok ? _out.lines[_out.lines.length - 1] : "";
            if (temp === "") {
                _steps = [];
                return;
            }
            host.storeDirectory = temp + "/config/h2s_shell/modules";
            host.dataRoot = temp + "/data/h2s-shell/module-data";
            backups.dataHome = temp + "/data";
            backups.configHome = temp + "/config";
            host.backups = backups;
            _coreEntry = _entryComponent.createObject(_window.contentItem, { notice: core, modalHost: modalHost });
            // A core update failed in the same start
            core.reports = { load: { reset: [{ id: "2026-11-25-x-music-popup", error: "x" }], skipped: [], backup: "/c/config.json.bak-2026-01-15T10-29-03-120Z-migration" },
                             afterSeed: { reset: [], skipped: [] } };
            host.load([fixtures + "/migrating"], {});
        });
        _then("the module's run is reported and told", () => _settled() && _moduleNotice() !== null && _sentFor("Migrating fixture").length === 1
              && _sentFor("Updating settings to 2.2.0").length === 1, () => {
            const report = host.migrationReports.migrating;
            assert((report?.reset ?? []).some(entry => entry.id === "broken"), "broken threw: reset in the report");
            assertEqual(report?.version, "2.0.0", "the report names the module's version");
            assert(/^2\.0\.0-\d{8}-\d{6}$/.test(report?.backup ?? ""), "… and the backup taken before the run: " + report?.backup);

            const told = _sentFor("Migrating fixture")[0];
            assertEqual(told.summary, "Updating Migrating fixture settings to 2.0.0 failed", "the notification names the module by its display name");
            assertEqual(told.options.body, "Defaults are used where possible. See Settings for details.", "… the core's short body");
            assertEqual(told.options.urgency + " " + told.options.expireTime + " " + told.options.format, "critical 0 plain", "… critical, no timeout, plain text");
            assertEqual(told.options.actions.map(action => action.label).join(","), "Open Settings,Keep defaults,Restore previous settings",
                        "… Open Settings, Keep defaults, Restore previous settings");
            assertEqual(_sentFor("Updating settings to 2.2.0").length, 1, "the core's failure told on its own beside it");
            assertEqual(sent.length, 2, "two notifications: the core's and the module's");

            _moduleEntry = _entryComponent.createObject(_window.contentItem, { notice: _moduleNotice(), modalHost: modalHost, y: 200 });
            assert(_coreEntry.visible && _moduleEntry.visible, "both entries shown");
            assertEqual(_named(_coreEntry, "migrationFailureTitle")[0].text, "Updating settings to 2.2.0 failed", "the core's entry: its heading");
            assertEqual(_parts(_coreEntry), "•  music widget presets", "… its part");
            assertEqual(_named(_moduleEntry, "migrationFailureTitle")[0].text, "Updating Migrating fixture settings to 2.0.0 failed", "the module's entry names the module");
            assertEqual(_parts(_moduleEntry), "•  Broken settings in a new shape|•  Something it should not do",
                        "… and its failed parts (each migration's summary: broken threw, hostile wrote outside its scope)");

            // Restore: the module's steps, then the installer with the holds
            _named(_moduleEntry, "migrationRestore")[0].clicked();
            assertEqual(modalHost.spec?.body?.[3], "3. Migrating fixture settings update to 2.0.0, skipping Broken settings in a new shape, Something it should not do, The broken level is a text",
                        "Restore asks: the module's update, skipping the failed and the skipped part");
            assertEqual(modalHost.spec?.body?.[4], "4. Restart Migrating fixture", "… the module restarted, not the shell");
            assertEqual(installer.calls.length, 0, "… nothing before the answer");
            modalHost.onAnswer({ button: "restore", cancelled: false, subject: modalHost.spec.subject });
            assertEqual(JSON.stringify(installer.calls), JSON.stringify([{ id: "migrating", name: report.backup, options: { held: ["broken", "hostile", "after-broken"], version: "2.0.0" } }]),
                        "the answer restores the module's backup from before the run, holding the failed and the skipped ones under 2.0.0");
            assert(!_moduleEntry.visible && !told.handle.open, "restoring: the entry and the notification withdrawn");
            assert(_coreEntry.visible && _sentFor("Updating settings to 2.2.0")[0].handle.open, "… the core's untouched");
            installer.finished({ ok: false, action: "restore", ids: ["migrating"], message: "it did not stop in time: nothing restored" });
        });
        _then("a failed restore brings the entry back", () => _moduleEntry.visible, () => {
            assertEqual(_named(_moduleEntry, "migrationFailureProblem")[0].text, "it did not stop in time: nothing restored", "… with the problem");
            installer.finished({ ok: true, action: "restore", ids: ["other"], message: "" });
            assert(_moduleEntry.visible, "another module's restore: nothing changes");
            modalHost.onAnswer({ button: "restore", cancelled: false, subject: modalHost.spec.subject });
            assertEqual(installer.calls.length, 2, "asked again: restored again");
            installer.finished({ ok: true, action: "restore", ids: ["migrating"], message: "" });
            assert(!_moduleEntry.visible, "a restore done: the entry gone");
            assert(_coreEntry.visible, "… the core's stays until answered");

            // A later run of the same failure, then Keep defaults
            Config.migratedKeys = host._plainList(Config.migratedKeys).filter(entry => !entry.includes("mod.migrating/"));
            const list = JSON.parse(Config.profiles);
            list[0].set["mod.migrating.broken.level"] = 4;
            Config.profiles = JSON.stringify(list);
            host.setEnabled("migrating", false);
        });
        _then("turned off", () => _settled() && host.statuses.some(status => status.id === "migrating" && status.state === "disabled"), () => {
            sent = [];
            host.setEnabled("migrating", true);
        });
        _then("a new run told again", () => _settled() && _sentFor("Migrating fixture").length === 1 && _moduleEntry.visible, () => {
            const key = _moduleNotice().current.key;
            _named(_moduleEntry, "migrationKeepDefaults")[0].clicked();
            assert(!_moduleEntry.visible && !_sentFor("Migrating fixture")[0].handle.open, "Keep defaults: the entry and the notification gone");
            assertEqual(_moduleNotice().current.key, key, "… the defaults kept, the failure unchanged");

            // The module gone: its id named, nothing to restore into
            suite.names = {};
        });
        _then("gone: named by its id", () => _moduleNotice()?.current?.summary === "Updating migrating settings to 2.0.0 failed", () => {
            assert(!_moduleNotice().canRestore, "… nothing to restore into");
        });
        _clock.start();
    }
}
