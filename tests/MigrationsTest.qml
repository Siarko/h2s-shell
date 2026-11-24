import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

// Every registered settings migration (Migrations.all()) on its fixture,
// tests/fixtures/migrations/<id>/before.json and after.json (whole config files): the output
// as expected, idempotent, unknown keys surviving, the result inside its declared scope, a
// target key already set never overwritten; and the registry: ids, a "*" scope's reason,
// `since` a minor or major release not older than the one before. The harness itself is
// checked on a test-only migration (tests/fixtures/migrations-testonly/) and on broken
// variants of it, each of which it must refuse.
TestCase {
    id: suite
    suiteName: "Migrations"

    readonly property var rules: MigrationRules
    readonly property string _testOnlyDir: "tests/fixtures/migrations-testonly"

    property FileView _file: FileView {
        blockAllReads: true
        printErrors: false
    }

    function _read(relative) {
        _file.path = Quickshell.shellDir + "/" + relative;
        _file.reload();
        const text = _file.text();
        _file.path = "";
        return text;
    }

    function _json(relative) {
        const text = _read(relative);
        if (text === "")
            return null;
        try {
            return JSON.parse(text);
        } catch (error) {
            return undefined;
        }
    }

    // The settings each place holds (profile:<name>, globals, preset:<type>/<name>)
    function _places(document) {
        const places = {};
        for (const profile of document.profiles)
            places["profile:" + profile.name] = profile.set ?? {};
        places["globals"] = document.globals;
        for (const type of Object.keys(document.presets))
            for (const name of Object.keys(document.presets[type]))
                places["preset:" + type + "/" + name] = document.presets[type][name];
        return places;
    }

    // What is wrong with `migration` on the fixture in `dir` (before.json, after.json); [] when
    // nothing
    function _check(migration, dir) {
        const id = migration?.migrationId;
        const before = _json(dir + "/before.json");
        const after = _json(dir + "/after.json");
        if (before === null || after === null)
            return [id + ": no fixture in " + dir];
        if (before === undefined || after === undefined)
            return [id + ": its fixture is not JSON"];
        // Side files, when the migration reads or writes them: files-before.json and
        // files-after.json (path → content), both or neither
        const filesBefore = _json(dir + "/files-before.json");
        const filesAfter = _json(dir + "/files-after.json");
        if ((filesBefore === null) !== (filesAfter === null))
            return [id + ": its fixture has side files on one side only"];
        if (filesBefore === undefined || filesAfter === undefined)
            return [id + ": its side files are not JSON"];
        const input = rules.documentOf(before, filesBefore ?? {});
        const expected = rules.documentOf(after, filesAfter ?? {});
        if (!input.ok || !expected.ok)
            return [id + ": its fixture is not a config: " + (input.problem || expected.problem)];
        const problems = [];
        const context = { version: Version.number };
        const once = rules.applyOne(migration, input.document, context);
        if (!once.ok)
            return [id + ": " + once.error];
        if (rules.canonical(once.document) !== rules.canonical(expected.document))
            problems.push(id + ": the output differs from after.json: " + rules.canonical(once.document).slice(0, 400));
        const twice = rules.applyOne(migration, once.document, context);
        if (!twice.ok || rules.canonical(twice.document) !== rules.canonical(once.document))
            problems.push(id + ": not idempotent");

        // Unknown keys: a top-level key, a setting in every place, a preset type
        const marked = JSON.parse(JSON.stringify(input.document));
        marked.raw.zzMigrationsTestUnknown = { kept: true };
        for (const profile of marked.profiles)
            profile.set = Object.assign({}, profile.set ?? {}, { "zz.migrations-test.unknown": 1 });
        marked.globals["zz.migrations-test.unknown"] = 1;
        marked.presets.zzMigrationsTestUnknown = { Default: { kept: true } };
        marked.files["zz-migrations-test/unknown.json"] = { kept: true };
        const withUnknown = rules.applyOne(migration, marked, context);
        if (!withUnknown.ok)
            problems.push(id + ": fails with unknown keys present: " + withUnknown.error);
        else if (withUnknown.document.raw.zzMigrationsTestUnknown?.kept !== true
                 || withUnknown.document.profiles.some(profile => profile.set?.["zz.migrations-test.unknown"] !== 1)
                 || withUnknown.document.globals["zz.migrations-test.unknown"] !== 1
                 || withUnknown.document.presets.zzMigrationsTestUnknown?.Default?.kept !== true
                 || withUnknown.document.files["zz-migrations-test/unknown.json"]?.kept !== true)
            problems.push(id + ": an unknown key did not survive");

        // A target already set (a key the output has where the input had none) is kept
        const targets = JSON.parse(JSON.stringify(input.document));
        const inputPlaces = _places(targets);
        const outputPlaces = _places(once.document);
        const sentinels = [];
        for (const place of Object.keys(outputPlaces)) {
            const values = inputPlaces[place];
            if (!values)
                continue;
            for (const key of Object.keys(outputPlaces[place]))
                if (!Object.prototype.hasOwnProperty.call(values, key)) {
                    values[key] = "zz-already-set";
                    sentinels.push([place, key]);
                }
        }
        if (sentinels.length > 0) {
            const kept = rules.applyOne(migration, targets, context);
            if (!kept.ok)
                problems.push(id + ": fails with its targets already set: " + kept.error);
            else {
                const keptPlaces = _places(kept.document);
                const overwritten = sentinels.find(([place, key]) => keptPlaces[place]?.[key] !== "zz-already-set");
                if (overwritten)
                    problems.push(id + ": overwrote " + overwritten[1] + " already set in " + overwritten[0]);
            }
        }
        return problems;
    }

    function _all(registry, dirOf) {
        let problems = rules.registryProblems(registry);
        for (const migration of registry)
            problems = problems.concat(_check(migration, dirOf(migration)));
        return problems;
    }

    function run() {
        _registered();
        _harness();
    }

    function _registered() {
        const registry = Migrations.all();
        const problems = _all(registry, migration => "tests/fixtures/migrations/" + migration.migrationId);
        assertEqual(problems.join("\n"), "", "registered: every migration (" + registry.length + ") valid on its fixture");
        registry.push(null);
        assertEqual(Migrations.all().length, registry.length - 1, "registered: the registry is a new list at each call");
    }

    function _harness() {
        const component = Qt.createComponent(Quickshell.shellDir + "/" + _testOnlyDir + "/TestOnlyRename.qml");
        const testOnly = component.status === Component.Ready ? component.createObject(suite) : null;
        assert(testOnly !== null, "harness: the test-only migration loads" + (testOnly ? "" : ": " + component.errorString()));
        if (!testOnly)
            return;
        const dir = migration => _testOnlyDir + "/" + migration.migrationId;
        assertEqual(_all([testOnly], dir).join("\n"), "", "harness: the test-only migration passes on its fixture");

        const variant = changes => Object.assign({ migrationId: testOnly.migrationId, since: testOnly.since, summary: testOnly.summary, scope: testOnly.scope,
                                                   migrate: (doc, context) => testOnly.migrate(doc, context) }, changes);
        const refused = (registry, dirOf, expected, what) => {
            const problems = _all(registry, dirOf).join("\n");
            assert(problems.includes(expected), "harness refuses " + what + (problems.includes(expected) ? "" : " (got: " + problems.slice(0, 300) + ")"));
        };
        refused([variant({ migrationId: "2026-11-26-no-fixture" })], dir, "no fixture", "a migration without a fixture");
        refused([variant({ migrate: doc => MigrationHelpers.renameKey(doc, "testonly.old", "testonly.other") })], dir, "differs from after.json", "a wrong output");
        refused([variant({ migrate: doc => {
            const result = testOnly.migrate(doc);
            result.globals["testonly.runs"] = (result.globals["testonly.runs"] ?? 0) + 1;
            return result;
        } })],
                dir, "not idempotent", "a migration that is not idempotent");
        refused([variant({ migrate: doc => {
            const result = MigrationHelpers.forEachSetting(doc, values => {
                if ("testonly.old" in values)
                    values["testonly.new"] = values["testonly.old"];
                delete values["testonly.old"];
            });
            // The fixture's own case (Quiet's target set) kept, so only the harness's check sees it
            if (result.profiles[1] && doc.profiles[1].set["testonly.new"] === "set later")
                result.profiles[1].set["testonly.new"] = "set later";
            return result;
        } })], dir, "overwrote", "a migration that overwrites a target already set");
        refused([variant({ migrate: doc => { const result = testOnly.migrate(doc); result.globals["theme.name"] = "x"; return result; } })], dir,
                "outside its scope", "a write outside the scope");
        refused([variant({ scope: ["*"], wholeScopeReason: "test" , migrate: doc => { const result = testOnly.migrate(doc); delete result.raw.zzMigrationsTestUnknown; return result; } })],
                dir, "unknown key did not survive", "a migration that drops an unknown key");
        refused([variant({ scope: ["*"] })], dir, "wholeScopeReason", "a \"*\" scope without its reason");

        // Side files: a test-only migration over theme files, its fixture with files-before/-after.json
        const renameInThemes = (doc, extra) => {
            for (const path of Object.keys(doc.files)) {
                const theme = doc.files[path];
                if ("barHeight" in theme && !("height" in theme))
                    theme.height = theme.barHeight;
                delete theme.barHeight;
                extra?.(theme);
            }
            return doc;
        };
        const themes = { migrationId: "2026-11-25-testonly-theme", since: "2.2.0", summary: "A theme key renamed", scope: ["file:themes/*"], migrate: doc => renameInThemes(doc) };
        assertEqual(_all([themes], dir).join("\n"), "", "harness: a side-file migration passes on its fixture's files");
        refused([Object.assign({}, themes, { migrate: doc => renameInThemes(doc, theme => { theme.runs = (theme.runs ?? 0) + 1; }) })], dir,
                "not idempotent", "a side-file migration that is not idempotent");
        refused([Object.assign({}, themes, { migrate: doc => doc })], dir, "differs from after.json", "a side-file migration whose files differ");
        refused([Object.assign({}, themes, { migrate: doc => { delete doc.files["zz-migrations-test/unknown.json"]; return renameInThemes(doc); }, scope: ["*"], wholeScopeReason: "test" })],
                dir, "unknown key did not survive", "a migration that drops a side file it does not know");
        refused([Object.assign({}, themes, { migrationId: "2026-11-25-testonly-half" })], dir, "side files on one side only", "a fixture with side files on one side only");
        refused([variant({ since: "2.2.1" })], dir, "x.y.0", "since a patch release");
        refused([variant({ since: "2.3.0" }), variant({ migrationId: "2026-11-25-testonly-second", since: "2.2.0" })], dir, "older than the migration before it",
                "since older than the migration before");
        testOnly.destroy();
    }
}
