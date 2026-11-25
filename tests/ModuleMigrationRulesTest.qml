import QtQuick
import qs.singletons

// ModuleMigrationRules (pure): the manifest's `migrations` read and checked (and through
// ModuleManifestRules.parseManifest: a fault fails the module), a module scope confined to
// the module's own settings and store — another module's keys and the core's refused, in the
// scope and in a result —, the records "mod.<id>/<mid>" (reset:, held:) and their removal
// with the module, and the run with the per-scope reset on a failure.
TestCase {
    id: suite
    suiteName: "ModuleMigrationRules"

    readonly property var rules: ModuleMigrationRules

    function _manifest(fields) {
        return JSON.stringify(Object.assign({ id: "tailscale", name: "Tailscale", version: "0.9.0", api: "1.43" }, fields ?? {}));
    }

    function _entry(fields) {
        return Object.assign({ id: "taildrop-folder", since: "0.8.0", file: "migrations/TaildropFolder.qml" }, fields ?? {});
    }

    function _has(list, fragment) {
        return (list ?? []).some(entry => String(entry).includes(fragment));
    }

    // The core's profiles and globals with the module's keys, another module's and the core's
    function _part() {
        const profiles = [
            { name: "Full", enabled: true, set: { "mod.tailscale.taildrop.folder": "~/In", "mod.tailscale.exitNode": "a", "clock.format": "hh", "mod.other.x": 1 } },
            { name: "Battery", enabled: true, set: { "battery.warn": 20 } }
        ];
        const globals = { "mod.tailscale.taildrop.ask": true, "theme.name": "dark", "mod.tailscalex.y": 2 };
        return rules.partOf("tailscale", profiles, globals, { folders: ["a"], token: "t" }).part;
    }

    function _migration(id, scope, migrate) {
        return { migrationId: id, scope: scope, migrate: migrate };
    }

    function run() {
        _manifestField();
        _scopes();
        _records();
        _partAndProjection();
        _confinement();
        _runs();
        _failure();
        _hostDecisions();
    }

    function _manifestField() {
        let read = rules.readMigrations(undefined, "tailscale", "0.9.0");
        assertEqual(JSON.stringify(read), JSON.stringify({ migrations: [], errors: [] }), "none: no migrations, no error");
        read = rules.readMigrations([_entry({ scope: ["setting:taildrop.*", "store:folders"] }), _entry({ id: "exit-node", since: "0.9.0" })], "tailscale", "0.9.0");
        assertEqual(read.errors.length, 0, "two good entries: no error");
        assertEqual(JSON.stringify(read.migrations), JSON.stringify([
            { id: "taildrop-folder", since: "0.8.0", file: "migrations/TaildropFolder.qml", scope: ["setting:taildrop.*", "store:folders"] },
            { id: "exit-node", since: "0.9.0", file: "migrations/TaildropFolder.qml", scope: ["*"] }]), "… kept in order; an omitted scope is \"*\"");
        const refused = (value, fragment, message) => {
            const result = rules.readMigrations(value, "tailscale", "0.9.0");
            assert(result.migrations.length === 0 && _has(result.errors, fragment), message + " — " + JSON.stringify(result.errors));
        };
        refused({}, "not a list", "not a list: refused");
        refused(["x"], "not an object", "an entry that is no object: refused, nothing kept");
        refused([_entry(), _entry({ id: "Bad Id" })], "not a migration id", "a bad id: the whole list refused, the good entry too");
        refused([_entry({ id: "a".repeat(65) })], "not a migration id", "an id of 65 characters: refused");
        assertEqual(rules.readMigrations([_entry({ id: "a".repeat(64) })], "tailscale", "0.9.0").errors.length, 0, "… of 64: taken");
        refused([_entry(), _entry()], "listed twice", "an id twice: refused");
        refused([_entry({ since: 8 })], "not a version", "since not a version: refused");
        refused([_entry({ since: "1.0.0" })], "newer than the module's version", "since newer than the module: refused");
        assertEqual(rules.readMigrations([_entry({ since: "0.9.0" })], "tailscale", "0.9.0").errors.length, 0, "… since the module's own version: taken");
        refused([_entry({ since: "0.9.0" }), _entry({ id: "b", since: "0.8.0" })], "older than the migration before", "since out of order: refused");
        assertEqual(rules.readMigrations([_entry({ since: "0.8.0" }), _entry({ id: "b", since: "0.8.0" })], "tailscale", "0.9.0").errors.length, 0, "… the same since twice: taken");
        refused([_entry({ file: "migrations/../../core/Evil.qml" })], "leaves the module's directory", "a file outside the module: refused");
        refused([_entry({ file: "/etc/x.qml" })], "absolute path", "an absolute file: refused");
        refused([_entry({ file: "migrations/x.js" })], "not a .qml file", "a file not .qml: refused");
        refused([_entry({ file: undefined })], "not a file name", "no file: refused");
        refused([_entry({ summary: "x" })], "unknown field", "an unknown field: refused");
        refused([_entry({ scope: ["setting:mod.other.x"] })], "not a scope path", "a scope naming another module's key: refused");
        refused([_entry({ scope: [] })], "not a list of paths", "an empty scope: refused");
        assertEqual(rules.readMigrations(new Array(200).fill(0).map((_, i) => _entry({ id: "m" + i })), "tailscale", "0.9.0").migrations.length, 200, "200 entries: taken");
        refused(new Array(201).fill(0).map((_, i) => _entry({ id: "m" + i })), "at most", "more entries than ModuleRules.maxEntries: refused");

        // Through the manifest
        const good = ModuleManifestRules.parseManifest(_manifest({ migrations: [_entry()] }));
        assert(good.valid && good.migrations.length === 1 && good.migrations[0].id === "taildrop-folder", "parseManifest: migrations read, the module valid");
        assert(!_has(good.warnings, "migrations"), "… no warning (not an unknown field, its API asked for)");
        assertEqual(ModuleManifestRules.parseManifest(_manifest()).migrations.length, 0, "parseManifest: none: []");
        const bad = ModuleManifestRules.parseManifest(_manifest({ migrations: [_entry({ scope: ["setting:clock.format", "*"] })] }));
        assert(!bad.valid && bad.migrations.length === 0 && _has(bad.errors, "migrations[0]"), "parseManifest: a fault fails the module — " + JSON.stringify(bad.errors));
        const old = ModuleManifestRules.parseManifest(_manifest({ api: "1.42", migrations: [_entry()] }));
        assert(old.valid && _has(old.warnings, "a field of API 1.43"), "parseManifest: asked for 1.42, read with a warning");
        const noId = ModuleManifestRules.parseManifest(_manifest({ id: "Bad", migrations: [_entry()] }));
        assert(!noId.valid && _has(noId.errors, "migrations: not read without a module id"), "parseManifest: without an id, migrations not read and the module fails");
        const noVersion = ModuleManifestRules.parseManifest(_manifest({ version: "", migrations: [_entry()] }));
        assert(!noVersion.valid, "parseManifest: a bad version still fails the module");
    }

    function _scopes() {
        const path = text => JSON.stringify(rules.parsePath("tailscale", text));
        assertEqual(path("setting:exitNode"), JSON.stringify({ kind: "setting", key: "mod.tailscale.exitNode", prefix: "" }), "setting:<name>: the full key");
        assertEqual(path("setting:taildrop.*"), JSON.stringify({ kind: "setting", key: "", prefix: "mod.tailscale.taildrop." }), "setting:<prefix>.*: the full prefix");
        assertEqual(path("store:folders"), JSON.stringify({ kind: "store", key: "folders" }), "store:<key>");
        assertEqual(path("store:a/b.c"), JSON.stringify({ kind: "store", key: "a/b.c" }), "store: any key text");
        assertEqual(path("*"), JSON.stringify({ kind: "whole" }), "*: the module's whole part");
        for (const text of ["setting:mod.other.x", "setting:mod.tailscale.x", "setting:mod", "setting:mod.*", "setting:../clock", "setting:clock format",
                            "setting:*", "setting:", "setting:a.", "store:", "store:*", "store:__proto__", "store:" + "k".repeat(129),
                            "raw:gcal", "preset:music", "file:themes/x.json", "read:setting:x", "clock.format", 7, null])
            assertEqual(path(text), "null", "refused: " + JSON.stringify(text));
        assert(path("store:" + "k".repeat(128)) !== "null", "store: a key of 128 characters is taken");
        assert(path("setting:" + "a".repeat(192)) !== "null" && path("setting:" + "a".repeat(193)) === "null", "a path of 200 characters is taken, of 201 not");
        assertEqual(rules.parseScope("tailscale", ["*", "store:x"]).whole, false, "an unreadable scope is not read as \"*\"");
        assertEqual(JSON.stringify(rules.parsePath("Bad Id", "*")), "null", "a bad module id: no path");
        assert(rules.parseScope("tailscale", undefined).ok && rules.parseScope("tailscale", undefined).whole, "scope omitted: the whole part");
        assert(!rules.parseScope("tailscale", "setting:x").ok, "scope not a list: refused");
        assert(!rules.parseScope("tailscale", ["*", "store:x"]).ok, "\"*\" stands alone");
        assert(!rules.parseScope("tailscale", new Array(33).fill("store:x")).ok, "more than 32 paths: refused");
        assert(rules.parseScope("tailscale", new Array(32).fill("store:x")).ok, "… 32: taken");
        const scope = list => rules.parseScope("tailscale", list);
        assert(rules.scopesOverlap(scope(["setting:taildrop.*"]), scope(["setting:taildrop.folder"])), "overlap: a key under a prefix");
        assert(rules.scopesOverlap(scope(["setting:taildrop.folder"]), scope(["setting:taildrop.*"])), "overlap: … either way");
        assert(rules.scopesOverlap(scope(["setting:a.b.*"]), scope(["setting:a.*"])), "overlap: two prefixes, one under the other");
        assert(!rules.scopesOverlap(scope(["setting:taildrop.*"]), scope(["setting:exitNode"])), "no overlap: different settings");
        assert(!rules.scopesOverlap(scope(["setting:a"]), scope(["setting:b"])) && rules.scopesOverlap(scope(["setting:a"]), scope(["setting:a"])), "two keys: overlap when the same");
        assert(!rules.scopesOverlap(scope(["setting:ab.*"]), scope(["setting:a.*"])), "no overlap: a prefix is cut at a dot");
        assert(!rules.scopesOverlap(scope(["setting:x"]), scope(["store:x"])), "no overlap: a setting and a store key of one name");
        assert(rules.scopesOverlap(scope(["store:x"]), scope(["store:x"])) && !rules.scopesOverlap(scope(["store:x"]), scope(["store:y"])), "store keys: overlap by name");
        assert(rules.scopesOverlap(scope(["*"]), scope(["store:y"])), "overlap: \"*\" with anything");
        assert(rules.scopesOverlap(scope(["bad"]), scope(["store:y"])), "overlap: an unreadable scope with anything");
    }

    function _records() {
        assertEqual(rules.recordOf("tailscale", "taildrop-folder"), "mod.tailscale/taildrop-folder", "record: mod.<id>/<mid>");
        const parse = entry => JSON.stringify(rules.parseRecord("tailscale", entry));
        assertEqual(parse("mod.tailscale/taildrop-folder"), JSON.stringify({ kind: "applied", id: "taildrop-folder", version: "" }), "applied");
        assertEqual(parse("reset:mod.tailscale/taildrop-folder"), JSON.stringify({ kind: "reset", id: "taildrop-folder", version: "" }), "reset:");
        assertEqual(parse("held:mod.tailscale/taildrop-folder@0.9.0"), JSON.stringify({ kind: "held", id: "taildrop-folder", version: "0.9.0" }), "held:…@<version>");
        for (const entry of ["mod.other/taildrop-folder", "mod.tailscalex/a", "mod.tailscale/Bad", "reset:mod.other/a", "held:mod.other/a@1",
                             "held:mod.tailscale/a", "2026-11-25-popup-mode", "theme.barLayout", "mod.tailscale.exitNode", 7])
            assertEqual(rules.parseRecord("tailscale", entry).kind, "other", "not this module's record: " + JSON.stringify(entry));
        assertEqual(MigrationRules.parseRecord("mod.tailscale/taildrop-folder").kind, "other", "the core does not read a module's record as its own");
        const records = ["2026-11-25-popup-mode", "mod.tailscale/a", "reset:mod.tailscale/b", "held:mod.tailscale/c@0.9.0", "mod.other/a", "bar.height"];
        assertEqual(JSON.stringify(rules.moduleRecords("tailscale", records)), JSON.stringify(["mod.tailscale/a", "reset:mod.tailscale/b", "held:mod.tailscale/c@0.9.0"]), "the module's records");
        assertEqual(JSON.stringify(rules.withoutModuleRecords("tailscale", records)), JSON.stringify(["2026-11-25-popup-mode", "mod.other/a", "bar.height"]),
                    "removed with its data: its records dropped, every other kept");
        assertEqual(JSON.stringify(rules.withoutModuleRecords("tailscale", "x")), "[]", "records not a list: none");
        assert(rules.isDone("tailscale", "a", records) && rules.isDone("tailscale", "b", records) && !rules.isDone("tailscale", "c", records), "done: applied and reset, not held");
        assert(!rules.isDone("other", "b", records), "done: another module's record is not");
        assert(rules.isHeld("tailscale", "c", records, "0.9.0") && !rules.isHeld("tailscale", "c", records, "1.0.0"), "held only under its version");
        const migrations = ["a", "b", "c", "d"].map(id => _migration(id, ["*"], part => part));
        assertEqual(rules.pending("tailscale", migrations, records).map(migration => migration.migrationId).join(","), "c,d", "pending: not done, held included");
        assertEqual(JSON.stringify(rules.baseline("tailscale", migrations, ["x", "mod.tailscale/a"])),
                    JSON.stringify(["x", "mod.tailscale/a", "mod.tailscale/b", "mod.tailscale/c", "mod.tailscale/d"]), "baseline: every id recorded once");
        assertEqual(JSON.stringify(rules.baseline("Bad Id", migrations, ["x"])), JSON.stringify(["x"]), "baseline: a bad module id records nothing");
    }

    function _partAndProjection() {
        const part = _part();
        assert(rules.partOf("tailscale", [], {}, {}).ok, "part: readable input is ok");
        assertEqual(JSON.stringify(part.settings.profiles), JSON.stringify([
            { name: "Full", set: { "mod.tailscale.taildrop.folder": "~/In", "mod.tailscale.exitNode": "a" } },
            { name: "Battery", set: {} }]), "part: every profile by name, the module's keys only");
        assertEqual(JSON.stringify(part.settings.globals), JSON.stringify({ "mod.tailscale.taildrop.ask": true }), "part: its pinned keys only (not mod.tailscalex.*)");
        assertEqual(JSON.stringify(part.store), JSON.stringify({ folders: ["a"], token: "t" }), "part: the store");
        assert(!rules.partOf("tailscale", "x", {}, {}).ok && !rules.partOf("tailscale", [], [], {}).ok && !rules.partOf("tailscale", [], {}, []).ok
               && !rules.partOf("Bad Id", [], {}, {}).ok && !rules.partOf("tailscale", [{ set: {} }], {}, {}).ok, "part: unreadable input refused");
        assertEqual(JSON.stringify(rules.partOf("tailscale", [], {}, undefined).part.store), "{}", "part: no store yet: {}");
        const handed = rules.projection("tailscale", part, rules.parseScope("tailscale", ["setting:taildrop.*", "store:folders"]));
        assertEqual(JSON.stringify(handed), JSON.stringify({
            settings: { profiles: [{ name: "Full", set: { "mod.tailscale.taildrop.folder": "~/In" } }, { name: "Battery", set: {} }],
                        globals: { "mod.tailscale.taildrop.ask": true } },
            store: { folders: ["a"] } }), "projection: only the scope's keys");
        const whole = rules.projection("tailscale", part, rules.parseScope("tailscale", ["*"]));
        assertEqual(JSON.stringify(whole), JSON.stringify(part), "projection: \"*\" the whole part");
    }

    function _confinement() {
        const part = _part();
        const scope = rules.parseScope("tailscale", ["setting:taildrop.*", "store:folders"]);
        const handed = rules.projection("tailscale", part, scope);
        const write = change => {
            const result = JSON.parse(JSON.stringify(handed));
            change(result);
            return rules.resultProblem("tailscale", result, handed, scope);
        };
        assertEqual(write(result => { result.settings.profiles[0].set["mod.tailscale.taildrop.dir"] = "x"; }), "", "a key in scope: taken");
        assertEqual(write(result => { result.store.folders = []; }), "", "a store key in scope: taken");
        assert(write(result => { result.settings.profiles[0].set["clock.format"] = "x"; }).includes("clock.format outside its scope"), "a core key: refused");
        assert(write(result => { result.settings.globals["theme.name"] = "x"; }).includes("outside its scope"), "a core key pinned: refused");
        assert(write(result => { result.settings.profiles[1].set["mod.other.x"] = 1; }).includes("mod.other.x outside"), "another module's key: refused");
        assert(write(result => { result.settings.globals["mod.tailscalex.y"] = 1; }).includes("outside"), "a module whose id starts the same: refused");
        assert(write(result => { result.settings.profiles[0].set["mod.tailscale.exitNode"] = "b"; }).includes("outside"), "its own key outside the scope: refused");
        assert(write(result => { result.store.token = "x"; }).includes("store key token outside"), "a store key outside the scope: refused");
        assert(write(result => { result.settings.profiles.push({ name: "New", set: {} }); }).includes("profile"), "a profile added: refused");
        assert(write(result => { result.settings.profiles[1].name = "Other"; }).includes("profile"), "a profile renamed: refused");
        assert(write(result => { result.settings.profiles[0].enabled = false; }).includes("malformed"), "a profile's other field: refused");
        assert(write(result => { result.settings.profiles[0].set = 1; }).includes("malformed"), "a set that is no object: refused");
        assert(write(result => { result.settings.profiles = "x"; }).includes("malformed"), "profiles that are no list: refused");
        assert(write(result => { result.settings.profiles[0] = null; }).includes("malformed"), "a profile that is null: refused");
        assert(write(result => { result.raw = {}; }).includes("no module part has"), "a core part (raw): refused");
        assert(write(result => { result.settings.presets = {}; }).includes("no module part has"), "presets: refused");
        assert(write(result => { delete result.store; }).includes("no settings and store"), "no store: refused");
        assertEqual(rules.resultProblem("tailscale", null, handed, scope), "it returned no settings and store", "null: refused");
        // "*": all of its own, still never the core's or another module's
        const wholeScope = rules.parseScope("tailscale", ["*"]);
        const wholeHanded = rules.projection("tailscale", part, wholeScope);
        const writeWhole = change => {
            const result = JSON.parse(JSON.stringify(wholeHanded));
            change(result);
            return rules.resultProblem("tailscale", result, wholeHanded, wholeScope);
        };
        assertEqual(writeWhole(result => { result.settings.profiles[1].set["mod.tailscale.new"] = 1; result.store.anything = 2; }), "", "\"*\": any key of its own and of its store");
        assert(writeWhole(result => { result.settings.profiles[1].set["battery.warn"] = 1; }).includes("battery.warn outside"), "\"*\": a core key refused");
        assert(writeWhole(result => { result.settings.globals["mod.other.x"] = 1; }).includes("outside"), "\"*\": another module's key refused");
        assert(writeWhole(result => { result.settings.globals["mod.tailscale.bad key"] = 1; }).includes("outside"), "\"*\": a key that is no setting name refused");
    }

    function _runs() {
        const part = _part();
        const migrations = [
            _migration("taildrop-folder", ["setting:taildrop.*"], (doc, context) => {
                for (const profile of doc.settings.profiles)
                    if (profile.set["mod.tailscale.taildrop.folder"] !== undefined) {
                        profile.set["mod.tailscale.taildrop.dir"] = profile.set["mod.tailscale.taildrop.folder"] + "@" + context.fromVersion;
                        delete profile.set["mod.tailscale.taildrop.folder"];
                    }
                return doc;
            }),
            _migration("folders-count", ["store:folders"], doc => { doc.store.folders = doc.store.folders.length; return doc; })
        ];
        const report = rules.run("tailscale", migrations, part, { records: ["x", "mod.other/taildrop-folder"], version: "0.9.0", context: { fromVersion: "0.7.0", toVersion: "0.9.0" } });
        assertEqual(report.applied.join(","), "taildrop-folder,folders-count", "run: both applied in order");
        assertEqual(JSON.stringify(report.part.settings.profiles[0].set), JSON.stringify({ "mod.tailscale.exitNode": "a", "mod.tailscale.taildrop.dir": "~/In@0.7.0" }),
                    "run: the result merged, the rest kept, the context handed");
        assertEqual(JSON.stringify(report.part.store), JSON.stringify({ folders: 1, token: "t" }), "run: the store merged");
        assertEqual(JSON.stringify(report.records), JSON.stringify(["x", "mod.other/taildrop-folder", "mod.tailscale/taildrop-folder", "mod.tailscale/folders-count"]),
                    "run: recorded as mod.<id>/<mid>, other records kept (another module's of the same id too)");
        assert(report.write && report.changed, "run: to be written");
        const again = rules.run("tailscale", migrations, report.part, { records: report.records, version: "0.9.0" });
        assert(again.applied.length === 0 && !again.write && !again.changed, "run again: nothing pending, nothing written");
        assertEqual(JSON.stringify(_part()), JSON.stringify(part), "run: the input part not modified");
        const fresh = rules.run("tailscale", migrations, part, { records: ["x"], fresh: true });
        assert(fresh.applied.length === 0 && fresh.write && fresh.part === part, "fresh: none run");
        assertEqual(JSON.stringify(fresh.records), JSON.stringify(["x", "mod.tailscale/taildrop-folder", "mod.tailscale/folders-count"]), "fresh: every id recorded");
        const freshAgain = rules.run("tailscale", migrations, part, { records: fresh.records, fresh: true });
        assert(!freshAgain.write, "fresh with all recorded: nothing written");
        const nothing = rules.run("tailscale", [_migration("same", ["*"], doc => doc)], part, { records: [] });
        assert(nothing.write && !nothing.changed && nothing.applied.length === 1, "a migration that changes nothing: recorded, the part unchanged");
        const badModule = rules.run("Bad Id", migrations, part, { records: ["x"] });
        assert(!badModule.write && !badModule.changed && badModule.applied.length === 0, "a bad module id: nothing run");
        // The part's keys stay plain: written and removed by the host afterwards
        report.part.store.folders = 2;
        report.part.settings.profiles[0].set["mod.tailscale.taildrop.dir"] = "d";
        delete report.part.store.token;
        assertEqual(JSON.stringify(report.part.store) + report.part.settings.profiles[0].set["mod.tailscale.taildrop.dir"], "{\"folders\":2}d", "run: the merged part's keys can be changed and removed");
        // A held record is dropped only for the migration that now runs
        const records = rules.run("tailscale", migrations.slice(0, 1), part,
                                  { records: ["held:mod.tailscale/taildrop-folder@0.8.0", "keep", "held:mod.tailscale/other@0.8.0"], version: "0.9.0", context: {} }).records;
        assertEqual(JSON.stringify(records), JSON.stringify(["keep", "held:mod.tailscale/other@0.8.0", "mod.tailscale/taildrop-folder"]), "run: the held record of the one run replaced, others kept");
    }

    function _failure() {
        const part = _part();
        const migrations = [
            _migration("a-exit", ["setting:exitNode"], doc => { doc.settings.profiles[0].set["mod.tailscale.exitNode"] = "b"; return doc; }),
            _migration("x-taildrop", ["setting:taildrop.*"], doc => { throw new Error("broken"); }),
            _migration("y-taildrop-ask", ["setting:taildrop.ask"], doc => { doc.settings.globals["mod.tailscale.taildrop.ask"] = false; return doc; }),
            _migration("z-store", ["store:folders"], doc => { doc.store.folders = []; return doc; }),
            _migration("w-core", ["store:token"], doc => { doc.settings.globals["clock.format"] = "evil"; return doc; }),
            _migration("v-token", ["store:token"], doc => { doc.store.token = "new"; return doc; })
        ];
        const report = rules.run("tailscale", migrations, part, { records: ["held:mod.tailscale/a-exit@0.8.0"], version: "0.9.0" });
        assertEqual(report.applied.join(","), "a-exit,z-store", "failure: the ones before and the independent ones applied");
        assertEqual(report.reset.map(each => each.id).join(","), "x-taildrop,w-core", "failure: the throwing one and the one writing a core key reset");
        assertEqual(report.reset[0].error, "it failed: broken", "failure: the error said");
        assert(report.reset[1].error.includes("clock.format outside its scope"), "failure: the reason names the key outside — " + report.reset[1].error);
        assertEqual(JSON.stringify(report.skipped), JSON.stringify([{ id: "y-taildrop-ask", after: "x-taildrop" }, { id: "v-token", after: "w-core" }]), "failure: dependents skipped");
        assertEqual(JSON.stringify(report.part.settings.profiles[0].set), JSON.stringify({ "mod.tailscale.exitNode": "b" }), "failure: its scope reset (taildrop keys removed)");
        assertEqual(JSON.stringify(report.part.settings.globals), "{}", "failure: … in the globals too, the dependent's change not made");
        assertEqual(JSON.stringify(report.part.store), "{\"folders\":[]}", "failure: the store key of the failed scope removed, the independent applied");
        assertEqual(JSON.stringify(report.records), JSON.stringify(["mod.tailscale/a-exit", "reset:mod.tailscale/x-taildrop", "mod.tailscale/z-store", "reset:mod.tailscale/w-core"]),
                    "failure: reset:mod.<id>/<mid> recorded, a held record of another version replaced, skipped ones not recorded");
        const next = rules.run("tailscale", migrations, report.part, { records: report.records, version: "0.9.0" });
        assertEqual(next.applied.join(","), "y-taildrop-ask,v-token", "next start: the skipped ones run on the reset scope");
        // Held: not run, its dependents skipped, its record kept
        const held = rules.run("tailscale", migrations.slice(1, 3), part, { records: ["held:mod.tailscale/x-taildrop@0.9.0"], version: "0.9.0" });
        assert(held.held.join(",") === "x-taildrop" && held.skipped.length === 1 && held.applied.length === 0, "held: not run, its dependent skipped");
        assertEqual(JSON.stringify(held.part), JSON.stringify(part), "held: the part kept as it was");
        assertEqual(JSON.stringify(held.records), JSON.stringify(["held:mod.tailscale/x-taildrop@0.9.0"]), "held: its record kept");
        // "*" failing: the whole part reset, never more; later ones skipped
        const whole = rules.run("tailscale", [_migration("all", ["*"], doc => { doc.settings.globals["theme.name"] = "x"; return doc; }),
                                              _migration("after", ["store:token"], doc => doc)], part, { records: [] });
        assertEqual(JSON.stringify(whole.part), JSON.stringify({ settings: { profiles: [{ name: "Full", set: {} }, { name: "Battery", set: {} }], globals: {} }, store: {} }),
                    "\"*\" failing: the module's whole part reset");
        assert(whole.skipped.length === 1 && whole.reset.length === 1 && whole.write, "\"*\" failing: recorded reset, the later one skipped");
        // An unreadable scope or no migrate function: the whole part reset
        const unreadable = rules.run("tailscale", [_migration("odd", ["setting:mod.core"], doc => doc)], part, { records: [] });
        assert(unreadable.reset.length === 1 && Object.keys(unreadable.part.store).length === 0, "an unreadable scope: failed, the whole part reset");
        const noFunction = rules.run("tailscale", [{ migrationId: "none", scope: ["store:token"] }], part, { records: [] });
        assert(noFunction.reset.length === 1 && noFunction.part.store.token === undefined && noFunction.part.store.folders !== undefined, "no migrate function: its scope reset");
        const noDocument = rules.run("tailscale", [_migration("void", ["store:token"], doc => undefined)], part, { records: [] });
        assert(noDocument.reset.length === 1 && noDocument.reset[0].error.includes("no settings and store"), "no part returned: reset");
        const badId = rules.run("tailscale", [_migration("Bad", ["*"], doc => doc)], part, { records: [] });
        assert(badId.applied.length === 0 && badId.reset.length === 0 && !badId.write, "a migration with a bad id: not run");
    }

    // What the host does with a run: a first install, the backup, the store's writes, a summary
    function _hostDecisions() {
        const empty = { settings: { profiles: [{ name: "Full", set: {} }], globals: {} }, store: {} };
        assert(rules.isFresh("tailscale", empty, ["2.1.0-core", "mod.other/x"]), "isFresh: no setting, no store key, no record of its own");
        assert(!rules.isFresh("tailscale", empty, ["mod.tailscale/x"]), "… a record of its own: not fresh");
        assert(!rules.isFresh("tailscale", empty, ["held:mod.tailscale/x@1.0.0"]), "… a hold of its own: not fresh");
        assert(!rules.isFresh("tailscale", { settings: { profiles: [{ name: "Full", set: { "mod.tailscale.a": 1 } }], globals: {} }, store: {} }, []), "… a setting in a profile: not fresh");
        assert(!rules.isFresh("tailscale", { settings: { profiles: [], globals: { "mod.tailscale.a": 1 } }, store: {} }, []), "… a pinned one: not fresh");
        assert(!rules.isFresh("tailscale", { settings: { profiles: [], globals: {} }, store: { token: "t" } }, []), "… a store key: not fresh");
        assert(!rules.isFresh("tailscale", null, []) && !rules.isFresh("Bad id", empty, []), "… nothing readable: not fresh");
        assert(!rules.isFresh("tailscale", { settings: { profiles: [], globals: {} }, store: null }, [])
               && !rules.isFresh("tailscale", { settings: null, store: {} }, []), "… a store or settings not read: not fresh");

        assert(rules.backupNeeded({ write: true, changed: true, reset: [] }, false), "backupNeeded: something changed");
        assert(rules.backupNeeded({ write: true, changed: false, reset: [{ id: "x" }] }, false), "… a scope reset (even one that held nothing)");
        assert(!rules.backupNeeded({ write: true, changed: false, reset: [] }, false), "… only records written: none");
        assert(!rules.backupNeeded({ write: true, changed: true, reset: [] }, true), "… right after a switch's backup: none");
        assert(!rules.backupNeeded({ write: false, changed: true, reset: [] }, false) && !rules.backupNeeded(null, false), "… nothing written: none");

        assertEqual(JSON.stringify(rules.storeChanges({ a: 1, b: [1], c: "x", d: { k: 1, j: 2 } }, { b: [1, 2], c: "x", d: { j: 2, k: 1 }, e: null })),
                    JSON.stringify([{ key: "a" }, { key: "b", value: [1, 2] }, { key: "e", value: null }]),
                    "storeChanges: a key removed (value undefined), one changed, one added; equal values in another key order left out");
        assertEqual(JSON.stringify(rules.storeChanges(null, undefined)), "[]", "… nothing: nothing");

        assertEqual(rules.summaryOf("Town is now City"), "Town is now City", "summaryOf: the file's text");
        assertEqual(rules.summaryOf("two\nlines<b>"), "two lines<b>", "… one line, plain");
        assertEqual(rules.summaryOf("x".repeat(300)).length, 200, "… at most 200 characters");
        assertEqual(JSON.stringify(rules.recordsAfterRestore("tailscale", ["2.1.0-core", "mod.tailscale/a", "reset:mod.tailscale/b", "held:mod.tailscale/b@1.0.0",
                                                                         "mod.tailscalex/a", "reset:mod.other/c", 5])),
                    JSON.stringify(["2.1.0-core", "held:mod.tailscale/b@1.0.0", "mod.tailscalex/a", "reset:mod.other/c"]),
                    "recordsAfterRestore: its applied and reset records go, its hold and every other record stay");
        assertEqual(rules.summaryOf(undefined) + rules.summaryOf(5), "", "… none declared: empty");
    }
}
