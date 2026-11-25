pragma Singleton

import Quickshell
import QtQuick

// What the user is told after a settings update failed at start, and what restoring the
// settings from before it writes. Pure: the last runs' reports (ConfigFile.migrationReports,
// { load, afterSeed }), the registry and the running version in; texts, records and config
// text out. Checked by tests/MigrationNoticeRulesTest.qml.
//
// Two kinds of failure: "reset" — a migration failed, its part was reset to defaults and the
// rest of the run applied (the user keeps the defaults, or restores the backup taken before
// the run with that migration and the ones skipped after it held); "readOnly" — the config
// could not be migrated or written at all (a "*" migration failed, a file could not be
// read or written): the session saves nothing, and the way out is a new config with
// the defaults.
Singleton {
    id: root

    // A list as handed through a `var` property may come as a sequence that is no Array
    function _list(value) {
        if (Array.isArray(value))
            return value;
        return value !== null && typeof value === "object" && typeof value.length === "number" ? Array.from(value) : [];
    }

    // The words for a migration's part: its scopeLabel, else its summary, else its id
    function partLabel(migration, id) {
        for (const text of [migration?.scopeLabel, migration?.summary])
            if (typeof text === "string" && text.trim() !== "")
                return text.trim();
        return typeof id === "string" ? id : "";
    }

    function _labels(ids, registry) {
        const labels = [];
        for (const id of ids) {
            const label = partLabel(_list(registry).find(each => each?.migrationId === id), id);
            if (label !== "" && !labels.includes(label))
                labels.push(label);
        }
        return labels;
    }

    // The notice for the last runs. `reports`: { load, afterSeed } (each null when not run);
    // `saveBlocked`: the session saves nothing (ConfigFile.migrationReadOnly); `version`: the
    // running shell's; `registry`: the migrations, for the parts' words.
    // → { kind: "" | "reset" | "readOnly", key (changes when what is said changes), summary,
    //   body, parts: [label] (the parts reset to defaults), held: [id] (what a restore holds:
    //   the failed migrations and those skipped after them), heldParts: [label], backup (the
    //   backup taken before the first run that wrote one; "" none), startDefaults (a
    //   whole-config ("*") migration failed: Start with default settings is the way out — not
    //   for a file that could not be read or written, which the next start tries again) }
    function notice(reports, saveBlocked, version, registry) {
        const phases = [reports?.load ?? null, reports?.afterSeed ?? null].filter(report => report !== null && typeof report === "object");
        const reset = [];
        const held = [];
        let backup = "";
        let whole = false;
        for (const report of phases) {
            const failed = _list(registry).find(each => each?.migrationId === report.failure?.id && typeof report.failure?.id === "string");
            if (failed && MigrationRules.parseScope(failed.scope).whole)
                whole = true;
            for (const entry of _list(report.reset))
                if (typeof entry?.id === "string" && !reset.includes(entry.id))
                    reset.push(entry.id);
            for (const entry of _list(report.reset).concat(_list(report.skipped)))
                if (typeof entry?.id === "string" && !held.includes(entry.id))
                    held.push(entry.id);
            if (backup === "" && typeof report.backup === "string")
                backup = report.backup;
        }
        const kind = saveBlocked === true ? "readOnly" : reset.length > 0 ? "reset" : "";
        const shown = typeof version === "string" ? version : "";
        const result = {
            kind: kind, summary: "", body: "", parts: [], held: [], heldParts: [], backup: "", startDefaults: false, key: ""
        };
        if (kind === "")
            return result;
        result.summary = "Updating settings to " + shown + " failed";
        if (kind === "readOnly") {
            result.body = "Changes are not saved. See Settings for details.";
            result.startDefaults = whole;
        } else {
            result.body = "Defaults are used where possible. See Settings for details.";
            result.parts = _labels(reset, registry);
            result.held = held;
            result.heldParts = _labels(held, registry);
            result.backup = backup;
        }
        result.key = JSON.stringify([kind, shown, result.parts, result.held, result.backup, result.startDefaults]);
        return result;
    }

    // The time in a config backup's name (config.json.bak-<stamp>[-<reason>], the stamp an
    // ISO time in UTC with ":" and "." as "-"), a path or a bare name → a Date, or null
    function backupTime(path) {
        const name = String(path ?? "").replace(/^.*\//, "");
        const match = /^config\.json\.bak-([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2})-([0-9]{2})-([0-9]{2})-([0-9]{3})Z(-[a-z]+)?$/.exec(name);
        if (!match)
            return null;
        const numbers = match.slice(1, 8).map(Number);
        return new Date(Date.UTC(numbers[0], numbers[1] - 1, numbers[2], numbers[3], numbers[4], numbers[5], numbers[6]));
    }

    // A backup named for people: "15 Jan 2026, 10:29" in local time; "" when the name has no time
    function backupDate(path) {
        const time = backupTime(path);
        return time === null ? "" : Qt.formatDateTime(time, "d MMM yyyy, hh:mm");
    }

    // The question before Restore previous settings: the steps, naming the backup by its date
    // and the parts the settings update skips (held)
    function restoreQuestion(notice) {
        const date = backupDate(notice?.backup);
        const parts = _list(notice?.heldParts);
        const update = "Settings update to " + String(notice?.summary ?? "").replace(/^Updating settings to (.*) failed$/, "$1")
            + (parts.length > 0 ? ", skipping " + parts.join(", ") : "");
        const steps = ["Create a new backup", "Load the backup of " + (date !== "" ? date : "before the update"), update, "Restart the shell"];
        return { kind: "warning", title: "Restore the settings from before the update?",
                 body: ["Steps:"].concat(steps.map((step, index) => (index + 1) + ". " + step)),
                 buttons: [{ id: "restore", label: "Restore and restart", kind: "warning" }], cancelLabel: "Cancel" };
    }

    // The question before Start with default settings (a session that saves nothing)
    function defaultsQuestion() {
        const steps = ["Create a new backup", "Start with default settings", "Restart the shell"];
        return { kind: "warning", title: "Start with default settings?",
                 body: ["Steps:"].concat(steps.map((step, index) => (index + 1) + ". " + step)),
                 buttons: [{ id: "defaults", label: "Start and restart", kind: "warning" }], cancelLabel: "Cancel" };
    }

    // The records a restored backup is written with: its own, with "held:<id>@<version>" for
    // each of `held` (an older hold of the same id replaced), so that those do not run again
    // under this version and run under any other
    function restoredRecords(records, held, version) {
        const kept = _list(records).filter(entry => typeof entry === "string");
        const ids = _list(held).filter(id => MigrationRules.validId(id));
        const result = kept.filter(entry => {
            const record = MigrationRules.parseRecord(entry);
            return !(record.kind === "held" && ids.includes(record.id));
        });
        for (const id of ids)
            result.push("held:" + id + "@" + version);
        return result;
    }

    // The config a restore writes: the backup's text with restoredRecords → { ok, text, problem }
    function restoredConfig(backupText, held, version) {
        let config = null;
        try {
            config = JSON.parse(String(backupText ?? ""));
        } catch (error) {
            config = null;
        }
        if (config === null || typeof config !== "object" || Array.isArray(config))
            return { ok: false, text: "", problem: "the backup is not a settings file" };
        config.migratedKeys = restoredRecords(config.migratedKeys, held, version);
        return { ok: true, text: MigrationRules.configText(config), problem: "" };
    }

    // A new config with the defaults: the registered migrations recorded as done, but for those
    // that reach side files (file: paths): the side files stay as they are, so whether those
    // are migrated is the next start's own check — and the version that wrote it
    function defaultsConfig(registry, version) {
        const reachFiles = migration => MigrationRules.parseScope(migration?.scope).paths.some(path => path.kind === "file");
        return MigrationRules.configText({ migratedKeys: MigrationRules.baseline(_list(registry).filter(migration => !reachFiles(migration)), []), writtenBy: version });
    }

    // The last runs as IPC tells them: the notice and both reports, as JSON
    function reportText(notice, reports) {
        return JSON.stringify({
            failed: notice?.kind !== "" && notice?.kind !== undefined, kind: notice?.kind ?? "",
            summary: notice?.summary ?? "", parts: _list(notice?.parts), held: _list(notice?.held), backup: notice?.backup ?? "",
            load: reports?.load ?? null, afterSeed: reports?.afterSeed ?? null
        }, null, 2);
    }
}
