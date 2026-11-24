import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

// Golden outputs of the settings migrations as Profiles and ThemeFiles run them at startup:
// for each old config in tests/fixtures/migrations-golden/<case>/ (before.json, the config
// as those singletons see it when their migrations run; files-before.json, the theme files
// then, path → content), what they leave behind (after.json, files-after.json). The steps
// below are theirs, in their order, each on the result of the one before — Profiles'
// legacy settings and changed defaults (_migrateIfNeeded), the widget presets
// (_migratePresetsIfNeeded), ThemeFiles' bar geometry (_migrateBarLayoutIfNeeded,
// _finishMigration) — on the same rules functions, without their file I/O, backups or logs.
// What the save adds (writtenBy, the declared keys' defaults) is not part of it.
//
// A config from before profiles is seeded (Profiles._seedIfNeeded, the power profile
// "balanced") before any of them runs: its before.json holds the seeded profiles, so the
// case does not depend on the defaults of the day. The core's entries only: a module's
// popup mode migrates when its module loads, and none is loaded here.
TestCase {
    id: suite
    suiteName: "MigrationsGolden"

    readonly property string _dir: "tests/fixtures/migrations-golden"
    readonly property var _cases: ["1.0-pre-profiles", "1.x-widget-profiles", "2.0-before-themes", "2.1-former-default"]

    property FileView _file: FileView {
        blockAllReads: true
        printErrors: false
    }

    function _json(relative) {
        _file.path = Quickshell.shellDir + "/" + relative;
        _file.reload();
        const text = _file.text();
        _file.path = "";
        if (text === "")
            return null;
        try {
            return JSON.parse(text);
        } catch (error) {
            return undefined;
        }
    }

    // Today's startup migrations on `config` (the file's object) and `files` (theme files,
    // "themes/<name>.json" → content). → { config, files, failed }
    function startup(config, files) {
        const out = JSON.parse(JSON.stringify(config));
        const outFiles = JSON.parse(JSON.stringify(files));
        const old = JSON.parse(JSON.stringify(config));
        const entries = SettingsSchema.coreEntries;
        const parsedProfiles = () => JSON.parse(out.profiles);
        const parsedGlobals = () => {
            const parsed = JSON.parse(out.globals ?? "{}");
            return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {};
        };
        const markers = () => out.migratedKeys ?? [];
        let failed = [];

        // Profiles._migrateIfNeeded: the legacy settings, then the changed defaults
        if ((out.profiles ?? "") !== "") {
            const result = ProfileRules.migrateLegacy(entries, path => ProfileRules.readLegacy(old, path),
                                                      markers(), parsedProfiles(), parsedGlobals());
            failed = result.failed;
            const defaults = ProfileRules.migrateDefaults(entries, result.migratedKeys, result.profiles);
            if (defaults.migratedKeys.length !== markers().length) {
                out.profiles = JSON.stringify(defaults.profiles);
                out.globals = JSON.stringify(result.globals);
                out.migratedKeys = defaults.migratedKeys;
            }
        }

        // Profiles._migratePresetsIfNeeded: the preset library from the old widget settings
        if ((out.widgetPresets ?? "") === "") {
            let widgetProfiles = {};
            try {
                widgetProfiles = JSON.parse(old.widgetProfiles || "{}");
            } catch (error) {}
            out.widgetPresets = JSON.stringify(ProfileRules.presetsFromWidgetProfiles(widgetProfiles));
        }

        // ThemeFiles._migrateBarLayoutIfNeeded and _finishMigration: the bar geometry into themes
        if ((out.profiles ?? "") !== "" && !markers().includes("theme.barLayout")) {
            const legacy = markers().includes("bar.layout.barHeight") ? undefined : old.bar?.layout;
            const result = ThemeRules.themesFromBarLayout(parsedProfiles(), parsedGlobals(), legacy,
                                                          name => ("themes/" + name + ".json") in outFiles);
            for (const entry of result.themes)
                outFiles["themes/" + entry.name + ".json"] = entry.theme;
            out.profiles = JSON.stringify(result.profiles);
            out.globals = JSON.stringify(result.globals);
            out.migratedKeys = markers().concat(["theme.barLayout"]);
        }
        return { config: out, files: outFiles, failed: failed };
    }

    // A config compared by what it holds: the JSON texts read, key order not counted, a
    // text left empty kept apart from an empty value
    function _comparable(config) {
        const copy = JSON.parse(JSON.stringify(config));
        for (const key of ["profiles", "globals", "widgetPresets"]) {
            if (typeof copy[key] === "string" && copy[key] !== "")
                copy[key] = { json: JSON.parse(copy[key]) };
        }
        return MigrationRules.canonical(copy);
    }

    function run() {
        for (const name of _cases)
            _case(name);
    }

    function _case(name) {
        const dir = _dir + "/" + name;
        const before = _json(dir + "/before.json");
        const after = _json(dir + "/after.json");
        const filesBefore = _json(dir + "/files-before.json") ?? {};
        const filesAfter = _json(dir + "/files-after.json") ?? {};
        if (!before || !after || filesBefore === undefined || filesAfter === undefined) {
            assert(false, name + ": its fixture is there and is JSON");
            return;
        }
        const result = startup(before, filesBefore);
        assertEqual(result.failed.join("; "), "", name + ": every legacy setting read");
        const same = _comparable(result.config) === _comparable(after);
        if (!same)
            console.log("  " + name + " gave: " + JSON.stringify(result.config));
        assert(same, name + ": the config as today's code leaves it (after.json)");
        const sameFiles = MigrationRules.canonical(result.files) === MigrationRules.canonical(filesAfter);
        if (!sameFiles)
            console.log("  " + name + " gave files: " + JSON.stringify(result.files));
        assert(sameFiles, name + ": the theme files as today's code leaves them (files-after.json)");
        const again = startup(after, filesAfter);
        assert(_comparable(again.config) === _comparable(after) && MigrationRules.canonical(again.files) === MigrationRules.canonical(filesAfter),
               name + ": the next start changes nothing");
    }
}
