import QtQuick
import Quickshell
import qs.singletons
import qs.singletons.io

// A module's settings migrations run by the module host (singletons/ModuleHost.qml, API 1.43)
// on the fixture modules migrating, migrating-escape and migrating-syntax
// (tests/fixtures/modules), with its store in a private temporary directory and a backup
// taker (ModuleBackups) on stand-in homes there. Covered: the pending ones run before its
// main, on its settings in every profile and the pinned globals and on its store; one that
// throws has only its scope reset, the one overlapping it skipped, the independent ones run;
// one that writes outside its scope (a core setting, another module's, another store key) is
// refused and only its own scope reset; the records; one backup ("migration") holding what
// was there before; turned off and on, nothing applied runs again, the skipped one runs on
// the reset scope, and a run that only records takes no backup; a backup that cannot be
// taken fails the module and changes nothing; a first install with no settings of its own
// records every migration, none run; each migration that succeeds is idempotent; a
// migration file that links out of the module, or does not compile, fails the module before
// anything is built or changed. Changes the profiles, the records and the modules turned off
// through Config, as other suites do: in a process of its own.
TestCase {
    id: suite
    suiteName: "ModuleMigrations"
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

    readonly property var _profiles: [
        { name: "Full", enabled: true, when: {}, set: { "mod.migrating.town": "Oslo", "mod.migrating.broken.level": 3, "mod.migrating.broken.mode": "x",
                                                       "mod.migratingx.town": "Rome", "bar.height": 30 } },
        { name: "Power save", enabled: false, when: {}, set: { "mod.migrating.town": "Bergen", "mod.migrating.city": "Trondheim" } }
    ]
    readonly property var _globals: ({ "mod.migrating.loud": true, "mod.migrating.town": "Tromsø", "mod.other.x": 5 })
    readonly property string _store: "{\"folders\":\"a:b\",\"hostile\":\"x\",\"keep\":1}"

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
        host.unload();
        if (_saved) {
            Config.profiles = _savedProfiles;
            Config.globals = _savedGlobals;
            Config.migratedKeys = _savedMigrated;
            Config.disabledModules = _savedDisabled;
        }
        if (temp.startsWith("/") && temp.includes("h2s-migrations.")) {
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

    function _status(name) {
        return host.statuses.find(status => status.directory === fixtures + "/" + name) ?? null;
    }

    function _state(name) {
        return _status(name)?.state ?? "";
    }

    function _settled() {
        return host.statuses.length > 0 && !host.statuses.some(status => status.state === "pending") && !host.checkingPrograms;
    }

    function _set(profile) {
        return JSON.parse(Config.profiles).find(each => each.name === profile)?.set ?? {};
    }

    function _globalsNow() {
        return JSON.parse(Config.globals || "{}");
    }

    function _records() {
        return host._plainList(Config.migratedKeys).filter(entry => entry.includes("mod.migrating/"));
    }

    function _store_() {
        return host.handle("migrating")?.store?.data ?? {};
    }

    function _backupNames(next) {
        _sh("ls -1 \"$1/data/h2s-shell/module-backups/migrating\" 2>/dev/null; true", [temp]);
    }

    // Turned off, `between` run, turned on again; then `check` once it settled
    function _offAndOn(description, between, check) {
        _then(description + ": off", _settled, () => host.setEnabled("migrating", false));
        _then(description + ": turned off", () => _settled() && _state("migrating") === "disabled", () => {
            between();
            host.setEnabled("migrating", true);
        });
        _then(description + ": on again", () => _settled() && _state("migrating") !== "disabled", check);
    }

    // ---- The run ----

    function runAsync() {
        _then("the config is read", () => Config.ready, () => {
            _savedProfiles = Config.profiles;
            _savedGlobals = Config.globals;
            _savedMigrated = host._plainList(Config.migratedKeys);
            _savedDisabled = host._plainList(Config.disabledModules);
            _saved = true;
            Config.disabledModules = [];
            Config.migratedKeys = ["2.1.0-lock-notification-detail-default", "mod.migratingx/city-rename"];
            Config.profiles = JSON.stringify(_profiles);
            Config.globals = JSON.stringify(_globals);
            _sh("T=$(mktemp -d -p \"${XDG_RUNTIME_DIR:-/tmp}\" h2s-migrations.XXXXXX) && mkdir -p \"$T/config/h2s_shell/modules\" \"$T/data\" "
                + "&& printf '%s' \"$1\" > \"$T/config/h2s_shell/modules/migrating.json\" && echo \"$T\"", [_store]);
        });
        _then("the stand-ins are made", () => _out !== null, () => {
            assert(_out.ok, "the temporary homes and the store are made");
            temp = _out.ok ? _out.lines[_out.lines.length - 1] : "";
            if (temp === "") {
                _steps = [];
                return;
            }
            host.storeDirectory = temp + "/config/h2s_shell/modules";
            // Its data directory made first, as in the shell: the migrations wait for it
            host.dataRoot = temp + "/data/h2s-shell/module-data";
            backups.dataHome = temp + "/data";
            backups.configHome = temp + "/config";
            host.backups = backups;
            host.load([fixtures + "/migrating", fixtures + "/migrating-escape", fixtures + "/migrating-syntax"], {});
        });
        _then("the modules settle", _settled, () => {
            const status = _status("migrating");
            assertEqual(status?.state, "loaded", "migrating: loaded after its migrations (" + (status?.errors ?? []).join("; ") + ")");
            const main = host.mainObject("migrating");
            assertEqual(JSON.stringify(main?.seen), JSON.stringify({ folders: ["a", "b"], hostile: null }),
                        "its main saw its store migrated (written after its settings): the migrations ran before it was made");

            // Its settings, in every profile and the globals
            const full = _set("Full");
            assertEqual(full["mod.migrating.city"] + " " + full["mod.migrating.town"], "Oslo undefined", "city-rename: town moved to city in Full");
            const powerSave = _set("Power save");
            assertEqual(powerSave["mod.migrating.city"] + " " + powerSave["mod.migrating.town"], "Trondheim undefined",
                        "… in a profile not in effect too, a city already set kept");
            const pinned = _globalsNow();
            assertEqual(pinned["mod.migrating.city"] + " " + pinned["mod.migrating.town"] + " " + pinned["mod.migrating.loud"], "Tromsø undefined true",
                        "… in the pinned globals; a setting out of every scope untouched");
            assertEqual(full["mod.migrating.broken.level"] + " " + full["mod.migrating.broken.mode"], "undefined undefined",
                        "broken threw: its scope (broken.*) reset to defaults");
            assertEqual(full["mod.migratingx.town"] + " " + full["bar.height"] + " " + pinned["mod.other.x"] + " " + pinned["bar.height"], "Rome 30 5 undefined",
                        "hostile wrote a core setting and another module's: refused, nothing of theirs changed — and a similar id's settings untouched");

            // Its store
            const store = _store_();
            assertEqual(MigrationRules.canonical(store), MigrationRules.canonical({ keep: 1, folders: ["a", "b"] }),
                        "store-shape ran (independent of the failures); hostile's own scope (store:hostile) reset, the key it wrote outside (keep) not");

            // The records
            assertEqual(JSON.stringify(_records()), JSON.stringify(["mod.migrating/city-rename", "reset:mod.migrating/broken",
                                                                     "reset:mod.migrating/hostile", "mod.migrating/store-shape"]),
                        "records: the applied ones, the reset ones; after-broken (overlapping broken) skipped, not recorded");
            assert(host._plainList(Config.migratedKeys).includes("2.1.0-lock-notification-detail-default")
                   && host._plainList(Config.migratedKeys).includes("mod.migratingx/city-rename"), "… the core's and another module's records kept");
            assert(_has(status?.errors, "settings migration broken failed") && _has(status?.errors, "it failed: the broken migration broke"),
                   "the failure is in its status: " + (status?.errors ?? []).join("; "));
            assert(_has(status?.errors, "settings migration hostile failed (it wrote setting bar.height outside its scope)"),
                   "… and the refusal: " + (status?.errors ?? []).join("; "));
            assert(_has(status?.errors, "migrations/Hostile.qml"), "the migration file's import of the shell is reported (its imports are checked)");
            const report = host.migrationReports.migrating;
            assertEqual(JSON.stringify(report?.applied), JSON.stringify([{ id: "city-rename", summary: "Town is now City" }, { id: "store-shape", summary: "Folders are a list" }]),
                        "the run's report: what was applied, with each migration's summary from its file");
            assertEqual((report?.reset ?? []).map(entry => entry.id + ":" + entry.summary + ":" + entry.scope).join(" | "),
                        "broken:Broken settings in a new shape:setting:broken.* | hostile:Something it should not do:store:hostile", "… what was reset, with its summary and scope");
            assertEqual(JSON.stringify(report?.skipped), JSON.stringify([{ id: "after-broken", after: "broken" }]), "… what was skipped");
            assert(/^2\.0\.0-\d{8}-\d{6}$/.test(report?.backup ?? ""), "… the backup taken before it: " + report?.backup);

            // The files that fail the check
            const escape = _status("migrating-escape");
            assertEqual(escape?.state, "failed", "migrating-escape: failed");
            assert(_has(escape?.errors, "migration outside: migrations/Outside.qml leaves the module directory through a link"),
                   "… a migration file that links out of the module, never built: " + (escape?.errors ?? []).join("; "));
            assertEqual(host.mainObject("migrating-escape"), null, "… no main");
            const syntax = _status("migrating-syntax");
            assertEqual(syntax?.state, "failed", "migrating-syntax: failed");
            assert(_has(syntax?.errors, "its settings migrations did not run") && _has(syntax?.errors, "Unbuildable.qml"),
                   "… a migration file that does not compile, named: " + (syntax?.errors ?? []).join("; "));
            assertEqual(host.mainObject("migrating-syntax"), null, "… no main");
            _backupNames();
        });
        _then("the backups are listed", () => _out !== null, () => {
            assertEqual(_out.lines.filter(line => line !== "").length, 1, "one backup before the run: " + _out.lines.join(", "));
            _sh("cat \"$1/data/h2s-shell/module-backups/migrating/\"*/settings.json; echo; cat \"$1/data/h2s-shell/module-backups/migrating/\"*/store.json; echo; "
                + "cat \"$1/data/h2s-shell/module-backups/migrating/\"*/meta.json", [temp]);
        });
        _then("the backup is read", () => _out !== null, () => {
            const settings = JSON.parse(_out.lines[0] || "{}");
            assertEqual(settings.profiles?.[0]?.set?.["mod.migrating.town"] + " " + settings.profiles?.[0]?.set?.["mod.migrating.broken.level"] + " " + settings.globals?.["mod.migrating.town"],
                        "Oslo 3 Tromsø", "the backup holds its settings as they were before the run");
            assertEqual(_out.lines[1], _store, "… and its store's file as it was");
            assertEqual(JSON.parse(_out.lines[2] || "{}").reason, "migration", "… taken for a migration");
        });

        // Applied once: town set again is not moved; the skipped one runs on the reset scope
        _offAndOn("turned off and on", () => {
            const list = JSON.parse(Config.profiles);
            list[0].set["mod.migrating.town"] = "Bergen";
            Config.profiles = JSON.stringify(list);
        }, () => {
            assertEqual(_state("migrating"), "loaded", "loaded again");
            assertEqual(_set("Full")["mod.migrating.town"] + " " + _set("Full")["mod.migrating.city"], "Bergen Oslo",
                        "city-rename recorded: not run again (town set since stays)");
            assertEqual(JSON.stringify(_records()), JSON.stringify(["mod.migrating/city-rename", "reset:mod.migrating/broken", "reset:mod.migrating/hostile",
                                                                     "mod.migrating/store-shape", "mod.migrating/after-broken"]),
                        "after-broken ran at the next on, on broken's reset scope, and is recorded; the reset ones not run again");
            assertEqual(_set("Full")["mod.migrating.broken.level"], undefined, "… on the reset scope: nothing to change");
            assertEqual(host.migrationReports.migrating?.backup, "", "… a run that only records takes no backup");
            _backupNames();
        });
        _then("still one backup", () => _out !== null, () => assertEqual(_out.lines.filter(line => line !== "").length, 1, "still one backup: " + _out.lines.join(", ")));

        // A backup that cannot be taken: nothing changed, the module fails
        _offAndOn("a backup that cannot be taken", () => {
            Config.migratedKeys = host._plainList(Config.migratedKeys).filter(entry => entry !== "mod.migrating/city-rename");
            backups.dataHome = "not-absolute";
        }, () => {
            const status = _status("migrating");
            assertEqual(status?.state, "failed", "the module fails");
            assert(_has(status?.errors, "its configuration could not be backed up first"), "… said: " + (status?.errors ?? []).join("; "));
            assertEqual(_set("Full")["mod.migrating.town"] + " " + _set("Full")["mod.migrating.city"], "Bergen Oslo", "… nothing changed");
            assert(!_records().includes("mod.migrating/city-rename"), "… nothing recorded");
            assertEqual(host.mainObject("migrating"), null, "… its main not made");
            backups.dataHome = temp + "/data";
        });

        // Right after the installer's backup (an update, a switch, a restore): none of its own
        _offAndOn("after the installer's backup", () => host.noteBackupTaken("migrating"), () => {
            assertEqual(_state("migrating"), "loaded", "loaded");
            assertEqual(_set("Full")["mod.migrating.town"] + " " + _set("Full")["mod.migrating.city"], "undefined Oslo", "city-rename ran (town dropped, the city set kept)");
            assert(_records().includes("mod.migrating/city-rename"), "… recorded");
            assertEqual(host.migrationReports.migrating?.backup, "", "… no backup of its own");
            _backupNames();
        });
        _then("still one backup after the installer's", () => _out !== null, () => assertEqual(_out.lines.filter(line => line !== "").length, 1, "… none on disk either"));

        // A first install: no settings of its own, no store, no records
        _offAndOn("a first install", () => {
            Config.migratedKeys = host._plainList(Config.migratedKeys).filter(entry => !entry.includes("mod.migrating/"));
            const without = set => {
                const kept = {};
                for (const key of Object.keys(set))
                    if (!key.startsWith("mod.migrating."))
                        kept[key] = set[key];
                return kept;
            };
            Config.profiles = JSON.stringify(JSON.parse(Config.profiles).map(profile => Object.assign({}, profile, { set: without(profile.set) })));
            Config.globals = JSON.stringify(without(_globalsNow()));
            const store = host.handle("migrating").store;
            for (const key of Object.keys(store.data))
                store.remove(key);
        }, () => {
            assertEqual(_state("migrating"), "loaded", "loaded");
            assertEqual(JSON.stringify(_records()), JSON.stringify(["mod.migrating/city-rename", "mod.migrating/broken", "mod.migrating/after-broken",
                                                                     "mod.migrating/hostile", "mod.migrating/store-shape"]),
                        "every migration recorded as done");
            assertEqual(host.migrationReports.migrating?.applied.length + " " + host.migrationReports.migrating?.reset.length + " " + host.migrationReports.migrating?.fresh,
                        "0 0 true", "… none run (broken did not throw, hostile wrote nothing)");
            assertEqual(JSON.stringify(_store_()), "{}", "… the store left empty");
            _backupNames();
        });
        _then("no backup for a first install", () => _out !== null, () => assertEqual(_out.lines.filter(line => line !== "").length, 1, "… and no backup taken"));
        _then("idempotence", () => true, _idempotence);
        _clock.start();
    }

    // Each migration that succeeds gives the same result run on its own result
    function _idempotence() {
        const part = { settings: { profiles: [{ name: "Full", set: { "mod.migrating.town": "Oslo", "mod.migrating.broken.level": 3 } }], globals: { "mod.migrating.town": "Bodø" } },
                       store: { folders: "a::b" } };
        for (const file of ["CityRename", "AfterBroken", "StoreShape"]) {
            const component = Qt.createComponent(fixtures + "/migrating/migrations/" + file + ".qml", Component.PreferSynchronous);
            const object = component.createObject(suite);
            const once = object.migrate(JSON.parse(JSON.stringify(part)), {});
            const twice = object.migrate(JSON.parse(JSON.stringify(once)), {});
            assertEqual(MigrationRules.canonical(twice), MigrationRules.canonical(once), file + ": idempotent");
            assert(MigrationRules.canonical(once) !== MigrationRules.canonical(part), file + ": … and it changes something");
            object.destroy();
        }
    }

    function _has(list, fragment) {
        return (list ?? []).some(entry => String(entry).includes(fragment));
    }
}
