import QtQuick
import qs.singletons

// MigrationRules (pure): which migrations are pending from the registry and the records
// ("<id>", "reset:<id>", "held:<id>@<version>"), the scope language, the projection a
// migration is handed and a result reaching outside it as a failure, dependency derived from
// overlapping scopes, the run in registry order with the per-scope reset on a failure (the
// ones before applied, the failed scope removed, dependents skipped, independent ones run), a
// failing "*" migration writing nothing and asking for read-only, a new config's baseline,
// a config from a newer version and what is said about it, the undeclared top-level keys a
// save puts back, the registry's own checks (ids, since x.y.0 in order) and the
// backups kept. MigrationHelpers: rename, map and remove across every profile, the globals
// and asked presets, an existing target never overwritten.
TestCase {
    id: suite
    suiteName: "MigrationRules"

    readonly property var rules: MigrationRules
    readonly property var helpers: MigrationHelpers

    // A config.json as Config writes it: profiles, globals and presets as JSON text
    function _raw() {
        return {
            profiles: JSON.stringify([
                { name: "Full", enabled: true, when: {}, set: { "clock.format": "hh:mm", "battery.warn": 20, "bar.height": 30 } },
                { name: "Power save", enabled: true, when: { power: "battery" }, set: { "clock.format": "hh" } }
            ]),
            globals: JSON.stringify({ "clock.seconds": true, "theme.name": "dark" }),
            widgetPresets: JSON.stringify({ music: { "Default": { popupMode: "click" }, "compact": { popupMode: "hover" } },
                                            clock: { "Default": { format: "hh:mm:ss" } } }),
            migratedKeys: ["bar.height", "default:lockscreen.lockNotificationDetail"],
            writtenBy: "2.1.0",
            futureSection: { kept: true },
            gcal: { viewMode: "day" }
        };
    }

    function _document() {
        return rules.documentOf(_raw(), { "themes/dark.json": { bar: 1 } }).document;
    }

    // A test-only migration
    function _migration(id, since, scope, migrate, extra) {
        return Object.assign({ migrationId: id, since: since, summary: "test " + id, scope: scope, migrate: migrate }, extra ?? {});
    }

    // The failing-migration fixture: A succeeds, X throws (its scope the music presets), Y
    // overlaps X (one music preset), Z is independent (battery settings)
    readonly property var _failing: [
        _migration("2026-11-25-a-clock-format", "2.2.0", ["setting:clock.*"],
                   doc => MigrationHelpers.renameKey(doc, "clock.format", "clock.pattern")),
        _migration("2026-11-25-x-music-popup", "2.2.0", ["preset:music"], doc => { throw new Error("broken"); }),
        _migration("2026-11-25-y-music-compact", "2.2.0", ["preset:music/compact", "setting:compact.*"],
                   doc => { doc.presets.music = doc.presets.music ?? {}; doc.presets.music.compact = { bindings: ["y"] }; return doc; }),
        _migration("2026-11-25-z-battery-warn", "2.2.0", ["setting:battery.*"],
                   doc => MigrationHelpers.mapValue(doc, "battery.warn", value => Math.max(value, 25)))
    ]

    function run() {
        _records();
        _scopes();
        _documentParts();
        _projection();
        _runs();
        _failure();
        _wholeScope();
        _baseline();
        _newer();
        _newerNotice();
        _undeclaredKeys();
        _registry();
        _backups();
        _helpers();
    }

    function _records() {
        assertEqual(JSON.stringify(rules.parseRecord("2026-11-25-popup-mode")), JSON.stringify({ kind: "applied", id: "2026-11-25-popup-mode", version: "" }), "record: an id is applied");
        assertEqual(JSON.stringify(rules.parseRecord("reset:2026-11-25-popup-mode")), JSON.stringify({ kind: "reset", id: "2026-11-25-popup-mode", version: "" }), "record: reset:");
        assertEqual(JSON.stringify(rules.parseRecord("held:1.0.0-widget-presets@2.2.0")), JSON.stringify({ kind: "held", id: "1.0.0-widget-presets", version: "2.2.0" }), "record: held:<id>@<version>");
        assertEqual(rules.parseRecord("bar.height").kind, "other", "record: an older per-key marker is not a migration's");
        assertEqual(rules.parseRecord("default:lockscreen.x").kind, "other", "record: a default: marker is not a migration's");
        assertEqual(rules.parseRecord("held:2026-11-25-x").kind, "other", "record: held without a version is not a record");
        assertEqual(rules.parseRecord(7).kind, "other", "record: not a text");
        assertEqual(rules.parseRecord("reset:Not an id").kind, "other", "record: reset: before something that is no id is not a record");
        assert(rules.validId("2026-11-25-" + "a".repeat(85)) && !rules.validId("2026-11-25-" + "a".repeat(86)), "id: at most 96 characters");
        assert(rules.validId("2026-11-25-popup-mode") && rules.validId("1.0.0-legacy-settings"), "id: dated and versioned forms");
        assert(!rules.validId("2026-11-25") && !rules.validId("Popup-Mode") && !rules.validId("2026-11-25-a--b") && !rules.validId("theme.barLayout"), "id: other forms are not ids");

        const registry = _failing;
        const ids = list => list.map(migration => migration.migrationId).join(",");
        assertEqual(ids(rules.pending(registry, [])), registry.map(m => m.migrationId).join(","), "pending: none recorded, all, in registry order");
        assertEqual(ids(rules.pending(registry, ["2026-11-25-a-clock-format", "reset:2026-11-25-x-music-popup"])),
                    "2026-11-25-y-music-compact,2026-11-25-z-battery-warn", "pending: applied and reset ones never again");
        assertEqual(ids(rules.pending(registry, ["held:2026-11-25-a-clock-format@2.2.0"])).split(",").length, 4, "pending: a held one is still pending (the run holds it)");
        assert(rules.isHeld("2026-11-25-a-clock-format", ["held:2026-11-25-a-clock-format@2.2.0"], "2.2.0"), "held: under the version it names");
        assert(!rules.isHeld("2026-11-25-a-clock-format", ["held:2026-11-25-a-clock-format@2.2.0"], "2.3.0"), "held: not under another version");
        assert(!rules.isDone("2026-11-25-a-clock-format", null), "records that are no list: nothing done");
    }

    function _scopes() {
        assertEqual(JSON.stringify(rules.parsePath("setting:widgets.music.*")), JSON.stringify({ kind: "setting", prefix: "widgets.music.", key: "" }), "path: a setting prefix");
        assertEqual(JSON.stringify(rules.parsePath("setting:bar.height")), JSON.stringify({ kind: "setting", prefix: "", key: "bar.height" }), "path: one setting");
        assertEqual(JSON.stringify(rules.parsePath("preset:music/compact")), JSON.stringify({ kind: "preset", type: "music", name: "compact", key: "" }), "path: one preset");
        assertEqual(JSON.stringify(rules.parsePath("preset:music")), JSON.stringify({ kind: "preset", type: "music", name: "", key: "" }), "path: a preset type");
        assertEqual(JSON.stringify(rules.parsePath("preset:music/*/popupMode")), JSON.stringify({ kind: "preset", type: "music", name: "", key: "popupMode" }), "path: a key in every preset of a type");
        assertEqual(JSON.stringify(rules.parsePath("preset:music/compact/popupMode")), JSON.stringify({ kind: "preset", type: "music", name: "compact", key: "popupMode" }), "path: a key of one preset");
        assertEqual(JSON.stringify(rules.parsePath("raw:widgetProfiles")), JSON.stringify({ kind: "raw", key: "widgetProfiles" }), "path: a raw key");
        assertEqual(JSON.stringify(rules.parsePath("file:themes/*")), JSON.stringify({ kind: "file", pattern: "themes/*" }), "path: side files");
        for (const bad of ["raw:migratedKeys", "raw:writtenBy", "raw:profiles", "raw:globals", "raw:widgetPresets", "raw:__proto__", "setting:", "setting:a..b",
                           "setting:*", "preset:", "preset:/b", "preset:a/", "preset:__proto__/b", "preset:a/*", "preset:a/b/*", "preset:a/*/__proto__", "preset:a/b/c/d", "preset:a//k", "preset:/b/k", "file:", "file:a/", "rawx", ":raw", "raw", "Raw:x", "preset:__proto__", "file:../x", "file:/etc/passwd", "file:a//b", "other:x", "bar.height", 3])
            assertEqual(rules.parsePath(bad), null, "path: " + JSON.stringify(bad) + " is not one");
        assert(!rules.parseScope([]).ok && !rules.parseScope("setting:a").ok, "scope: empty or not a list: unreadable");
        assert(rules.parsePath("preset:" + "a".repeat(128)) !== null && rules.parsePath("preset:" + "a".repeat(129)) === null, "path: a name of at most 128 characters");
        assert(rules.parsePath("setting:" + "a".repeat(248)) !== null && rules.parsePath("setting:" + "a".repeat(249)) === null, "path: at most 256 characters");
        assertEqual(rules.parseScope(["setting:a", "bad path"]).problem, "not a scope path: bad path", "scope: the unreadable path named");
        assertEqual(rules.parseScope(["x".repeat(100)]).problem, "not a scope path: " + "x".repeat(80), "scope: … cut short");
        assert(!rules.parseScope(["*", "setting:a"]).ok, "scope: \"*\" stands alone");
        assert(rules.parseScope(["*"]).whole, "scope: \"*\" is the whole document");

        const overlap = (a, b) => rules.scopesOverlap(rules.parseScope(a), rules.parseScope(b));
        assert(overlap(["setting:a.b"], ["setting:a.b"]), "overlap: the same setting");
        assert(!overlap(["setting:a.b"], ["setting:a.c"]), "overlap: other settings do not");
        assert(overlap(["setting:a.*"], ["setting:a.b"]) && overlap(["setting:a.b"], ["setting:a.*"]), "overlap: a setting under a prefix, both ways");
        assert(overlap(["setting:a.*"], ["setting:a.b.*"]), "overlap: nested prefixes");
        assert(!overlap(["setting:a.*"], ["setting:ab.c"]) && !overlap(["setting:a.*"], ["setting:a"]), "overlap: a prefix covers only keys under it");
        assert(overlap(["preset:music/compact"], ["preset:music"]), "overlap: a preset under its type, the other way");
        assert(overlap(["preset:music/*/popupMode"], ["preset:music/compact"]) && overlap(["preset:music/compact/popupMode"], ["preset:music/*/popupMode"]),
               "overlap: a preset key with its preset, and with the same key in every preset");
        assert(!overlap(["preset:music/*/popupMode"], ["preset:music/*/bindings"]) && !overlap(["preset:music/a/popupMode"], ["preset:music/b/popupMode"])
               && !overlap(["preset:music/*/popupMode"], ["preset:clock/*/popupMode"]), "overlap: other keys, presets or types do not");
        assert(overlap(["preset:music"], ["preset:music/compact"]) && !overlap(["preset:music/a"], ["preset:music/b"]) && !overlap(["preset:music"], ["preset:clock"]),
               "overlap: presets by type and name");
        assert(overlap(["raw:a"], ["raw:a"]) && !overlap(["raw:a"], ["raw:b"]), "overlap: raw keys");
        assert(overlap(["file:themes/*"], ["file:themes/dark.json"]) && !overlap(["file:themes/*"], ["file:other/x"]) && overlap(["file:themes/*"], ["file:themes/d*"]),
               "overlap: file patterns");
        assert(!overlap(["file:themes/a.json"], ["file:themes/b.json"]) && overlap(["file:themes/a.json"], ["file:themes/a.json"]), "overlap: two files");
        assert(overlap(["file:themes/dark.json"], ["file:themes/*"]) && !overlap(["file:other/x"], ["file:themes/*"]), "overlap: a file and a pattern, the other way");
        assert(overlap(["file:*x"], ["file:a*"]), "overlap: a pattern starting with \"*\" overlaps any");
        assert(!overlap(["file:a/*"], ["file:b/*"]), "overlap: patterns in other folders");
        assert(overlap(["file:a/*"], ["file:a/*/b"]), "overlap: patterns by the text before their first \"*\"");
        assert(!overlap(["setting:a"], ["raw:a"]) && !overlap(["preset:a"], ["setting:a"]), "overlap: different kinds never");
        assert(overlap(["*"], ["raw:x"]) && overlap(["setting:q"], ["*"]), "overlap: \"*\" overlaps everything");
        assert(rules.scopesOverlap({ ok: false }, rules.parseScope(["raw:x"])), "overlap: an unreadable scope overlaps everything");
        assert(overlap(["setting:x", "preset:music"], ["raw:y", "preset:music/a"]), "overlap: any path of one with any of the other");
    }

    function _documentParts() {
        const parsed = rules.documentOf(_raw(), {});
        assert(parsed.ok, "document: read");
        assertEqual(parsed.document.profiles.length, 2, "document: the profiles parsed");
        assertEqual(parsed.document.presets.music.compact.popupMode, "hover", "document: the presets parsed");
        assertEqual(JSON.stringify(Object.keys(parsed.document.raw)), JSON.stringify(["futureSection", "gcal"]), "document: raw holds the other keys, not the runner's");
        assertEqual(parsed.records.length, 2, "document: the records apart");
        assertEqual(parsed.writtenBy, "2.1.0", "document: writtenBy apart");
        const original = _raw();
        const back = rules.rawOf(parsed.document, parsed.records, original);
        assertEqual(rules.canonical(back), rules.canonical(original), "document: an unchanged document is written back as it was");
        assertEqual(back.profiles, original.profiles, "document: an unchanged part keeps its text");
        const empty = rules.rawOf(rules.documentOf({}, {}).document, [], {});
        assertEqual(rules.canonical(empty), rules.canonical({ migratedKeys: [] }), "document: absent parts stay absent");
        for (const [key, value] of [["profiles", "{"], ["profiles", "{}"], ["globals", "[]"], ["widgetPresets", "{\"music\":3}"], ["migratedKeys", "x"],
                                    ["profiles", JSON.stringify([{ set: {} }])]]) {
            const raw = _raw();
            raw[key] = value;
            assert(!rules.documentOf(raw, {}).ok, "document: " + key + " " + value + " unreadable: no document");
        }
        assert(!rules.documentOf(null, {}).ok, "document: no object: no document");
        assert(rules.documentOf({ profiles: JSON.stringify([{ name: "A" }]) }, {}).ok, "document: a profile without settings is readable");
        assert(!rules.documentOf({ profiles: JSON.stringify([{ name: "A", set: 3 }]) }, {}).ok, "document: a profile with settings that are no object: unreadable");
        const spaced = { profiles: "[ ]", globals: "{ \"a\": 1 }", widgetPresets: "" };
        const spacedBack = rules.rawOf(rules.documentOf(spaced, {}).document, [], spaced);
        assertEqual(spacedBack.profiles + "|" + spacedBack.globals + "|" + spacedBack.widgetPresets, "[ ]|{ \"a\": 1 }|", "document: unchanged parts keep their exact text, an empty one too");
        const changedDocument = rules.documentOf(spaced, {}).document;
        changedDocument.globals.b = 2;
        changedDocument.presets.music = {};
        const changedBack = rules.rawOf(changedDocument, [], spaced);
        assertEqual(changedBack.globals + "|" + changedBack.widgetPresets + "|" + changedBack.profiles, "{\"a\":1,\"b\":2}|{\"music\":{}}|[ ]", "document: changed parts written anew");
        const absentBack = rules.rawOf(changedDocument, [], {});
        assertEqual(absentBack.globals + "|" + absentBack.profiles, "{\"a\":1,\"b\":2}|undefined", "document: an absent part with content written, an empty one left out");
    }

    function _projection() {
        const document = _document();
        const scope = rules.parseScope(["setting:clock.*", "preset:music/compact", "raw:futureSection", "file:themes/*"]);
        const handed = rules.projection(document, scope);
        assertEqual(rules.canonical(handed), rules.canonical({
            raw: { futureSection: { kept: true } },
            profiles: [{ name: "Full", set: { "clock.format": "hh:mm" } }, { name: "Power save", set: { "clock.format": "hh" } }],
            globals: { "clock.seconds": true },
            presets: { music: { compact: { popupMode: "hover" } } },
            files: { "themes/dark.json": { bar: 1 } }
        }), "projection: only the scope's paths, every profile by name");
        const exact = rules.projection(document, rules.parseScope(["setting:clock.seconds"]));
        assertEqual(rules.canonical(exact.globals) + rules.canonical(exact.profiles.map(profile => profile.set)), "{\"clock.seconds\":true}[{},{}]",
                    "projection: one setting, exactly");
        const sameName = rules.projection({ raw: { x: 1 }, profiles: [], globals: { x: 2 }, presets: {}, files: {} }, rules.parseScope(["raw:x"]));
        assertEqual(rules.canonical(sameName.globals) + rules.canonical(sameName.raw), "{}{\"x\":1}", "projection: a raw key is not the setting of the same name");
        handed.profiles[0].set["clock.format"] = "changed";
        assertEqual(document.profiles[0].set["clock.format"], "hh:mm", "projection: a copy");

        const apply = (scopeList, migrate) => rules.applyOne(_migration("2026-11-25-t", "2.2.0", scopeList, migrate), document, {});
        const outside = [
            [["setting:clock.*"], doc => { doc.globals["theme.name"] = "x"; return doc; }, "a global"],
            [["setting:clock.*"], doc => { doc.profiles[0].set["bar.height"] = 1; return doc; }, "a setting in a profile"],
            [["setting:clock.*"], doc => { doc.profiles.push({ name: "New", set: {} }); return doc; }, "a new profile"],
            [["setting:clock.*"], doc => { doc.profiles[1].name = "Renamed"; return doc; }, "a renamed profile"],
            [["setting:clock.*"], doc => { doc.profiles[0].enabled = false; return doc; }, "a profile's other field"],
            [["preset:music/compact"], doc => { doc.presets.music.Default = {}; return doc; }, "another preset of the type"],
            [["preset:music/compact"], doc => { doc.presets.clock = {}; return doc; }, "another preset type"],
            [["raw:futureSection"], doc => { doc.raw.gcal = {}; return doc; }, "another raw key"],
            [["file:themes/*"], doc => { doc.files["other.json"] = {}; return doc; }, "another file"],
            [["setting:clock.*"], doc => { doc.extra = 1; return doc; }, "a part no document has"]
        ];
        for (const [scopeList, migrate, what] of outside) {
            const outcome = apply(scopeList, migrate);
            assert(!outcome.ok, "outside the scope: " + what + " is a failure (" + outcome.error + ")");
            assert(outcome.document === document, "outside the scope: " + what + ": the result discarded");
        }
        for (const part of ["raw", "profiles", "globals", "presets", "files"])
            assert(!apply(["setting:clock.*"], doc => { delete doc[part]; return doc; }).ok, "not a document: " + part + " missing is a failure");
        for (const [profile, what] of [[3, "no object"], [{ set: {} }, "no name"], [{ name: "Full", set: 3 }, "settings no object"]])
            assert(!apply(["setting:clock.*"], doc => { doc.profiles[0] = profile; return doc; }).ok, "not a document: a profile with " + what + " is a failure");
        for (const reserved of ["profiles", "globals", "widgetPresets", "migratedKeys", "writtenBy"])
            assert(!apply(["*"], doc => { doc.raw[reserved] = "[]"; return doc; }).ok, "not a document: a \"*\" result with raw." + reserved + " (the runner's)");
        assert(!apply(["*"], doc => { doc.profiles[0] = { set: {} }; return doc; }).ok, "not a document: a \"*\" result with a profile without a name");
        assert(apply(["setting:clock.*"], doc => { delete doc.profiles[1].set; return doc; }).ok, "a profile returned without settings is a document");
        for (const [migrate, what] of [[doc => null, "null"], [doc => [], "a list"], [doc => ({ profiles: [] }), "parts missing"],
                                       [doc => { throw new Error("nope"); }, "a throw"], [doc => { doc.profiles = [{ set: {} }]; return doc; }, "a malformed profile"],
                                       [doc => { doc.presets.music = 1; return doc; }, "a malformed preset type"]])
            assert(!apply(["setting:clock.*"], migrate).ok, "not a document: " + what + " is a failure");
        assert(!rules.applyOne({ migrationId: "2026-11-25-t", scope: ["setting:x"] }, document, {}).ok, "no migrate function: a failure");
        assert(!apply(["nonsense"], doc => doc).ok, "an unreadable scope: a failure");

        const inside = apply(["setting:clock.*", "preset:music/compact", "raw:futureSection", "file:themes/*"], doc => {
            doc.profiles[1].set["clock.pattern"] = "hh";
            delete doc.profiles[1].set["clock.format"];
            delete doc.globals["clock.seconds"];
            doc.presets.music.compact = { popupMode: "click" };
            doc.raw.futureSection = 2;
            doc.files["themes/new.json"] = { made: true };
            return doc;
        });
        assert(inside.ok, "inside the scope: applied");
        const merged = inside.document;
        assertEqual(rules.canonical(merged.profiles[1]), rules.canonical({ name: "Power save", enabled: true, when: { power: "battery" }, set: { "clock.pattern": "hh" } }),
                    "merged: the profile's other fields and settings kept, its scope as returned");
        assertEqual(rules.canonical(merged.globals), rules.canonical({ "theme.name": "dark" }), "merged: a removed key removed, the rest kept");
        assertEqual(rules.canonical(merged.presets.music), rules.canonical({ Default: { popupMode: "click" }, compact: { popupMode: "click" } }), "merged: one preset replaced, its sibling kept");
        assertEqual(merged.raw.futureSection, 2, "merged: the raw key");
        assertEqual(JSON.stringify(merged.raw.gcal), JSON.stringify({ viewMode: "day" }), "merged: unknown keys outside the scope survive");
        assertEqual(Object.keys(merged.files).sort().join(","), "themes/dark.json,themes/new.json", "merged: the side files");
        assertEqual(document.globals["clock.seconds"], true, "merged: the input not modified");
        merged.presets.music.compact = "changed";
        merged.raw.futureSection = 3;
        delete merged.files["themes/new.json"];
        assert(merged.presets.music.compact === "changed" && merged.raw.futureSection === 3 && !("themes/new.json" in merged.files),
               "merged: the caller may change and remove what was merged in");

        const keyScope = rules.parseScope(["preset:music/*/popupMode"]);
        const keyed = rules.projection(document, keyScope);
        assertEqual(rules.canonical(keyed.presets), rules.canonical({ music: { Default: { popupMode: "click" }, compact: { popupMode: "hover" } } }),
                    "preset key: only that key of every preset of the type handed");
        const withBindings = JSON.parse(JSON.stringify(document));
        withBindings.presets.music.compact.bindings = ["x"];
        withBindings.presets.music.bare = {};
        assert("bare" in rules.projection(withBindings, keyScope).presets.music, "preset key: a preset without the key handed too (to set it)");
        const keyApply = migrate => rules.applyOne(_migration("2026-11-25-k", "2.2.0", ["preset:music/*/popupMode"], migrate), withBindings, {});
        const keyMoved = keyApply(doc => { for (const name of Object.keys(doc.presets.music)) doc.presets.music[name].popupMode = "press"; delete doc.presets.music.Default.popupMode; return doc; });
        assert(keyMoved.ok, "preset key: changing and removing the key is inside the scope");
        assertEqual(rules.canonical(keyMoved.document.presets.music), rules.canonical({ Default: {}, compact: { popupMode: "press", bindings: ["x"] }, bare: { popupMode: "press" } }),
                    "preset key: merged into each preset, its other keys kept");
        assert(!keyApply(doc => { doc.presets.music.compact.bindings = []; return doc; }).ok, "preset key: another key of the preset is outside");
        assert(!keyApply(doc => { doc.presets.music.made = { popupMode: "x" }; return doc; }).ok, "preset key: a new preset is outside");
        assert(!keyApply(doc => { doc.presets.music.compact = 3; return doc; }).ok, "preset key: a preset replaced by no object is outside");
        const keyReset = rules.withoutScope(withBindings, keyScope, true);
        assertEqual(rules.canonical(keyReset.presets), rules.canonical({ music: { Default: {}, compact: { bindings: ["x"] }, bare: {} }, clock: { Default: { format: "hh:mm:ss" } } }),
                    "preset key: the reset removes only that key");
        const keyFailed = rules.run([_migration("2026-11-25-k", "2.2.0", ["preset:music/*/popupMode"], doc => { throw new Error("x"); })], withBindings, { records: [], version: "2.2.0" });
        assertEqual(rules.canonical(keyFailed.document.presets.music.compact), rules.canonical({ bindings: ["x"] }), "preset key: a failure resets the key, not the presets");

        const mutating = rules.applyOne(_migration("2026-11-25-t", "2.2.0", ["setting:clock.*"], doc => { doc.globals["clock.seconds"] = false; return doc; }), document, {});
        assert(mutating.ok && document.globals["clock.seconds"] === true, "a migration changing what it is handed: the document stays");
        const context = rules.applyOne(_migration("2026-11-25-t", "2.2.0", ["raw:futureSection"], (doc, given) => { doc.raw.futureSection = given.version; return doc; }),
                                       document, { version: "2.2.0" });
        assertEqual(context.document.raw.futureSection, "2.2.0", "the context reaches the migration");
        const whole = rules.applyOne(_migration("2026-11-25-t", "2.2.0", ["*"], doc => { doc.raw.anything = 1; doc.globals = {}; return doc; }), document, {});
        assert(whole.ok && whole.document.raw.anything === 1 && Object.keys(whole.document.globals).length === 0, "\"*\": anything may change");
    }

    function _runs() {
        const document = _document();
        const options = { records: ["bar.height"], version: "2.2.0", context: {} };
        const first = rules.run(_failing.filter((m, i) => i !== 1), document, options);
        assertEqual(first.applied.join(","), "2026-11-25-a-clock-format,2026-11-25-y-music-compact,2026-11-25-z-battery-warn", "run: in registry order");
        assertEqual(first.records.join(","), "bar.height,2026-11-25-a-clock-format,2026-11-25-y-music-compact,2026-11-25-z-battery-warn", "run: each recorded, older markers kept");
        assert(first.write && first.changed && !first.readOnly, "run: changed, to be written");
        assertEqual(first.document.profiles[0].set["clock.pattern"], "hh:mm", "run: A's work in the document");
        assertEqual(first.document.profiles[0].set["battery.warn"], 25, "run: Z's work in the document");
        const again = rules.run(_failing, first.document, Object.assign({}, options, { records: first.records.concat(["reset:2026-11-25-x-music-popup"]) }));
        assert(!again.write && !again.changed && again.applied.length === 0, "run: nothing pending, nothing written");
        const twice = rules.run(_failing.filter((m, i) => i !== 1), first.document, options);
        assertEqual(rules.canonical(twice.document), rules.canonical(first.document), "run: the same migrations again give the same document (idempotent)");

        const held = rules.run(_failing.filter((m, i) => i !== 1), document,
                               Object.assign({}, options, { records: ["held:2026-11-25-a-clock-format@2.1.0", "bar.height"] }));
        assert(held.records.includes("bar.height"), "run: removing an old hold keeps the records beside it");
        const heldLast = rules.run(_failing.filter((m, i) => i !== 1), document,
                                   Object.assign({}, options, { records: ["bar.height", "held:2026-11-25-a-clock-format@2.1.0"] }));
        assert(!heldLast.records.some(entry => entry.startsWith("held:")), "run: an old hold removed wherever it stands");
        assert(held.applied.includes("2026-11-25-a-clock-format"), "run: a hold from another version no longer holds");
        assert(!held.records.some(entry => entry.startsWith("held:")), "run: an applied migration's old hold removed");

        const noFiles = rules.run([_migration("2026-11-25-f", "2.2.0", ["file:themes/*"], doc => { doc.files["themes/new.json"] = 1; delete doc.files["themes/dark.json"]; return doc; })],
                                  document, options);
        assertEqual(noFiles.filesWritten.join(",") + "|" + noFiles.filesRemoved.join(","), "themes/new.json|themes/dark.json", "run: the side files to write and remove");
        const withTwo = rules.documentOf(_raw(), { "themes/dark.json": { bar: 1 }, "themes/light.json": { bar: 2 } }).document;
        const rewritten = rules.run([_migration("2026-11-25-f", "2.2.0", ["file:themes/*"], doc => { doc.files["themes/dark.json"] = { bar: 3 }; return doc; })], withTwo, options);
        assertEqual(rewritten.filesWritten.join(",") + "|" + rewritten.filesRemoved.length, "themes/dark.json|0", "run: a changed file to write, an unchanged one not");
        const recordOnly = rules.run([_migration("2026-11-25-noop", "2.2.0", ["raw:nothing"], doc => doc)], document, options);
        assert(!recordOnly.changed && recordOnly.write, "run: nothing changed but a record: still written");
        const fileReset = rules.run([_migration("2026-11-25-g", "2.2.0", ["file:themes/*", "raw:futureSection"], doc => { throw new Error("x"); })], document, options);
        assertEqual(JSON.stringify(fileReset.document.files) + "|" + fileReset.filesRemoved.length + "|" + ("futureSection" in fileReset.document.raw),
                    JSON.stringify({ "themes/dark.json": { bar: 1 } }) + "|0|false", "failure: side files are not reset (not written), the rest of the scope is");
    }

    function _failure() {
        const document = _document();
        const version = "2.2.0";
        const outcome = rules.run(_failing, document, { records: [], version: version });
        assertEqual(outcome.applied.join(","), "2026-11-25-a-clock-format,2026-11-25-z-battery-warn", "failure: the one before applied, the independent one run");
        assertEqual(JSON.stringify(outcome.reset.map(each => each.id)), JSON.stringify(["2026-11-25-x-music-popup"]), "failure: X reset");
        assert(outcome.reset[0].error.includes("broken"), "failure: the error kept for the report");
        assertEqual(JSON.stringify(outcome.skipped), JSON.stringify([{ id: "2026-11-25-y-music-compact", after: "2026-11-25-x-music-popup" }]), "failure: the dependent skipped, named with what it waits on");
        assert(outcome.records.includes("reset:2026-11-25-x-music-popup"), "failure: reset:<id> recorded");
        assert(!outcome.records.some(entry => entry.includes("y-music-compact")), "failure: the skipped one not recorded");
        assert(outcome.records.includes("2026-11-25-a-clock-format") && outcome.records.includes("2026-11-25-z-battery-warn"), "failure: the others recorded");
        assert(!("music" in outcome.document.presets), "failure: X's scope removed: the music presets gone (defaults)");
        assertEqual(JSON.stringify(outcome.document.presets.clock), JSON.stringify({ Default: { format: "hh:mm:ss" } }), "failure: other presets intact");
        assertEqual(outcome.document.profiles[0].set["clock.pattern"], "hh:mm", "failure: the one before stays applied");
        assertEqual(outcome.document.profiles[0].set["battery.warn"], 25, "failure: the independent one's work kept");
        assert(outcome.write && !outcome.readOnly, "failure: the result is to be written");

        const next = rules.run(_failing, outcome.document, { records: outcome.records, version: version });
        assertEqual(next.applied.join(","), "2026-11-25-y-music-compact", "next start: the skipped one runs on the reset scope");
        assertEqual(JSON.stringify(next.document.presets.music), JSON.stringify({ compact: { bindings: ["y"] } }), "next start: its work on the defaults");
        assert(next.reset.length === 0, "next start: the reset one not run again");

        const holds = ["held:2026-11-25-x-music-popup@2.2.0", "held:2026-11-25-y-music-compact@2.2.0"];
        const held = rules.run(_failing, document, { records: holds, version: version });
        assertEqual(held.held.join(","), "2026-11-25-x-music-popup,2026-11-25-y-music-compact", "held: X and Y held under the same version");
        assertEqual(JSON.stringify(held.document.presets.music), JSON.stringify(document.presets.music), "held: their scope keeps its old values");
        assert(held.reset.length === 0 && held.applied.includes("2026-11-25-z-battery-warn"), "held: nothing reset, the others run");
        assertEqual(held.records.filter(entry => entry.startsWith("held:")).length, 2, "held: the holds kept");
        const heldOne = rules.run(_failing, document, { records: ["held:2026-11-25-x-music-popup@2.2.0"], version: version });
        assertEqual(JSON.stringify(heldOne.skipped.map(each => each.id)), JSON.stringify(["2026-11-25-y-music-compact"]), "held: a dependent of a held one waits too");
        const other = rules.run(_failing, document, { records: holds, version: "2.3.0" });
        assert(other.reset.length === 1 && other.reset[0].id === "2026-11-25-x-music-popup", "held: another version runs X again");

        // Transitive: W overlaps only Y (a setting of Y's scope), which waits on X
        const chain = _failing.concat([_migration("2026-11-25-w-compact-other", "2.2.0", ["setting:compact.mode"], doc => doc)]);
        const transitive = rules.run(chain, document, { records: [], version: version });
        assertEqual(transitive.skipped.map(each => each.id + "<" + each.after).join(","),
                    "2026-11-25-y-music-compact<2026-11-25-x-music-popup,2026-11-25-w-compact-other<2026-11-25-y-music-compact",
                    "failure: dependents skipped transitively");

        // An outside-scope write is a failure like a throw
        const writer = [_migration("2026-11-25-v-sneaky", "2.2.0", ["setting:clock.*"], doc => { doc.globals["theme.name"] = "evil"; return doc; })];
        const sneaky = rules.run(writer, document, { records: [], version: version });
        assertEqual(sneaky.reset.length, 1, "failure: a write outside the scope resets the scope");
        assertEqual(sneaky.document.globals["theme.name"], "dark", "failure: the write outside never lands");
        assert(!("clock.seconds" in sneaky.document.globals) && !("clock.format" in sneaky.document.profiles[0].set), "failure: its own scope reset");
    }

    function _wholeScope() {
        const document = _document();
        const registry = [
            _failing[0],
            _migration("2026-11-25-whole", "2.2.0", ["*"], doc => { throw new Error("whole broken"); }, { wholeScopeReason: "test" }),
            _failing[3]
        ];
        const outcome = rules.run(registry, document, { records: ["bar.height"], version: "2.2.0" });
        assert(outcome.readOnly && !outcome.write, "\"*\" failure: nothing to write, read-only");
        assertEqual(outcome.failure?.id, "2026-11-25-whole", "\"*\" failure: named");
        assertEqual(outcome.records.join(","), "bar.height", "\"*\" failure: no record added");
        assertEqual(outcome.applied.join(","), "2026-11-25-a-clock-format", "\"*\" failure: the run stops there");
        assertEqual(outcome.document.profiles[0].set["clock.pattern"], "hh:mm", "\"*\" failure: the ones before in memory");
        assertEqual(outcome.document.profiles[0].set["battery.warn"], 20, "\"*\" failure: the ones after not run");
        const unreadable = rules.run([_migration("2026-11-25-bad-scope", "2.2.0", ["nonsense"], doc => doc)], document, { records: [], version: "2.2.0" });
        assert(unreadable.readOnly && !unreadable.write, "an unreadable scope fails the strict way (it cannot be reset)");
        assert(outcome.changed && !unreadable.changed, "\"*\" failure: changed says whether the ones before changed the document");
        const afterHeld = rules.run([_failing[1], registry[1]], document, { records: ["held:2026-11-25-x-music-popup@2.2.0"], version: "2.2.0" });
        assert(!afterHeld.readOnly && afterHeld.skipped.length === 1, "a \"*\" migration after a held one waits (it overlaps everything)");
    }

    function _baseline() {
        const fresh = rules.run(_failing, _document(), { records: ["bar.height"], version: "2.2.0", fresh: true });
        assertEqual(fresh.records.join(","), ["bar.height"].concat(_failing.map(m => m.migrationId)).join(","), "new config: every id recorded");
        assert(fresh.applied.length === 0 && !fresh.changed && fresh.write, "new config: none run, only the records written");
        assertEqual(rules.baseline(_failing, ["reset:2026-11-25-x-music-popup"]).filter(entry => entry.includes("x-music-popup")).length, 1, "baseline: a done one not recorded twice");
        assert(rules.isNewConfig(null, _failing), "new config: no file");
        assert(rules.isNewConfig({ writtenBy: "2.1.0", migratedKeys: [], gcal: { viewMode: "day" }, profiles: "", globals: "{}", widgetPresets: "" }, _failing),
               "new config: a file with nothing set");
        assert(!rules.isNewConfig(_raw(), _failing), "not new: profiles");
        assert(!rules.isNewConfig({ profiles: JSON.stringify([{ name: "Full", set: {} }]) }, _failing), "not new: one profile");
        assert(rules.isNewConfig({}, [_migration("2026-11-25-bad", "2.2.0", ["nonsense"], doc => doc)]), "new: an unreadable scope reads no key");
        assert(!rules.isNewConfig({ globals: "{\"a\":1}" }, _failing), "not new: a pinned setting");
        assert(!rules.isNewConfig({ widgetPresets: "{\"music\":{}}" }, _failing), "not new: presets");
        const legacy = [_migration("1.0.0-legacy", "1.0.0", ["raw:bar"], doc => doc)];
        assert(!rules.isNewConfig({ bar: { height: 30 } }, legacy), "not new: a top-level key a migration reads");
        assert(rules.isNewConfig({ bar: { height: 30 } }, _failing), "new: a top-level key no migration reads");
        assert(rules.isNewConfig({ bar: { height: 30 } }, [_migration("2.0.0-bar", "2.0.0", ["setting:bar"], doc => doc)]), "new: a setting of the same name is not a top-level key");
        assert(!rules.isNewConfig({ profiles: "{" }, _failing), "not new: an unreadable config is never taken as new");
        const themes = [_migration("2.0.0-themes", "2.0.0", ["file:themes/*"], doc => doc)];
        assert(!rules.isNewConfig(null, themes, { "themes/old.json": { bar: 1 } }), "not new: no config, but a side file a migration reads");
        assert(!rules.isNewConfig({}, themes, { "themes/old.json": { bar: 1 } }), "not new: an empty config, but a side file a migration reads");
        assert(rules.isNewConfig(null, themes, { "other/x.json": 1 }) && rules.isNewConfig(null, themes, {}), "new: side files no migration reads, or none");
    }

    function _newer() {
        const registry = _failing;
        assert(!rules.newerConfig("2.1.0", ["bar.height", "2026-11-25-a-clock-format"], "2.2.0", registry).newer, "newer: an older writer, known ids: no");
        assert(!rules.newerConfig("2.2.0", [], "2.2.0", registry).newer, "newer: the same version: no");
        assert(rules.newerConfig("2.3.0", [], "2.2.0", registry).newer, "newer: a newer writtenBy");
        const unknown = rules.newerConfig("2.1.0", ["2026-12-01-future", "reset:2026-12-02-other", "held:2026-12-03-third@2.3.0", "mod.weather/2026-12-01-x", "default:a"], "2.2.0", registry);
        assert(unknown.newer, "newer: records naming migrations not registered");
        assertEqual(unknown.unknown.join(","), "2026-12-01-future,2026-12-02-other,2026-12-03-third", "newer: the unknown ids, a module's and markers left out");
        const one = rules.newerConfig("2.1.0", ["2026-12-01-future"], "2.2.0", registry);
        assert(one.newer && one.writtenBy === "2.1.0", "newer: one unknown id is enough; writtenBy given back");
        assertEqual(rules.newerConfig(null, [], "2.2.0", registry).writtenBy, "", "newer: no writtenBy: empty");
        assert(!rules.newerConfig("", [], "2.2.0", registry).newer && !rules.newerConfig("garbage", [], "2.2.0", registry).newer, "newer: no or unreadable writtenBy is not newer");
    }

    function _newerNotice() {
        const none = rules.newerNotice(rules.newerConfig("2.1.0", ["bar.height"], "2.1.0", _failing), "2.1.0");
        assert(!none.shown && none.title === "" && none.log === "", "newer notice: a config of this version: nothing said");
        assert(!rules.newerNotice(null, "2.1.0").shown && !rules.newerNotice(undefined, "2.1.0").shown, "newer notice: nothing known: nothing said");
        const byVersion = rules.newerNotice(rules.newerConfig("2.3.0", [], "2.1.0", _failing), "2.1.0");
        assert(byVersion.shown, "newer notice: a newer writtenBy: shown");
        assertEqual(byVersion.title, "Settings written by h2s-shell 2.3.0", "… its title names the version that wrote it");
        assertEqual(byVersion.body, "This is h2s-shell 2.1.0. What this version does not know is kept, unused.", "… its body: kept, nothing refused");
        assertEqual(byVersion.log, "settings written by h2s-shell 2.3.0 (this is 2.1.0): what this version does not know is kept, unused", "… one log line");
        const byRecords = rules.newerNotice(rules.newerConfig("2.1.0", ["2026-12-01-future"], "2.1.0", _failing), "2.1.0");
        assertEqual(byRecords.title, "Settings written by a newer h2s-shell", "newer notice: unknown records under the same writtenBy: no version named");
        assert(byRecords.log.endsWith("; settings updates it does not know: 2026-12-01-future"), "… the log names the unknown ids");
        assert(byRecords.key !== byVersion.key, "… another reason, another key");
    }

    function _undeclaredKeys() {
        const written = JSON.stringify({ gcal: { viewMode: "week" }, profiles: "[]", writtenBy: "2.1.0" }, null, 4) + "\n";
        const loaded = JSON.stringify({ writtenBy: "2.3.0", profiles: "[1]", acknowledgedModules: "{\"weather\":{}}", futureSection: { list: [1, 2], nested: { a: null } } });
        const kept = rules.keepUndeclaredKeys(written, loaded);
        const parsed = JSON.parse(kept);
        assertEqual(JSON.stringify(parsed.futureSection), JSON.stringify({ list: [1, 2], nested: { a: null } }), "undeclared: a key the adapter lacks put back as loaded");
        assertEqual(parsed.acknowledgedModules, "{\"weather\":{}}", "… every such key");
        assert(parsed.profiles === "[]" && parsed.writtenBy === "2.1.0" && parsed.gcal.viewMode === "week", "… the declared keys as the adapter wrote them, never the loaded values");
        assertEqual(Object.keys(parsed).join(","), "acknowledgedModules,futureSection,gcal,profiles,writtenBy", "… keys sorted, as JsonAdapter writes them");
        assert(kept.endsWith("}\n") && kept.includes("\n    \"gcal\": {\n        \"viewMode\""), "… indented by four, a closing newline");
        assertEqual(rules.keepUndeclaredKeys(written, JSON.stringify({ profiles: "[9]", writtenBy: "2.0.0" })), "", "undeclared: none in the file: nothing to put back");
        assertEqual(rules.keepUndeclaredKeys(written, ""), "", "undeclared: no file loaded: nothing");
        assertEqual(rules.keepUndeclaredKeys(written, "{"), "", "undeclared: an unreadable file: nothing");
        assertEqual(rules.keepUndeclaredKeys(written, "[1]"), "", "undeclared: not an object: nothing");
        assertEqual(rules.keepUndeclaredKeys("{", loaded), "", "undeclared: unreadable written text: nothing");
        const proto = JSON.parse(rules.keepUndeclaredKeys(written, "{\"__proto__\": {\"polluted\": 1}}"));
        assert(Object.prototype.hasOwnProperty.call(proto, "__proto__") && ({}).polluted === undefined, "undeclared: a key named __proto__ stays a key");
    }

    function _registry() {
        assertEqual(rules.registryProblems(_failing).length, 0, "registry: the fixture is valid");
        const problems = list => rules.registryProblems(list).join("\n");
        const base = _failing[0];
        assert(problems([base, base]).includes("registered twice"), "registry: an id twice");
        assert(problems([Object.assign({}, base, { migrationId: undefined })]).startsWith("(no id): "), "registry: a missing id named so");
        assert(problems([Object.assign({}, base, { migrationId: "bad" })]).includes("not a migration id"), "registry: a bad id");
        assert(problems([Object.assign({}, base, { since: "2.2.1" })]).includes("x.y.0"), "registry: since a patch release refused");
        assert(problems([Object.assign({}, base, { since: "2.2" })]).includes("x.y.0"), "registry: since not a release");
        assert(problems([Object.assign({}, base, { since: "2.3.0-rc1" })]).includes("x.y.0"), "registry: since a pre-release refused");
        const older = problems([base, Object.assign({}, _failing[3], { since: "2.1.0" })]);
        assert(older.includes("older than the migration before it"), "registry: since older than the one before");
        assert(rules.registryProblems([Object.assign({}, base, { since: "2.1.0" }), Object.assign({}, _failing[3], { since: "3.0.0" })]).length === 0,
               "registry: a later major after a minor is fine");
        assert(rules.registryProblems([Object.assign({}, base, { since: "2.10.0" }), Object.assign({}, _failing[3], { since: "2.9.0" })]).length === 1,
               "registry: since compared as versions, not texts");
        assert(problems([Object.assign({}, base, { summary: " " })]).includes("no summary"), "registry: a summary needed");
        assert(problems([Object.assign({}, base, { scope: ["x"] })]).includes("not a scope path"), "registry: an unreadable scope");
        assert(problems([Object.assign({}, base, { scope: ["*"] })]).includes("wholeScopeReason"), "registry: \"*\" needs its reason");
        assertEqual(rules.registryProblems([Object.assign({}, base, { scope: ["*"], wholeScopeReason: "it moves everything" })]).length, 0, "registry: \"*\" with a reason");
        assert(problems([Object.assign({}, base, { migrate: null })]).includes("no migrate"), "registry: a migrate function needed");
    }

    function _backups() {
        const stamp = day => "config.json.bak-2026-10-" + String(day).padStart(2, "0") + "T10-00-00-000Z";
        const names = [];
        for (let day = 1; day <= 12; day++)
            names.push(stamp(day));
        const newest = "config.json.bak-2026-10-13T10-00-00-000Z-migration";
        names.push(newest, "config.json", "config.json.bak-notes", "other.bak-2026-10-01T10-00-00-000Z", "config.json.bak-2026-10-14T10-00-00-000Z.tmp",
                   "config.json.bak-2026-10-15T10-00-00-000Z-made-2", "config.json.bak-2026-10-15T10-00-00-000Z-other");
        const plan = rules.backupsToKeep(names, { written: newest, protect: [stamp(1)] });
        assertEqual(plan.keep.length, 11, "backups: the newest ten and the protected one kept");
        assertEqual(plan.keep[0], newest, "backups: newest first, a reason in the name counted");
        assertEqual(plan.delete.join(","), stamp(3) + "," + stamp(2), "backups: the older ones deleted");
        assert(plan.keep.includes(stamp(1)), "backups: the protected one kept");
        assert(![...plan.keep, ...plan.delete].some(name => name === "config.json" || name.includes("notes") || name.startsWith("other") || name.endsWith(".tmp")
                                                          || name.endsWith("-made-2") || name.endsWith("-other")),
               "backups: only names of the exact pattern with a known reason, nothing else in the folder");
        assertEqual(rules.backupsToKeep(names.slice(0, 10), {}).delete.length, 0, "backups: ten or fewer: none deleted");
        assertEqual(rules.backupsToKeep(null, null).keep.length, 0, "backups: no list: nothing");
        assertEqual(rules.backupsToKeep(names, null).delete.length, 3, "backups: no protected one");

        // The clock behind: the backup just written has the oldest stamp
        const behind = "config.json.bak-2026-09-01T10-00-00-000Z-migration";
        const skewed = rules.backupsToKeep(names.concat([behind]), { written: behind });
        assert(skewed.keep.includes(behind), "backups: the one just written kept, whatever its stamp");
        assertEqual(skewed.keep.length, 10, "backups: … and counted among the ten");
        assertEqual(skewed.delete.join(","), [stamp(4), stamp(3), stamp(2), stamp(1)].join(","), "backups: … so one more of the others goes");
        const manual = "config.json.bak-2026-10-01T09-00-00-000Z-manual";
        const kept = rules.backupsToKeep(names.concat([manual]), { neverPrune: [manual] });
        assert(kept.keep.includes(manual) && kept.keep.length === 11 && kept.delete.length === 3, "backups: one never to be pruned kept, not counted");
        const tie = rules.backupsToKeep(["config.json.bak-2026-10-01T10-00-00-000Z-manual", "config.json.bak-2026-10-01T10-00-00-000Z-restore",
                                         "config.json.bak-2026-10-01T10-00-00-000Z"], {});
        assertEqual(tie.keep.join(","), "config.json.bak-2026-10-01T10-00-00-000Z-restore,config.json.bak-2026-10-01T10-00-00-000Z-manual,config.json.bak-2026-10-01T10-00-00-000Z",
                    "backups: equal stamps ordered by name, the same each time");
    }


    function _helpers() {
        const document = {
            raw: {}, files: {},
            profiles: [{ name: "Full", set: { "old.key": 1, "new.key": 9 } }, { name: "Quiet", set: { "old.key": 2 } }, { name: "Bare" }],
            globals: { "old.key": 3 },
            presets: { music: { Default: { popupMode: "click" }, compact: { popupMode: "hover", bindings: "kept" } }, clock: { Default: { popupMode: "x" } } }
        };
        const renamed = helpers.renameKey(document, "old.key", "new.key");
        assertEqual(rules.canonical(renamed.profiles.map(profile => profile.set ?? null)), rules.canonical([{ "new.key": 9 }, { "new.key": 2 }, null]),
                    "rename: every profile; an existing target kept, the old key removed");
        assertEqual(rules.canonical(renamed.globals), rules.canonical({ "new.key": 3 }), "rename: the globals");
        assertEqual(document.profiles[1].set["old.key"], 2, "rename: input not modified");
        renamed.globals["new.key"] = 5;
        assertEqual(renamed.globals["new.key"], 5, "rename: a migration can change a renamed key afterwards");
        delete renamed.globals["new.key"];
        assert(!("new.key" in renamed.globals), "rename: … and remove it");
        assertEqual(rules.canonical(helpers.renameKey(document, "old.key", "old.key", { presets: ["music"] })), rules.canonical(document), "rename: a key to itself changes nothing");
        assertEqual(rules.canonical(helpers.renameKey(document, "old.key", "new.key", { settings: true })), rules.canonical(helpers.renameKey(document, "old.key", "new.key")),
                    "rename: settings: true is the default");
        assertEqual(rules.canonical(renamed.presets), rules.canonical(document.presets), "rename: presets untouched unless asked");
        const inPresets = helpers.renameKey(document, "popupMode", "bindings", { settings: false, presets: ["music"] });
        assertEqual(rules.canonical(inPresets.presets.music), rules.canonical({ Default: { bindings: "click" }, compact: { bindings: "kept" } }),
                    "rename in presets: the asked type, an existing target kept");
        assertEqual(inPresets.presets.clock.Default.popupMode, "x", "rename in presets: other types untouched");
        assertEqual(inPresets.profiles[0].set["old.key"], 1, "rename in presets: settings untouched when not asked");
        const mapped = helpers.mapValue(document, "old.key", (value, place) => value === 2 ? undefined : place + "=" + value);
        assertEqual(mapped.profiles[0].set["old.key"] + "|" + ("old.key" in mapped.profiles[1].set) + "|" + mapped.globals["old.key"], "profile:Full=1|false|globals=3",
                    "map: each value with its place; undefined removes");
        const removed = helpers.removeKey(document, "old.key", { presets: ["music"] });
        assert(!removed.profiles.some(profile => profile.set && "old.key" in profile.set) && !("old.key" in removed.globals), "remove: everywhere");
        const places = [];
        helpers.forEachSetting(document, (values, place) => places.push(place), { presets: ["music", "absent"] });
        assertEqual(places.join(","), "profile:Full,profile:Quiet,globals,preset:music/Default,preset:music/compact", "forEachSetting: every place");
        const viaRule = rules.applyOne(_migration("2026-11-25-h", "2.2.0", ["setting:old.*", "setting:new.*"], doc => helpers.renameKey(doc, "old.key", "new.key")),
                                       rules.documentOf(_raw(), {}).document, {});
        assert(viaRule.ok, "a helper's result stays inside a migration's scope");
    }
}
