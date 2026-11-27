import QtQuick
import qs.singletons

// MigrationNoticeRules (pure): the notice after the start's migration runs — none for a
// successful run, "reset" naming the parts reset (scopeLabel, else summary, else id) and
// holding the failed and the skipped ones, the backup of the first run that wrote one,
// "readOnly" for a session that saves nothing —, the backup's date from its name, the
// questions as steps lists, the records a restore writes (held:<id>@<version>, an older hold
// replaced), the restored and the default config, and the IPC report; a module's own notice
// (named by its display name, its id when gone; its parts and holds, its backup's date and
// question).
TestCase {
    id: suite
    suiteName: "MigrationNoticeRules"

    readonly property var rules: MigrationNoticeRules

    readonly property var _registry: [
        { migrationId: "2026-11-25-x-music-popup", scopeLabel: "music widget presets", summary: "Music popup" },
        { migrationId: "2026-11-25-y-music-more", summary: "More music" },
        { migrationId: "2026-11-25-z-other" },
        { migrationId: "2026-11-25-w-everything", scope: ["*"], wholeScopeReason: "a test" }
    ]
    readonly property string _backup: "/c/config.json.bak-2026-01-15T10-29-03-120Z-migration"

    function _report(extra) {
        return Object.assign({ phase: "load", fresh: false, records: [], applied: [], reset: [], skipped: [], held: [], failure: null, problem: "", backup: "" }, extra);
    }

    function run() {
        _none();
        _reset();
        _readOnly();
        _dates();
        _questions();
        _records();
        _configs();
        _ipc();
        _module();
    }

    function _module() {
        const report = { applied: [{ id: "a", summary: "A" }], reset: [{ id: "broken", summary: "Taildrop folder", scope: "setting:taildrop.*", error: "x" }, { id: "other", summary: "", error: "y" }],
                         skipped: [{ id: "after", after: "broken", summary: "After it" }], held: [], backup: "0.8.0-20260115-102903", version: "0.8.0", fresh: false };
        const notice = rules.moduleNotice("tailscale", "Tailscale", report, true);
        assertEqual(notice.kind, "reset", "module: a migration reset");
        assertEqual(notice.summary, "Updating Tailscale settings to 0.8.0 failed", "module: the heading names it by its display name");
        assertEqual(notice.body, "Defaults are used where possible. See Settings for details.", "module: the core's short body");
        assertEqual(JSON.stringify(notice.parts), JSON.stringify(["Taildrop folder", "other"]), "module: the parts reset, by summary, else id");
        assertEqual(JSON.stringify(notice.held) + JSON.stringify(notice.heldParts), JSON.stringify(["broken", "other", "after"]) + JSON.stringify(["Taildrop folder", "other", "After it"]),
                    "module: held, the failed ones and those skipped after them");
        assertEqual(notice.backup + " " + notice.version + " " + notice.module.id + " " + notice.module.name, "0.8.0-20260115-102903 0.8.0 tailscale Tailscale", "module: its backup, version and names");
        assert(notice.key !== "" && notice.key !== rules.moduleNotice("tailscale", "Tailscale", Object.assign({}, report, { backup: "0.8.0-20260116-102903" }), true).key,
               "module: the key changes with the run");
        assertEqual(rules.moduleNotice("tailscale", "", report, false).summary, "Updating tailscale settings to 0.8.0 failed", "module: gone, its id named");
        assertEqual(rules.moduleNotice("tailscale", "", report, false).backup, "", "module: gone, nothing to restore into");
        assertEqual(rules.moduleNotice("tailscale", "Tail\n<b>scale</b>", report, true).summary, "Updating Tail <b>scale</b> settings to 0.8.0 failed", "module: its name on one line, as text");
        assertEqual(rules.moduleNotice("tailscale", "Tail\u202escale\u0007", report, true).module.name, "Tailscale", "module: its name without direction overrides or controls");
        assertEqual(rules.moduleNotice("tailscale", "", report, false).key, notice.key, "module: the key the same when its name or presence changes (no new failure)");
        assertEqual(rules.moduleNotice("tailscale", "x".repeat(61), report, true).module.name, "x".repeat(59) + "…", "module: its name capped at 60");
        assertEqual(rules.moduleNotice("tailscale", "x".repeat(60), report, true).module.name, "x".repeat(60), "module: a name of 60 kept whole");
        assertEqual(rules.moduleNotice("tailscale", "T", Object.assign({}, report, { version: "1".repeat(100) }), true).version.length, 64, "module: its version capped");
        assertEqual(notice.startDefaults + " " + rules.moduleNotice("tailscale", "T", null, true).startDefaults, "false false", "module: never Start with default settings");
        assertEqual(JSON.stringify(rules.moduleNotice("tailscale", "T", Object.assign({}, report, { reset: [{ id: "p", summary: "Same" }, { id: "q", summary: "Same" }], skipped: [] }), true).parts),
                    JSON.stringify(["Same"]), "module: a part named twice listed once");
        assertEqual(rules.moduleNotice("tailscale", "Tailscale", Object.assign({}, report, { version: undefined }), true).summary, "Updating Tailscale settings failed", "module: no version known");
        assertEqual(rules.moduleNotice("tailscale", "Tailscale", Object.assign({}, report, { reset: [] }), true).kind, "", "module: nothing reset, no notice");
        assertEqual(rules.moduleNotice("tailscale", "Tailscale", undefined, true).kind + rules.moduleNotice("", "x", report, true).kind, "", "module: no report or no id, no notice");
        assertEqual(rules.moduleBackupDate("0.8.0-20260115-102903"), Qt.formatDateTime(new Date(Date.UTC(2026, 0, 15, 10, 29, 3)), "d MMM yyyy, hh:mm"), "module backup: its date, local");
        assertEqual(rules.moduleBackupDate("0.8.0-20260115-102903-2") !== "" && rules.moduleBackupDate("0.8.0") === "" && rules.moduleBackupDate(undefined) === "", true, "module backup: a suffixed name dated, none without a time");
        const question = rules.restoreQuestion(notice);
        assertEqual(question.title, "Restore the settings from before the update?", "module question: the core's title");
        assertEqual(JSON.stringify(question.body), JSON.stringify(["Steps:", "1. Create a new backup", "2. Load the backup of " + rules.moduleBackupDate(report.backup),
                                                                 "3. Tailscale settings update to 0.8.0, skipping Taildrop folder, other, After it", "4. Restart Tailscale"]),
                    "module question: the steps name the module, its backup's date and the parts skipped");
        const text = JSON.parse(rules.reportText(rules.notice({}, false, "2.2.0", []), {}, [notice, rules.moduleNotice("x", "X", null, true), { kind: "reset", module: null }]));
        assertEqual(JSON.stringify(text.modules.map(each => each.id + ":" + each.summary)), JSON.stringify(["tailscale:Updating Tailscale settings to 0.8.0 failed"]),
                    "report: the modules' failed updates listed");
    }

    function _none() {
        assertEqual(rules.notice({ load: null, afterSeed: null }, false, "2.2.0", _registry).kind, "", "none: no run, no notice");
        const applied = rules.notice({ load: _report({ applied: ["a"], backup: _backup }), afterSeed: _report({ phase: "afterSeed" }) }, false, "2.2.0", _registry);
        assertEqual(applied.kind + "|" + applied.summary + "|" + applied.key, "||", "none: a successful run says nothing");
        assertEqual(rules.notice(undefined, false, "2.2.0", _registry).kind, "", "none: no reports at all");
    }

    function _reset() {
        const load = _report({ reset: [{ id: "2026-11-25-x-music-popup", error: "broken" }], skipped: [{ id: "2026-11-25-y-music-more", after: "2026-11-25-x-music-popup" }], backup: _backup });
        const notice = rules.notice({ load: load, afterSeed: _report({ phase: "afterSeed", backup: "/c/config.json.bak-later" }) }, false, "2.2.0", _registry);
        assertEqual(notice.kind, "reset", "reset: the kind");
        assertEqual(notice.summary, "Updating settings to 2.2.0 failed", "reset: the summary names the running version");
        assertEqual(notice.body, "Defaults are used where possible. See Settings for details.", "reset: the body, short");
        assertEqual(notice.parts.join("|"), "music widget presets", "reset: the parts reset, by scopeLabel; a skipped one is not reset");
        assertEqual(notice.held.join("|"), "2026-11-25-x-music-popup|2026-11-25-y-music-more", "reset: the failed and the skipped ones held");
        assertEqual(notice.heldParts.join("|"), "music widget presets|More music", "reset: held parts in words, the summary without a scopeLabel");
        assertEqual(notice.backup, _backup, "reset: the backup of the first run that wrote one");
        const later = rules.notice({ load: _report({}), afterSeed: _report({ phase: "afterSeed", reset: [{ id: "2026-11-25-z-other", error: "x" }], backup: "/c/b2" }) }, false, "2.2.0", _registry);
        assertEqual(later.parts.join("|") + "|" + later.backup, "2026-11-25-z-other|/c/b2", "reset: after seeding: the id without words, that run's backup");
        const both = rules.notice({ load: load, afterSeed: _report({ phase: "afterSeed", reset: [{ id: "2026-11-25-z-other", error: "x" }] }) }, false, "2.2.0", _registry);
        assertEqual(both.parts.length + "|" + both.held.length, "2|3", "reset: both phases' failures together");
        assert(both.key !== notice.key, "reset: another failure, another key");
        const repeated = rules.notice({ load: _report({ reset: [{ id: 5 }, { id: "2026-11-25-x-music-popup" }, { id: "2026-11-25-x-music-popup" }], skipped: [{ id: null }] }),
                                        afterSeed: _report({ reset: [{ id: "2026-11-25-x-music-popup" }] }) }, false, "2.2.0", _registry);
        assertEqual(repeated.parts.join("|") + "/" + repeated.held.join("|"), "music widget presets/2026-11-25-x-music-popup", "reset: each id once, an entry without an id left out");
        assertEqual(rules.notice({ load: _report({ reset: [{ id: 5 }, {}] }) }, false, "2.2.0", _registry).kind, "", "reset: entries without an id are no failure to tell");
        const sameWords = [{ migrationId: "a-1", scopeLabel: "music widget presets" }, { migrationId: "a-2", scopeLabel: "music widget presets" }, { migrationId: "a-3", scopeLabel: " " }];
        const twice = rules.notice({ load: _report({ reset: [{ id: "a-1" }, { id: "a-2" }] }) }, false, "2.2.0", sameWords);
        assertEqual(twice.parts.join("|"), "music widget presets", "reset: the same words once");
        assertEqual(rules.partLabel(sameWords[2], "a-3") + "|" + rules.partLabel(null, 7), "a-3|", "reset: blank words fall back to the id; no id, nothing");
        assertEqual(rules.notice({ load: load }, false, "2.2.0", _registry).key, rules.notice({ load: load }, false, "2.2.0", _registry).key, "reset: the same failure, the same key");
    }

    function _readOnly() {
        const notice = rules.notice({ load: _report({ failure: { id: "w", error: "broken" } }) }, true, "2.2.0", _registry);
        assertEqual(notice.kind, "readOnly", "readOnly: a session that saves nothing");
        assertEqual(notice.summary + "|" + notice.body, "Updating settings to 2.2.0 failed|Changes are not saved. See Settings for details.", "readOnly: the texts");
        assertEqual(notice.held.length + "|" + notice.backup, "0|", "readOnly: nothing to restore");
        assert(!notice.startDefaults, "readOnly: a failure that is no registered \"*\" migration: no Start with default settings");
        const whole = rules.notice({ load: null, afterSeed: _report({ failure: { id: "2026-11-25-w-everything", error: "broken" } }) }, true, "2.2.0", _registry);
        assert(whole.startDefaults, "readOnly: a \"*\" migration failed: Start with default settings");
        assert(whole.key !== notice.key, "readOnly: … another key");
        const unreadable = rules.notice({ load: _report({ failure: { id: "", error: "themes/dark.json could not be read" } }) }, true, "2.2.0", _registry);
        assert(!unreadable.startDefaults, "readOnly: a file that could not be read: no Start with default settings (the next start tries again)");
        assert(!rules.notice({ load: _report({ failure: { id: "2026-11-25-w-everything", error: "x" } }) }, false, "2.2.0", _registry).startDefaults, "readOnly: none while saving works");
        const both = rules.notice({ load: _report({ reset: [{ id: "a", error: "x" }], backup: _backup }) }, true, "2.2.0", _registry);
        assertEqual(both.kind, "readOnly", "readOnly: wins over a reset");
    }

    function _dates() {
        const time = rules.backupTime(_backup);
        assertEqual(time ? time.getTime() : -1, Date.UTC(2026, 0, 15, 10, 29, 3, 120), "date: the stamp read as UTC, with a reason");
        assertEqual(rules.backupTime("config.json.bak-2026-01-15T10-29-03-120Z")?.getTime() ?? -1, Date.UTC(2026, 0, 15, 10, 29, 3, 120), "date: a bare name without a reason");
        assert(rules.backupTime("/c/config.json.bak-later") === null && rules.backupTime("") === null && rules.backupTime(null) === null, "date: no stamp, no time");
        assertEqual(rules.backupDate(_backup), Qt.formatDateTime(new Date(Date.UTC(2026, 0, 15, 10, 29, 3)), "d MMM yyyy, hh:mm"), "date: in words, local time");
        assertEqual(rules.backupDate("nonsense"), "", "date: none for a name without one");
    }

    function _questions() {
        const notice = rules.notice({ load: _report({ reset: [{ id: "2026-11-25-x-music-popup", error: "x" }], backup: _backup }) }, false, "2.2.0", _registry);
        const question = rules.restoreQuestion(notice);
        assertEqual(question.title, "Restore the settings from before the update?", "restore question: the title");
        assertEqual(question.body.join("\n"), "Steps:\n1. Create a new backup\n2. Load the backup of " + rules.backupDate(_backup)
                    + "\n3. Settings update to 2.2.0, skipping music widget presets\n4. Restart the shell", "restore question: the steps");
        assertEqual(question.buttons.map(button => button.id + ":" + button.label).join("|") + "|" + question.cancelLabel, "restore:Restore and restart|Cancel", "restore question: the buttons");
        assertEqual(question.kind, "warning", "restore question: a warning");
        const noParts = rules.restoreQuestion(Object.assign({}, notice, { heldParts: [] }));
        assertEqual(noParts.body[3], "3. Settings update to 2.2.0", "restore question: nothing skipped, nothing named");
        const defaults = rules.defaultsQuestion();
        assertEqual(defaults.title + "\n" + defaults.body.join("\n"), "Start with default settings?\nSteps:\n1. Create a new backup\n2. Start with default settings\n3. Restart the shell", "defaults question: the steps");
        assertEqual(defaults.buttons[0].id, "defaults", "defaults question: its button");
    }

    function _records() {
        assertEqual(rules.restoredRecords(["bar.height", "a-1"], ["2026-11-25-x-music-popup"], "2.2.0").join(","),
                    "bar.height,a-1,held:2026-11-25-x-music-popup@2.2.0", "records: held under this version, the rest kept");
        assertEqual(rules.restoredRecords(["held:2026-11-25-x-music-popup@2.1.0", "held:2026-11-25-z-other@2.1.0"], ["2026-11-25-x-music-popup"], "2.2.0").join(","),
                    "held:2026-11-25-z-other@2.1.0,held:2026-11-25-x-music-popup@2.2.0", "records: an older hold of the same id replaced, another's kept");
        assertEqual(rules.restoredRecords(undefined, ["not an id", 5], "2.2.0").length, 0, "records: nothing that is not an id held");
        // The runner reads them back as held under 2.2.0 only
        const records = rules.restoredRecords([], ["2026-11-25-x-music-popup"], "2.2.0");
        assert(MigrationRules.isHeld("2026-11-25-x-music-popup", records, "2.2.0") && !MigrationRules.isHeld("2026-11-25-x-music-popup", records, "2.3.0"),
               "records: held under this version, not under another");
    }

    function _configs() {
        const restored = rules.restoredConfig('{"profiles":"[]","migratedKeys":["a-1"],"keep":true}', ["2026-11-25-x-music-popup"], "2.2.0");
        const parsed = JSON.parse(restored.text);
        assert(restored.ok && parsed.keep === true && parsed.profiles === "[]", "restored config: the backup's content");
        assertEqual(parsed.migratedKeys.join(","), "a-1,held:2026-11-25-x-music-popup@2.2.0", "restored config: with the holds");
        assert(!rules.restoredConfig("not json", [], "2.2.0").ok && !rules.restoredConfig("[1]", [], "2.2.0").ok && !rules.restoredConfig("", [], "2.2.0").ok,
               "restored config: a backup that is not a settings file refused");
        const defaults = JSON.parse(rules.defaultsConfig([{ migrationId: "2026-11-25-a", scope: ["setting:a.*"] }, { migrationId: "2026-11-25-t", scope: ["setting:bar.*", "file:themes/*.json"] },
                                                          { migrationId: "2026-11-25-b", scope: ["*"] }], "2.2.0"));
        assertEqual(JSON.stringify(defaults), JSON.stringify({ migratedKeys: ["2026-11-25-a", "2026-11-25-b"], writtenBy: "2.2.0" }),
                    "defaults config: the baseline but for the migrations of side files (left to the next start's check), nothing else");
    }

    function _ipc() {
        const reports = { load: _report({ reset: [{ id: "2026-11-25-x-music-popup", error: "broken" }], backup: _backup }), afterSeed: null };
        const report = JSON.parse(rules.reportText(rules.notice(reports, false, "2.2.0", _registry), reports));
        assert(report.failed && report.kind === "reset" && report.parts[0] === "music widget presets" && report.backup === _backup, "report: the notice");
        assertEqual(report.load.reset[0].error, "broken", "report: the run's own report");
        assert(!JSON.parse(rules.reportText(rules.notice({}, false, "2.2.0", []), {})).failed, "report: nothing failed");
    }
}
