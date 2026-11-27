import QtQuick
import Quickshell
import qs.components
import qs.singletons
import qs.singletons.io

// Configuration backups (singletons/ModuleBackups.qml, through singletons/ModuleInstaller.qml)
// on stand-ins made in a private temporary directory (tests/fixtures/backup/setup.sh): a
// folder module installed and updated by the installer, its store's file, its data directory
// with named files, a link out inside a named folder and a named path that is a link out,
// and profiles and globals holding its `mod.kappa.*` settings beside a similar prefix
// (`mod.kappax.*`) and core ones. Covered: an update takes a backup (settings, store, only
// the named data files; the link out refused, the link inside kept as a link, nothing
// followed); a restore while locked, of a staging leftover or of a name it has none of is
// refused; a restore round trip (settings, store and files back, the module off and on
// again, the current configuration backed up first, the backup put back marked for the
// module's next migration run only once its settings are written); a module turned off
// stays off after a restore; switches back and forth take one each, under and over the cap
// of 5, a staging leftover never counted nor deleted. Changes the acknowledgements, the modules turned off
// through Config and the profiles, as other suites do: in a process of its own.
TestCase {
    id: suite
    suiteName: "ModuleBackup"
    asynchronous: true
    timeLimitMs: 240000
    ownProcess: true

    property ModuleHost host: null
    property ModuleInstaller installer: null
    property Component _hostComponent: Component {
        ModuleHost {
            logStates: false
            confirmations: true
        }
    }
    property Component _installerComponent: Component {
        ModuleInstaller {
            loadTimeoutMs: 20000
        }
    }
    property CommandRunner runner: CommandRunner {}
    // The config backup a switch takes, on a scratch config.json in the temporary config home
    property ConfigRestore configBackup: ConfigRestore {}

    property string temp: ""
    property var _out: null
    property var _steps: []
    property bool _saved: false
    property string _savedAcknowledged: ""
    property var _savedDisabled: []
    property var _savedEnabled: []
    property string _savedProfiles: ""
    property string _savedGlobals: ""
    property var _savedMigrated: []
    property string _updateBackup: ""

    readonly property var _profiles: [
        { name: "Full", enabled: true, when: {}, set: { "mod.kappa.city": "Oslo", "mod.kappa.units": "metric", "mod.kappax.city": "Rome", "bar.height": 30 } },
        { name: "Power save", enabled: true, when: {}, set: { "mod.kappa.city": "Bergen" } }
    ]
    readonly property var _globals: ({ "mod.kappa.refresh": 600, "mod.kappax.refresh": 60 })

    // ---- The scheduler, as in ModuleInstallerTest: each step waits for its condition ----

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
        if (_saved) {
            Config.profiles = _savedProfiles;
            Config.globals = _savedGlobals;
            Config.migratedKeys = _savedMigrated;
            Config.setAcknowledgedModulesText(_savedAcknowledged);
            Config.disabledModules = _savedDisabled;
            Config.enabledModules = _savedEnabled;
        }
        host?.unload();
        if (temp.startsWith("/") && temp.includes("h2s-backup.")) {
            runner.start(["rm", "-rf", "--", temp], { timeoutMs: 30000, done: () => suite.finish() });
            return;
        }
        finish();
    }

    // ---- Helpers ----

    function _sh(script, args) {
        _out = null;
        runner.start(["sh", "-c", script, "sh"].concat(args ?? []), {
            timeoutMs: 30000,
            done: result => suite._out = { ok: result.ok, lines: result.stdout === "" ? [] : result.stdout.split("\n") }
        });
    }

    // Runs a script once nothing runs, then checks its lines
    function _shell(description, script, check) {
        _then(description + ": nothing runs", _idle, () => _sh(script, [temp]));
        _then(description + ": read", () => _out !== null, () => {
            assert(_out.ok, description + ": the script ran (" + _out.lines.join("; ") + ")");
            check(_out.lines);
        });
    }

    function _idle() {
        return !installer.busy && host.settled && !host.discovering;
    }

    function _job(description, start, check, timeoutMs) {
        _then(description + ": nothing runs", _idle, () => {
            const why = start();
            assertEqual(why, "", description + ": started");
        });
        _then(description + ": done", () => !installer.busy, () => check(installer.lastResult ?? {}), timeoutMs ?? 60000);
    }

    function _backups() {
        return installer.backupLists.kappa?.backups ?? [];
    }

    function _setting(profile, key) {
        return JSON.parse(Config.profiles).find(each => each.name === profile)?.set?.[key];
    }

    function _version(version) {
        return JSON.stringify({ id: "kappa", name: "Kappa", version: version, api: "1.37", main: "Main.qml", backup: ["notes.db", "sub", "escape", "missing"] });
    }

    readonly property string _backupsDir: "$1/data/h2s-shell/module-backups/kappa"
    readonly property string _dataDir: "$1/data/h2s-shell/module-data/kappa"

    // ---- The run ----

    function runAsync() {
        _then("the config is read", () => Config.ready, () => {
            host = _hostComponent.createObject(suite);
            installer = _installerComponent.createObject(suite, { host: host });
            _savedAcknowledged = Config.acknowledgedModulesText;
            _savedDisabled = host._plainList(Config.disabledModules);
            _savedEnabled = host._plainList(Config.enabledModules);
            _savedProfiles = Config.profiles;
            _savedGlobals = Config.globals;
            _savedMigrated = host._plainList(Config.migratedKeys);
            _saved = true;
            Config.setAcknowledgedModules({});
            Config.disabledModules = [];
            Config.enabledModules = [];
            Config.profiles = JSON.stringify(_profiles);
            Config.globals = JSON.stringify(_globals);
            _sh("bash \"$1\"", [Quickshell.shellDir + "/tests/fixtures/backup/setup.sh"]);
        });
        _then("the stand-ins are made", () => _out !== null, () => {
            assert(_out.ok, "the stand-ins are made");
            temp = _out.ok ? _out.lines[_out.lines.length - 1] : "";
            if (temp === "") {
                _steps = [];
                return;
            }
            host.sourcePlaces = ModuleInstallRules.sourcePlaces({ dataHome: temp + "/data", moduleDataDirs: "", builtin: "" });
            host.discoveryCommand = ["bash", Quickshell.shellDir + "/scripts/launch.sh", "--discover-modules"];
            host.discoveryEnvironment = { XDG_DATA_HOME: temp + "/data", H2S_SHELL_MODULE_PATH: "", H2S_SHELL_MODULE_DATA_DIRS: "",
                                          H2S_SHELL_BUILTIN_MODULES: "" };
            installer.dataHome = temp + "/data";
            installer.configHome = temp + "/config";
            installer.home = temp;
            configBackup.configPath = temp + "/config/h2s_shell/config.json";
            installer.configBackup = configBackup;
            assertEqual(host.rediscover(), "", "the host searches the temporary data home");
        });
        _job("kappa 1.0.0 from a folder", () => installer.install(temp + "/folders/kappa", {}), result =>
             assert(result.ok, "kappa installed (" + result.message + ")"));
        _then("kappa runs", () => _idle() && host.status("kappa")?.state === "loaded", () => {
            assertEqual(installer.backupLists.kappa, undefined, "a first install takes no backup: nothing to back up from");
        });
        _update();
        _refusals();
        _roundTrip();
        _offStaysOff();
        _cap();
        _failures();
        _lockDuring();
        _clock.start();
    }

    // An update (the folder copied again at 1.1.0) backs up 1.0.0's configuration first
    function _update() {
        _shell("a config file", "mkdir -p \"$1/config/h2s_shell\" && printf '%s\\n' '{\"writtenBy\": \"2.2.0\"}' > \"$1/config/h2s_shell/config.json\"", () => {});
        _shell("kappa 1.1.0 in its folder", "printf '%s\\n' '" + _version("1.1.0") + "' > \"$1/folders/kappa/module.json\"", () => {});
        _job("kappa updated to 1.1.0", () => installer.install(temp + "/folders/kappa", {}), result => {
            assert(result.ok, "kappa updated (" + result.message + ")");
            assertEqual((result.details?.backups ?? []).length, 1, "… one backup taken before its link moved");
        });
        _then("the backups are listed", () => _idle() && _backups().length === 1, () => {
            const entry = _backups()[0];
            _updateBackup = entry.name;
            assert(/^1\.0\.0-\d{8}-\d{6}$/.test(entry.name), "the backup is named by the version it was taken from and the time: " + entry.name);
            assertEqual(entry.reason + " " + entry.version + " " + entry.store + " " + entry.includesData, "update 1.0.0 ok true", "… before an update, with store and data");
            assertEqual(JSON.stringify(entry.data), JSON.stringify([{ path: "notes.db", present: true }, { path: "sub", present: true }, { path: "missing", present: false }]),
                        "… the named paths there, one missing, the link out not among them");
        });
        _shell("the backup on disk", "b=" + _backupsDir + "; n=$(ls \"$b\"); d=$b/$n; "
               + "printf 'settings\\t%s\\n' \"$(cat \"$d/settings.json\")\"; printf 'store\\t%s\\n' \"$(cat \"$d/store.json\")\"; "
               + "printf 'notes\\t%s\\n' \"$(cat \"$d/data/notes.db\")\"; printf 'a\\t%s\\n' \"$(cat \"$d/data/sub/a.txt\")\"; "
               + "if [ -L \"$d/data/sub/out\" ]; then printf 'out\\tlink\\t%s\\n' \"$(readlink \"$d/data/sub/out\")\"; else printf 'out\\tnot a link\\n'; fi; "
               + "for p in data/escape data/cache data/missing; do { [ -e \"$d/$p\" ] || [ -L \"$d/$p\" ]; } && printf 'there\\t%s\\n' \"$p\"; done; "
               + "printf 'meta\\t%s\\n' \"$(cat \"$d/meta.json\")\"; true", lines => {
            const field = name => lines.find(line => line.startsWith(name + "\t"))?.slice(name.length + 1) ?? "";
            const settings = JSON.parse(field("settings") || "{}");
            assertEqual(JSON.stringify(settings), JSON.stringify({ profiles: [{ name: "Full", set: { "mod.kappa.city": "Oslo", "mod.kappa.units": "metric" } },
                                                                              { name: "Power save", set: { "mod.kappa.city": "Bergen" } }],
                                                                   globals: { "mod.kappa.refresh": 600 } }),
                        "settings.json: mod.kappa.* from every profile and the globals; mod.kappax.* and core settings left out");
            assertEqual(field("store"), "{\"token\":\"one\"}", "store.json: the store's file");
            assertEqual(field("notes") + " " + field("a"), "one a", "data: the named files and folders");
            assertEqual(field("out"), "link\t" + temp + "/outside/secret", "data: a link inside a named folder copied as a link, never what it points to");
            assertEqual(lines.filter(line => line.startsWith("there\t")).join(","), "", "data: the named link out refused, the unnamed cache and the missing path not there");
            const meta = JSON.parse(field("meta") || "{}");
            assertEqual(JSON.stringify(meta.refused), JSON.stringify([{ path: "escape", why: "leads outside its data directory" }]), "meta.json: what was left out, and why");
        });
    }

    function _refusals() {
        _then("refusals: nothing runs", _idle, () => {
            host.locked = true;
            assertEqual(installer.restore("kappa", _updateBackup), "Refused while the session is locked", "a restore while locked: refused");
            host.locked = false;
            assert(installer.restore("kappa", ".incoming-x").startsWith("Not a backup's name"), "a staging leftover's name: refused at once");
            assert(installer.restore("nothere", _updateBackup).startsWith("No module"), "a module that is not here: refused at once");
            assertEqual(installer.busy, false, "… and no job started");
        });
        _job("a restore of a name it has none of", () => installer.restore("kappa", "1.0.0-20991231-000000"), result =>
             assert(!result.ok && result.message.startsWith("No backup"), "a name it has no backup of: refused (" + result.message + ")"));
    }

    // The configuration changed since, then the update's backup put back
    function _roundTrip() {
        _shell("the configuration changed", "d=" + _dataDir + "; printf 'two\\n' > \"$d/notes.db\"; rm -f \"$d/sub/a.txt\"; printf 'new\\n' > \"$d/sub/b.txt\"; "
               + "printf '{\"token\":\"two\"}' > \"$1/config/h2s_shell/modules/kappa.json\"", () => {
            const changed = JSON.parse(JSON.stringify(_profiles));
            changed[0].set["mod.kappa.city"] = "Tromsø";
            changed[0].set["mod.kappa.extra"] = true;
            changed[0].set["mod.kappax.city"] = "Paris";
            Config.profiles = JSON.stringify(changed);
            Config.globals = JSON.stringify({ "mod.kappax.refresh": 30 });
            Config.migratedKeys = ["2.1.0-core", "mod.kappa/rename", "reset:mod.kappa/broken", "held:mod.kappa/broken@1.1.0", "mod.kappax/rename"];
        });
        _job("the update's backup restored", () => {
            suite._markedWhen = [];
            suite._watchRestoring = true;
            return installer.restore("kappa", _updateBackup);
        }, result => {
            assert(result.ok, "restored (" + result.message + ")");
            suite._watchRestoring = false;
            assert(suite._markedWhen.length > 0 && suite._markedWhen.every(back => back),
                   "… the backup put back marked for the next run only once its settings were written (" + JSON.stringify(suite._markedWhen) + ")");
            assertEqual((result.details?.backups ?? []).length, 1, "… the current configuration backed up first");
        });
        _then("restored: kappa runs again", () => _idle() && host.status("kappa")?.state === "loaded" && _backups().length === 2, () => {
            assertEqual(_setting("Full", "mod.kappa.city") + " " + _setting("Full", "mod.kappa.units") + " " + _setting("Power save", "mod.kappa.city"),
                        "Oslo metric Bergen", "settings: the module's values back in each profile");
            assertEqual(_setting("Full", "mod.kappa.extra"), undefined, "settings: a value set since is gone");
            assertEqual(_setting("Full", "mod.kappax.city") + " " + _setting("Full", "bar.height"), "Paris 30", "settings: a similar prefix and core settings untouched");
            const pinned = JSON.parse(Config.globals);
            assertEqual(Object.keys(pinned).sort().map(key => key + "=" + pinned[key]).join(","), "mod.kappa.refresh=600,mod.kappax.refresh=30", "settings: the pinned globals");
            assert(host.isEnabled("kappa"), "kappa turned on again: it was on");
            assertEqual(_backups().length, 2, "two backups now");
            assertEqual(_backups()[0].reason, "restore", "… the newest taken before the restore");
            assertEqual(JSON.stringify(host._plainList(Config.migratedKeys)), JSON.stringify(["2.1.0-core", "held:mod.kappa/broken@1.1.0", "mod.kappax/rename"]),
                        "its settings migrations' applied and reset records gone (they run again on what came back), its hold and every other record kept");
            assert(host._switchBackups.includes("kappa"), "… the restore's backup marked for its migrations' next run (it takes none of its own)");
            assertEqual(host._switchBackupNames.kappa, _updateBackup, "… the backup put back named as what that run starts from");
            host.forgetBackupTaken("kappa");
        });
        _shell("restored: the files", "d=" + _dataDir + "; b=" + _backupsDir + "; "
               + "printf 'notes\\t%s\\n' \"$(cat \"$d/notes.db\")\"; printf 'a\\t%s\\n' \"$(cat \"$d/sub/a.txt\" 2>/dev/null)\"; "
               + "[ -e \"$d/sub/b.txt\" ] && printf 'b\\tthere\\n'; [ -L \"$d/sub/out\" ] && printf 'out\\t%s\\n' \"$(readlink \"$d/sub/out\")\"; "
               + "[ -L \"$d/escape\" ] && printf 'escape\\tlink\\n'; [ -e \"$d/cache/big\" ] && printf 'cache\\tthere\\n'; "
               + "printf 'secret\\t%s\\n' \"$(cat \"$1/outside/secret\")\"; printf 'store\\t%s\\n' \"$(cat \"$1/config/h2s_shell/modules/kappa.json\")\"; "
               + "ls -A \"$d\" \"$d/sub\" | grep -c '^\\.h2s-restore' | sed 's/^/temporaries\\t/'; "
               + "n=$(ls -t \"$b\" | head -1); printf 'before\\t%s\\n' \"$(cat \"$b/$n/store.json\")\"; true", lines => {
            const field = name => lines.find(line => line.startsWith(name + "\t"))?.slice(name.length + 1) ?? "";
            assertEqual(field("notes") + " " + field("a") + " " + field("b"), "one a ", "data: the named files back as backed up, a file made since in a named folder gone");
            assertEqual(field("out"), temp + "/outside/secret", "data: the link inside the named folder back as a link");
            assertEqual(field("escape") + " " + field("cache") + " " + field("secret"), "link there secret",
                        "data: what the backup did not hold (the refused link, the unnamed cache) untouched, the file outside untouched");
            assertEqual(field("store"), "{\"token\":\"one\"}", "store: back as backed up");
            assertEqual(field("temporaries"), "0", "no temporary left");
            assertEqual(field("before"), "{\"token\":\"two\"}", "the backup taken before the restore holds the configuration it replaced");
        });
    }

    // A module turned off stays off after a restore
    function _offStaysOff() {
        _then("kappa turned off", _idle, () => assert(host.setEnabled("kappa", false), "kappa turned off"));
        _then("records before a restore with holds", _idle, () => {
            Config.migratedKeys = ["2.1.0-core", "mod.kappa/rename", "reset:mod.kappa/broken", "held:mod.kappa/broken@1.0.0", "mod.kappax/rename"];
        });
        _job("a restore while it is off", () => installer.restore("kappa", _updateBackup, { held: ["broken", "after"], version: "1.1.0" }), result =>
             assert(result.ok, "restored while off (" + result.message + ")"));
        _then("still off", _idle, () => {
            assertEqual(JSON.stringify(host._plainList(Config.migratedKeys)),
                        JSON.stringify(["2.1.0-core", "mod.kappax/rename", "held:mod.kappa/broken@1.1.0", "held:mod.kappa/after@1.1.0"]),
                        "a restore with holds: the failed and skipped ones held under the version that failed, the older hold replaced");
            host.forgetBackupTaken("kappa");
            assert(!host.isEnabled("kappa"), "kappa stays off after the restore");
            assert(host.setEnabled("kappa", true), "kappa turned on again");
        });
    }

    // Switches back and forth, each with its backup: over the cap the oldest go, a staging
    // leftover is never counted nor deleted
    function _cap() {
        _shell("a staging leftover", "mkdir -p \"" + _backupsDir + "/.incoming-1.0.0-20000101-000000\"", () => {});
        _then("three backups so far", () => _idle() && _backups().length === 3, () => {});
        for (let i = 0; i < 4; i++) {
            _then("switch " + (i + 1) + ": nothing runs", _idle, () => {
                suite._switchTarget = host.status("kappa")?.version === "1.1.0" ? "1.0.0" : "1.1.0";
            });
            _shell("switch " + (i + 1) + ": the version directories", "ls \"$1/data/h2s-shell/module-versions/kappa\"", lines => {
                suite._switchDir = lines.find(line => line.startsWith(suite._switchTarget + "-")) ?? "";
                assert(suite._switchDir !== "", "the kept version " + suite._switchTarget + " is there");
            });
            _job("switch " + (i + 1), () => installer.switchVersion("kappa", suite._switchDir), result =>
                 assert(result.ok && (result.details?.backups ?? []).length === 1, "switched with a backup (" + result.message + ")"));
            if (i === 1)
                _then("under the cap", _idle, () => assertEqual(_backups().length, 5, "five backups: none deleted yet"));
        }
        _then("over the cap", _idle, () => {
            assertEqual(_backups().length, 5, "the newest five kept");
            assert(!_backups().some(each => each.name === _updateBackup), "… the oldest (the update's) deleted");
            assertEqual(_backups()[0].reason, "switch", "… the newest taken before a switch");
            assertEqual(installer.backupLists.kappa.unknown.join(","), ".incoming-1.0.0-20000101-000000", "the staging leftover: unknown, not counted");
        });
        _shell("the config backups", "ls -A \"$1/config/h2s_shell\"", lines => {
            const named = lines.filter(line => /^config\.json\.bak-[0-9T-]+Z-module~kappa~/.test(line)).map(line => line.replace(/^.*-module~/, ""));
            assert(named.includes("kappa~1.0.0~1.1.0"), "the update took a config backup naming the module and both versions");
            assert(named.includes("kappa~1.1.0~1.0.0"), "a switch back took one too");
            assertEqual(named.length, 5, "one per update and switch");
        });
        _shell("the backups on disk", "ls -A \"" + _backupsDir + "\"", lines => {
            assertEqual(lines.filter(line => line !== "").length, 6, "five backups and the leftover on disk");
            assert(lines.includes(".incoming-1.0.0-20000101-000000"), "the staging leftover never deleted");
        });
        // The oldest restored: the backup taken before it does not push it out first
        _then("the oldest: nothing runs", _idle, () => suite._oldest = _backups()[4]?.name ?? "");
        _job("the oldest backup restored", () => installer.restore("kappa", suite._oldest), result =>
             assert(result.ok, "the oldest of five restored, though a backup was taken before it (" + result.message + ")"));
    }

    // The module's state as it is: its version, the version directories, its store's file
    function _snapshot(description) {
        _shell(description, "ls \"$1/data/h2s-shell/module-versions/kappa\" | sed 's/^/version\t/'; printf 'store\t%s\n' \"$(cat \"$1/config/h2s_shell/modules/kappa.json\")\"",
               lines => suite._state = { version: host.status("kappa")?.version ?? "", lines: lines.join("|"), profiles: Config.profiles });
    }

    function _unchanged(description) {
        const before = { value: null };
        _then(description + ": the state before is kept", () => true, () => before.value = suite._state);
        _snapshot(description + ": the state after");
        _then(description + ": compared", () => true, () => {
            assertEqual(suite._state.version + "|" + suite._state.lines, before.value.version + "|" + before.value.lines,
                        description + ": nothing moved (version, version directories, store)");
            assertEqual(suite._state.profiles, before.value.profiles, description + ": the settings untouched");
        });
    }

    // A backup that cannot be taken stops an update, a switch and a restore, nothing moved
    function _failures() {
        _shell("kappa 1.2.0 in its folder", "printf '%s\\n' '" + _version("1.2.0") + "' > \"$1/folders/kappa/module.json\"", () => {});
        _snapshot("before the failures");
        _then("the settings unreadable", _idle, () => {
            suite._oldest = _backups()[0]?.name ?? "";
            Config.globals = "{";
        });
        _job("an update with the settings unreadable", () => installer.install(temp + "/folders/kappa", {}), result =>
             assert(!result.ok && result.message.includes("could not be backed up"), "the update stops (" + result.message + ")"));
        _unchanged("the update that stopped");
        _then("switch: the other version", _idle, () => suite._switchTarget = host.status("kappa")?.version === "1.1.0" ? "1.0.0" : "1.1.0");
        _shell("switch: its directory", "ls \"$1/data/h2s-shell/module-versions/kappa\"", lines =>
               suite._switchDir = lines.find(line => line.startsWith(suite._switchTarget + "-")) ?? "");
        _job("a switch with the settings unreadable", () => installer.switchVersion("kappa", suite._switchDir), result =>
             assert(!result.ok && result.message.includes("could not be backed up"), "the switch stops (" + result.message + ")"));
        _unchanged("the switch that stopped");
        _job("a restore with the settings unreadable", () => installer.restore("kappa", suite._oldest), result =>
             assert(!result.ok && result.message.includes("nothing restored"), "the restore stops (" + result.message + ")"));
        _unchanged("the restore that stopped");
        _then("the settings readable again", _idle, () => Config.globals = JSON.stringify(_globals));
        _shell("the backups folder a link", "b=" + _backupsDir + "; mv \"$b\" \"$b.real\" && ln -s \"$b.real\" \"$b\"", () => {});
        _snapshot("before the link");
        _job("a switch with the backups folder a link", () => installer.switchVersion("kappa", suite._switchDir), result =>
             assert(!result.ok && result.message.includes("could not be backed up"), "the switch stops (" + result.message + ")"));
        _unchanged("the switch that stopped at the link");
        _shell("the backups folder back", "b=" + _backupsDir + "; [ -d \"$b.real/\" ] && rm \"$b\" && mv \"$b.real\" \"$b\"", () => {});
    }

    // The session locks while a restore runs: nothing is written, the module stays on
    function _lockDuring() {
        _snapshot("before the lock");
        _then("a restore, then the lock: nothing runs", _idle, () => {
            assertEqual(installer.restore("kappa", suite._oldest), "", "a restore started");
            host.locked = true;
        });
        _then("the restore under the lock: done", () => !installer.busy, () => {
            const result = installer.lastResult ?? {};
            assert(!result.ok && result.message.includes("locked"), "the lock stops it before anything is written (" + result.message + ")");
            assert(!host._switchBackups.includes("kappa"), "… the backup it took before failing is not marked: a migration run takes its own");
            host.locked = false;
            assert(host.isEnabled("kappa"), "… kappa still on");
        });
        _unchanged("the restore the lock stopped");
    }

    // While set, whether kappa's settings were back each time the backup put back was marked
    // for its next migration run
    property bool _watchRestoring: false
    property var _markedWhen: []
    property Connections _marks: Connections {
        target: suite.host
        function on_SwitchBackupNamesChanged() {
            if (suite._watchRestoring && suite.host._switchBackupNames.kappa === suite._updateBackup)
                suite._markedWhen = suite._markedWhen.concat([suite._setting("Full", "mod.kappa.city") === "Oslo"]);
        }
    }

    property var _state: null
    property string _switchTarget: ""
    property string _oldest: ""
    property string _switchDir: ""
}
