pragma Singleton

import Quickshell

// A module's settings migrations (API 1.43), beside MigrationRules (the core's): the
// manifest's `migrations` list read and checked, a module migration's scope — confined to
// the module's own part, its settings (mod.<id>.* in every profile and the pinned globals)
// and its store, never anything else —, its records in Config.migratedKeys, and running a
// module's pending migrations in order on its part with the core's per-scope failure model:
// a failed migration's scope reset (its settings keys and store keys removed: defaults), its
// later dependents skipped, the independent ones run. A module's whole part can always be
// reset on its own, so a failing "*" migration resets that part — never the strict
// whole-config outcome. Pure: no file, no process, no clock. Checked by
// tests/ModuleMigrationRulesTest.qml.
//
// THE MANIFEST FIELD — "migrations": an ordered list, each
//   { "id": "taildrop-folder", "since": "0.8.0", "file": "migrations/TaildropFolder.qml",
//     "scope": ["setting:taildrop.*", "store:folders"] }
//   id     ^[a-z0-9]+(-[a-z0-9]+)*$, at most maxIdLength; once in the list
//   since  the module version it first ships in (the manifest's version form), not newer
//          than the module's version, not older than the one before it (where both read as
//          semver)
//   file   a .qml file inside the module's directory
//   scope  optional, the paths it reads and writes: "setting:<name>" and
//          "setting:<prefix>.*" — the module's settings, written without "mod.<id>." (the
//          host adds it), "store:<key>" — a key of its store, or "*" — its whole part (all
//          its settings and its store), which stands alone. Omitted: "*".
// A malformed list or entry fails the module: a migration skipped would leave the data in a
// shape its code no longer reads, and the later ones would run on a guess.
//
// THE PART a module's migrations run on: { settings: { profiles: [{ name, set }], globals },
// store } — every profile by name with the module's keys (full keys, "mod.<id>.<name>"), the
// pinned ones, the store's object. A migration: { migrationId, scope (the manifest's list),
// migrate(part, context) → part }, handed only its scope's projection; a result with a key
// outside the scope (so outside mod.<id>.* and the store) is its failure.
//
// RECORDS (strings in migratedKeys, as the core's): "mod.<id>/<mid>" applied,
// "reset:mod.<id>/<mid>" failed with its scope reset (counts as applied),
// "held:mod.<id>/<mid>@<module version>" not run while the module's version is that one.
// Removed with the module when its data and settings are deleted (withoutModuleRecords).
Singleton {
    id: root

    readonly property int maxIdLength: 64
    readonly property int maxScopePaths: 32

    function _object(value) {
        return value !== null && typeof value === "object" && !Array.isArray(value);
    }

    function _put(object, key, value) {
        Object.defineProperty(object, key, { value: value, enumerable: true, writable: true, configurable: true });
    }

    function _copy(value) {
        return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
    }

    function _moduleIdOk(moduleId) {
        return typeof moduleId === "string" && ModuleRules.idPattern.test(moduleId);
    }

    // ---- Ids and records ----

    function validId(id) {
        return typeof id === "string" && id.length <= maxIdLength && /^[a-z0-9]+(-[a-z0-9]+)*$/.test(id);
    }

    // The record of module `moduleId`'s migration `id`: "mod.<id>/<mid>"
    function recordOf(moduleId, id) {
        return "mod." + moduleId + "/" + id;
    }

    // One entry of migratedKeys, as module `moduleId`'s → { kind: "applied" | "reset" |
    // "held" | "other", id, version } — "other" for anything not this module's
    function parseRecord(moduleId, entry) {
        const other = { kind: "other", id: "", version: "" };
        if (typeof entry !== "string" || !_moduleIdOk(moduleId))
            return other;
        const prefix = "mod." + moduleId + "/";
        const own = text => text.startsWith(prefix) && validId(text.slice(prefix.length)) ? text.slice(prefix.length) : "";
        if (entry.startsWith("reset:")) {
            const id = own(entry.slice(6));
            return id !== "" ? { kind: "reset", id: id, version: "" } : other;
        }
        const held = /^held:([^@]+)@(.+)$/.exec(entry);
        if (held) {
            const id = own(held[1]);
            return id !== "" ? { kind: "held", id: id, version: held[2] } : other;
        }
        const id = own(entry);
        return id !== "" ? { kind: "applied", id: id, version: "" } : other;
    }

    function _records(records) {
        return Array.isArray(records) ? records.filter(entry => typeof entry === "string") : [];
    }

    // The module's records among `records`, and `records` without them (the module removed
    // with its data and settings: its records go with them)
    function moduleRecords(moduleId, records) {
        return _records(records).filter(entry => parseRecord(moduleId, entry).kind !== "other");
    }

    function withoutModuleRecords(moduleId, records) {
        return _records(records).filter(entry => parseRecord(moduleId, entry).kind === "other");
    }

    function isDone(moduleId, id, records) {
        return _records(records).some(entry => {
            const record = parseRecord(moduleId, entry);
            return (record.kind === "applied" || record.kind === "reset") && record.id === id;
        });
    }

    function isHeld(moduleId, id, records, version) {
        return _records(records).some(entry => {
            const record = parseRecord(moduleId, entry);
            return record.kind === "held" && record.id === id && record.version === version;
        });
    }

    // The module's migrations not done, in their order (held ones included: run() holds them)
    function pending(moduleId, migrations, records) {
        return (Array.isArray(migrations) ? migrations : []).filter(migration => !isDone(moduleId, migration?.migrationId, records));
    }

    // A first install with no settings of its own: every migration recorded, none run
    function baseline(moduleId, migrations, records) {
        const kept = _records(records);
        if (!_moduleIdOk(moduleId))
            return kept;
        for (const migration of Array.isArray(migrations) ? migrations : [])
            if (validId(migration?.migrationId) && !isDone(moduleId, migration.migrationId, kept))
                kept.push(recordOf(moduleId, migration.migrationId));
        return kept;
    }

    // ---- Scopes ----

    // A name of the module's settings, as written in a scope: without "mod.<id>." — one that
    // starts with "mod." would land under mod.<id>.mod.…, never where it was meant
    function _settingName(text) {
        return typeof text === "string" && /^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)*$/.test(text) && text !== "mod" && !text.startsWith("mod.");
    }

    function _storeKey(text) {
        return typeof text === "string" && text !== "" && text !== "*" && text !== "__proto__" && text.length <= 128;
    }

    // One scope path of module `moduleId` → { kind: "whole" } | { kind: "setting", key, prefix }
    // (full keys: "mod.<id>.<name>", or a prefix "mod.<id>.<prefix>.") | { kind: "store", key }
    // | null
    function parsePath(moduleId, text) {
        if (!_moduleIdOk(moduleId) || typeof text !== "string" || text.length > 200)
            return null;
        if (text === "*")
            return { kind: "whole" };
        const own = "mod." + moduleId + ".";
        if (text.startsWith("setting:")) {
            const rest = text.slice(8);
            if (rest.endsWith(".*") && _settingName(rest.slice(0, -2)))
                return { kind: "setting", key: "", prefix: own + rest.slice(0, -1) };
            return _settingName(rest) ? { kind: "setting", key: own + rest, prefix: "" } : null;
        }
        if (text.startsWith("store:"))
            return _storeKey(text.slice(6)) ? { kind: "store", key: text.slice(6) } : null;
        return null;
    }

    // A migration's scope (the manifest's list; undefined: "*") → { ok, problem, whole, paths }
    function parseScope(moduleId, scope) {
        const refused = problem => ({ ok: false, problem: problem, whole: false, paths: [] });
        if (scope === undefined)
            return { ok: true, problem: "", whole: true, paths: [{ kind: "whole" }] };
        if (!Array.isArray(scope) || scope.length === 0)
            return refused("the scope is not a list of paths");
        if (scope.length > maxScopePaths)
            return refused("the scope has more than " + maxScopePaths + " paths");
        const paths = [];
        for (const text of scope) {
            const path = parsePath(moduleId, text);
            if (!path)
                return refused("not a scope path: " + ModuleRules.show(text)
                               + " (setting:<name>, setting:<prefix>.* without mod." + moduleId + ", store:<key> or *)");
            paths.push(path);
        }
        const whole = paths.some(path => path.kind === "whole");
        if (whole && paths.length > 1)
            return refused("\"*\" stands alone");
        return { ok: true, problem: "", whole: whole, paths: paths };
    }

    function _settingMatches(key, path) {
        return path.key !== "" ? key === path.key : key.startsWith(path.prefix);
    }

    // A setting key in scope: always one of the module's own; "*" takes every one of them
    function _settingIn(moduleId, key, scope) {
        if (!ModuleManifestRules.isOwnSettingKey(moduleId, key))
            return false;
        return scope.whole || scope.paths.some(path => path.kind === "setting" && _settingMatches(key, path));
    }

    function _storeIn(key, scope) {
        return scope.whole || scope.paths.some(path => path.kind === "store" && path.key === key);
    }

    function pathsOverlap(first, second) {
        if (first.kind === "whole" || second.kind === "whole")
            return true;
        if (first.kind !== second.kind)
            return false;
        if (first.kind === "store")
            return first.key === second.key;
        if (first.key !== "" && second.key !== "")
            return first.key === second.key;
        if (first.key !== "")
            return first.key.startsWith(second.prefix);
        if (second.key !== "")
            return second.key.startsWith(first.prefix);
        return first.prefix.startsWith(second.prefix) || second.prefix.startsWith(first.prefix);
    }

    // Two parsed scopes overlap; an unreadable scope overlaps everything
    function scopesOverlap(first, second) {
        if (!first?.ok || !second?.ok)
            return true;
        return first.paths.some(a => second.paths.some(b => pathsOverlap(a, b)));
    }

    // ---- The manifest ----

    // The manifest's `migrations` (its raw value; undefined: none), for module `moduleId` at
    // version `moduleVersion` → { migrations: [{ id, since, file, scope }], errors } — any
    // error fails the module, and then no migration is kept
    function readMigrations(value, moduleId, moduleVersion) {
        const errors = [];
        const failed = () => ({ migrations: [], errors: errors });
        if (value === undefined)
            return { migrations: [], errors: [] };
        if (!Array.isArray(value)) {
            errors.push("migrations: not a list");
            return failed();
        }
        if (value.length > ModuleRules.maxEntries) {
            errors.push("migrations: " + value.length + " entries, at most " + ModuleRules.maxEntries);
            return failed();
        }
        const known = ["id", "since", "file", "scope"];
        const migrations = [];
        let previous = "";
        value.forEach((entry, index) => {
            const where = "migrations[" + index + "]";
            if (!_object(entry)) {
                errors.push(where + ": not an object");
                return;
            }
            const unknown = Object.keys(entry).find(key => !known.includes(key));
            if (unknown !== undefined) {
                errors.push(where + ": unknown field " + ModuleRules.show(unknown));
                return;
            }
            const id = ModuleRules.get(entry, "id");
            if (!validId(id)) {
                errors.push(where + ": id " + ModuleRules.show(id) + " is not a migration id (lowercase letters and digits in words joined by -, at most " + maxIdLength + ")");
                return;
            }
            if (migrations.some(migration => migration.id === id)) {
                errors.push(where + ": id " + ModuleRules.show(id) + " is listed twice");
                return;
            }
            const since = ModuleRules.get(entry, "since");
            if (typeof since !== "string" || !/^[0-9A-Za-z][0-9A-Za-z.+~-]{0,63}$/.test(since)) {
                errors.push(where + ": since " + ModuleRules.show(since) + " is not a version");
                return;
            }
            if (ModuleUpdateRules.compareVersions(since, moduleVersion) === 1) {
                errors.push(where + ": since " + since + " is newer than the module's version " + moduleVersion);
                return;
            }
            if (previous !== "" && ModuleUpdateRules.compareVersions(since, previous) === -1) {
                errors.push(where + ": since " + since + " is older than the migration before it (" + previous + ")");
                return;
            }
            const file = ModuleRules.get(entry, "file");
            const fileProblem = ModuleFileRules.pathProblem(file);
            if (fileProblem !== "") {
                errors.push(where + ": file " + ModuleRules.show(file) + ": " + fileProblem);
                return;
            }
            const scopeValue = ModuleRules.get(entry, "scope");
            const scope = parseScope(moduleId, scopeValue);
            if (!scope.ok) {
                errors.push(where + ": " + scope.problem);
                return;
            }
            previous = since;
            migrations.push({ id: id, since: since, file: file, scope: scopeValue === undefined ? ["*"] : scopeValue.slice() });
        });
        return errors.length > 0 ? failed() : { migrations: migrations, errors: [] };
    }

    // ---- The part ----

    // Module `moduleId`'s part out of the core's profiles and pinned globals and its store →
    // { ok, problem, part }: every profile by name with the module's keys only
    function partOf(moduleId, profiles, globals, store) {
        const refused = problem => ({ ok: false, problem: problem, part: null });
        if (!_moduleIdOk(moduleId))
            return refused("not a module id");
        if (!Array.isArray(profiles) || profiles.some(profile => !_object(profile) || typeof profile.name !== "string") || !_object(globals))
            return refused("the settings could not be read");
        if (store !== undefined && !_object(store))
            return refused("the store could not be read");
        const own = set => {
            const kept = {};
            for (const key of Object.keys(_object(set) ? set : {}))
                if (ModuleManifestRules.isOwnSettingKey(moduleId, key))
                    _put(kept, key, _copy(set[key]));
            return kept;
        };
        return { ok: true, problem: "", part: { settings: { profiles: profiles.map(profile => ({ name: profile.name, set: own(profile.set) })),
                                                            globals: own(globals) },
                                                store: _copy(store ?? {}) } };
    }

    // What a migration with scope `scope` (parsed) is handed: only the keys it names, a copy
    function projection(moduleId, part, scope) {
        const settings = set => {
            const kept = {};
            for (const key of Object.keys(set))
                if (_settingIn(moduleId, key, scope))
                    _put(kept, key, _copy(set[key]));
            return kept;
        };
        const store = {};
        for (const key of Object.keys(part.store))
            if (_storeIn(key, scope))
                _put(store, key, _copy(part.store[key]));
        return { settings: { profiles: part.settings.profiles.map(profile => ({ name: profile.name, set: settings(profile.set) })),
                             globals: settings(part.settings.globals) },
                 store: store };
    }

    // The problem with a migration's result, "" when it is a part inside the scope: the same
    // profiles (by count and name), every setting key the module's own and in scope, every
    // store key in scope
    function resultProblem(moduleId, result, handed, scope) {
        if (!_object(result) || !_object(result.settings) || !_object(result.store))
            return "it returned no settings and store";
        if (Object.keys(result).some(key => key !== "settings" && key !== "store")
                || Object.keys(result.settings).some(key => key !== "profiles" && key !== "globals"))
            return "it returned a part no module part has";
        const profiles = result.settings.profiles;
        if (!Array.isArray(profiles) || !_object(result.settings.globals)
                || profiles.some(profile => !_object(profile) || typeof profile.name !== "string" || !_object(profile.set)
                                            || Object.keys(profile).some(key => key !== "name" && key !== "set")))
            return "it returned malformed settings";
        if (profiles.length !== handed.settings.profiles.length || profiles.some((profile, i) => profile.name !== handed.settings.profiles[i].name))
            return "it added, removed or renamed a profile";
        for (const set of profiles.map(profile => profile.set).concat([result.settings.globals])) {
            const outside = Object.keys(set).find(key => !_settingIn(moduleId, key, scope));
            if (outside !== undefined)
                return "it wrote setting " + outside + " outside its scope";
        }
        const outsideStore = Object.keys(result.store).find(key => !_storeIn(key, scope));
        if (outsideStore !== undefined)
            return "it wrote store key " + outsideStore + " outside its scope";
        return "";
    }

    // The part without what `scope` names: a failed migration's reset (its settings keys and
    // store keys removed — defaults), and the base its result is merged into
    function withoutScope(moduleId, part, scope) {
        const result = _copy(part);
        const clear = set => {
            for (const key of Object.keys(set))
                if (_settingIn(moduleId, key, scope))
                    delete set[key];
        };
        for (const profile of result.settings.profiles)
            clear(profile.set);
        clear(result.settings.globals);
        for (const key of Object.keys(result.store))
            if (_storeIn(key, scope))
                delete result.store[key];
        return result;
    }

    function _merged(moduleId, part, result, scope) {
        const merged = withoutScope(moduleId, part, scope);
        result.settings.profiles.forEach((profile, i) => {
            for (const key of Object.keys(profile.set))
                _put(merged.settings.profiles[i].set, key, profile.set[key]);
        });
        for (const key of Object.keys(result.settings.globals))
            _put(merged.settings.globals, key, result.settings.globals[key]);
        for (const key of Object.keys(result.store))
            _put(merged.store, key, result.store[key]);
        return merged;
    }

    // One migration on the part → { ok, error, part } — not ok when its scope is unreadable,
    // it has no migrate function, throws, or returns something outside its scope (the part
    // then the input)
    function applyOne(moduleId, migration, part, context) {
        const scope = parseScope(moduleId, migration?.scope);
        const failed = error => ({ ok: false, error: error, part: part });
        if (!scope.ok)
            return failed("its scope is unreadable: " + scope.problem);
        if (typeof migration.migrate !== "function")
            return failed("it has no migrate function");
        const handed = projection(moduleId, part, scope);
        let result;
        try {
            result = _copy(migration.migrate(_copy(handed), _copy(context ?? {})));
        } catch (error) {
            return failed("it failed: " + String(error?.message ?? error).slice(0, 300));
        }
        const problem = resultProblem(moduleId, result, handed, scope);
        if (problem !== "")
            return failed(problem);
        return { ok: true, error: "", part: _merged(moduleId, part, result, scope) };
    }

    // ---- What the host does with a run ----

    // A first install with no settings of its own: no record of the module's, and its part
    // (partOf's) holds no setting and no store key — then every migration is recorded, none
    // run (defaults are current by definition)
    function isFresh(moduleId, part, records) {
        if (!_moduleIdOk(moduleId) || !_object(part) || !_object(part.settings) || !_object(part.store))
            return false;
        if (moduleRecords(moduleId, records).length > 0)
            return false;
        const empty = set => _object(set) && Object.keys(set).length === 0;
        return (part.settings.profiles ?? []).every(profile => empty(profile?.set)) && empty(part.settings.globals)
            && Object.keys(part.store).length === 0;
    }

    // Whether a run's write needs a module backup first: something changed or a scope was
    // reset — not when only records are written (a baseline, a hold dropped), nor right after
    // the backup a version switch took (`switchBackup`)
    function backupNeeded(report, switchBackup) {
        if (!report?.write || switchBackup === true)
            return false;
        return report.changed === true || (Array.isArray(report.reset) && report.reset.length > 0);
    }

    // The store's changes from `before` to `after` (both objects): [{ key, value }] — value
    // undefined for a key removed; unchanged keys left out
    function storeChanges(before, after) {
        const changes = [];
        const old = _object(before) ? before : {};
        const next = _object(after) ? after : {};
        for (const key of Object.keys(old))
            if (!Object.prototype.hasOwnProperty.call(next, key))
                changes.push({ key: key, value: undefined });
        for (const key of Object.keys(next))
            if (!Object.prototype.hasOwnProperty.call(old, key) || MigrationRules.canonical(old[key]) !== MigrationRules.canonical(next[key]))
                changes.push({ key: key, value: _copy(next[key]) });
        return changes;
    }

    // A migration's summary as its file declares it, for the log and the failure notice: one
    // line of plain text, at most 200 characters ("" when it declares none)
    function summaryOf(value) {
        return typeof value === "string" ? ModuleInstallRules._plain(value, 200) : "";
    }

    // ---- The run ----

    // Module `moduleId`'s pending migrations run in their order on `part` (partOf's).
    // `options`: { records (all of migratedKeys), version (the module's running version),
    // fresh (a first install with no settings of its own: the baseline, nothing run), context
    // ({ fromVersion, toVersion }, handed to each) }.
    // A failed migration X: the ones before stay applied, X's result is discarded and its
    // scope removed from the part ("*" or an unreadable scope: the whole part), X recorded as
    // "reset:mod.<id>/<mid>"; the later ones whose scopes overlap X's, transitively through
    // those skipped, are skipped (not recorded: pending again next time); the independent
    // ones run. A held one is not run, and its dependents are skipped the same way. Records
    // of anything but this module are kept as they are.
    // → { write, changed, part, records, applied: [id], reset: [{ id, error }],
    //   skipped: [{ id, after }], held: [id] }
    function run(moduleId, migrations, part, options) {
        const records = _records(options?.records);
        const version = typeof options?.version === "string" ? options.version : "";
        const report = { write: false, changed: false, part: part, records: records, applied: [], reset: [], skipped: [], held: [] };
        if (!_moduleIdOk(moduleId))
            return report;
        if (options?.fresh === true) {
            report.records = baseline(moduleId, migrations, records);
            report.write = report.records.length !== records.length;
            return report;
        }
        let current = part;
        const nextRecords = records.slice();
        const blocked = [];
        const record = (id, entry) => {
            for (let i = nextRecords.length - 1; i >= 0; i--) {
                const old = parseRecord(moduleId, nextRecords[i]);
                if (old.kind === "held" && old.id === id)
                    nextRecords.splice(i, 1);
            }
            nextRecords.push(entry);
        };
        for (const migration of pending(moduleId, migrations, records)) {
            const id = migration?.migrationId;
            if (!validId(id))
                continue;
            const scope = parseScope(moduleId, migration?.scope);
            const blocker = blocked.find(each => scopesOverlap(each.scope, scope));
            if (isHeld(moduleId, id, records, version)) {
                report.held.push(id);
                blocked.push({ id: id, scope: scope });
                continue;
            }
            if (blocker) {
                report.skipped.push({ id: id, after: blocker.id });
                blocked.push({ id: id, scope: scope });
                continue;
            }
            const outcome = applyOne(moduleId, migration, current, options?.context);
            if (outcome.ok) {
                current = outcome.part;
                report.applied.push(id);
                record(id, recordOf(moduleId, id));
                continue;
            }
            current = withoutScope(moduleId, current, scope.ok ? scope : parseScope(moduleId, undefined));
            report.reset.push({ id: id, error: outcome.error });
            record(id, "reset:" + recordOf(moduleId, id));
            blocked.push({ id: id, scope: scope });
        }
        report.part = current;
        report.records = nextRecords;
        report.changed = MigrationRules.canonical(current) !== MigrationRules.canonical(part);
        report.write = report.changed || MigrationRules.canonical(nextRecords) !== MigrationRules.canonical(records);
        return report;
    }
}
