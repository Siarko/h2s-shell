import QtQuick
import qs.singletons

// ConfigBackupRules (pure): a backup's name and its parts (the reason, a module switch's
// module and versions; nothing but the exact pattern is a backup), the rows (newest first,
// automatic, manual and kept, an older one with no reason, a missing version, a newer writer
// by version and by records, an unreadable file shown as such), Apply's preview of an older,
// a current and a newer backup (pending, held, failing with the skipped held, a whole-config
// failure), the opened row's line, Apply's question as steps and its subject, the IPC text;
// the pruning of module-switch backups as automatic (MigrationRules.backupsToKeep); Make a
// backup now's refusals and its line, manual backups kept by pruning past ten automatic ones;
// Delete's refusals (only a backup's bare name, not under the test runner, not one at a time,
// not the backup being applied or the one Restore previous settings needs) and its question;
// which side files a restore puts back or removes (only a backup in the config's folder has
// them; a name that is no path inside the folder refuses, the limit).
TestCase {
    id: suite
    suiteName: "ConfigBackupRules"

    readonly property var rules: ConfigBackupRules

    function _migration(id, scope, migrate, extra) {
        return Object.assign({ migrationId: id, since: "2.2.0", summary: "test " + id, scope: scope, migrate: migrate }, extra ?? {});
    }

    readonly property var _rename: _migration("2026-11-25-testonly-rename", ["setting:testonly.*"],
                                              doc => MigrationHelpers.renameKey(doc, "testonly.old", "testonly.new"))
    readonly property var _broken: _migration("2026-11-25-x-music-popup", ["preset:music"], doc => { throw new Error("broken"); },
                                              { scopeLabel: "music widget presets" })
    readonly property var _dependent: _migration("2026-11-25-y-music-more", ["preset:music"], doc => doc, { scopeLabel: "music extras" })
    readonly property var _whole: _migration("2026-11-25-w-everything", ["*"], doc => { throw new Error("broken whole"); },
                                             { wholeScopeReason: "a test" })

    function _config(records, writtenBy) {
        return JSON.stringify({
            profiles: JSON.stringify([{ name: "Full", enabled: true, when: {}, set: { "testonly.old": "a" } }]),
            widgetPresets: JSON.stringify({ music: { Default: { popupMode: "click" } } }),
            migratedKeys: records, writtenBy: writtenBy
        });
    }

    function run() {
        _names();
        _rows();
        _preview();
        _texts();
        _pruning();
        _manualAndDelete();
        _sideFiles();
    }

    // Which side files a restore puts back and removes, and whose
    function _sideFiles() {
        const name = "config.json.bak-2026-01-12T09-14-40-123Z-migration";
        assertEqual(rules.sideBackupName("/c/" + name, "/c"), name, "side files: a backup in the config's folder has them");
        assertEqual(rules.sideBackupName("file:///c/" + name, "/c"), name, "… named by a file URL too");
        assertEqual(rules.sideBackupName("/elsewhere/" + name, "/c"), "", "… one in another folder has none here");
        assertEqual(rules.sideBackupName("/c/sub/" + name, "/c"), "", "… nor one in a folder inside it");
        assertEqual(rules.sideBackupName("/c/notes.txt", "/c"), "", "… a file that is no backup has none");
        assertEqual(rules.sideBackupName("/c/" + name, ""), "", "… nor without a config folder");
        assertEqual(rules.sideBackupName("/" + name, ""), "", "… nor at the root without a config folder");
        assertEqual(rules.sideBackupName("/c/" + name, undefined), "", "… nor with no folder named");
        assertEqual(rules.sideFilePlan("/etc/passwd", "").problem, "a side file of the backup has a name it cannot have: \"/etc/passwd\"", "plan: the refused name said");

        const themes = [{ migrationId: "2026-11-26-testonly-themes", scope: ["file:themes/*.json"] }];
        const hashA = Qt.md5("a\n");
        const hashNew = Qt.md5("new\n");
        const created = c => rules.createdEntries(c);
        assertEqual(JSON.stringify(created(hashNew + " themes/new one.json\nnot a line\n" + "0".repeat(31) + " x\n" + hashA.toUpperCase() + " y\n\n")),
                    JSON.stringify([{ hash: hashNew, path: "themes/new one.json" }]), "created list: hash and path (spaces kept), other lines left out");
        assertEqual(rules.createdText({ "themes/b.json": "new\n", "themes/a.json": "a\n" }), hashA + " themes/a.json\n" + hashNew + " themes/b.json\n",
                    "created list as written: a line each, sorted");
        assertEqual(JSON.stringify(created(rules.createdText({ "themes/x y.json": "new\n" }))), JSON.stringify([{ hash: hashNew, path: "themes/x y.json" }]),
                    "created list: read back as written");
        const plan = rules.sideFilePlan("themes/b.json\nthemes/a.json\n.created-files\n",
                                        created(hashNew + " themes/new.json\n" + hashA + " themes/a.json\n" + hashNew + " themes/new.json\n"),
                                        themes, { "themes/new.json": hashNew, "themes/a.json": hashA });
        assertEqual(plan.ok, true, "plan: listed files and created ones");
        assertEqual(plan.write.join(","), "themes/a.json,themes/b.json", "plan: the listed ones put back, sorted, the list of created ones not among them");
        assertEqual(plan.remove.join(","), "themes/new.json", "plan: a created one removed once; one also kept is put back, not removed");
        const removed = (path, now, registry) => rules.sideFilePlan("", created(hashNew + " " + path), registry ?? themes, now).remove.join(",");
        assertEqual(removed("themes/new.json", { "themes/new.json": hashNew }), "themes/new.json", "plan: a created one unchanged removed");
        assertEqual(removed("themes/new.json", { "themes/new.json": hashA }), "", "plan: … changed since: kept");
        assertEqual(removed("themes/new.json", { "themes/new.json": "" }), "", "plan: … gone or empty: nothing to remove");
        assertEqual(removed("themes/new.json", {}), "", "plan: … not read: kept");
        assertEqual(removed("themes/new.json", undefined), "", "plan: … nothing read at all: kept");
        assertEqual(removed("other/new.json", { "other/new.json": hashNew }), "", "plan: … no registered migration's file: kept");
        assertEqual(removed("themes/new.json", { "themes/new.json": hashNew }, []), "", "plan: … no migrations: kept");
        const empty = rules.sideFilePlan("", []);
        assertEqual(empty.ok + "|" + empty.write.length + "|" + empty.remove.length, "true|0|0", "plan: none");
        for (const bad of ["/etc/passwd", "../x.json", "themes/../../x", "themes//a.json", "./a.json", "themes/.", "config.json",
                           ".created-files", "config.json.bak-2026-01-12T09-14-40-123Z", "backup-side-files/x/a.json",
                           ".config-restore.abc/config.json", "themes/a\u0001.json", "themes/a\u007f.json"]) {
            const refused = rules.sideFilePlan(bad, []);
            // The list of created files is no side file: left out of what is put back
            if (bad === ".created-files")
                assert(refused.ok && refused.write.length === 0, "plan: the list of created files not put back");
            else
                assert(!refused.ok && refused.write.length === 0 && refused.problem.includes("cannot have"), "plan: " + JSON.stringify(bad) + " refused");
            assert(!rules.sideFilePlan("themes/a.json", [{ hash: hashA, path: bad }], themes, {}).ok, "plan: " + JSON.stringify(bad) + " refused as a created one too");
            assert(rules.sidePathProblem(bad) !== "", "path: " + JSON.stringify(bad) + " no side file's");
        }
        assertEqual(rules.sidePathProblem(""), "a side file of the backup has a name it cannot have: \"\"", "path: an empty one none");
        assertEqual(rules.sidePathProblem("themes/a.json"), "", "path: a side file's");
        assert(rules.sideFilePlan("themes/config.json\nthemes/.created-files\nother/backup-side-files", []).ok, "plan: those names inside a folder are side files");
        const many = [];
        for (let i = 0; i <= rules.maxSideFiles; i++)
            many.push("themes/" + i + ".json");
        assert(rules.sideFilePlan(many.slice(1).join("\n"), []).ok, "plan: as many as the limit taken");
        assert(!rules.sideFilePlan(many.join("\n"), []).ok, "plan: more than the limit refused");
        assert(!rules.sideFilePlan(many.slice(2).join("\n"), created(hashA + " a.json\n" + hashA + " b.json")).ok, "plan: the created ones count towards the limit");

        const restore = "config.json.bak-2026-01-12T09-14-40-123Z-restore";
        assertEqual(rules.keptForSideFiles([restore, name, "config.json.bak-2026-01-12T09-14-40-123Z-manual", "notes", 3]).join(","), restore,
                    "kept: a restore's backup with side files, no other");
        assertEqual(rules.keptForSideFiles(undefined).length, 0, "kept: none listed");
        const automatic = [];
        for (let i = 10; i < 21; i++)
            automatic.push("config.json.bak-2026-02-" + i + "T00-00-00-000Z-migration");
        const older = "config.json.bak-2025-01-01T00-00-00-000Z-restore";
        const plan2 = MigrationRules.backupsToKeep(automatic.concat([older]), { written: automatic[10], neverPrune: rules.keptForSideFiles([older]) });
        assert(plan2.keep.includes(older) && plan2.delete.length === 1 && plan2.delete[0] === automatic[0], "kept: never pruned, no place among the ten");
    }

    function _names() {
        const time = "2026-01-12T09:14:40.123Z";
        assertEqual(rules.name(time, "migration"), "config.json.bak-2026-01-12T09-14-40-123Z-migration", "name: the stamp and the reason");
        assertEqual(rules.name(time, ""), "config.json.bak-2026-01-12T09-14-40-123Z", "name: no reason");
        assertEqual(rules.name(time, "other"), "config.json.bak-2026-01-12T09-14-40-123Z", "name: an unknown reason left out");
        assertEqual(rules.name("noon", "manual"), "", "name: not a time");
        assertEqual(rules.name(time, "module", { id: "tailscale", from: "1.2.0", to: "1.3.0" }),
                    "config.json.bak-2026-01-12T09-14-40-123Z-module~tailscale~1.2.0~1.3.0", "name: a module switch names the module and versions");
        assertEqual(rules.name(time, "module", { id: "Bad/Id", from: "1.2.0", to: "1.3.0" }), "config.json.bak-2026-01-12T09-14-40-123Z-module",
                    "name: a module id that is none left out");
        assertEqual(rules.name(time, "module", { id: "tailscale", from: "../1", to: "1.3.0" }), "config.json.bak-2026-01-12T09-14-40-123Z-module",
                    "name: a version that is none left out");
        assertEqual(rules.name(time, "module", { id: "tailscale", from: "", to: "1.3.0" }), "config.json.bak-2026-01-12T09-14-40-123Z-module",
                    "name: a missing version left out");
        assertEqual(rules.name(time, "manual", { id: "tailscale", from: "1", to: "2" }), "config.json.bak-2026-01-12T09-14-40-123Z-manual",
                    "name: a module only for a module switch");

        const parsed = rules.parseName("/c/config.json.bak-2026-01-12T09-14-40-123Z-module~tailscale~1.2.0~1.3.0");
        assert(parsed.ok, "parse: a module switch's backup");
        assertEqual(parsed.name, "config.json.bak-2026-01-12T09-14-40-123Z-module~tailscale~1.2.0~1.3.0", "parse: a path's last part");
        assertEqual(parsed.time, Date.UTC(2026, 0, 12, 9, 14, 40, 123), "parse: the time, UTC");
        assertEqual(parsed.reason + "|" + parsed.module.id + "|" + parsed.module.from + "|" + parsed.module.to, "module|tailscale|1.2.0|1.3.0",
                    "parse: the reason, module and versions");
        assertEqual(rules.parseName("config.json.bak-2026-01-12T09-14-40-123Z-module").module, null, "parse: a module backup without names");
        assertEqual(rules.parseName("config.json.bak-2026-01-12T09-14-40-123Z").reason, "", "parse: an older one, no reason");
        const none = rules.parseName("notes");
        assertEqual(none.time + "|" + none.reason + "|" + none.module, "0||null", "parse: not a backup: no time, reason or module");
        assertEqual(rules.parseName("config.json.bak-2026-01-12T09-14-40-123Z-manual").reason, "manual", "parse: manual");
        for (const bad of ["config.json", "config.json.bak-notes", "config.json.bak-2026-01-12T09-14-40-123Z-other",
                           "config.json.bak-2026-01-12T09-14-40-123Z.tmp", "x-config.json.bak-2026-01-12T09-14-40-123Z",
                           "config.json.bak-2026-01-12T09-14-40Z", "config.json.bak-2026-01-12T09-14-40-123Z-manual~a~1~2",
                           "config.json.bak-2026-01-12T09-14-40-123Z-module~a~1", "config.json.bak-2026-01-12T09-14-40-123Z-module~A~1~2", null])
            assert(!rules.parseName(bad).ok, "parse: not a backup: " + bad);
        assertEqual(rules.date("config.json.bak-2026-01-12T09-14-40-123Z"), Qt.formatDateTime(new Date(Date.UTC(2026, 0, 12, 9, 14, 40, 123)), "d MMM yyyy, hh:mm"),
                    "date: in local time");
        assertEqual(rules.date("nothing"), "", "date: none for a name with no time");
    }

    function _rows() {
        const entries = [
            { name: "config.json.bak-2026-01-05T21-30-00-000Z-manual", text: _config([], "2.1.0"), readable: true },
            { name: "config.json.bak-2026-01-10T08-41-02-000Z-migration", text: _config([], "2.1.0"), readable: true },
            { name: "config.json.bak-2026-01-12T09-14-40-000Z-module~tailscale~1.2.0~1.3.0", text: _config([], "2.2.0"), readable: true },
            { name: "config.json.bak-2026-01-14T18-02-11-000Z-restore", text: _config([], "2.2.0"), readable: true },
            { name: "config.json.bak-2026-01-08T22-15-57-000Z-migration", text: _config([], "2.3.0"), readable: true },
            { name: "config.json.bak-2026-01-07T22-15-57-000Z-migration", text: _config(["2026-12-01-from-the-future"], "2.2.0"), readable: true },
            { name: "config.json.bak-2025-12-20T14-05-33-000Z", text: _config([], ""), readable: true },
            { name: "config.json.bak-2025-12-01T11-47-09-000Z", text: "{ not json", readable: true },
            { name: "config.json.bak-2025-11-01T11-47-09-000Z-restore", text: "", readable: false },
            { name: "config.json.bak-2025-10-01T11-47-09-000Z-restore", text: "[1, 2]", readable: true },
            { name: "config.json", text: _config([], "2.2.0"), readable: true },
            { name: "notes.txt", text: "", readable: true }
        ];
        const rows = rules.rows(entries, "2.2.0", [_rename]);
        assertEqual(rows.length, 10, "rows: every backup, unreadable ones too; other files left out");
        assertEqual(rows.map(row => row.name.slice(16, 26)).join(","),
                    "2026-01-14,2026-01-12,2026-01-10,2026-01-08,2026-01-07,2026-01-05,2025-12-20,2025-12-01,2025-11-01,2025-10-01", "rows: newest first");
        const by = prefix => rows.find(row => row.name.startsWith("config.json.bak-" + prefix));
        assertEqual(by("2026-01-14").reasonText, "Before a restore", "rows: before a restore");
        assertEqual(by("2026-01-12").reasonText, "Before updating tailscale 1.2.0 → 1.3.0", "rows: a module gone: its id and the versions");
        const named = rules.rows(entries, "2.2.0", [_rename], { tailscale: "Tailscale" });
        assertEqual(named.find(row => row.reason === "module").reasonText, "Before updating Tailscale 1.2.0 → 1.3.0", "rows: a module there: its display name");
        const odd = rules.rows(entries, "2.2.0", [_rename], { tailscale: "<b>Tail</b>\nscale " + "x".repeat(80) });
        const oddText = odd.find(row => row.reason === "module").reasonText;
        assert(!oddText.includes("\n") && oddText.length < 100, "rows: a display name on one line, capped");
        const capped = rules.reasonText(rules.parseName("config.json.bak-2026-01-12T09-14-40-000Z-module~t~1~2"), "y".repeat(61));
        assertEqual(capped, "Before updating " + "y".repeat(59) + "… 1 → 2", "rows: a display name capped at 60 characters");
        assertEqual(rules.maxBackupBytes, 4194304, "rows: files over 4 MB are not read");
        assertEqual(rules.rows(entries, "2.2.0", [_rename], { other: "Other" }).find(row => row.reason === "module").reasonText,
                    "Before updating tailscale 1.2.0 → 1.3.0", "rows: another module's name not taken");
        assertEqual(rules.reasonText(rules.parseName("config.json.bak-2026-01-12T09-14-40-000Z-module~tailscale~1.3.0~1.2.0"), "Tailscale"),
                    "Before going back: Tailscale 1.3.0 → 1.2.0", "rows: to an older version: a way back");
        const large = rules.rows([{ name: "config.json.bak-2026-01-12T09-14-40-000Z", text: _config([], "2.2.0"), tooLarge: true }], "2.2.0", [])[0];
        assert(!large.readable && large.versionText === "too large", "rows: a file too large: not read, said");
        assertEqual(by("2026-01-10").reasonText, "Before a settings update", "rows: before a settings update");
        assertEqual(by("2026-01-05").reasonText, "Made by you", "rows: manual");
        const sided = rules.rows(entries, "2.2.0", [_rename], {}, ["config.json.bak-2026-01-14T18-02-11-000Z-restore", "config.json.bak-2026-01-10T08-41-02-000Z-migration"]);
        assertEqual(sided.filter(row => row.kept).map(row => row.name.slice(16, 26)).join(","), "2026-01-14,2026-01-05",
                    "rows: a restore's backup with side files kept (as pruning keeps it), the manual one; a migration's with side files not");
        assertEqual(rows.filter(row => row.kept).length, 1, "rows: no side folders listed: the manual one alone kept");
        assert(by("2026-01-05").kept && !by("2026-01-10").kept && !by("2025-12-20").kept, "rows: only a manual one kept");
        assertEqual(by("2025-12-20").reasonText, "Older backup, reason not recorded", "rows: an older one, no reason");
        assertEqual(by("2025-12-20").versionText, "version unknown", "rows: no version recorded");
        assertEqual(by("2026-01-10").versionText + "|" + by("2026-01-10").writtenBy, "2.1.0|2.1.0", "rows: the version that wrote it");
        const newer = by("2026-01-08");
        assert(newer.newer, "rows: written by a newer version");
        assertEqual(newer.newerLine, "Written by shell 2.3.0 (newer than current) — may be incompatible, expect odd behaviour", "rows: the newer line");
        assert(!by("2026-01-10").newer && by("2026-01-10").newerLine === "", "rows: an older one not newer");
        assert(by("2026-01-07").newer, "rows: newer by records this version does not know");
        assertEqual(by("2026-01-07").newerLine, "Written by a newer shell (newer than current) — may be incompatible, expect odd behaviour",
                    "rows: … said without a version");
        for (const prefix of ["2025-12-01", "2025-11-01", "2025-10-01"]) {
            assert(!by(prefix).readable, "rows: unreadable shown, not dropped: " + prefix);
            assertEqual(by(prefix).versionText, "can't be read", "rows: … and said: " + prefix);
        }
        assert(by("2026-01-10").readable, "rows: a settings file readable");
        const tie = rules.rows([{ name: "config.json.bak-2026-01-05T21-30-00-000Z", text: "{}" },
                                { name: "config.json.bak-2026-01-05T21-30-00-000Z-manual", text: "{}" }], "2.2.0", []);
        assertEqual(tie.map(row => row.reason).join(","), "manual,", "rows: equal times by name, the same each time");
        assertEqual(rules.rows(null, "2.2.0", []).length, 0, "rows: no entries");
    }

    function _preview() {
        const registry = [_rename, _broken, _dependent];
        const older = rules.preview(registry, _config(["bar.height"], "2.1.0"), "2.2.0");
        assert(older.ok, "preview: an older backup read");
        assertEqual(older.updates, 3, "preview: its pending migrations counted");
        assertEqual(older.held.join(","), "2026-11-25-x-music-popup,2026-11-25-y-music-more", "preview: the failing one and the one skipped after it held");
        assertEqual(older.failing.join(","), "music widget presets", "preview: the failing part, in words");
        assertEqual(older.heldParts.join(","), "music widget presets,music extras", "preview: the parts skipped");
        assert(!older.readOnly && !older.newer, "preview: neither read-only nor newer");

        const same = rules.preview(registry, _config(registry.map(each => each.migrationId), "2.2.0"), "2.2.0");
        assertEqual(same.updates + same.held.length + same.failing.length, 0, "preview: a current backup needs nothing");

        const held = rules.preview(registry, _config(["2026-11-25-testonly-rename", "held:2026-11-25-x-music-popup@2.2.0"], "2.2.0"), "2.2.0");
        assertEqual(held.updates, 1, "preview: a migration held under this version does not run");
        assertEqual(held.held.join(","), "2026-11-25-y-music-more", "preview: … not held again (its record stays); the one skipped after it held");
        const heldOther = rules.preview(registry, _config(["2026-11-25-testonly-rename", "held:2026-11-25-x-music-popup@2.1.0"], "2.1.0"), "2.2.0");
        assertEqual(heldOther.updates, 2, "preview: held under another version, it runs");

        const newer = rules.preview(registry, _config(registry.map(each => each.migrationId).concat(["2026-12-01-from-the-future"]), "2.3.0"), "2.2.0");
        assert(newer.ok && newer.newer, "preview: a newer backup");
        assertEqual(newer.updates, 0, "preview: … no migration runs backwards");

        const whole = rules.preview([_rename, _whole], _config([], "2.1.0"), "2.2.0");
        assert(whole.readOnly, "preview: a whole-config failure: the shell would start read-only");
        assertEqual(whole.held.length, 0, "preview: … nothing held");
        const broken = rules.preview(registry, JSON.stringify({ profiles: "{ broken" }), "2.2.0");
        assert(broken.ok && broken.readOnly, "preview: profiles that cannot be read: read-only");
        const notSettings = rules.preview(registry, "{ not json", "2.2.0");
        assert(!notSettings.ok && !notSettings.readOnly && !notSettings.newer && notSettings.problem === "the backup is not a settings file", "preview: not a settings file");
        assert(!rules.preview(registry, "[]", "2.2.0").ok, "preview: a list is not a settings file");
        assertEqual(rules.preview(registry, "{}", "2.2.0").updates, 0, "preview: an empty config is new: nothing runs");
    }

    function _texts() {
        const registry = [_rename, _broken, _dependent];
        const row = rules.rows([{ name: "config.json.bak-2026-01-10T08-41-02-000Z-migration", text: _config([], "2.1.0") }], "2.2.0", registry)[0];
        const failing = rules.preview(registry, _config([], "2.1.0"), "2.2.0");
        assertEqual(rules.previewText(failing, "2.2.0"), "Apply: 3 settings updates bring it up to 2.2.0. Fails for: music widget presets.",
                    "line: the updates and the failing part");
        assertEqual(rules.previewText({ ok: true, updates: 1, failing: [] }, "2.2.0"), "Apply: 1 settings update brings it up to 2.2.0.", "line: one update");
        assertEqual(rules.previewText({ ok: true, updates: 0, failing: [] }, "2.2.0"), "Apply: No settings updates are needed.", "line: none");
        assertEqual(rules.previewText({ ok: true, updates: 2, newer: true, failing: ["x"] }, "2.2.0"), "Apply: No settings updates are needed.",
                    "line: a newer backup: nothing converted back");
        assertEqual(rules.previewText({ ok: true, updates: 1, readOnly: true, failing: [] }, "2.2.0"),
                    "Apply: 1 settings update brings it up to 2.2.0. The shell would start read-only with it.", "line: read-only");
        assertEqual(rules.previewText({ ok: false }, "2.2.0"), "Can't be read.", "line: unreadable");

        const question = rules.applyQuestion(row, failing, "2.2.0");
        assertEqual(question.title, "Apply the backup of " + row.date + "?", "question: names the backup by its date");
        assertEqual(question.body.join("|"), "Before a settings update · 2.1.0|Steps:|1. Create a new backup|2. Load the selected backup"
                    + "|3. Settings update to 2.2.0, skipping music widget presets, music extras|4. Restart the shell", "question: reason, version, four steps");
        assertEqual(question.buttons.map(button => button.id + ":" + button.label).join(","), "apply:Apply and restart", "question: its button");
        assertEqual(question.cancelLabel, "Cancel", "question: cancel");
        assertEqual(question.kind, "warning", "question: a warning");
        assertEqual(question.subject.name + "|" + question.subject.held.join(","),
                    row.name + "|2026-11-25-x-music-popup,2026-11-25-y-music-more", "question: keyed to the backup and what it holds");
        const plain = rules.applyQuestion(row, { ok: true, updates: 1, heldParts: [], held: [] }, "2.2.0");
        assertEqual(plain.body.slice(1).join("|"), "Steps:|1. Create a new backup|2. Load the selected backup|3. Settings update to 2.2.0|4. Restart the shell",
                    "question: an update with nothing skipped");
        const current = rules.applyQuestion(row, { ok: true, updates: 0, heldParts: [], held: [] }, "2.2.0");
        assertEqual(current.body.slice(1).join("|"), "Steps:|1. Create a new backup|2. Load the selected backup|3. Restart the shell",
                    "question: no update: three steps");
        const newerRow = rules.rows([{ name: "config.json.bak-2026-01-08T22-15-57-000Z-migration", text: _config([], "2.3.0") }], "2.2.0", registry)[0];
        const newer = rules.applyQuestion(newerRow, { ok: true, newer: true, updates: 2, heldParts: ["x"], held: [] }, "2.2.0");
        assertEqual(newer.title, "Load a backup from a newer shell?", "newer: its title");
        assertEqual(JSON.stringify(newer.body[0]), JSON.stringify({ text: "⚠ Written by shell 2.3.0 (newer than current) — may be incompatible, expect odd behaviour", strong: true }),
                    "newer: the one line, in bold");
        assertEqual(newer.body.slice(1).join("|"), "Steps:|1. Create a new backup|2. Load the selected backup|3. Restart the shell",
                    "newer: the same steps without an update");
        const readOnly = rules.applyQuestion(row, { ok: true, readOnly: true, updates: 1, heldParts: [], held: [] }, "2.2.0");
        assertEqual(JSON.stringify(readOnly.body[1]), JSON.stringify({ text: "⚠ The shell would start read-only with this backup", strong: true }),
                    "read-only: said in the question, in bold");
        const byPreview = rules.applyQuestion(row, { ok: true, newer: true, updates: 1, held: [] }, "2.2.0");
        assertEqual(byPreview.title, "Load a backup from a newer shell?", "newer: by the preview alone");
        assertEqual(byPreview.body[0].text, "⚠ Written by a newer shell (newer than current) — may be incompatible, expect odd behaviour",
                    "newer: the line without a version when the row has none");
        assertEqual(rules.applyQuestion(newerRow, { ok: true, newer: false, updates: 1, held: [] }, "2.2.0").title, "Load a backup from a newer shell?",
                    "newer: by the row alone");
        assertEqual(rules.steps({ length: 2, 0: "a", 1: "b" }).join("|"), "Steps:|1. a|2. b", "steps: a sequence that is no Array taken as a list");
        assertEqual(rules.steps({ length: "2", 0: "a" }).join("|"), "Steps:", "steps: an object with no length is no list");
        assertEqual(rules.steps(["a", "b"]).join("|"), "Steps:|1. a|2. b", "steps: numbered");

        const text = JSON.parse(rules.listText(true, [row]));
        assert(text.known && text.backups.length === 1, "ipc: known, the rows");
        assertEqual(text.backups[0].name + "|" + text.backups[0].reason + "|" + text.backups[0].writtenBy + "|" + text.backups[0].kept,
                    row.name + "|migration|2.1.0|false", "ipc: name, reason, version, kept");
        assert(!JSON.parse(rules.listText(false, null)).known, "ipc: not read yet");
    }

    function _pruning() {
        const names = [];
        for (let day = 1; day <= 11; day++)
            names.push("config.json.bak-2026-10-" + String(day).padStart(2, "0") + "T10-00-00-000Z-module~kappa~1.0.0~1.1.0");
        const manual = "config.json.bak-2026-09-01T10-00-00-000Z-manual";
        const plan = MigrationRules.backupsToKeep(names.concat([manual, "sub/config.json.bak-2026-10-20T10-00-00-000Z"]), {});
        assertEqual(plan.delete.join(","), names[0], "pruning: module-switch backups are automatic, counted among the ten");
        assert(plan.keep.includes(manual), "pruning: a manual one never pruned");
        assert(!plan.keep.some(name => name.includes("/")), "pruning: only names in the folder");
        assertEqual(MigrationRules.backupName("2026-01-12T09:14:40.123Z", "module", { id: "kappa", from: "1", to: "2" }),
                    "config.json.bak-2026-01-12T09-14-40-123Z-module~kappa~1~2", "pruning: the runner names backups the same way");
    }

    function _manualAndDelete() {
        assertEqual(rules.backupRefusal({}), "", "backup now: allowed");
        assertEqual(rules.backupRefusal(null), "", "backup now: no state, allowed");
        assertEqual(rules.backupRefusal({ testRunner: true }), "Not under the test runner", "backup now: not under the test runner");
        assertEqual(rules.backupRefusal({ busy: true }), "The settings update is still running", "backup now: not while a run goes on");
        assertEqual(rules.backupRefusal({ restoring: true }), "A restore is under way", "backup now: not while a restore is under way");
        assertEqual(rules.backupRefusal({ running: true }), "A backup is being written", "backup now: one at a time");
        assertEqual(rules.backupRefusal({ testRunner: "yes", busy: 1, restoring: "x", running: {} }), "", "backup now: only true refuses");

        const made = rules.name("2026-01-15T10:30:00.000Z", "manual");
        assertEqual(made, "config.json.bak-2026-01-15T10-30-00-000Z-manual", "backup now: named manual");
        assertEqual(rules.madeLine(made), "✓ Backup made: " + rules.date(made), "backup now: the line names its date");
        assertEqual(rules.madeLine("notes.txt"), "", "backup now: no line for a name that is no backup");
        assertEqual(rules.madeLine(""), "", "backup now: no line for none");

        const manuals = ["config.json.bak-2025-01-01T10-00-00-000Z-manual", "config.json.bak-2025-01-02T10-00-00-000Z-manual"];
        const automatic = [];
        for (let day = 1; day <= 12; day++)
            automatic.push("config.json.bak-2026-02-" + String(day).padStart(2, "0") + "T10-00-00-000Z-migration");
        const plan = MigrationRules.backupsToKeep(manuals.concat(automatic), { written: automatic[11] });
        assert(manuals.every(name => plan.keep.includes(name)), "pruning: manual ones kept past ten automatic ones, the oldest though they are");
        assertEqual(plan.delete.slice().sort().join(","), automatic.slice(0, 2).join(","), "pruning: only the automatic ones pruned to ten");
        const justMade = "config.json.bak-2026-03-01T10-00-00-000Z-manual";
        const afterManual = MigrationRules.backupsToKeep(automatic.slice(0, 10).concat([justMade]), { written: justMade });
        assertEqual(afterManual.delete.length, 0, "pruning: a manual one just written takes no place among the ten automatic ones");

        const name = "config.json.bak-2026-01-05T21-30-00-000Z-manual";
        assertEqual(rules.deleteRefusal(name, {}), "", "delete: a backup's name");
        assertEqual(rules.deleteRefusal(name, null), "", "delete: no state, allowed");
        assertEqual(rules.deleteRefusal("config.json", {}), "Not a backup: config.json", "delete: not the settings file");
        assertEqual(rules.deleteRefusal("notes.txt", {}), "Not a backup: notes.txt", "delete: not another file");
        assertEqual(rules.deleteRefusal("../" + name, {}), "Not a backup: ../" + name, "delete: nothing outside the folder");
        assertEqual(rules.deleteRefusal("/tmp/" + name, {}), "Not a backup: /tmp/" + name, "delete: not a path");
        assertEqual(rules.deleteRefusal(name + "/x", {}), "Not a backup: " + name + "/x", "delete: nothing under a backup's name");
        assertEqual(rules.deleteRefusal(null, {}), "Not a backup: ", "delete: no name");
        assertEqual(rules.deleteRefusal("x".repeat(200), {}).length, "Not a backup: ".length + 80, "delete: a long name cut");
        assertEqual(rules.deleteRefusal(name, { testRunner: true }), "Not under the test runner", "delete: not under the test runner");
        assertEqual(rules.deleteRefusal(name, { deleting: true }), "Already deleting", "delete: one at a time");
        assertEqual(rules.deleteRefusal(name, { reading: "/home/u/.config/h2s_shell/" + name }), "Being applied", "delete: not the backup a restore reads (a path)");
        assertEqual(rules.deleteRefusal(name, { reading: name }), "Being applied", "delete: … or its name");
        assertEqual(rules.deleteRefusal(name, { reading: "/x/config.json.bak-2026-01-05T21-30-00-000Z-migration" }), "",
                    "delete: another backup being applied does not refuse");
        assertEqual(rules.deleteRefusal(name, { needed: ["/x/other", "/home/u/" + name] }), "Needed by Restore previous settings",
                    "delete: not the failure notice's backup");
        assertEqual(rules.deleteRefusal(name, { needed: ["/x/config.json.bak-2026-01-05T21-30-00-000Z"] }), "",
                    "delete: another one needed does not refuse");
        assertEqual(rules.deleteRefusal(name, { reading: "", needed: [""] }), "", "delete: none read, none needed");
        assertEqual(rules.deleteRefusal(name, { testRunner: "yes", deleting: 1 }), "", "delete: only true refuses");

        const row = rules.rows([{ name: name, text: JSON.stringify({ writtenBy: "2.1.0" }) }], "2.2.0", [])[0];
        const question = rules.deleteQuestion(row);
        assertEqual(question.title, "Delete the backup of " + rules.date(name) + " (manual, 2.1.0)?", "delete: asks naming date, reason and version");
        assertEqual(question.body.join("|"), "Only this backup is removed. This cannot be undone.", "delete: says what it removes");
        assertEqual(question.kind + "|" + question.buttons.map(button => button.id + ":" + button.label + ":" + button.kind).join(",") + "|" + question.cancelLabel,
                    "danger|delete:Delete:delete|Cancel", "delete: a danger question, Delete and Cancel");
        assertEqual(question.subject.name, name, "delete: keyed to the backup");
        const reasons = ["migration", "restore", "module", "manual", ""].map(reason => rules.reasonShort(reason));
        assertEqual(reasons.join("|"), "before a settings update|before a restore|before a module update|manual|reason not recorded",
                    "delete: each reason, short");
        const old = rules.rows([{ name: "config.json.bak-2025-12-01T11-47-09-000Z", text: "", readable: false }], "2.2.0", [])[0];
        assertEqual(rules.deleteQuestion(old).title, "Delete the backup of " + rules.date(old.name) + " (reason not recorded, can't be read)?",
                    "delete: an unreadable one asked about too");
    }
}
