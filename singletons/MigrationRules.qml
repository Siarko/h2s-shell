pragma Singleton

import Quickshell

// The settings migrations' decisions: which registered migrations are pending (the registry,
// the records in Config.migratedKeys, a new config), each migration's scope (the paths it may
// read and write), running the pending ones in order on one document — each handed only the
// projection of its scope, a result reaching outside it a failure —, the per-scope reset when
// one fails (its later dependents skipped, the independent ones run), the strict outcome of a
// failing whole-config ("*") migration, a new config's baseline, a config written by a newer
// version, and which config backups are kept. Pure: no file, no process, no clock; the
// migrations themselves (Migrations.all()) are pure too. Checked by
// tests/MigrationRulesTest.qml; every registered migration by tests/MigrationsTest.qml.
//
// The document: { raw, profiles, globals, presets, files } — `raw` the top-level keys of
// config.json other than the parsed ones and the runner's own, `profiles` the profile list
// ([{ name, enabled, when, set }]), `globals` the pinned settings, `presets` the widget preset
// library ({ type: { name: { key: value } } }), `files` the side files in play (a path under
// the config's folder → its content). The records (migratedKeys) and writtenBy are the
// runner's, never in the document, never in a scope.
//
// A migration: { migrationId, since, summary, scope: [path…], wholeScopeReason (for "*"),
// migrate(document, context) → document } — `migrationId`, as a QML object cannot have a
// property named `id`. Optional: `phase` ("afterSeed"); `ownsRecord(entry)` → bool, the
// entries of migratedKeys that are its own markers (only ones that are no id or record form:
// the markers older code wrote per key), handed to it as `document.records` and taken back
// from its result's `records` — no other record ever reaches it; `appliedBefore(config)` →
// bool, config.json as read (migratedKeys included) already migrated the way it does by code
// from before the runner, so it is not run, nor recorded.
Singleton {
    id: root

    // Config backups kept after a new one is written
    readonly property int backupsKept: 10

    // Top-level keys of config.json that are never a raw: path: parsed into the document, or
    // the runner's
    readonly property var _reservedRaw: ["profiles", "globals", "widgetPresets", "migratedKeys", "writtenBy"]

    function _object(value) {
        return value !== null && typeof value === "object" && !Array.isArray(value);
    }

    function _own(object, key) {
        return _object(object) && Object.prototype.hasOwnProperty.call(object, key);
    }

    // An own key from JSON, "__proto__" included, stays a key (a plain assignment would set
    // the prototype)
    function _put(object, key, value) {
        Object.defineProperty(object, key, { value: value, enumerable: true, writable: true, configurable: true });
    }

    function _copy(value) {
        return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
    }

    // JSON with every object's keys sorted: two documents equal in content compare equal
    function canonical(value) {
        if (Array.isArray(value))
            return "[" + value.map(item => canonical(item)).join(",") + "]";
        if (_object(value))
            return "{" + Object.keys(value).sort().filter(key => value[key] !== undefined)
                .map(key => JSON.stringify(key) + ":" + canonical(value[key])).join(",") + "}";
        return JSON.stringify(value === undefined ? null : value);
    }

    // ---- Ids and records ----

    // Ids older code wrote as its markers, kept as the ids of the migrations that took over
    // from it (an older shell then sees them done)
    readonly property var _compatIds: ["theme.barLayout"]

    // A migration's id: "<yyyy-mm-dd>-<what>" (new migrations) or "<x.y.z>-<what>" (the
    // release a converted one first shipped in), lower-case words joined by "-"; or one of
    // _compatIds
    function validId(id) {
        if (_compatIds.includes(id))
            return true;
        return typeof id === "string" && id.length <= 96
            && /^([0-9]{4}-[0-9]{2}-[0-9]{2}|(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*))-[a-z0-9]+(-[a-z0-9]+)*$/.test(id);
    }

    // One entry of migratedKeys. → { kind: "applied" | "reset" | "held" | "other", id, version }
    // — "<id>" applied, "reset:<id>" failed with its scope reset (counts as applied),
    // "held:<id>@<version>" not run while the version is <version>; anything else (the
    // per-key markers older code wrote) "other"
    function parseRecord(entry) {
        if (typeof entry !== "string")
            return { kind: "other", id: "", version: "" };
        if (entry.startsWith("reset:") && validId(entry.slice(6)))
            return { kind: "reset", id: entry.slice(6), version: "" };
        const held = /^held:([^@]+)@(.+)$/.exec(entry);
        if (held && validId(held[1]))
            return { kind: "held", id: held[1], version: held[2] };
        if (validId(entry))
            return { kind: "applied", id: entry, version: "" };
        return { kind: "other", id: "", version: "" };
    }

    function _records(records) {
        return Array.isArray(records) ? records.filter(entry => typeof entry === "string") : [];
    }

    // Done: recorded as applied or as reset — never run again
    function isDone(id, records) {
        return _records(records).some(entry => {
            const record = parseRecord(entry);
            return (record.kind === "applied" || record.kind === "reset") && record.id === id;
        });
    }

    // Held while the running version is the one its record names
    function isHeld(id, records, version) {
        return _records(records).some(entry => {
            const record = parseRecord(entry);
            return record.kind === "held" && record.id === id && record.version === version;
        });
    }

    // The registered migrations not done, in registry order (held ones included: run()
    // holds them)
    function pending(registry, records) {
        return (Array.isArray(registry) ? registry : []).filter(migration => !isDone(migration?.migrationId, records));
    }

    // The migration's own check that `config` (config.json as read) was already migrated its
    // way by code from before the runner; a check that throws or is absent says no
    function appliedBefore(migration, config) {
        if (typeof migration?.appliedBefore !== "function" || !_object(config))
            return false;
        try {
            return migration.appliedBefore(_copy(config)) === true;
        } catch (error) {
            return false;
        }
    }

    function _owns(migration, entry) {
        try {
            return migration.ownsRecord(entry) === true;
        } catch (error) {
            return false;
        }
    }

    // Of `records`, the migration's own markers (ownsRecord): never an id or a record form
    function ownedRecords(migration, records) {
        if (typeof migration?.ownsRecord !== "function")
            return [];
        return _records(records).filter(entry => parseRecord(entry).kind === "other" && _owns(migration, entry));
    }

    // A new config's records: every registered id applied, none run (defaults are current)
    function baseline(registry, records) {
        const kept = _records(records);
        for (const migration of Array.isArray(registry) ? registry : [])
            if (validId(migration?.migrationId) && !isDone(migration.migrationId, kept))
                kept.push(migration.migrationId);
        return kept;
    }

    // Whether there is nothing to migrate, so the baseline is recorded instead: config.json
    // absent (null) or holding no profiles, no pinned or preset values and none of the
    // top-level keys a registered migration reads (raw: paths), and none of the side files
    // present (`files`, path → content, as for documentOf) in a registered migration's scope
    // (file: paths) — old theme files beside a missing config are still migrated
    function isNewConfig(raw, registry, files) {
        let document = { raw: {}, profiles: [], globals: {}, presets: {}, files: {} };
        if (_object(raw)) {
            const parsed = documentOf(raw, {});
            if (!parsed.ok)
                return false;
            document = parsed.document;
        }
        if (document.profiles.length > 0 || Object.keys(document.globals).length > 0 || Object.keys(document.presets).length > 0)
            return false;
        const present = Object.keys(_object(files) ? files : {});
        for (const migration of Array.isArray(registry) ? registry : []) {
            // An unreadable scope has no paths: it reads nothing
            const paths = parseScope(migration?.scope).paths;
            if (paths.some(path => path.kind === "raw" && _own(document.raw, path.key)))
                return false;
            if (present.some(file => _fileIn(file, paths)))
                return false;
        }
        return true;
    }

    // A config written by a newer shell: its writtenBy newer than `version`, or records naming
    // core migrations the registry does not know (a module's, "mod.<id>/…", are not the
    // core's). Never refused: what this version does not know is kept.
    // → { newer, writtenBy, unknown: [ids] }
    function newerConfig(writtenBy, records, version, registry) {
        const known = (Array.isArray(registry) ? registry : []).map(migration => migration?.migrationId);
        const unknown = [];
        for (const entry of _records(records)) {
            const record = parseRecord(entry);
            if (record.kind !== "other" && !known.includes(record.id) && !unknown.includes(record.id))
                unknown.push(record.id);
        }
        const byVersion = typeof writtenBy === "string" && writtenBy !== "" && ModuleUpdateRules.compareVersions(writtenBy, version) === 1;
        return { newer: byVersion || unknown.length > 0, writtenBy: typeof writtenBy === "string" ? writtenBy : "", unknown: unknown };
    }

    // What the shell says about a config newerConfig found written by a newer shell: the
    // startup banner and one log line. `version` is the running shell's.
    // → { shown, key, title, body, log }
    function newerNotice(newer, version) {
        if (!newer?.newer)
            return { shown: false, key: "", title: "", body: "", log: "" };
        const writtenBy = typeof newer.writtenBy === "string" && newer.writtenBy !== "" && ModuleUpdateRules.compareVersions(newer.writtenBy, version) === 1
            ? newer.writtenBy : "";
        const unknown = Array.isArray(newer.unknown) ? newer.unknown.filter(id => typeof id === "string") : [];
        const named = writtenBy !== "" ? "h2s-shell " + writtenBy : "a newer h2s-shell";
        return {
            shown: true,
            key: writtenBy + "\n" + unknown.join("\n"),
            title: "Settings written by " + named,
            body: "This is h2s-shell " + version + ". What this version does not know is kept, unused.",
            log: "settings written by " + named + " (this is " + version + "): what this version does not know is kept, unused"
                + (unknown.length > 0 ? "; settings updates it does not know: " + unknown.join(", ") : "")
        };
    }

    // ---- Keys the config file holds that this version does not declare ----

    // The text to save: `writtenText` (the config adapter's content — every key it declares)
    // with the keys of `loadedText` (the file as last read or written) that it lacks put back:
    // top-level keys, and keys inside an object both hold (a declared JsonObject), at any
    // depth; lists and other values are the adapter's. So a key a newer shell wrote survives
    // this one's saves. Keys sorted at every level, as JsonAdapter writes them. "" when
    // nothing is to be put back, or either text is not a JSON object (the adapter's own write
    // then stands).
    function keepUndeclaredKeys(writtenText, loadedText) {
        let written = null;
        let loaded = null;
        try {
            written = JSON.parse(writtenText);
            loaded = JSON.parse(loadedText);
        } catch (error) {
            return "";
        }
        if (!_object(written) || !_object(loaded))
            return "";
        const merged = _withUndeclared(written, loaded);
        return merged.added ? JSON.stringify(merged.value, null, 4) + "\n" : "";
    }

    // → { value, added }: `written` with `loaded`'s keys it lacks, recursively
    function _withUndeclared(written, loaded) {
        const keys = Object.keys(written);
        for (const key of Object.keys(loaded))
            if (!_own(written, key))
                keys.push(key);
        const value = {};
        let added = keys.length > Object.keys(written).length;
        for (const key of keys.sort()) {
            if (!_own(written, key)) {
                _put(value, key, loaded[key]);
            } else if (_object(written[key]) && _object(loaded[key])) {
                const inner = _withUndeclared(written[key], loaded[key]);
                added = added || inner.added;
                _put(value, key, inner.value);
            } else {
                _put(value, key, written[key]);
            }
        }
        return { value: value, added: added };
    }

    // ---- Scopes ----

    function _settingKey(text) {
        return /^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*$/.test(text);
    }

    function _name(text) {
        return typeof text === "string" && text !== "" && text !== "__proto__" && !text.includes("/") && text.length <= 128;
    }

    // One scope path → { kind, … } or null. "setting:<key>", "setting:<prefix>.*",
    // "preset:<type>" (every preset of the type; "preset:*" the whole library, every type),
    // "preset:<type>/<name>" (one preset),
    // "preset:<type>/*/<key>" (one key in every preset of the type),
    // "preset:<type>/<name>/<key>", "raw:<top-level key>", "file:<path>" (a relative path;
    // "*" matches within one folder level), "*". "setting:<a>.*.<b>": "*" one part of the key
    // between dots (its `prefix` the text before it, its `pattern` the whole). "read:<path>"
    // (not "*"): handed to the migration to read, never written by it and never reset.
    function parsePath(text) {
        if (typeof text !== "string" || text.length > 256)
            return null;
        if (text === "*")
            return { kind: "whole" };
        if (text.startsWith("read:")) {
            const inner = parsePath(text.slice(5));
            return inner && inner.kind !== "whole" && inner.read !== true ? Object.assign(inner, { read: true }) : null;
        }
        const parts = /^([a-z]+):(.*)$/.exec(text);
        if (!parts)
            return null;
        const kind = parts[1];
        const rest = parts[2];
        if (kind === "setting") {
            if (rest.endsWith(".*") && _settingKey(rest.slice(0, -2)))
                return { kind: "setting", prefix: rest.slice(0, -1), key: "" };
            const star = rest.indexOf(".*.");
            // The key with "x" for each "*" must be one: no "*" first, last or twice in a row
            if (star !== -1 && _settingKey(rest.replace(/\.\*\./g, ".x.")))
                return { kind: "setting", prefix: rest.slice(0, star + 1), key: "", pattern: rest };
            return _settingKey(rest) ? { kind: "setting", prefix: "", key: rest } : null;
        }
        if (kind === "preset") {
            const names = rest.split("/");
            if (names.length === 1 && _name(names[0]))
                return { kind: "preset", type: names[0], name: "", key: "" };
            if (names[0] === "*")
                return null;
            if (names.length === 2 && _name(names[0]) && _name(names[1]) && names[1] !== "*")
                return { kind: "preset", type: names[0], name: names[1], key: "" };
            if (names.length === 3 && _name(names[0]) && _name(names[1]) && _name(names[2]) && names[2] !== "*")
                return { kind: "preset", type: names[0], name: names[1] === "*" ? "" : names[1], key: names[2] };
            return null;
        }
        if (kind === "raw")
            return _name(rest) && !rest.includes(".") && !_reservedRaw.includes(rest) ? { kind: "raw", key: rest } : null;
        if (kind === "file") {
            if (rest.split("/").some(part => part === "." || part === ".." || !/^[A-Za-z0-9_.*-]+$/.test(part)))
                return null;
            return { kind: "file", pattern: rest };
        }
        return null;
    }

    // A migration's scope, a list of paths. → { ok, problem, whole, paths }; "*" makes the
    // whole document the scope and stands alone. Unreadable: no paths, `whole` not to be read.
    function parseScope(scope) {
        const refused = problem => ({ ok: false, problem: problem, paths: [] });
        if (!Array.isArray(scope) || scope.length === 0)
            return refused("no scope");
        const paths = [];
        for (const text of scope) {
            const path = parsePath(text);
            if (!path)
                return refused("not a scope path: " + String(text).slice(0, 80));
            paths.push(path);
        }
        const whole = paths.some(path => path.kind === "whole");
        if (whole && paths.length > 1)
            return refused("\"*\" stands alone");
        const read = paths.filter(path => path.read === true);
        if (read.some(path => paths.some(other => other.read !== true && pathsOverlap(path, other))))
            return refused("a read: path overlaps one it writes");
        return { ok: true, problem: "", whole: whole, paths: paths };
    }

    // Of a parsed scope, the paths it writes (and is reset on a failure), or those it only reads
    function writable(scope) {
        return Object.assign({}, scope, { paths: (scope?.paths ?? []).filter(path => path.read !== true) });
    }

    function readOnly(scope) {
        return Object.assign({}, scope, { whole: false, paths: (scope?.paths ?? []).filter(path => path.read === true) });
    }

    function _settingMatches(key, path) {
        if (path.key !== "")
            return key === path.key;
        if (path.pattern === undefined)
            return key.startsWith(path.prefix);
        const expression = "^" + path.pattern.split(".").map(part => part === "*" ? "[^.]+" : part).join("\\.") + "$";
        return new RegExp(expression).test(key);
    }

    function _settingIn(key, paths) {
        return paths.some(path => path.kind === "setting" && _settingMatches(key, path));
    }

    function _fileMatches(file, pattern) {
        const expression = "^" + pattern.split("*").map(part => part.replace(/[.+?^${}()|[\]\\]/g, "\\$&")).join("[^/]*") + "$";
        return new RegExp(expression).test(file);
    }

    function _fileIn(file, paths) {
        return paths.some(path => path.kind === "file" && _fileMatches(file, path.pattern));
    }

    // A preset path naming preset `name` of `type` (any of its keys)
    function _presetPath(path, type, name) {
        return path.kind === "preset" && (path.type === type || path.type === "*") && (path.name === "" || path.name === name);
    }

    // The whole preset is in scope
    function _presetIn(type, name, paths) {
        return paths.some(path => _presetPath(path, type, name) && path.key === "");
    }

    // Some of the preset's keys are in scope
    function _presetTouched(type, name, paths) {
        return paths.some(path => _presetPath(path, type, name));
    }

    function _presetKeyIn(type, name, key, paths) {
        return paths.some(path => _presetPath(path, type, name) && (path.key === "" || path.key === key));
    }

    function _wholeTypeIn(type, paths) {
        return paths.some(path => path.kind === "preset" && (path.type === type || path.type === "*") && path.name === "" && path.key === "");
    }

    function _rawIn(key, paths) {
        return paths.some(path => path.kind === "raw" && path.key === key);
    }

    // The text of a file pattern before its first "*"
    function _literal(pattern) {
        const star = pattern.indexOf("*");
        return star < 0 ? pattern : pattern.slice(0, star);
    }

    // Two paths overlap when one equals or lies under the other; "*" overlaps everything.
    // Two file patterns are compared by the text before their first "*": overlapping more
    // than they do only skips more.
    function pathsOverlap(first, second) {
        if (first.kind === "whole" || second.kind === "whole")
            return true;
        if (first.kind !== second.kind)
            return false;
        if (first.kind === "setting") {
            if (first.key !== "" && second.key !== "")
                return first.key === second.key;
            if (first.key !== "")
                return first.key.startsWith(second.prefix);
            if (second.key !== "")
                return second.key.startsWith(first.prefix);
            return first.prefix.startsWith(second.prefix) || second.prefix.startsWith(first.prefix);
        }
        if (first.kind === "preset")
            return (first.type === second.type || first.type === "*" || second.type === "*")
                && (first.name === "" || second.name === "" || first.name === second.name)
                && (first.key === "" || second.key === "" || first.key === second.key);
        if (first.kind === "raw")
            return first.key === second.key;
        // Two files
        if (!first.pattern.includes("*") && !second.pattern.includes("*"))
            return first.pattern === second.pattern;
        if (!first.pattern.includes("*"))
            return _fileMatches(first.pattern, second.pattern);
        if (!second.pattern.includes("*"))
            return _fileMatches(second.pattern, first.pattern);
        const a = _literal(first.pattern);
        const b = _literal(second.pattern);
        return a.startsWith(b) || b.startsWith(a);
    }

    // Two parsed scopes overlap; an unreadable scope overlaps everything
    function scopesOverlap(first, second) {
        if (!first?.ok || !second?.ok)
            return true;
        return first.paths.some(a => second.paths.some(b => (a.read !== true || b.read !== true) && pathsOverlap(a, b)));
    }

    // ---- The document ----

    // config.json parsed (`raw`, an object) and the side files read for the run → { ok,
    // problem, document, records, writtenBy }. A part that does not parse makes the whole
    // unreadable: a migration never runs on a guess.
    function documentOf(raw, files) {
        const refused = problem => ({ ok: false, problem: problem, document: null, records: [], writtenBy: "" });
        if (!_object(raw))
            return refused("the config is not an object");
        const parse = (text, fallback) => {
            if (text === undefined || text === "")
                return fallback;
            if (typeof text !== "string")
                return undefined;
            try {
                return JSON.parse(text);
            } catch (error) {
                return undefined;
            }
        };
        const profiles = parse(raw.profiles, []);
        const globals = parse(raw.globals, {});
        const presets = parse(raw.widgetPresets, {});
        if (!Array.isArray(profiles) || profiles.some(profile => !_object(profile) || typeof profile.name !== "string" || (profile.set !== undefined && !_object(profile.set))))
            return refused("the profiles could not be read");
        if (!_object(globals))
            return refused("the pinned settings could not be read");
        if (!_object(presets) || Object.keys(presets).some(type => !_object(presets[type])))
            return refused("the widget presets could not be read");
        if (raw.migratedKeys !== undefined && !Array.isArray(raw.migratedKeys))
            return refused("the migration records could not be read");
        const rest = {};
        for (const key of Object.keys(raw))
            if (!_reservedRaw.includes(key))
                _put(rest, key, _copy(raw[key]));
        const sideFiles = {};
        for (const path of Object.keys(_object(files) ? files : {}))
            _put(sideFiles, path, _copy(files[path]));
        return { ok: true, problem: "", document: { raw: rest, profiles: profiles, globals: globals, presets: presets, files: sideFiles },
                 records: _records(raw.migratedKeys), writtenBy: typeof raw.writtenBy === "string" ? raw.writtenBy : "" };
    }

    // The document back as config.json's content, with `records` and the original's
    // writtenBy. A part whose content did not change keeps the original's text, so a config
    // nothing changed is written back as it was. Side files are not in it (document.files).
    function rawOf(document, records, original) {
        const before = _object(original) ? original : {};
        const raw = {};
        for (const key of Object.keys(document.raw))
            _put(raw, key, _copy(document.raw[key]));
        const text = (key, value, fallback) => {
            const old = before[key];
            if (typeof old === "string") {
                try {
                    if (canonical(old === "" ? fallback : JSON.parse(old)) === canonical(value))
                        return old;
                } catch (error) {}
            } else if (old === undefined && canonical(value) === canonical(fallback)) {
                return undefined;
            }
            return JSON.stringify(value);
        };
        const parts = [["profiles", document.profiles, []], ["globals", document.globals, {}], ["widgetPresets", document.presets, {}]];
        for (const [key, value, fallback] of parts) {
            const written = text(key, value, fallback);
            if (written !== undefined)
                raw[key] = written;
        }
        raw.migratedKeys = _records(records);
        if (typeof before.writtenBy === "string")
            raw.writtenBy = before.writtenBy;
        return raw;
    }

    // What a migration with scope `scope` (parsed) is handed: only the paths it names, a
    // copy. Each profile keeps its name (to tell them apart) and the settings in scope.
    function projection(document, scope) {
        if (scope.whole)
            return _copy(document);
        const paths = scope.paths;
        const projected = { raw: {}, profiles: [], globals: {}, presets: {}, files: {} };
        const settings = set => {
            const kept = {};
            for (const key of Object.keys(_object(set) ? set : {}))
                if (_settingIn(key, paths))
                    _put(kept, key, _copy(set[key]));
            return kept;
        };
        projected.profiles = document.profiles.map(profile => ({ name: profile.name, set: settings(profile.set) }));
        projected.globals = settings(document.globals);
        for (const type of Object.keys(document.presets)) {
            if (_wholeTypeIn(type, paths)) {
                _put(projected.presets, type, _copy(document.presets[type]));
                continue;
            }
            const kept = {};
            for (const name of Object.keys(document.presets[type])) {
                const preset = document.presets[type][name];
                if (_presetIn(type, name, paths)) {
                    _put(kept, name, _copy(preset));
                } else if (_presetTouched(type, name, paths) && _object(preset)) {
                    // Only its keys in scope; the preset itself is not, so it is handed even
                    // when none of them is set
                    const keys = {};
                    for (const key of Object.keys(preset))
                        if (_presetKeyIn(type, name, key, paths))
                            _put(keys, key, _copy(preset[key]));
                    _put(kept, name, keys);
                }
            }
            if (Object.keys(kept).length > 0)
                _put(projected.presets, type, kept);
        }
        for (const key of Object.keys(document.raw))
            if (_rawIn(key, paths))
                _put(projected.raw, key, _copy(document.raw[key]));
        for (const file of Object.keys(document.files))
            if (_fileIn(file, paths))
                _put(projected.files, file, _copy(document.files[file]));
        return projected;
    }

    // The problem with a migration's result, "" when it is a document that stays inside the
    // scope: the same profiles (by count and name), every setting, preset, raw key and file
    // it holds named by the scope
    function resultProblem(result, handed, scope) {
        if (!_object(result))
            return "it returned no document";
        const parts = ["raw", "profiles", "globals", "presets", "files"];
        if (Object.keys(result).some(key => !parts.includes(key)))
            return "it returned a document with a part no document has";
        if (!_object(result.raw) || !Array.isArray(result.profiles) || !_object(result.globals) || !_object(result.presets) || !_object(result.files))
            return "it returned no document";
        if (result.profiles.some(profile => !_object(profile) || typeof profile.name !== "string" || (profile.set !== undefined && !_object(profile.set))))
            return "it returned a malformed profile";
        if (Object.keys(result.presets).some(type => !_object(result.presets[type])))
            return "it returned a malformed preset type";
        const reserved = Object.keys(result.raw).find(key => _reservedRaw.includes(key));
        if (reserved !== undefined)
            return "it wrote " + reserved + " as a top-level key, which the runner keeps";
        if (scope.whole)
            return "";
        const paths = scope.paths;
        if (result.profiles.length !== handed.profiles.length || result.profiles.some((profile, i) => profile.name !== handed.profiles[i].name))
            return "it added, removed or renamed a profile";
        for (const profile of result.profiles) {
            if (Object.keys(profile).some(key => key !== "name" && key !== "set"))
                return "it changed profile " + profile.name + " outside its settings";
            const outside = Object.keys(profile.set ?? {}).find(key => !_settingIn(key, paths));
            if (outside !== undefined)
                return "it wrote setting " + outside + " outside its scope";
        }
        const outsideGlobal = Object.keys(result.globals).find(key => !_settingIn(key, paths));
        if (outsideGlobal !== undefined)
            return "it wrote setting " + outsideGlobal + " outside its scope";
        for (const type of Object.keys(result.presets)) {
            if (_wholeTypeIn(type, paths))
                continue;
            const names = Object.keys(result.presets[type]);
            for (const name of names) {
                if (_presetIn(type, name, paths))
                    continue;
                const preset = result.presets[type][name];
                // Only keys of a preset that was handed: the preset itself is outside the scope
                if (!_presetTouched(type, name, paths) || !_own(handed.presets[type], name) || !_object(preset))
                    return "it wrote preset " + type + "/" + name + " outside its scope";
                const outsideKey = Object.keys(preset).find(key => !_presetKeyIn(type, name, key, paths));
                if (outsideKey !== undefined)
                    return "it wrote " + outsideKey + " of preset " + type + "/" + name + " outside its scope";
            }
            if (names.length === 0 && !_own(handed.presets, type))
                return "it wrote preset type " + type + " outside its scope";
        }
        const outsideRaw = Object.keys(result.raw).find(key => !_rawIn(key, paths));
        if (outsideRaw !== undefined)
            return "it wrote " + outsideRaw + " outside its scope";
        const outsideFile = Object.keys(result.files).find(file => !_fileIn(file, paths));
        if (outsideFile !== undefined)
            return "it wrote file " + outsideFile + " outside its scope";
        return "";
    }

    // The document without the paths `scope` names (side files kept): the reset of a failed
    // migration, and the base its result is merged into. Input not modified.
    function withoutScope(document, scope, keepFiles) {
        const result = _copy(document);
        const paths = scope.paths;
        const settings = set => {
            if (!_object(set))
                return;
            for (const key of Object.keys(set))
                if (_settingIn(key, paths))
                    delete set[key];
        };
        for (const profile of result.profiles)
            settings(profile.set);
        settings(result.globals);
        for (const type of Object.keys(result.presets)) {
            if (_wholeTypeIn(type, paths)) {
                delete result.presets[type];
                continue;
            }
            for (const name of Object.keys(result.presets[type])) {
                const preset = result.presets[type][name];
                if (_presetIn(type, name, paths))
                    delete result.presets[type][name];
                else if (_object(preset))
                    for (const key of Object.keys(preset))
                        if (_presetKeyIn(type, name, key, paths))
                            delete preset[key];
            }
        }
        for (const key of Object.keys(result.raw))
            if (_rawIn(key, paths))
                delete result.raw[key];
        if (!keepFiles)
            for (const file of Object.keys(result.files))
                if (_fileIn(file, paths))
                    delete result.files[file];
        return result;
    }

    // A result that stays inside the scope merged back: the document without the scope, the
    // result's paths put in
    function _merged(document, result, scope) {
        if (scope.whole)
            return _copy(result);
        const merged = withoutScope(document, scope, false);
        result.profiles.forEach((profile, i) => {
            const keys = Object.keys(profile.set ?? {});
            if (keys.length === 0)
                return;
            const target = merged.profiles[i];
            if (!_object(target.set))
                target.set = {};
            for (const key of keys)
                _put(target.set, key, profile.set[key]);
        });
        for (const key of Object.keys(result.globals))
            _put(merged.globals, key, result.globals[key]);
        for (const type of Object.keys(result.presets)) {
            if (_wholeTypeIn(type, scope.paths)) {
                _put(merged.presets, type, result.presets[type]);
                continue;
            }
            const names = Object.keys(result.presets[type]);
            if (names.length === 0)
                continue;
            if (!_own(merged.presets, type))
                _put(merged.presets, type, {});
            for (const name of names) {
                if (_presetIn(type, name, scope.paths)) {
                    _put(merged.presets[type], name, result.presets[type][name]);
                    continue;
                }
                // Keys of a preset that is there (resultProblem checked it was handed)
                const target = merged.presets[type][name];
                for (const key of Object.keys(result.presets[type][name]))
                    _put(target, key, result.presets[type][name][key]);
            }
        }
        for (const key of Object.keys(result.raw))
            _put(merged.raw, key, result.raw[key]);
        for (const file of Object.keys(result.files))
            _put(merged.files, file, result.files[file]);
        return merged;
    }

    // One migration on the document: handed its projection (and its own markers of
    // `records`, ownedRecords, as `records`), its result checked and merged back.
    // → { ok, error, document, records } — not ok when it throws, returns no document, reaches
    // outside its scope or hands back a marker it does not own (its result discarded;
    // `document` and `records` then the input). `records`: the markers it changed in place,
    // new ones after the others, in the order it gave them.
    function applyOne(migration, document, context, records) {
        const allRecords = _records(records);
        const scope = parseScope(migration?.scope);
        const failed = error => ({ ok: false, error: error, document: document, records: allRecords });
        if (!scope.ok)
            return failed("its scope is unreadable: " + scope.problem);
        if (typeof migration.migrate !== "function")
            return failed("it has no migrate function");
        const handed = projection(document, scope);
        const owns = typeof migration.ownsRecord === "function";
        const owned = ownedRecords(migration, allRecords);
        let result;
        try {
            const input = _copy(handed);
            if (owns)
                input.records = owned.slice();
            result = migration.migrate(input, _copy(context ?? {}));
            // Only plain data comes back (a cycle or a function never reaches the document)
            result = _copy(result);
        } catch (error) {
            return failed("it failed: " + String(error?.message ?? error).slice(0, 300));
        }
        let markers = owned;
        if (owns && _object(result) && _own(result, "records")) {
            markers = result.records;
            delete result.records;
            if (!Array.isArray(markers) || markers.some(entry => typeof entry !== "string" || parseRecord(entry).kind !== "other" || !_owns(migration, entry)))
                return failed("it wrote a record it does not own");
        }
        const problem = resultProblem(result, handed, scope);
        if (problem !== "")
            return failed(problem);
        const reading = readOnly(scope);
        if (canonical(projection(result, reading)) !== canonical(projection(handed, reading)))
            return failed("it changed what its scope only reads");
        const nextRecords = allRecords.filter(entry => !owned.includes(entry) || markers.includes(entry));
        for (const entry of markers)
            if (!nextRecords.includes(entry))
                nextRecords.push(entry);
        // What it only reads is the same as handed: the document's stays
        return { ok: true, error: "", document: _merged(document, withoutScope(result, reading), writable(scope)), records: nextRecords };
    }

    // ---- The run ----

    // The pending migrations run in registry order on `document` (documentOf's). `options`:
    // { records, version (the running shell's), fresh (a new config: the baseline, nothing
    // run), context (handed to each migration) }.
    // On a failure of migration X whose scope is not "*": the ones before stay applied, X's
    // result is discarded and its scope removed from the document (defaults), X recorded as
    // "reset:<id>"; the later ones whose scopes overlap X's, transitively through those
    // skipped, are skipped (not recorded: pending again next time); the independent ones run.
    // A held migration is not run, and its dependents are skipped the same way.
    // A failure of a "*" migration (or one whose scope is unreadable) stops the run: the
    // document as the ones before left it, in memory only — nothing is to be written, no
    // record added, the config read-only.
    // → { write, readOnly, changed (the document differs), document, records, applied: [id],
    //   reset: [{ id, error }], skipped: [{ id, after }], held: [id], failure: { id, error } | null,
    //   filesWritten: [path], filesRemoved: [path] }
    function run(registry, document, options) {
        const records = _records(options?.records);
        const version = typeof options?.version === "string" ? options.version : "";
        const report = { readOnly: false, changed: false, document: document, records: records,
                         applied: [], reset: [], skipped: [], held: [], failure: null, filesWritten: [], filesRemoved: [] };
        if (options?.fresh === true) {
            report.records = baseline(registry, records);
            report.write = report.records.length !== records.length;
            return report;
        }
        let current = document;
        let nextRecords = records.slice();
        // The scopes of the migrations that failed, were held or skipped: what overlaps them waits
        const blocked = [];
        const record = (id, entry) => {
            for (let i = nextRecords.length - 1; i >= 0; i--) {
                const old = parseRecord(nextRecords[i]);
                if (old.kind === "held" && old.id === id)
                    nextRecords.splice(i, 1);
            }
            nextRecords.push(entry);
        };
        for (const migration of pending(registry, records)) {
            const id = migration?.migrationId;
            const scope = parseScope(migration?.scope);
            const blocker = blocked.find(each => scopesOverlap(each.scope, scope));
            if (isHeld(id, records, version)) {
                report.held.push(id);
                blocked.push({ id: id, scope: scope });
                continue;
            }
            if (blocker) {
                report.skipped.push({ id: id, after: blocker.id });
                blocked.push({ id: id, scope: scope });
                continue;
            }
            const outcome = applyOne(migration, current, options?.context, nextRecords);
            if (outcome.ok) {
                current = outcome.document;
                nextRecords = outcome.records;
                report.applied.push(id);
                record(id, id);
                continue;
            }
            if (!scope.ok || scope.whole) {
                report.failure = { id: id, error: outcome.error };
                report.readOnly = true;
                report.write = false;
                report.document = current;
                report.records = records;
                report.changed = canonical(current) !== canonical(document);
                return report;
            }
            current = withoutScope(current, writable(scope), true);
            report.reset.push({ id: id, error: outcome.error });
            record(id, "reset:" + id);
            blocked.push({ id: id, scope: scope });
        }
        report.document = current;
        report.records = nextRecords;
        report.changed = canonical(current) !== canonical(document);
        for (const file of Object.keys(current.files))
            if (!_own(document.files, file) || canonical(document.files[file]) !== canonical(current.files[file]))
                report.filesWritten.push(file);
        for (const file of Object.keys(document.files))
            if (!_own(current.files, file))
                report.filesRemoved.push(file);
        report.write = report.changed || canonical(nextRecords) !== canonical(records);
        return report;
    }

    // ---- At start ----

    // The registered migrations of `phase`: "load" (before any reader sees the config; a
    // migration naming no phase) or "afterSeed" (once the profiles exist)
    function inPhase(registry, phase) {
        const wanted = phase === "afterSeed" ? "afterSeed" : "load";
        return (Array.isArray(registry) ? registry : []).filter(migration => (migration?.phase === "afterSeed" ? "afterSeed" : "load") === wanted);
    }

    // How many folder levels below the config's folder the side files of the registered
    // migrations lie (file: paths): 0 when none has any, so nothing is listed
    function sideFileDepth(registry) {
        let depth = 0;
        for (const migration of Array.isArray(registry) ? registry : [])
            for (const path of parseScope(migration?.scope).paths)
                if (path.kind === "file")
                    depth = Math.max(depth, path.pattern.split("/").length);
        return depth;
    }

    // Of the files listed in the config's folder (paths relative to it), those a registered
    // migration's scope names: the side files a run reads
    function sideFilesIn(registry, listed) {
        const paths = [];
        for (const migration of Array.isArray(registry) ? registry : [])
            for (const path of parseScope(migration?.scope).paths)
                if (path.kind === "file")
                    paths.push(path);
        return (Array.isArray(listed) ? listed : []).filter(file => typeof file === "string" && _fileIn(file, paths));
    }

    // What one run of the migrations at start does. `raw`: config.json parsed — null when there
    // is none (or it is empty), anything but an object when it could not be read (then nothing
    // is done: the config reports it). `files`: the side files read (path → content);
    // `unreadable`: side files present that did not parse. `options`: { phase ("load" or
    // "afterSeed"), version (the running shell's), context (handed to each migration) }.
    // A new config (load phase only) records every registered id, none run. A config that
    // cannot be made into a document, or a side file in a pending migration's scope that does
    // not parse, is never migrated on a guess: nothing written, the session read-only. A run
    // stopped by a failing "*" migration leaves `view`, the config as the migrations before it
    // left it, for the readers, unwritten.
    // → { write, readOnly, backup (some migration changed something or a scope was reset),
    //   config (the content to write, an object) | null, view (an object) | null,
    //   files: { path: content } to write, removed: [path], report: { phase, fresh, records,
    //   applied, reset, skipped, held, failure, problem } }
    function startup(registry, raw, files, unreadable, options) {
        const phase = options?.phase === "afterSeed" ? "afterSeed" : "load";
        const all = Array.isArray(registry) ? registry : [];
        const report = { phase: phase, fresh: false, records: [], applied: [], reset: [], skipped: [], held: [], failure: null, problem: "" };
        const outcome = { write: false, readOnly: false, backup: false, config: null, view: null, files: {}, removed: [], report: report };
        if (raw !== null && !_object(raw))
            return outcome;
        const sideFiles = _object(files) ? files : {};
        if (phase === "load" && isNewConfig(raw, all, sideFiles)) {
            const records = _records(raw?.migratedKeys);
            report.fresh = true;
            report.records = baseline(all, records);
            if (report.records.length !== records.length) {
                outcome.write = true;
                outcome.config = _copy(raw ?? {});
                outcome.config.migratedKeys = report.records;
            }
            return outcome;
        }
        const parsed = documentOf(raw ?? {}, sideFiles);
        const records = parsed.ok ? parsed.records : _records(raw?.migratedKeys);
        report.records = records;
        // Those that code from before the runner already applied its way are neither run nor
        // recorded (appliedBefore): such a config is left as it is
        const ofPhase = inPhase(all, phase).filter(migration => !appliedBefore(migration, raw ?? {}));
        const due = pending(ofPhase, records);
        if (due.length === 0)
            return outcome;
        const unread = (Array.isArray(unreadable) ? unreadable : [])
            .filter(file => due.some(migration => _fileIn(file, parseScope(migration?.scope).paths)));
        if (!parsed.ok || unread.length > 0) {
            report.problem = !parsed.ok ? parsed.problem : unread[0] + " could not be read";
            report.failure = { id: "", error: report.problem };
            outcome.readOnly = true;
            return outcome;
        }
        const result = run(ofPhase, parsed.document, { records: records, version: options?.version, context: options?.context });
        report.applied = result.applied;
        report.reset = result.reset;
        report.skipped = result.skipped;
        report.held = result.held;
        report.failure = result.failure;
        if (result.readOnly) {
            outcome.readOnly = true;
            if (result.changed)
                outcome.view = rawOf(result.document, records, raw);
            return outcome;
        }
        report.records = result.records;
        if (!result.write)
            return outcome;
        outcome.write = true;
        outcome.backup = result.changed || result.reset.length > 0;
        outcome.config = rawOf(result.document, result.records, raw);
        for (const file of result.filesWritten)
            _put(outcome.files, file, _copy(result.document.files[file]));
        outcome.removed = result.filesRemoved;
        return outcome;
    }

    // config.json's text for `config` (an object): keys sorted at every level, as JsonAdapter
    // writes them
    function configText(config) {
        const sorted = value => {
            if (Array.isArray(value))
                return value.map(item => sorted(item));
            if (!_object(value))
                return value;
            const object = {};
            for (const key of Object.keys(value).sort())
                _put(object, key, sorted(value[key]));
            return object;
        };
        return JSON.stringify(sorted(config), null, 4) + "\n";
    }

    // A config backup's name for the time `isoTime` (Date.toISOString()) and `reason` (one of
    // backupReasons, or "" for none); `module` names a module switch's module and versions
    // (ConfigBackupRules.name); "" for a time that is not one
    function backupName(isoTime, reason, module) {
        return ConfigBackupRules.name(isoTime, reason, module);
    }

    // ---- The registry ----

    // What is wrong with the registry, each as a line ([] when nothing): an id that is not
    // one or is used twice, a `since` that is not a minor or major release ("x.y.0") or older
    // than the one before it, no summary, an unreadable scope, a "*" scope without its
    // reason, no migrate function
    function registryProblems(registry) {
        const problems = [];
        const seen = [];
        let previous = "";
        for (const migration of Array.isArray(registry) ? registry : []) {
            const id = migration?.migrationId;
            const name = typeof id === "string" ? id : "(no id)";
            if (!validId(id))
                problems.push(name + ": not a migration id");
            else if (seen.includes(id))
                problems.push(name + ": registered twice");
            seen.push(id);
            const since = migration?.since;
            if (typeof since !== "string" || !/^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.0$/.test(since))
                problems.push(name + ": since is not a minor or major release (x.y.0)");
            else if (previous !== "" && ModuleUpdateRules.compareVersions(since, previous) === -1)
                problems.push(name + ": since " + since + " is older than the migration before it (" + previous + ")");
            else
                previous = since;
            if (typeof migration?.summary !== "string" || migration.summary.trim() === "")
                problems.push(name + ": no summary");
            const scope = parseScope(migration?.scope);
            if (!scope.ok)
                problems.push(name + ": " + scope.problem);
            else if (scope.whole && (typeof migration?.wholeScopeReason !== "string" || migration.wholeScopeReason.trim() === ""))
                problems.push(name + ": a \"*\" scope without its wholeScopeReason");
            if (typeof migration?.migrate !== "function")
                problems.push(name + ": no migrate function");
        }
        return problems;
    }

    // ---- Backups ----

    // Why a config backup was made, the last part of its name
    readonly property var backupReasons: ConfigBackupRules.reasons

    // Which config backups stay after a new one: of the names in the config's folder only
    // "config.json.bak-<stamp>" (and "-<reason>" after it, one of backupReasons;
    // ConfigBackupRules.parseName) count; every
    // other name is left alone. A manual backup ("-manual") is never pruned: kept, not
    // counted. `options`: { written (the backup just written: always kept, whatever its stamp
    // says — the clock may have gone back —, and counted unless manual), protect: [names] (one being
    // restored from: kept, not counted), neverPrune: [names] (kept, not counted) }.
    // The rest by their stamps, newest first, fill up to `backupsKept`; equal stamps by name.
    // → { keep, delete } (newest first)
    function backupsToKeep(names, options) {
        // The stamp has a fixed width and comes first: the names sort as their stamps do
        const backups = (Array.isArray(names) ? names : []).filter(name => typeof name === "string" && !name.includes("/") && ConfigBackupRules.parseName(name).ok).sort().reverse();
        const listed = value => Array.isArray(value) ? value : [];
        const written = typeof options?.written === "string" ? options.written : "";
        const kept = listed(options?.protect).concat(listed(options?.neverPrune));
        // The backup just written takes a place among the automatic ones only when it is one
        let room = backupsKept - (backups.includes(written) && ConfigBackupRules.parseName(written).reason !== "manual" ? 1 : 0);
        const keep = [];
        const deleted = [];
        for (const name of backups) {
            if (name === written || kept.includes(name) || ConfigBackupRules.parseName(name).reason === "manual") {
                keep.push(name);
            } else if (room > 0) {
                keep.push(name);
                room--;
            } else {
                deleted.push(name);
            }
        }
        return { keep: keep, delete: deleted };
    }
}
