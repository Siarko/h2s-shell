import QtQuick
import qs.singletons

// ConfigBackupRules (pure): a backup's name and its parts (the reason, a module switch's
// module and versions; nothing but the exact pattern is a backup), the rows (newest first,
// automatic, manual and kept, an older one with no reason, a missing version, a newer writer
// by version and by records, an unreadable file shown as such), Apply's preview of an older,
// a current and a newer backup (pending, held, failing with the skipped held, a whole-config
// failure), the opened row's line, Apply's question as steps and its subject, the IPC text;
// and the pruning of module-switch backups as automatic (MigrationRules.backupsToKeep).
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
        assertEqual(by("2026-01-12").reasonText, "Before updating tailscale 1.2.0 → 1.3.0", "rows: a module switch names the module and versions");
        assertEqual(by("2026-01-10").reasonText, "Before a settings update", "rows: before a settings update");
        assertEqual(by("2026-01-05").reasonText, "Made by you", "rows: manual");
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
}
