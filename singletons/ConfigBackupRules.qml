pragma Singleton

import Quickshell
import QtQuick

// The config backups as the Settings list shows them and Apply restores them: a backup's
// name (config.json.bak-<stamp>[-<reason>], the reason a module version switch gives naming
// the module and both versions), the rows (newest first: the date, why it was made, the shell
// version that wrote it, a newer writer marked, an unreadable file shown as such), Apply's
// in-memory preview of the migrations the backup still needs (how many, which fail under this
// version and are held, a whole-config failure), the opened row's line and Apply's question
// as a steps list. Pure: names, texts, the registry and the running version in. Checked by
// tests/ConfigBackupRulesTest.qml.
Singleton {
    id: root

    // Why a config backup was made, the last part of its name: before a migration run, the
    // current config before a restore, before a module version switch, made by the user
    readonly property var reasons: ["migration", "restore", "module", "manual"]

    // A backup larger than this is not read for the list (a settings file is far smaller)
    readonly property real maxBackupBytes: 4 * 1024 * 1024

    readonly property string _prefix: "config.json.bak-"
    readonly property var _namePattern: /^config\.json\.bak-([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2})-([0-9]{2})-([0-9]{2})-([0-9]{3})Z(?:-(migration|restore|manual)|-(module)(?:~([a-z][a-z0-9_-]{0,31})~([A-Za-z0-9._+-]{1,40})~([A-Za-z0-9._+-]{1,40}))?)?$/
    readonly property var _versionPattern: /^[A-Za-z0-9._+-]{1,40}$/

    function _list(value) {
        if (Array.isArray(value))
            return value;
        return value !== null && typeof value === "object" && typeof value.length === "number" ? Array.from(value) : [];
    }

    // A backup's name for the time `isoTime` (Date.toISOString()) and `reason` (one of
    // `reasons`, else none); `module` ({ id, from, to }) names a "module" backup's module and
    // versions — left out when any part is not one. "" for a time that is not one
    function name(isoTime, reason, module) {
        if (typeof isoTime !== "string" || !/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$/.test(isoTime))
            return "";
        let suffix = reasons.includes(reason) ? "-" + reason : "";
        if (reason === "module" && typeof module?.id === "string" && ModuleRules.idPattern.test(module.id)
                && _versionPattern.test(String(module?.from ?? "")) && _versionPattern.test(String(module?.to ?? "")))
            suffix += "~" + module.id + "~" + module.from + "~" + module.to;
        return _prefix + isoTime.replace(/[:.]/g, "-") + suffix;
    }

    // A config backup's name (a bare name, or a path: its last part) → { ok, name, time (ms
    // since the epoch, UTC), reason ("" none recorded), module: { id, from, to } | null }.
    // Only names of the exact pattern are backups; every other file in the folder is not
    function parseName(path) {
        const name = String(path ?? "").replace(/^.*\//, "");
        const match = _namePattern.exec(name);
        if (!match)
            return { ok: false, name: name, time: 0, reason: "", module: null };
        const numbers = match.slice(1, 8).map(Number);
        const time = Date.UTC(numbers[0], numbers[1] - 1, numbers[2], numbers[3], numbers[4], numbers[5], numbers[6]);
        const reason = match[8] ?? match[9] ?? "";
        const module = match[10] !== undefined ? { id: match[10], from: match[11], to: match[12] } : null;
        return { ok: true, name: name, time: time, reason: reason, module: module };
    }

    // A backup named for people: "15 Jan 2026, 10:29" in local time; "" when the name has no time
    function date(path) {
        const parsed = parseName(path);
        return parsed.ok ? Qt.formatDateTime(new Date(parsed.time), "d MMM yyyy, hh:mm") : "";
    }

    // Why it was made, in words. `moduleName`: the display name of a module switch's module
    // ("" when it is gone: its id stands); a switch to an older version is a way back
    function reasonText(parsed, moduleName) {
        switch (parsed?.reason) {
        case "migration": return "Before a settings update";
        case "restore": return "Before a restore";
        case "manual": return "Made by you";
        case "module": {
            if (!parsed.module)
                return "Before a module update";
            const name = ModuleInstallRules._plain(typeof moduleName === "string" ? moduleName : "", 60) || parsed.module.id;
            const back = ModuleUpdateRules.compareVersions(parsed.module.to, parsed.module.from) === -1;
            return (back ? "Before going back: " : "Before updating ") + name + " " + parsed.module.from + " → " + parsed.module.to;
        }
        default: return "Older backup, reason not recorded";
        }
    }

    // The one line a backup written by a newer shell carries (MigrationRules.newerConfig's
    // answer); "" when it is not newer
    function newerLine(newer) {
        if (!newer?.newer)
            return "";
        const writtenBy = typeof newer.writtenBy === "string" ? newer.writtenBy : "";
        return "Written by " + (writtenBy !== "" && newer.byVersion !== false ? "shell " + writtenBy : "a newer shell")
            + " (newer than current) — may be incompatible, expect odd behaviour";
    }

    // config.json's text parsed → the object, or null when it is not a settings file
    function _parsed(text) {
        let config = null;
        try {
            config = JSON.parse(String(text ?? ""));
        } catch (error) {
            config = null;
        }
        return config !== null && typeof config === "object" && !Array.isArray(config) ? config : null;
    }

    // The list's rows. `entries`: [{ name, text, readable, tooLarge }] — each file in the
    // config's folder with its content (`readable` false: it could not be read; `tooLarge`: over
    // maxBackupBytes, not read); `version` the running shell's; `registry` the migrations (a
    // newer writer by its records); `moduleNames` { id: display name } of the modules there now.
    // Names that are no backup are left out; a backup that cannot be read or is not a settings
    // file stays, as such. Newest first; equal times by name, the same each time.
    // → [{ key, name, time, date, reason, reasonText, module, kept, readable, writtenBy,
    //   versionText, newer, newerLine }]
    function rows(entries, version, registry, moduleNames) {
        const names = moduleNames !== null && typeof moduleNames === "object" ? moduleNames : {};
        const result = [];
        for (const entry of _list(entries)) {
            const parsed = parseName(entry?.name);
            if (!parsed.ok)
                continue;
            const tooLarge = entry?.tooLarge === true;
            const config = entry?.readable === false || tooLarge ? null : _parsed(entry?.text);
            const moduleName = parsed.module && Object.prototype.hasOwnProperty.call(names, parsed.module.id) ? names[parsed.module.id] : "";
            const writtenBy = typeof config?.writtenBy === "string" ? config.writtenBy : "";
            const newer = config ? MigrationRules.newerConfig(config.writtenBy, config.migratedKeys, version, registry) : { newer: false };
            const byVersion = writtenBy !== "" && ModuleUpdateRules.compareVersions(writtenBy, version) === 1;
            result.push({
                key: parsed.name, name: parsed.name, time: parsed.time, date: date(parsed.name),
                reason: parsed.reason, reasonText: reasonText(parsed, moduleName), module: parsed.module,
                kept: parsed.reason === "manual", readable: config !== null, writtenBy: writtenBy,
                versionText: tooLarge ? "too large" : config === null ? "can't be read" : writtenBy !== "" ? writtenBy : "version unknown",
                newer: newer.newer === true,
                newerLine: newerLine({ newer: newer.newer, writtenBy: writtenBy, byVersion: byVersion })
            });
        }
        // Names in one folder differ: equal times need no "equal" answer
        return result.sort((first, second) => first.time !== second.time ? second.time - first.time : first.name < second.name ? 1 : -1);
    }

    // What Apply would do with the backup's `text`, run in memory: its migrations still
    // pending under this version (the records it holds decide, as at start), the ones that fail
    // now — held when it is written, with those skipped after them, as the failure notice's
    // restore does — and a whole-config failure (the shell would start read-only). Side files
    // are not read: the preview is the config's; the start runs on the files as they are then.
    // → { ok, problem, updates (how many run), held: [id], heldParts: [label], failing: [label],
    //   readOnly, newer }
    function preview(registry, text, version) {
        const answer = { ok: false, problem: "", updates: 0, held: [], heldParts: [], failing: [], readOnly: false, newer: false };
        const config = _parsed(text);
        if (config === null) {
            answer.problem = "the backup is not a settings file";
            return answer;
        }
        const all = _list(registry);
        answer.newer = MigrationRules.newerConfig(config.writtenBy, config.migratedKeys, version, all).newer;
        answer.ok = true;
        const parsed = MigrationRules.documentOf(config, {});
        if (!parsed.ok) {
            answer.readOnly = true;
            return answer;
        }
        // A new config records the baseline at start: nothing runs
        if (MigrationRules.isNewConfig(config, all, {}))
            return answer;
        const ofConfig = all.filter(migration => !MigrationRules.appliedBefore(migration, config));
        answer.updates = MigrationRules.pending(ofConfig, parsed.records)
            .filter(migration => !MigrationRules.isHeld(migration?.migrationId, parsed.records, version)).length;
        const run = MigrationRules.run(ofConfig, parsed.document, { records: parsed.records, version: version, context: { version: version } });
        if (run.readOnly) {
            answer.readOnly = true;
            return answer;
        }
        const label = id => MigrationNoticeRules.partLabel(all.find(each => each?.migrationId === id), id);
        for (const entry of _list(run.reset)) {
            answer.held.push(entry.id);
            if (!answer.failing.includes(label(entry.id)))
                answer.failing.push(label(entry.id));
        }
        for (const entry of _list(run.skipped))
            if (!answer.held.includes(entry.id))
                answer.held.push(entry.id);
        for (const id of answer.held)
            if (!answer.heldParts.includes(label(id)))
                answer.heldParts.push(label(id));
        return answer;
    }

    // The opened row's line: what Apply would do
    function previewText(preview, version) {
        if (!preview?.ok)
            return "Can't be read.";
        const count = preview.newer ? 0 : Number(preview.updates) || 0;
        let text = "Apply: " + (count === 0 ? "No settings updates are needed."
                                            : count + (count === 1 ? " settings update brings" : " settings updates bring") + " it up to " + version + ".");
        if (!preview.newer && _list(preview.failing).length > 0)
            text += " Fails for: " + _list(preview.failing).join(", ") + ".";
        if (preview.readOnly)
            text += " The shell would start read-only with it.";
        return text;
    }

    // A question's steps, numbered: "Steps:" and one line each
    function steps(list) {
        return ["Steps:"].concat(_list(list).map((step, index) => (index + 1) + ". " + step));
    }

    // Apply's question for `row` (rows'), with its `preview`: the reason and version (a newer
    // backup: its line, in bold), then the steps — the settings update only for a backup this
    // version updates, naming the parts it skips. `subject`: the backup and what is held,
    // what the answer acts on
    function applyQuestion(row, preview, version) {
        const newer = row?.newer === true || preview?.newer === true;
        const body = newer ? [{ text: "⚠ " + (row?.newerLine || newerLine({ newer: true })), strong: true }]
                           : [String(row?.reasonText ?? "") + " · " + String(row?.versionText ?? "")];
        if (preview?.readOnly)
            body.push({ text: "⚠ The shell would start read-only with this backup", strong: true });
        const list = ["Create a new backup", "Load the selected backup"];
        const parts = _list(preview?.heldParts);
        if (!newer && Number(preview?.updates) > 0)
            list.push("Settings update to " + version + (parts.length > 0 ? ", skipping " + parts.join(", ") : ""));
        list.push("Restart the shell");
        return {
            kind: "warning",
            title: newer ? "Load a backup from a newer shell?" : "Apply the backup of " + String(row?.date ?? "") + "?",
            body: body.concat(steps(list)),
            buttons: [{ id: "apply", label: "Apply and restart", kind: "warning" }],
            cancelLabel: "Cancel",
            subject: { name: String(row?.name ?? ""), held: _list(preview?.held).slice() }
        };
    }

    // The list as IPC tells it: whether it was read, and the rows, as JSON
    function listText(known, rows) {
        return JSON.stringify({ known: known === true, backups: _list(rows).map(row => ({
            name: row.name, date: row.date, reason: row.reason, reasonText: row.reasonText, module: row.module,
            kept: row.kept, readable: row.readable, writtenBy: row.writtenBy, newer: row.newer
        })) }, null, 2);
    }
}
