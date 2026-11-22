pragma Singleton

import Quickshell
import QtQuick

// The decisions about a module's configuration backups, beside ModuleUpdateRules.backupPlan
// (what a backup holds, where it goes) and backupKeepPlan (which stay): a module's settings
// taken out of the profiles and the pinned globals and put back, what the copying said,
// meta.json written and read, the list of a module's backups, and what a restore does. Pure:
// no file, no process, no clock. Input that cannot be read is unknown: never a backup to
// restore, never settings to write. Checked by tests/ModuleBackupRulesTest.qml.
Singleton {
    id: root

    // The largest settings.json and meta.json read back
    readonly property int maxSettingsBytes: 512 * 1024
    readonly property int maxMetaBytes: 16 * 1024
    // Backup directories of one module read at most (the rest unknown)
    readonly property int maxListed: 64
    // One argument's length when the settings go to a command (argv strings are capped)
    readonly property int chunkLength: 32 * 1024

    function _prefixOk(prefix) {
        return typeof prefix === "string" && /^mod\.[a-z][a-z0-9_-]{0,31}\.$/.test(prefix);
    }

    function _object(value) {
        return value !== null && typeof value === "object" && !Array.isArray(value);
    }

    function _under(source, prefix) {
        const kept = {};
        for (const key of Object.keys(_object(source) ? source : {}))
            if (key.startsWith(prefix))
                kept[key] = source[key];
        return kept;
    }

    // ---- Settings ----

    // A module's settings as stored: every value whose key starts with `prefix`
    // ("mod.<id>."), in each profile (by name) and in the pinned globals.
    // → { ok, problem, profiles: [{ name, set }] (the profiles that set any), globals, count }
    function settingsSnapshot(profiles, globals, prefix) {
        if (!_prefixOk(prefix))
            return { ok: false, problem: "not a module's settings", profiles: [], globals: {}, count: 0 };
        if (!Array.isArray(profiles) || !_object(globals))
            return { ok: false, problem: "the settings could not be read", profiles: [], globals: {}, count: 0 };
        const saved = [];
        let count = 0;
        for (const profile of profiles) {
            const set = _under(profile?.set, prefix);
            const keys = Object.keys(set).length;
            if (keys > 0 && typeof profile?.name === "string") {
                saved.push({ name: profile.name, set: set });
                count += keys;
            }
        }
        const pinned = JSON.parse(JSON.stringify(_under(globals, prefix)));
        count += Object.keys(pinned).length;
        return { ok: true, problem: "", profiles: JSON.parse(JSON.stringify(saved)), globals: pinned, count: count };
    }

    // settings.json's text, and the chunks it goes to a command in (null: too large)
    function settingsText(snapshot) {
        return JSON.stringify({ profiles: snapshot?.profiles ?? [], globals: snapshot?.globals ?? {} });
    }

    function chunks(text) {
        if (typeof text !== "string" || text.length > maxSettingsBytes)
            return null;
        const parts = [];
        for (let at = 0; at < text.length; at += chunkLength)
            parts.push(text.slice(at, at + chunkLength));
        return parts.length > 0 ? parts : [""];
    }

    // settings.json read back. Only keys under `prefix` are taken (a backup never brings
    // another setting in). → { ok, problem, profiles, globals }
    function parseSettings(text, prefix) {
        const refused = problem => ({ ok: false, problem: problem, profiles: [], globals: {} });
        if (!_prefixOk(prefix))
            return refused("not a module's settings");
        if (typeof text !== "string" || text.length > maxSettingsBytes)
            return refused("its settings could not be read");
        let parsed;
        try {
            parsed = JSON.parse(text);
        } catch (error) {
            return refused("its settings are not JSON");
        }
        if (!_object(parsed) || !Array.isArray(parsed.profiles) || !_object(parsed.globals))
            return refused("its settings are not { profiles, globals }");
        const profiles = [];
        for (const profile of parsed.profiles) {
            if (!_object(profile) || typeof profile.name !== "string" || !_object(profile.set))
                return refused("a profile in its settings is malformed");
            if (profiles.some(each => each.name === profile.name))
                return refused("a profile is named twice in its settings");
            profiles.push({ name: profile.name, set: _under(profile.set, prefix) });
        }
        return { ok: true, problem: "", profiles: profiles, globals: _under(parsed.globals, prefix) };
    }

    // The profiles and globals with the module's settings as a backup has them: every value
    // under `prefix` dropped (ProfileRules.withoutPrefix), then the saved ones put back —
    // into the profile of the same name; a profile that no longer exists gets nothing
    // (`missing`, its names). Inputs are not modified.
    // → { ok, problem, profiles, globals, restored, missing }
    function settingsRestored(profiles, globals, prefix, saved) {
        if (!_prefixOk(prefix) || !Array.isArray(profiles) || !_object(globals) || !_object(saved) || !Array.isArray(saved.profiles) || !_object(saved.globals))
            return { ok: false, problem: "the settings could not be read", profiles: [], globals: {}, restored: 0, missing: [] };
        const cleared = ProfileRules.withoutPrefix(profiles, globals, prefix);
        const missing = [];
        let restored = 0;
        for (const each of saved.profiles) {
            const profile = cleared.profiles.find(candidate => candidate?.name === each?.name);
            if (!profile) {
                if (typeof each?.name === "string")
                    missing.push(each.name);
                continue;
            }
            const values = _under(each.set, prefix);
            if (Object.keys(values).length === 0)
                continue;
            profile.set = Object.assign({}, profile.set ?? {}, JSON.parse(JSON.stringify(values)));
            restored += Object.keys(values).length;
        }
        const pinned = _under(saved.globals, prefix);
        restored += Object.keys(pinned).length;
        return { ok: true, problem: "", profiles: cleared.profiles, globals: Object.assign(cleared.globals, JSON.parse(JSON.stringify(pinned))),
                 restored: restored, missing: missing };
    }

    // ---- Taking a backup ----

    // What the copying said, line by line ("store\tok", "store\tabsent", "store\trefused\t<why>",
    // "data\tok|absent\t<path>", "data\trefused\t<path>\t<why>", "done" last).
    // `paths`: the data paths asked for. → { complete, store: "ok"|"absent"|"refused"|"",
    //   data: [{ path, present }], refused: [{ path, why }] } — complete only when every
    //   item was answered and "done" came
    function copyOutcome(lines, paths) {
        const outcome = { complete: false, store: "", data: [], refused: [] };
        const asked = Array.isArray(paths) ? paths : [];
        for (const line of Array.isArray(lines) ? lines : []) {
            const fields = String(line).split("\t");
            if (fields[0] === "done")
                outcome.complete = true;
            else if (fields[0] === "store" && ["ok", "absent", "refused"].includes(fields[1])) {
                outcome.store = fields[1];
                if (fields[1] === "refused")
                    outcome.refused.push({ path: "store", why: ModuleInstallRules._plain(fields[2] ?? "", 120) });
            } else if (fields[0] === "data" && asked.includes(fields[2]) && !outcome.data.some(each => each.path === fields[2])
                       && !outcome.refused.some(each => each.path === fields[2])) {
                if (fields[1] === "refused")
                    outcome.refused.push({ path: fields[2], why: ModuleInstallRules._plain(fields[3] ?? "", 120) });
                else if (fields[1] === "ok" || fields[1] === "absent")
                    outcome.data.push({ path: fields[2], present: fields[1] === "ok" });
            }
        }
        const answered = outcome.data.length + outcome.refused.filter(each => each.path !== "store").length;
        outcome.complete = outcome.complete && outcome.store !== "" && answered === asked.length;
        return outcome;
    }

    // meta.json of a backup taken: backupPlan's meta with what was copied — `store` ("ok":
    // its file is in it, "absent": there was none, "refused": it was there and left out — a
    // link —, so a restore leaves the current one alone), `data` (each named path: whether it was there), `refused`
    // (what was left out, and why). → the object, or null when the copying did not finish
    function takenMeta(plan, outcome) {
        if (!plan?.ok || !outcome?.complete)
            return null;
        return Object.assign({}, plan.meta, {
            includesData: outcome.data.some(each => each.present),
            store: outcome.store,
            data: outcome.data.map(each => ({ path: each.path, present: each.present })),
            refused: outcome.refused.slice()
        });
    }

    // Which backups stay once a new one is in (ModuleUpdateRules.backupKeepPlan), the ones
    // named in `protect` kept whatever their age — the backup a restore is about to read,
    // which the backup taken before the restore must not push out
    function keepPlan(entries, protect) {
        const plan = ModuleUpdateRules.backupKeepPlan(entries);
        const kept = Array.isArray(protect) ? protect : [];
        return { keep: plan.keep.concat(plan.delete.filter(dir => kept.includes(dir))),
                 delete: plan.delete.filter(dir => !kept.includes(dir)), unknown: plan.unknown };
    }

    // ---- Reading backups ----

    // A backup directory's name the shell made ("<version>-<YYYYMMDD-HHMMSS>", perhaps "-2"
    // after it): a plain name, never a staging leftover (".…")
    function validName(name) {
        return typeof name === "string" && name !== "" && !name.startsWith(".") && ModuleInstallRules._versionDirectory(name);
    }

    // meta.json read back for backup `name` of module `id`. → { ok, problem, entry: { name,
    //   version, commit, takenAt, reason, includesData, store ("ok" | "absent" | "refused"),
    //   data: [{ path, present }] } }
    function parseMeta(text, id, name) {
        const refused = problem => ({ ok: false, problem: problem, entry: null });
        if (!validName(name))
            return refused("not a backup's name");
        if (typeof text !== "string" || text === "" || text.length > maxMetaBytes)
            return refused("its meta.json could not be read");
        let meta;
        try {
            meta = JSON.parse(text);
        } catch (error) {
            return refused("its meta.json is not JSON");
        }
        if (!_object(meta) || meta.id !== id)
            return refused("its meta.json is not this module's");
        if (typeof meta.takenAt !== "number" || !Number.isFinite(meta.takenAt))
            return refused("its meta.json has no time");
        if (!ModuleUpdateRules.backupReasons.includes(meta.reason))
            return refused("its meta.json has no reason");
        if (!["ok", "absent", "refused"].includes(meta.store) || !Array.isArray(meta.data))
            return refused("its meta.json does not say what it holds");
        const data = [];
        for (const each of meta.data) {
            if (!_object(each) || typeof each.present !== "boolean" || ModuleUpdateRules._backupPathProblem(each.path) !== ""
                    || ModuleUpdateRules._cleanRelative(each.path) !== each.path || data.some(other => other.path === each.path))
                return refused("its meta.json names a path it cannot hold");
            data.push({ path: each.path, present: each.present });
        }
        if (data.length > ModuleUpdateRules.maxBackupPaths)
            return refused("its meta.json names too many paths");
        return { ok: true, problem: "", entry: {
            name: name, version: ModuleInstallRules._plain(typeof meta.version === "string" ? meta.version : "", ModuleInstallRules.maxVersionLength),
            commit: ModuleUpdateRules._commit(meta.commit), takenAt: meta.takenAt, reason: meta.reason,
            includesData: data.some(each => each.present), store: meta.store, data: data
        } };
    }

    // A module's backups from the lines the listing printed for it: "B\t<name>\t<kind>\t<meta
    // text>" (kind "d" a directory, else a link or a file), "X" for a name that is not plain.
    // `ok`: whether the listing finished. → { ok, backups: [entries, newest first], unknown:
    //   [names] } — a staging leftover, a link, or one whose meta.json cannot be read is
    //   unknown: never listed, never restored, never counted
    function listing(id, rows, ok) {
        const backups = [];
        const unknown = [];
        for (const row of Array.isArray(rows) ? rows : []) {
            if (backups.length + unknown.length >= maxListed)
                break;
            const name = row?.name;
            const parsed = row?.kind === "d" && validName(name) ? parseMeta(row?.meta, id, name) : null;
            if (parsed?.ok)
                backups.push(parsed.entry);
            else
                unknown.push(typeof name === "string" ? ModuleInstallRules._plain(name, 100) : "?");
        }
        backups.sort((first, second) => second.takenAt - first.takenAt || (first.name < second.name ? 1 : -1));
        return { ok: ok === true, backups: backups, unknown: unknown };
    }

    // The listing's lines, by module: "B\t<id>\t<name>\t<kind>\t<meta>", "X\t<id>". → { <id>:
    //   [{ name, kind, meta }] } (names that are not plain kept as "?", unknown)
    function listingRows(lines) {
        const byId = {};
        for (const line of Array.isArray(lines) ? lines : []) {
            const fields = String(line).split("\t");
            const id = fields[1];
            if (!ModuleManifestRules.validId(id) || (fields[0] !== "B" && fields[0] !== "X"))
                continue;
            byId[id] = byId[id] ?? [];
            if (fields[0] === "B")
                byId[id].push({ name: fields[2] ?? "", kind: fields[3] ?? "", meta: fields.slice(4).join("\t") });
            else if (fields[0] === "X")
                byId[id].push({ name: "?", kind: "", meta: "" });
        }
        return byId;
    }

    // ---- Restoring ----

    // Restoring backup `name` of module `id`, as the listing read just now has it.
    // `status`: the host's status of the module (null: not here); `enabled`: whether it is
    // on now. → { ok, problem, entry, enableAfter, store: "put"|"drop"|"keep", data: [{ op
    //   "put"|"drop", path }] } — what the backup held is written back, and what it did not
    //   hold of what it names is removed (the current state is backed up first); a store the
    //   backup left out (refused) is kept as it is; the module
    //   is turned off for it and on again only when it was on
    function restorePlan(id, name, listed, status, enabled) {
        const refused = problem => ({ ok: false, problem: problem, entry: null, enableAfter: false, store: "keep", data: [] });
        if (!ModuleManifestRules.validId(id))
            return refused("Not a module id");
        if (!validName(name))
            return refused("Not a backup's name: " + ModuleInstallRules._plain(String(name ?? ""), 60));
        if (!status)
            return refused("No module \"" + id + "\"");
        if (listed?.ok !== true)
            return refused("the backups of " + id + " could not be read: nothing restored");
        const entry = (listed.backups ?? []).find(each => each.name === name);
        if (!entry)
            return refused((listed.unknown ?? []).includes(name) ? "the backup " + name + " cannot be read: nothing restored"
                                                                 : "No backup " + name + " of " + id);
        return { ok: true, problem: "", entry: entry, enableAfter: enabled === true,
                 store: entry.store === "ok" ? "put" : entry.store === "absent" ? "drop" : "keep",
                 data: entry.data.map(each => ({ op: each.present ? "put" : "drop", path: each.path })) };
    }

    // What a restore's outcome says (lines "ok\t<what>", "fail\t<what>\t<why>", "done").
    // `asked`: how many items were sent. → { complete, problems: [text] }
    function writeOutcome(lines, asked) {
        const problems = [];
        let answered = 0;
        let done = false;
        for (const line of Array.isArray(lines) ? lines : []) {
            const fields = String(line).split("\t");
            if (fields[0] === "done")
                done = true;
            else if (fields[0] === "ok")
                answered++;
            else if (fields[0] === "fail") {
                answered++;
                problems.push(ModuleInstallRules._plain(fields[1] ?? "", 100) + ": " + ModuleInstallRules._plain(fields[2] ?? "", 120));
            }
        }
        if (!done || answered < asked)
            problems.push("not everything was written back");
        return { complete: done && answered >= asked, problems: problems };
    }
}
