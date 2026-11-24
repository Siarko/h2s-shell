import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

// Golden outputs of the settings migrations at startup, captured from the code before the
// runner (Profiles' legacy settings, changed defaults and widget presets, ThemeFiles' bar
// geometry): for each old config in tests/fixtures/migrations-golden/<case>/ (before.json,
// the config as the migrations see it; files-before.json, the theme files then, path →
// content), what that code left behind (after.json, files-after.json). The registered
// migrations run here as Config runs them — the load phase, then the after-seed phase once
// the profiles exist (MigrationRules.startup, without file I/O or backups) — and then
// ThemeFiles' bar geometry, not on the runner yet, on the same rules function. What the save
// adds (writtenBy, the declared keys' defaults) is not part of it.
//
// The records (migratedKeys) are compared as a set, without the ids of the registered
// migrations, which the code before the runner did not write: the per-key markers it wrote
// must be the same. A case with differs.json is where the runner deliberately does otherwise
// than that code did (old-code.json): its after.json is the runner's result, and differs.json
// says whether the session is left read-only.
//
// A config from before profiles is seeded (Profiles._seedIfNeeded, the power profile
// "balanced") before the after-seed phase: its before.json holds the seeded profiles, so the
// case does not depend on the defaults of the day.
TestCase {
    id: suite
    suiteName: "MigrationsGolden"

    readonly property string _dir: "tests/fixtures/migrations-golden"
    readonly property var _cases: ["1.0-pre-profiles", "1.x-widget-profiles", "2.0-before-themes", "2.1-former-default",
                                   "2.x-module-popup-mode", "broken-profiles-marked", "broken-profiles-unmarked",
                                   "1.x-legacy-partial", "1.x-no-full", "2.1-former-default-other-profiles"]

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

    // The startup migrations on `config` (the file's object) and `files` (theme files,
    // "themes/<name>.json" → content). → { config, files, readOnly }
    function startup(config, files) {
        const registry = Migrations.all();
        const options = phase => ({ phase: phase, version: Version.number, context: { version: Version.number } });
        let out = JSON.parse(JSON.stringify(config));
        const outFiles = JSON.parse(JSON.stringify(files));
        const old = JSON.parse(JSON.stringify(config));
        for (const phase of ["load", "afterSeed"]) {
            // ConfigFile.runAfterSeed: once the profiles exist
            if (phase === "afterSeed" && (out.profiles ?? "") === "")
                continue;
            const run = MigrationRules.startup(registry, out, outFiles, [], options(phase));
            if (run.readOnly)
                return { config: out, files: outFiles, readOnly: true };
            if (run.write)
                out = run.config;
            for (const path of Object.keys(run.files))
                outFiles[path] = run.files[path];
        }
        const parsedProfiles = () => JSON.parse(out.profiles);
        const parsedGlobals = () => {
            const parsed = JSON.parse(out.globals ?? "{}");
            return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {};
        };
        const markers = () => out.migratedKeys ?? [];

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
        return { config: out, files: outFiles, readOnly: false };
    }

    // A config compared by what it holds: the JSON texts read, key order not counted, a
    // text left empty kept apart from an empty value, the records as a set without the
    // registered ids
    function _comparable(config) {
        const copy = JSON.parse(JSON.stringify(config));
        const ids = Migrations.all().map(migration => migration.migrationId);
        if (Array.isArray(copy.migratedKeys))
            copy.migratedKeys = copy.migratedKeys.filter(entry => !ids.includes(entry)).sort();
        for (const key of ["profiles", "globals", "widgetPresets"]) {
            if (typeof copy[key] === "string" && copy[key] !== "") {
                try {
                    copy[key] = { json: JSON.parse(copy[key]) };
                } catch (error) {
                    // A text that does not parse is compared as it is
                    copy[key] = { text: copy[key] };
                }
            }
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
        const differs = _json(dir + "/differs.json");
        const result = startup(before, filesBefore);
        assertEqual(result.readOnly, differs?.readOnly === true, name + ": " + (differs?.readOnly === true ? "the session is read-only" : "the result is written"));
        if (differs) {
            const oldCode = _json(dir + "/old-code.json");
            assert(oldCode && _comparable(oldCode) !== _comparable(after), name + ": what the code before the runner did differs (old-code.json)");
        } else {
            // Each converted migration ran and was recorded, or the config said it was applied before
            const records = result.config.migratedKeys ?? [];
            const missing = Migrations.all().filter(migration => !records.includes(migration.migrationId)
                                                    && !MigrationRules.appliedBefore(migration, before));
            assertEqual(missing.map(migration => migration.migrationId).join(", "), "", name + ": every migration recorded or applied before");
        }
        const same = _comparable(result.config) === _comparable(after);
        if (!same)
            console.log("  " + name + " gave: " + JSON.stringify(result.config));
        assert(same, name + ": the config as expected (after.json)");
        const sameFiles = MigrationRules.canonical(result.files) === MigrationRules.canonical(filesAfter);
        if (!sameFiles)
            console.log("  " + name + " gave files: " + JSON.stringify(result.files));
        assert(sameFiles, name + ": the theme files as expected (files-after.json)");
        const again = startup(after, filesAfter);
        assert(_comparable(again.config) === _comparable(after) && MigrationRules.canonical(again.files) === MigrationRules.canonical(filesAfter),
               name + ": the next start changes nothing");
    }
}
