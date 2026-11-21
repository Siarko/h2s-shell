import QtQuick
import qs.singletons

// ModuleBackupRules (pure): a module's settings taken out of the profiles and globals and
// put back (a similar prefix untouched, a backup never bringing another setting in), what
// the copying said, meta.json written and read, a module's list of backups (staging
// leftovers, links and unreadable ones unknown, never listed), and a restore's plan keyed to
// the backup named. Malformed input never reads as fine. The manifest's `backup` field too.
TestCase {
    id: suite
    suiteName: "ModuleBackupRules"

    readonly property var rules: ModuleBackupRules

    readonly property var _profiles: [
        { name: "Full", enabled: true, when: {}, set: { "mod.weather.city": "Oslo", "mod.weather.units": "metric", "mod.weatherx.city": "Rome", "bar.height": 30 } },
        { name: "Power save", enabled: true, when: {}, set: { "mod.weather.city": "Bergen" } },
        { name: "Quiet", enabled: true, when: {}, set: { "mod.weatherx.city": "Paris" } }
    ]
    readonly property var _globals: ({ "mod.weather.refresh": 600, "mod.weatherx.refresh": 60, "theme.name": "dark" })

    function run() {
        _settings();
        _copying();
        _meta();
        _listing();
        _restore();
        _manifest();
    }

    function _settings() {
        const snapshot = rules.settingsSnapshot(_profiles, _globals, "mod.weather.");
        assert(snapshot.ok, "snapshot: read");
        assertEqual(JSON.stringify(snapshot.profiles), JSON.stringify([
            { name: "Full", set: { "mod.weather.city": "Oslo", "mod.weather.units": "metric" } },
            { name: "Power save", set: { "mod.weather.city": "Bergen" } }
        ]), "snapshot: the module's values in each profile, a similar prefix (mod.weatherx.) and core settings left out");
        assertEqual(JSON.stringify(snapshot.globals), JSON.stringify({ "mod.weather.refresh": 600 }), "snapshot: … and its pinned globals");
        assertEqual(snapshot.count, 4, "snapshot: counted");
        assert(!rules.settingsSnapshot(null, _globals, "mod.weather.").ok, "snapshot: profiles that could not be read: no snapshot");
        assert(!rules.settingsSnapshot(_profiles, [], "mod.weather.").ok, "snapshot: globals that are not an object: no snapshot");
        assert(!rules.settingsSnapshot(_profiles, _globals, "bar.").ok, "snapshot: only a module's prefix");

        const text = rules.settingsText(snapshot);
        const parsed = rules.parseSettings(text, "mod.weather.");
        assert(parsed.ok, "settings.json: read back");
        assertEqual(JSON.stringify(parsed.profiles), JSON.stringify(snapshot.profiles), "settings.json: round trip");
        const sneaky = rules.parseSettings(JSON.stringify({ profiles: [{ name: "Full", set: { "mod.weather.city": "X", "lock.enabled": false } }],
                                                            globals: { "theme.name": "evil" } }), "mod.weather.");
        assertEqual(JSON.stringify(sneaky.profiles[0].set) + JSON.stringify(sneaky.globals), "{\"mod.weather.city\":\"X\"}{}",
                    "settings.json: keys outside the module's prefix never come in");
        assert(!rules.parseSettings("{", "mod.weather.").ok, "settings.json: not JSON: unreadable");
        assert(!rules.parseSettings(JSON.stringify({ profiles: {}, globals: {} }), "mod.weather.").ok, "settings.json: no profile list: unreadable");
        assert(!rules.parseSettings(JSON.stringify({ profiles: [{ name: 3, set: {} }], globals: {} }), "mod.weather.").ok, "settings.json: a malformed profile: unreadable");
        assert(!rules.parseSettings(JSON.stringify({ profiles: [{ name: "A", set: {} }, { name: "A", set: {} }], globals: {} }), "mod.weather.").ok,
               "settings.json: a profile named twice: unreadable");
        assertEqual(rules.chunks("x".repeat(rules.chunkLength + 1)).length, 2, "settings.json: sent in chunks");
        assertEqual(rules.chunks("x".repeat(rules.maxSettingsBytes + 1)), null, "settings.json: too large, not sent");

        // Changed since: a new value, a value dropped, a profile gone
        const now = JSON.parse(JSON.stringify(_profiles));
        now[0].set["mod.weather.city"] = "Tromsø";
        now[0].set["mod.weather.new"] = true;
        const saved = { profiles: snapshot.profiles.concat([{ name: "Gone", set: { "mod.weather.city": "Nowhere" } }]), globals: snapshot.globals };
        const restored = rules.settingsRestored(now, { "mod.weather.refresh": 30, "mod.weatherx.refresh": 60 }, "mod.weather.", saved);
        assert(restored.ok, "restored: done");
        assertEqual(JSON.stringify(restored.profiles[0].set), JSON.stringify({ "mod.weatherx.city": "Rome", "bar.height": 30, "mod.weather.city": "Oslo", "mod.weather.units": "metric" }),
                    "restored: the module's values as saved, its newer ones dropped, others untouched");
        assertEqual(JSON.stringify(restored.profiles[2].set), JSON.stringify({ "mod.weatherx.city": "Paris" }), "restored: a similar prefix untouched");
        assertEqual(Object.keys(restored.globals).sort().map(key => key + "=" + restored.globals[key]).join(","), "mod.weather.refresh=600,mod.weatherx.refresh=60",
                    "restored: the pinned globals");
        assertEqual(restored.missing.join(","), "Gone", "restored: a profile that no longer exists gets nothing, and is named");
        assertEqual(restored.restored, 4, "restored: counted");
        assertEqual(now[0].set["mod.weather.city"], "Tromsø", "restored: inputs not modified");
        assert(!rules.settingsRestored(now, {}, "mod.weather.", null).ok, "restored: nothing saved: nothing written");
        assert(!rules.settingsRestored("broken", {}, "mod.weather.", saved).ok, "restored: profiles that could not be read: nothing written");
    }

    function _copying() {
        const lines = ["store\tok", "data\tok\tnotes.db", "data\trefused\tescape\tleads outside its data directory", "data\tabsent\tsub/x", "done"];
        const outcome = rules.copyOutcome(lines, ["notes.db", "escape", "sub/x"]);
        assert(outcome.complete, "copying: every item answered, then done");
        assertEqual(JSON.stringify(outcome.data), JSON.stringify([{ path: "notes.db", present: true }, { path: "sub/x", present: false }]), "copying: what was there");
        assertEqual(JSON.stringify(outcome.refused), JSON.stringify([{ path: "escape", why: "leads outside its data directory" }]), "copying: what was left out, and why");
        assert(!rules.copyOutcome(lines.slice(0, 4), ["notes.db", "escape", "sub/x"]).complete, "copying: no \"done\": not complete");
        assert(!rules.copyOutcome(["store\tok", "done"], ["notes.db"]).complete, "copying: an item not answered: not complete");
        assert(!rules.copyOutcome(["data\tok\tnotes.db", "done"], ["notes.db"]).complete, "copying: the store not answered: not complete");
        assertEqual(rules.copyOutcome(["store\tok", "data\tok\t/etc/passwd", "done"], []).data.length, 0, "copying: a path not asked for is ignored");
    }

    function _meta() {
        const plan = ModuleUpdateRules.backupPlan("weather", { backup: ["notes.db", "escape", "sub/x"] },
                                                  { dataHome: "/home/u/.local/share", configHome: "/home/u/.config", version: "1.2.0", commit: "abcdef1", reason: "update", nowMs: 1000 });
        const outcome = rules.copyOutcome(["store\tabsent", "data\tok\tnotes.db", "data\trefused\tescape\tleads outside its data directory", "data\tabsent\tsub/x", "done"],
                                          ["notes.db", "escape", "sub/x"]);
        const meta = rules.takenMeta(plan, outcome);
        assertEqual(JSON.stringify(meta), JSON.stringify({ id: "weather", version: "1.2.0", commit: "abcdef1", takenAt: 1000, reason: "update", includesData: true,
                                                          store: false, data: [{ path: "notes.db", present: true }, { path: "sub/x", present: false }],
                                                          refused: [{ path: "escape", why: "leads outside its data directory" }] }),
                    "meta: the plan's, with what was copied");
        assertEqual(rules.takenMeta(plan, Object.assign({}, outcome, { complete: false })), null, "meta: copying that did not finish: no backup");

        const read = rules.parseMeta(JSON.stringify(meta), "weather", "1.2.0-19700101-000001");
        assert(read.ok, "meta read: ok");
        assertEqual(read.entry.name + " " + read.entry.version + " " + read.entry.reason + " " + read.entry.store + " " + read.entry.data.length,
                    "1.2.0-19700101-000001 1.2.0 update false 2", "meta read: its fields");
        assert(!rules.parseMeta(JSON.stringify(meta), "clock", "1.2.0-x").ok, "meta read: another module's: refused");
        assert(!rules.parseMeta(JSON.stringify(meta), "weather", ".incoming-1.2.0").ok, "meta read: a staging name: never a backup");
        assert(!rules.parseMeta("{", "weather", "a").ok, "meta read: not JSON");
        assert(!rules.parseMeta("", "weather", "a").ok, "meta read: missing");
        assert(!rules.parseMeta(JSON.stringify(Object.assign({}, meta, { reason: "whim" })), "weather", "a").ok, "meta read: no known reason");
        assert(!rules.parseMeta(JSON.stringify(Object.assign({}, meta, { data: [{ path: "../etc", present: true }] })), "weather", "a").ok,
               "meta read: a path outside the data directory: refused");
        assert(!rules.parseMeta(JSON.stringify(Object.assign({}, meta, { store: undefined })), "weather", "a").ok, "meta read: does not say what it holds");
        assert(rules.validName("1.2.0-20261121-140200-2") && !rules.validName("../x") && !rules.validName(".incoming-1") && !rules.validName(""),
               "names: plain, never a staging leftover");
    }

    function _metaText(takenAt) {
        return JSON.stringify({ id: "weather", version: "1.0.0", commit: "", takenAt: takenAt, reason: "switch", includesData: false, store: true, data: [], refused: [] });
    }

    function _listing() {
        const rows = rules.listingRows([
            "B\tweather\t1.0.0-20261101-100000\td\t" + _metaText(1000),
            "B\tweather\t1.0.0-20261102-100000\td\t" + _metaText(2000),
            "B\tweather\t.incoming-1.0.0-20261103-100000\td\t",
            "B\tweather\t1.0.0-20261104-100000\tl\t" + _metaText(4000),
            "B\tweather\t1.0.0-20261105-100000\td\t{broken",
            "X\tweather",
            "B\t../evil\tx\td\t",
            "done"
        ]);
        assertEqual(Object.keys(rows).join(","), "weather", "listing rows: by module id, others dropped");
        const listed = rules.listing("weather", rows.weather, true);
        assertEqual(listed.backups.map(each => each.name).join(","), "1.0.0-20261102-100000,1.0.0-20261101-100000", "listing: readable ones, newest first");
        assertEqual(listed.unknown.join(","), ".incoming-1.0.0-20261103-100000,1.0.0-20261104-100000,1.0.0-20261105-100000,?",
                    "listing: a staging leftover, a link, an unreadable meta.json and a name that is not plain: unknown");
        assert(!rules.listing("weather", rows.weather, false).ok, "listing: one that did not finish is not ok");

        const six = [1, 2, 3, 4, 5, 6].map(day => ({ dir: "1.0.0-2026110" + day + "-100000", takenAt: day }));
        assertEqual(rules.keepPlan(six, []).delete.join(","), "1.0.0-20261101-100000", "keep: the newest five, the oldest goes");
        const guarded = rules.keepPlan(six, ["1.0.0-20261101-100000"]);
        assertEqual(guarded.delete.length + " " + guarded.keep.length, "0 6", "keep: the backup a restore is about to read stays, whatever its age");
    }

    function _restore() {
        const listed = rules.listing("weather", rules.listingRows([
            "B\tweather\t1.0.0-20261101-100000\td\t" + JSON.stringify({ id: "weather", version: "1.0.0", commit: "", takenAt: 1000, reason: "update", store: false,
                                                                         data: [{ path: "notes.db", present: true }, { path: "cache/x", present: false }] }),
            "B\tweather\t1.0.0-20261105-100000\td\t{broken"
        ]).weather, true);
        const status = { id: "weather", state: "loaded" };
        const plan = rules.restorePlan("weather", "1.0.0-20261101-100000", listed, status, true);
        assert(plan.ok, "restore: planned");
        assertEqual(plan.store + " " + JSON.stringify(plan.data) + " " + plan.enableAfter,
                    "drop [{\"op\":\"put\",\"path\":\"notes.db\"},{\"op\":\"drop\",\"path\":\"cache/x\"}] true",
                    "restore: what the backup held put back, what it named and did not hold removed, on again as it was");
        assertEqual(rules.restorePlan("weather", "1.0.0-20261101-100000", listed, status, false).enableAfter, false, "restore: a module that was off stays off");
        assert(rules.restorePlan("weather", "1.0.0-20261105-100000", listed, status, true).problem.includes("cannot be read"), "restore: an unreadable backup: refused");
        assert(rules.restorePlan("weather", "1.0.0-20991231-000000", listed, status, true).problem.startsWith("No backup"), "restore: a name it has none of: refused");
        assert(!rules.restorePlan("weather", "../x", listed, status, true).ok, "restore: not a backup's name");
        assert(!rules.restorePlan("weather", "1.0.0-20261101-100000", listed, null, true).ok, "restore: no such module");
        assert(!rules.restorePlan("weather", "1.0.0-20261101-100000", Object.assign({}, listed, { ok: false }), status, true).ok,
               "restore: a listing that did not finish: refused");

        assertEqual(JSON.stringify(rules.writeOutcome(["ok\tstore", "ok\tnotes.db", "done"], 2)), JSON.stringify({ complete: true, problems: [] }), "write back: all done");
        assertEqual(rules.writeOutcome(["ok\tstore", "fail\tnotes.db\tnot copied", "done"], 2).problems.join(";"), "notes.db: not copied", "write back: a failure said");
        assert(!rules.writeOutcome(["ok\tstore"], 2).complete, "write back: cut off: not complete");
    }

    function _manifest() {
        const parsed = ModuleManifestRules.parseManifest(JSON.stringify({ id: "weather", name: "Weather", version: "1.0.0", api: "1.37",
                                                                          backup: ["notes.db", "./sub//keep", "../x", "/etc", 3, "notes.db"] }));
        assert(parsed.valid, "manifest: valid with a backup list");
        assertEqual(parsed.backup.join(","), "notes.db,sub/keep", "manifest: backup paths cleaned, the ones outside dropped");
        assertEqual(parsed.warnings.filter(each => each.startsWith("backup[")).length, 3, "manifest: each dropped one warned about");
        const old = ModuleManifestRules.parseManifest(JSON.stringify({ id: "weather", name: "Weather", version: "1.0.0", api: "1.36", backup: ["a"] }));
        assert(old.warnings.some(each => each.startsWith("backup: a field of API 1.37")), "manifest: a field of 1.37, said in an older manifest");
        assertEqual(ModuleManifestRules.parseManifest(JSON.stringify({ id: "weather", name: "Weather", version: "1.0.0", api: "1.37", backup: "a" })).backup.length, 0,
                    "manifest: not a list: nothing named");
    }
}
