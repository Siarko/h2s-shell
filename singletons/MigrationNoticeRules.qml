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
    //   for a file that could not be read or written, which the next start tries again) }. A
    //   report with `restoreUnfinished` (a restore cut short could not be put back: the session
    //   saves nothing) says so in the summary
    function notice(reports, saveBlocked, version, registry) {
        const phases = [reports?.load ?? null, reports?.afterSeed ?? null].filter(report => report !== null && typeof report === "object");
        const reset = [];
        const held = [];
        let backup = "";
        let whole = false;
        let unfinished = false;
        for (const report of phases) {
            if (report.restoreUnfinished === true)
                unfinished = true;
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
        result.summary = unfinished && kind === "readOnly" ? "Restoring settings did not finish" : "Updating settings to " + shown + " failed";
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

    // The notice for module `moduleId`'s last settings migration run, its own beside the
    // core's (the module's backup and records are its own). `name`: its display name ("" when
    // it is gone: the id stands); `report`: ModuleHost.migrationReports[moduleId] (undefined
    // none); `present`: it is installed (a restore needs it).
    // → notice()'s shape, kind "" | "reset", with module: { id, name } and version (the
    //   module's, which the holds name); backup is a module backup's name
    function moduleNotice(moduleId, name, report, present) {
        const result = {
            kind: "", summary: "", body: "", parts: [], held: [], heldParts: [], backup: "", startDefaults: false, key: "",
            module: null, version: ""
        };
        if (typeof moduleId !== "string" || moduleId === "" || report === null || typeof report !== "object")
            return result;
        const reset = _list(report.reset).filter(entry => typeof entry?.id === "string");
        if (reset.length === 0)
            return result;
        const plain = text => String(text).replace(/\s+/g, " ").trim();
        const named = typeof name === "string" && plain(name) !== "" ? plain(name) : moduleId;
        const shown = named.length > 60 ? named.slice(0, 59) + "…" : named;
        const version = typeof report.version === "string" ? plain(report.version).slice(0, 64) : "";
        const entries = reset.concat(_list(report.skipped).filter(entry => typeof entry?.id === "string"));
        const labels = list => {
            const words = [];
            for (const entry of list) {
                const label = plain(partLabel(entry, entry.id)).slice(0, 200);
                if (label !== "" && !words.includes(label))
                    words.push(label);
            }
            return words;
        };
        result.kind = "reset";
        result.module = { id: moduleId, name: shown };
        result.version = version;
        result.summary = "Updating " + shown + " settings" + (version !== "" ? " to " + version : "") + " failed";
        result.body = "Defaults are used where possible. See Settings for details.";
        result.parts = labels(reset);
        result.held = entries.map(entry => entry.id).filter((id, index, all) => all.indexOf(id) === index);
        result.heldParts = labels(entries);
        result.backup = present === true && typeof report.backup === "string" ? report.backup : "";
        result.key = JSON.stringify(["module", moduleId, shown, version, result.parts, result.held, result.backup]);
        return result;
    }

    // A module backup's name ("<version>-YYYYMMDD-HHMMSS", UTC) for people: "15 Jan 2026,
    // 10:29" in local time; "" when the name has no time
    function moduleBackupDate(name) {
        const match = /-(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})(?:-[^/]*)?$/.exec(String(name ?? ""));
        if (!match)
            return "";
        const numbers = match.slice(1, 7).map(Number);
        const time = Date.UTC(numbers[0], numbers[1] - 1, ...numbers.slice(2));
        return isNaN(time) ? "" : Qt.formatDateTime(new Date(time), "d MMM yyyy, hh:mm");
    }

    // The time in a config backup's name (ConfigBackupRules.parseName), a path or a bare
    // name → a Date, or null
    function backupTime(path) {
        const parsed = ConfigBackupRules.parseName(path);
        return parsed.ok ? new Date(parsed.time) : null;
    }

    // A backup named for people: "15 Jan 2026, 10:29" in local time; "" when the name has no time
    function backupDate(path) {
        return ConfigBackupRules.date(path);
    }

    // The question before Restore previous settings: the steps, naming the backup by its date
    // and the parts the settings update skips (held)
    function restoreQuestion(notice) {
        const parts = _list(notice?.heldParts);
        const skipping = parts.length > 0 ? ", skipping " + parts.join(", ") : "";
        if (notice?.module) {
            const name = notice.module.name;
            const shownDate = moduleBackupDate(notice.backup);
            const moduleSteps = ["Create a new backup", "Load the backup of " + (shownDate !== "" ? shownDate : "before the update"),
                                 name + " settings update" + (notice.version !== "" ? " to " + notice.version : "") + skipping, "Restart " + name];
            return { kind: "warning", title: "Restore the settings from before the update?",
                     body: ConfigBackupRules.steps(moduleSteps),
                     buttons: [{ id: "restore", label: "Restore and restart", kind: "warning" }], cancelLabel: "Cancel" };
        }
        const date = backupDate(notice?.backup);
        const update = "Settings update to " + String(notice?.summary ?? "").replace(/^Updating settings to (.*) failed$/, "$1")
            + skipping;
        const steps = ["Create a new backup", "Load the backup of " + (date !== "" ? date : "before the update"), update, "Restart the shell"];
        return { kind: "warning", title: "Restore the settings from before the update?",
                 body: ConfigBackupRules.steps(steps),
                 buttons: [{ id: "restore", label: "Restore and restart", kind: "warning" }], cancelLabel: "Cancel" };
    }

    // The question before Start with default settings (a session that saves nothing)
    function defaultsQuestion() {
        const steps = ["Create a new backup", "Start with default settings", "Restart the shell"];
        return { kind: "warning", title: "Start with default settings?",
                 body: ConfigBackupRules.steps(steps),
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

    // The last runs as IPC tells them: the notice and both reports, and the modules' failed
    // updates (moduleNotice's, those of kind "reset"), as JSON
    function reportText(notice, reports, moduleNotices) {
        const modules = _list(moduleNotices).filter(each => each?.kind === "reset" && each.module).map(each => ({
            id: each.module.id, name: each.module.name, version: each.version, summary: each.summary,
            parts: _list(each.parts), held: _list(each.held), backup: each.backup
        }));
        return JSON.stringify({
            failed: notice?.kind !== "" && notice?.kind !== undefined, kind: notice?.kind ?? "",
            summary: notice?.summary ?? "", parts: _list(notice?.parts), held: _list(notice?.held), backup: notice?.backup ?? "",
            load: reports?.load ?? null, afterSeed: reports?.afterSeed ?? null, modules: modules
        }, null, 2);
    }
}
