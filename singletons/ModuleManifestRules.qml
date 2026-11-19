pragma Singleton

import Quickshell
import QtQuick

// The module system's decisions about a manifest (ModuleRules.qml has the overview): the
// namespaces a module's contributions must stay in, and reading and checking module.json.
// Pure, checked by tests/ModuleRulesTest.qml; nothing here throws on any input.
//
// THE MANIFEST (module.json, in the module's directory) — the public format:
//
//   id            required. ^[a-z][a-z0-9_-]{0,31}$, not one of `reservedIds`. The module's
//                 name everywhere: its settings are mod.<id>.*, its facts <id>.*, its widget
//                 types, popups and settings pages <id> or <id>.<name>.
//   name          required. A non-empty string (shown by `modules list` over IPC).
//   version       required. The module's own version, ^[0-9A-Za-z][0-9A-Za-z.+~-]{0,63}$
//                 (semver recommended, not enforced).
//   api           required. The module API it is written for, "major.minor" (Api.version):
//                 compatible when the major is the shell's and the minor neither above the
//                 shell's nor below its floor (ModuleRules.apiFloor).
//   description   optional string.
//   main          optional. A .qml file the host creates once the module is enabled: its
//                 IPC handlers, its facts, its long-lived objects. A module of widgets only
//                 needs none.
//   widgets       optional list of bar widget types, WidgetRegistry's fields:
//                 { type, name, widget, popup?, popupPanel?, settings?, multiple?,
//                   presetDefaults? }
//                 type and popup are <id> or <id>.<name>; widget, popupPanel, settings are
//                 files of the module; popupPanel needs popup. presetDefaults (API 1.0): an
//                 object { key: value } — what a key of the widget's presets is when the preset
//                 does not set it (WidgetPresets.defaults); keys are names, values plain JSON,
//                 at most 50 keys and 16 KiB.
//   settingsPages optional list: { id, label, component, tab?, parent? } — id <id> or
//                 <id>.<name>; tab "behaviour" (default), "appearance" or "system"; parent
//                 the id of a core group of pages (such as "network").
//   settings      optional list of settings, SettingsSchema's fields:
//                 { key, label, type, default, group?, global?, hint?, suffix?, min?, max?,
//                   options? } — key mod.<id>.<name>; type bool, number, slider, interval,
//                 enum (options: [{ value, label }]), string or stringList; the default must
//                 fit the type (and the range, and be one of the options). group defaults to
//                 mod.<id>.
//   facts         optional list of profile facts, ProfileRules.factTypes' fields:
//                 { fact, label, type, options? } — fact <id>.<name>; type bool, number,
//                 percent, string or enum (options: strings).
//   slots         optional list of contributions to slots the core declares:
//                 { slot, component } — slot a dotted name; the ones this shell offers are
//                 `slotTable` (a name it does not offer is a warning: the contribution is
//                 kept, and shows nowhere).
//   requires      optional: { programs: [names] } — programs that must be on PATH; without
//                 them the module is not loaded (state missing-program) and its setupHints
//                 are shown.
//   optionalPrograms  optional list of program names (API 1.9): looked up and judged like
//                 the required ones (the handle's `programs`), but a missing one does not
//                 stop the module. A name also required counts as required.
//   testPrograms  optional directory inside the module (API 1.10): in module test mode
//                 (tests/run-modules.sh, a test tree) every program it names is taken from
//                 there, as a stand-in (ModuleRules.programSource); ignored otherwise.
//   setupHints    optional list of strings: how to get the module working.
//   tests         optional list of .qml test suites (tests/run-modules.sh runs them).
//   exports       optional (API 1.18): { version: "major.minor" } — the module offers other
//                 modules an API object of its own: its main's `exports` property, a plain
//                 QtObject. The version is the module's own API's, not the module's: a
//                 dependent asking for "1.2" gets it from "1.2" up to "1.<anything>", never
//                 from "2.0" (ModuleMergeRules.usesFit). Malformed: the module fails.
//   uses          optional (API 1.18): { <module id>: "major.minor" } — the modules whose
//                 exports it needs, each with the least version of their `exports`. All are
//                 required: without one the module does not load (state missing-module,
//                 ModuleMergeRules.dependencyPlan), and it loads after them. The module gets
//                 each one's `exports` object as module.uses.<id>, nothing else of it. An id
//                 that is not a module id (or a reserved one) or a version that is not
//                 "major.minor": the module fails.
//                 exports or uses in a manifest whose `api` is below 1.18: read all the same,
//                 with a warning.
//
// Files are paths inside the module's directory: relative, "/"-separated, no "..", no
// leading "/", ending in .qml. Any other field is kept (in `raw`) and reported as a warning,
// so a manifest written for a newer shell still loads on an older one.
//
// A required field missing or malformed, or a bad `main`: the module fails (state failed).
// A bad entry in a list (a key outside the module's namespace, a default of the wrong type,
// a path outside the directory): that entry is dropped with an error, the module still loads.
Singleton {
    id: root

    // ---- Namespaces ----

    function validId(id) {
        return typeof id === "string" && ModuleRules.idPattern.test(id) && !ModuleRules.reservedIds.includes(id);
    }

    // A widget type, popup key or settings page id of module `id`: <id> or <id>.<name>
    function isOwnName(id, name) {
        if (typeof name !== "string" || name.length > 100)
            return false;
        if (name === id)
            return true;
        return name.startsWith(id + ".") && /^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*$/.test(name.slice(id.length + 1));
    }

    // A fact of module `id`: <id>.<name>
    function isOwnFact(id, fact) {
        return typeof fact === "string" && fact !== id && isOwnName(id, fact);
    }

    // A setting of module `id`: mod.<id>.<name>
    function isOwnSettingKey(id, key) {
        if (typeof key !== "string" || key.length > 120)
            return false;
        const prefix = "mod." + id + ".";
        return key.startsWith(prefix) && /^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)*$/.test(key.slice(prefix.length));
    }

    // ---- The manifest ----

    readonly property var _topFields: ["id", "name", "version", "api", "description", "main", "widgets",
        "settingsPages", "settings", "facts", "slots", "requires", "optionalPrograms", "testPrograms", "setupHints", "tests",
        "exports", "uses"]

    // A list field: its entries (at most maxEntries), or [] with an error when it is not a list
    function _list(raw, field, errors) {
        const value = ModuleRules.get(raw, field);
        if (value === undefined)
            return [];
        if (!Array.isArray(value)) {
            errors.push(field + ": not a list (ignored)");
            return [];
        }
        if (value.length > ModuleRules.maxEntries) {
            errors.push(field + ": " + value.length + " entries, only the first " + ModuleRules.maxEntries + " are read");
            return value.slice(0, ModuleRules.maxEntries);
        }
        return value;
    }

    // Each entry of a list checked by `check(entry, where)`, which returns the entry to keep
    // or a string (why it is dropped); fields an entry has beyond `known` are warned about
    function _entries(raw, field, known, check, errors, warnings) {
        const kept = [];
        _list(raw, field, errors).forEach((entry, index) => {
            const where = field + "[" + index + "]";
            if (!ModuleRules.isObject(entry)) {
                errors.push(where + ": not an object (dropped)");
                return;
            }
            let result;
            try {
                result = check(entry, where);
            } catch (error) {
                result = "could not be read (" + error + ")";
            }
            if (typeof result === "string") {
                errors.push(where + ": " + result + " (dropped)");
                return;
            }
            for (const key of Object.keys(entry)) {
                if (!known.includes(key))
                    warnings.push(where + ": unknown field " + ModuleRules.show(key) + " (ignored)");
            }
            kept.push(result);
        });
        return kept;
    }

    // A file field of an entry → { path } (path "" when absent and not required) or
    // { error }
    function _file(entry, field, required) {
        const value = ModuleRules.get(entry, field);
        if (value === undefined)
            return required ? { error: field + " is missing" } : { path: "" };
        const problem = ModuleFileRules.pathProblem(value);
        return problem === "" ? { path: value } : { error: field + " " + ModuleRules.show(value) + ": " + problem };
    }

    function _checkWidget(id, entry) {
        const type = ModuleRules.get(entry, "type");
        if (!isOwnName(id, type))
            return "type " + ModuleRules.show(type) + " is not \"" + id + "\" or \"" + id + ".<name>\"";
        const name = ModuleRules.get(entry, "name");
        if (!ModuleRules.isString(name, 100))
            return "name is missing or not a short text";
        const widget = _file(entry, "widget", true);
        if (widget.error)
            return widget.error;
        const result = { type: type, name: name, widget: widget.path };
        const popup = ModuleRules.get(entry, "popup");
        if (popup !== undefined) {
            if (!isOwnName(id, popup))
                return "popup " + ModuleRules.show(popup) + " is not \"" + id + "\" or \"" + id + ".<name>\"";
            result.popup = popup;
        }
        for (const field of ["popupPanel", "settings"]) {
            const file = _file(entry, field, false);
            if (file.error)
                return file.error;
            if (file.path !== "")
                result[field] = file.path;
        }
        if (result.popupPanel && !result.popup)
            return "popupPanel without popup";
        const multiple = ModuleRules.get(entry, "multiple");
        if (multiple !== undefined && typeof multiple !== "boolean")
            return "multiple is not true or false";
        result.multiple = multiple === true;
        const presetDefaults = ModuleRules.get(entry, "presetDefaults");
        if (presetDefaults !== undefined) {
            const problem = presetDefaultsProblem(presetDefaults);
            if (problem !== "")
                return "presetDefaults: " + problem;
            result.presetDefaults = JSON.parse(JSON.stringify(presetDefaults));
        }
        return result;
    }

    // A widget's presetDefaults: "" when fine, else why not
    function presetDefaultsProblem(value) {
        if (!ModuleRules.isObject(value))
            return "not an object";
        const keys = Object.keys(value);
        if (keys.length > 50)
            return "more than 50 keys";
        for (const key of keys) {
            if (!/^[A-Za-z_][A-Za-z0-9_]{0,63}$/.test(key) || key === "__proto__")
                return "the key " + ModuleRules.show(key) + " is not a name";
        }
        let text;
        try {
            text = JSON.stringify(value);
        } catch (error) {
            return "not plain JSON";
        }
        if (typeof text !== "string" || text.length > 16 * 1024)
            return "larger than 16 KiB";
        return "";
    }

    function _checkPage(id, entry) {
        const pageId = ModuleRules.get(entry, "id");
        if (!isOwnName(id, pageId))
            return "id " + ModuleRules.show(pageId) + " is not \"" + id + "\" or \"" + id + ".<name>\"";
        const label = ModuleRules.get(entry, "label");
        if (!ModuleRules.isString(label, 100))
            return "label is missing or not a short text";
        const component = _file(entry, "component", true);
        if (component.error)
            return component.error;
        const tab = ModuleRules.get(entry, "tab") ?? "behaviour";
        if (!ModuleRules.settingsTabs.includes(tab))
            return "tab " + ModuleRules.show(tab) + " is not one of " + ModuleRules.settingsTabs.join(", ");
        const result = { id: pageId, label: label, component: component.path, tab: tab };
        const parent = ModuleRules.get(entry, "parent");
        if (parent !== undefined) {
            if (typeof parent !== "string" || !/^[a-z][a-z0-9_]{0,40}$/.test(parent))
                return "parent " + ModuleRules.show(parent) + " is not the id of a group of pages";
            result.parent = parent;
        }
        return result;
    }

    function _checkSetting(id, entry) {
        const key = ModuleRules.get(entry, "key");
        if (!isOwnSettingKey(id, key))
            return "key " + ModuleRules.show(key) + " is not mod." + id + ".<name> (a module's settings live under mod." + id + ")";
        const label = ModuleRules.get(entry, "label");
        if (!ModuleRules.isString(label, 200))
            return key + ": label is missing or not a short text";
        const type = ModuleRules.get(entry, "type");
        if (!ModuleRules.settingTypes.includes(type))
            return key + ": type " + ModuleRules.show(type) + " is not one of " + ModuleRules.settingTypes.join(", ");
        if (!ModuleRules.has(entry, "default"))
            return key + ": no default";
        const value = entry["default"];
        const result = { key: key, label: label, type: type, "default": value, group: "mod." + id };
        for (const field of ["min", "max"]) {
            const bound = ModuleRules.get(entry, field);
            if (bound === undefined)
                continue;
            if (!ModuleRules.isNumber(bound))
                return key + ": " + field + " is not a number";
            result[field] = bound;
        }
        if (type === "bool" && typeof value !== "boolean")
            return key + ": the default is not true or false";
        if (type === "number" || type === "slider" || type === "interval") {
            if (!ModuleRules.isNumber(value))
                return key + ": the default is not a number";
            if ((result.min !== undefined && value < result.min) || (result.max !== undefined && value > result.max))
                return key + ": the default is outside min..max";
        }
        if (type === "string" && typeof value !== "string")
            return key + ": the default is not a text";
        if (type === "stringList" && !(Array.isArray(value) && value.every(item => typeof item === "string")))
            return key + ": the default is not a list of texts";
        if (type === "enum") {
            const options = ModuleRules.get(entry, "options");
            if (!Array.isArray(options) || options.length === 0 || options.length > 100)
                return key + ": an enum needs options";
            const kept = [];
            for (const option of options) {
                const optionValue = ModuleRules.isObject(option) ? ModuleRules.get(option, "value") : undefined;
                const optionLabel = ModuleRules.isObject(option) ? ModuleRules.get(option, "label") : undefined;
                if (!["string", "number", "boolean"].includes(typeof optionValue) || !ModuleRules.isString(optionLabel, 200))
                    return key + ": an option is not { value, label }";
                kept.push({ value: optionValue, label: optionLabel });
            }
            if (!kept.some(option => option.value === value))
                return key + ": the default is not one of the options";
            result.options = kept;
        }
        const group = ModuleRules.get(entry, "group");
        if (group !== undefined) {
            if (!isOwnSettingKey(id, group) && group !== "mod." + id)
                return key + ": group " + ModuleRules.show(group) + " is not mod." + id + " or under it";
            result.group = group;
        }
        for (const field of ["hint", "suffix"]) {
            const text = ModuleRules.get(entry, field);
            if (text === undefined)
                continue;
            if (typeof text !== "string" || text.length > 500)
                return key + ": " + field + " is not a short text";
            result[field] = text;
        }
        const global = ModuleRules.get(entry, "global");
        if (global !== undefined && typeof global !== "boolean")
            return key + ": global is not true or false";
        if (global === true)
            result.global = true;
        return result;
    }

    function _checkFact(id, entry) {
        const fact = ModuleRules.get(entry, "fact");
        if (!isOwnFact(id, fact))
            return "fact " + ModuleRules.show(fact) + " is not " + id + ".<name> (a module's facts live under " + id + ".)";
        const label = ModuleRules.get(entry, "label");
        if (!ModuleRules.isString(label, 200))
            return fact + ": label is missing or not a short text";
        const type = ModuleRules.get(entry, "type");
        if (!ModuleRules.factTypeNames.includes(type))
            return fact + ": type " + ModuleRules.show(type) + " is not one of " + ModuleRules.factTypeNames.join(", ");
        const result = { fact: fact, label: label, type: type };
        if (type === "enum") {
            const options = ModuleRules.get(entry, "options");
            if (!Array.isArray(options) || options.length === 0 || options.length > 100
                    || !options.every(option => ModuleRules.isString(option, 200)))
                return fact + ": an enum needs options, a list of texts";
            result.options = options.slice();
        }
        return result;
    }

    function _checkSlot(entry) {
        const slot = ModuleRules.get(entry, "slot");
        if (typeof slot !== "string" || slot.length > 100 || !/^[a-z][A-Za-z0-9]*(\.[a-z][A-Za-z0-9]*)*$/.test(slot))
            return "slot " + ModuleRules.show(slot) + " is not a slot's name (dotted, such as network.vpn.row)";
        const component = _file(entry, "component", true);
        if (component.error)
            return component.error;
        return { slot: slot, component: component.path };
    }

    // Reads module.json's text. Never throws. → {
    //   valid        the required fields are there and fine (the module can be considered)
    //   id, name, version, api, description, main ("" for none)
    //   widgets, settingsPages, settings, facts, slots   the entries kept, checked
    //   programs, optionalPrograms, testPrograms ("" for none, else without a trailing "/"),
    //   setupHints, tests
    //   exports      (1.18) { version } or null; uses (1.18) [{ id, version }]
    //   unknownFields   names of top-level fields this shell does not know (kept in raw)
    //   raw          the parsed object as written, or null
    //   errors, warnings
    // }
    function parseManifest(text) {
        const result = {
            valid: false, id: "", name: "", version: "", api: "", description: "", main: "",
            widgets: [], settingsPages: [], settings: [], facts: [], slots: [],
            programs: [], optionalPrograms: [], testPrograms: "", setupHints: [], tests: [], unknownFields: [], raw: null,
            exports: null, uses: [],
            errors: [], warnings: []
        };
        const errors = result.errors;
        const warnings = result.warnings;
        if (typeof text !== "string") {
            errors.push("module.json could not be read");
            return result;
        }
        if (text.length > ModuleRules.maxManifestBytes) {
            errors.push("module.json is too large (" + text.length + " bytes; at most " + ModuleRules.maxManifestBytes + ")");
            return result;
        }
        let raw;
        try {
            raw = JSON.parse(text);
        } catch (error) {
            errors.push("module.json is not valid JSON: " + String(error.message ?? error).slice(0, 200));
            return result;
        }
        if (!ModuleRules.isObject(raw)) {
            errors.push("module.json is not a JSON object");
            return result;
        }
        result.raw = raw;

        // Required
        const id = ModuleRules.get(raw, "id");
        if (id === undefined)
            errors.push("missing required field \"id\"");
        else if (typeof id !== "string" || !ModuleRules.idPattern.test(id))
            errors.push("id " + ModuleRules.show(id) + " is not a module id (a lowercase letter, then lowercase letters, digits, _ or -; at most 32)");
        else if (ModuleRules.reservedIds.includes(id))
            errors.push("id " + ModuleRules.show(id) + " is reserved for the shell");
        else
            result.id = id;
        const name = ModuleRules.get(raw, "name");
        if (name === undefined)
            errors.push("missing required field \"name\"");
        else if (!ModuleRules.isString(name, 100))
            errors.push("name is not a short text");
        else
            result.name = name;
        const version = ModuleRules.get(raw, "version");
        if (version === undefined)
            errors.push("missing required field \"version\"");
        else if (typeof version !== "string" || !/^[0-9A-Za-z][0-9A-Za-z.+~-]{0,63}$/.test(version))
            errors.push("version " + ModuleRules.show(version) + " is not a version (such as \"1.2.0\")");
        else
            result.version = version;
        const api = ModuleRules.get(raw, "api");
        if (api === undefined)
            errors.push("missing required field \"api\"");
        else if (!ModuleRules.parseApi(api))
            errors.push("api " + ModuleRules.show(api) + " is not \"major.minor\"");
        else
            result.api = api;
        const main = ModuleRules.get(raw, "main");
        if (main !== undefined) {
            const problem = ModuleFileRules.pathProblem(main);
            if (problem !== "")
                errors.push("main " + ModuleRules.show(main) + ": " + problem);
            else
                result.main = main;
        }
        const description = ModuleRules.get(raw, "description");
        if (description !== undefined) {
            if (typeof description === "string" && description.length <= 1000)
                result.description = description;
            else
                warnings.push("description is not a text of at most 1000 characters (ignored)");
        }
        _readExports(raw, result, errors, warnings);
        _readUses(raw, result, errors);
        // Fields of API 1.18 in a manifest that asks for an older one: read all the same,
        // and said — the module is written against an API that does not have them
        const asked = ModuleRules.parseApi(result.api);
        if (asked && (asked.major < 1 || (asked.major === 1 && asked.minor < 18))) {
            for (const field of ["exports", "uses"]) {
                if (ModuleRules.get(raw, field) !== undefined)
                    warnings.push(field + ": a field of API 1.18, the manifest asks for API " + result.api + " (read all the same)");
            }
        }
        result.valid = errors.length === 0;
        // Without a usable id the namespaces cannot be checked: nothing more is read
        if (result.id === "")
            return result;

        const moduleId = result.id;
        result.widgets = _entries(raw, "widgets", ["type", "name", "widget", "popup", "popupPanel", "settings", "multiple",
                                                   "presetDefaults"],
                                  entry => _checkWidget(moduleId, entry), errors, warnings);
        result.settingsPages = _entries(raw, "settingsPages", ["id", "label", "component", "tab", "parent"],
                                        entry => _checkPage(moduleId, entry), errors, warnings);
        result.settings = _entries(raw, "settings", ["key", "label", "type", "default", "group", "global", "hint",
                                                     "suffix", "min", "max", "options"],
                                   entry => _checkSetting(moduleId, entry), errors, warnings);
        result.facts = _entries(raw, "facts", ["fact", "label", "type", "options"],
                                entry => _checkFact(moduleId, entry), errors, warnings);
        result.slots = _entries(raw, "slots", ["slot", "component"], entry => _checkSlot(entry), errors, warnings);
        _dropRepeated(result.widgets, "type", "widgets", errors);
        _dropRepeated(result.widgets.filter(widget => widget.popup), "popup", "widgets", errors);
        _dropRepeated(result.settingsPages, "id", "settingsPages", errors);
        _dropRepeated(result.settings, "key", "settings", errors);
        _dropRepeated(result.facts, "fact", "facts", errors);
        result.widgets = result.widgets.filter(widget => !widget._repeated);
        result.settingsPages = result.settingsPages.filter(page => !page._repeated);
        result.settings = result.settings.filter(setting => !setting._repeated);
        result.facts = result.facts.filter(fact => !fact._repeated);

        const requires = ModuleRules.get(raw, "requires");
        if (requires !== undefined) {
            if (!ModuleRules.isObject(requires)) {
                errors.push("requires: not an object (ignored)");
            } else {
                for (const key of Object.keys(requires)) {
                    if (key !== "programs")
                        warnings.push("requires: unknown field " + ModuleRules.show(key) + " (ignored)");
                }
                _list(requires, "programs", errors).forEach((program, index) => {
                    if (typeof program !== "string" || !/^[A-Za-z0-9_][A-Za-z0-9_.+-]{0,63}$/.test(program))
                        errors.push("requires.programs[" + index + "]: " + ModuleRules.show(program) + " is not a program's name (dropped)");
                    else if (!result.programs.includes(program))
                        result.programs.push(program);
                });
            }
        }
        _list(raw, "optionalPrograms", errors).forEach((program, index) => {
            if (typeof program !== "string" || !/^[A-Za-z0-9_][A-Za-z0-9_.+-]{0,63}$/.test(program))
                errors.push("optionalPrograms[" + index + "]: " + ModuleRules.show(program) + " is not a program's name (dropped)");
            else if (!result.programs.includes(program) && !result.optionalPrograms.includes(program))
                result.optionalPrograms.push(program);
        });
        const testPrograms = ModuleRules.get(raw, "testPrograms");
        if (testPrograms !== undefined) {
            const problem = ModuleFileRules.directoryProblem(testPrograms);
            if (problem !== "")
                errors.push("testPrograms " + ModuleRules.show(testPrograms) + ": " + problem + " (ignored)");
            else
                result.testPrograms = testPrograms.replace(/\/$/, "");
        }
        _list(raw, "setupHints", errors).forEach((hint, index) => {
            if (typeof hint !== "string" || hint.length === 0 || hint.length > 1000)
                errors.push("setupHints[" + index + "]: not a text of at most 1000 characters (dropped)");
            else
                result.setupHints.push(hint);
        });
        _list(raw, "tests", errors).forEach((test, index) => {
            const problem = ModuleFileRules.pathProblem(test);
            if (problem !== "")
                errors.push("tests[" + index + "]: " + ModuleRules.show(test) + ": " + problem + " (dropped)");
            else if (!result.tests.includes(test))
                result.tests.push(test);
        });

        for (const key of Object.keys(raw)) {
            if (!_topFields.includes(key)) {
                result.unknownFields.push(key);
                warnings.push("unknown field " + ModuleRules.show(key) + " (kept; a newer shell may know it)");
            }
        }
        return result;
    }

    // `exports` (API 1.18): { version } → result.exports, or an error (the module fails: a
    // declaration other modules rely on is not guessed at)
    function _readExports(raw, result, errors, warnings) {
        const given = ModuleRules.get(raw, "exports");
        if (given === undefined)
            return;
        if (!ModuleRules.isObject(given)) {
            errors.push("exports: not an object such as { \"version\": \"1.0\" }");
            return;
        }
        for (const key of Object.keys(given)) {
            if (key !== "version")
                warnings.push("exports: unknown field " + ModuleRules.show(key) + " (ignored)");
        }
        const version = ModuleRules.get(given, "version");
        if (version === undefined)
            errors.push("exports: missing \"version\"");
        else if (!ModuleRules.parseApi(version))
            errors.push("exports.version " + ModuleRules.show(version) + " is not \"major.minor\"");
        else
            result.exports = { version: version };
    }

    // `uses` (API 1.18): { <id>: "major.minor" } → result.uses, [{ id, version }] in the
    // manifest's order, or errors (the module fails: it would run without what it needs).
    // Using itself is left to the dependency plan, which names it as a cycle.
    function _readUses(raw, result, errors) {
        const given = ModuleRules.get(raw, "uses");
        if (given === undefined)
            return;
        if (!ModuleRules.isObject(given)) {
            errors.push("uses: not an object such as { \"tailscale\": \"1.0\" }");
            return;
        }
        const ids = Object.keys(given);
        if (ids.length > ModuleRules.maxEntries) {
            errors.push("uses: " + ids.length + " modules, at most " + ModuleRules.maxEntries);
            return;
        }
        for (const id of ids) {
            const version = given[id];
            if (!ModuleRules.idPattern.test(id) || ModuleRules.reservedIds.includes(id))
                errors.push("uses: " + ModuleRules.show(id) + " is not a module id");
            else if (!ModuleRules.parseApi(version))
                errors.push("uses." + id + ": " + ModuleRules.show(version) + " is not a version \"major.minor\"");
            else
                result.uses.push({ id: id, version: version });
        }
    }

    // Marks every entry after the first with the same `field` as repeated, with an error
    function _dropRepeated(entries, field, list, errors) {
        const seen = [];
        for (const entry of entries) {
            if (seen.includes(entry[field])) {
                entry._repeated = true;
                errors.push(list + ": " + ModuleRules.show(entry[field]) + " is listed twice (the second dropped)");
            } else {
                seen.push(entry[field]);
            }
        }
    }
}
