pragma Singleton

import Quickshell
import QtQuick

// The module system's decisions (docs/plans/modules.md) — pure, so tests/ModuleRulesTest.qml
// checks them without a module on disk: reading and checking a manifest, whether its API
// version fits the shell's, the namespaces a module's contributions must stay in, the import
// check (a warning, by the owner's decision), which of two modules with one id wins, the
// state a module is in, and the contributions of several modules merged into the lists the
// core's registries will read. No file, no process, no other singleton; ModuleHost does the
// I/O. Nothing here throws on any input: a manifest is written by someone else.
//
// THE MANIFEST (module.json, in the module's directory) — the public format:
//
//   id            required. ^[a-z][a-z0-9_-]{0,31}$, not one of `reservedIds`. The module's
//                 name everywhere: its settings are mod.<id>.*, its facts <id>.*, its widget
//                 types, popups and settings pages <id> or <id>.<name>.
//   name          required. A non-empty string (shown in Settings → Modules).
//   version       required. The module's own version, ^[0-9A-Za-z][0-9A-Za-z.+~-]{0,63}$
//                 (semver recommended, not enforced).
//   api           required. The module API it is written for, "major.minor" (Api.version):
//                 compatible when the major is the shell's and the minor not above it.
//   description   optional string.
//   main          optional. A .qml file the host creates once the module is enabled: its
//                 IPC handlers, its facts, its long-lived objects. A module of widgets only
//                 needs none.
//   widgets       optional list of bar widget types, WidgetRegistry's fields:
//                 { type, name, widget, popup?, popupPanel?, settings?, multiple? }
//                 type and popup are <id> or <id>.<name>; widget, popupPanel, settings are
//                 files of the module; popupPanel needs popup.
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
//                 { slot, component } — slot a dotted name ("network.vpn.row").
//   requires      optional: { programs: [names] } — programs that must be on PATH; without
//                 them the module is not loaded (state missing-program) and its setupHints
//                 are shown.
//   setupHints    optional list of strings: how to get the module working.
//   tests         optional list of .qml test suites (tests/run-modules.sh runs them).
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

    // The largest module.json read; anything bigger is refused before parsing
    readonly property int maxManifestBytes: 256 * 1024
    // At most this many entries in each list of a manifest; the rest is dropped (an error)
    readonly property int maxEntries: 200
    // How much of a QML file the import check looks at (imports sit at the top)
    readonly property int maxHeaderBytes: 64 * 1024

    readonly property var idPattern: /^[a-z][a-z0-9_-]{0,31}$/

    // Ids a module cannot take: the core's own namespaces (settings groups and key prefixes,
    // fact prefixes, IPC targets, directories) — a module with id "battery" would own the
    // facts battery.* — and words that mean the shell itself. ModuleRulesTest checks that
    // every prefix of a core setting and fact is here.
    readonly property var reservedIds: [
        "animation", "animations", "api", "app", "appearance", "audio", "auth", "authentication", "bar", "battery",
        "bluetooth", "calendar", "clock", "colors", "components", "config", "constructor",
        "core", "curves", "debug", "dictation", "energy", "fonts", "gcal", "general", "graphs", "h2s",
        "h2s-shell", "hardware", "hud", "input", "ipc", "launcher", "lock", "lockscreen",
        "media", "mod", "module", "modules", "music", "network", "notifications", "panel",
        "panels", "performance", "polkit", "polling", "power", "profile", "profiles", "prototype", "qs",
        "quickshell", "safe-mode", "screen", "screensaver", "settings", "shell", "singletons",
        "sound", "stt", "system", "test", "tests", "theme", "themes", "tray", "vpn", "wallpaper",
        "wallpapers", "widget", "widgets", "window", "workspaces"
    ]

    // What a module's QML may import without a warning (plan §4, a warning by the owner's
    // decision): these modules, anything under the prefixes, and its own directory
    readonly property var allowedImports: ["Quickshell", "Quickshell.Io", "qs.api", "qs.components"]
    readonly property var allowedImportPrefixes: ["QtQuick", "QtQml"]

    readonly property var settingTypes: ["bool", "number", "slider", "interval", "enum", "string", "stringList"]
    readonly property var factTypeNames: ["bool", "number", "percent", "string", "enum"]
    readonly property var settingsTabs: ["behaviour", "appearance", "system"]

    // The states a module can be in (statusOf):
    //   loaded           running: its main (if any) was created, its contributions count
    //   disabled         turned off in Settings → Modules (Config.disabledModules)
    //   failed           its manifest is unusable, or its main could not be created
    //   incompatible     written for another module API
    //   missing-program  a program in requires.programs is not on PATH
    //   duplicate        another module with the same id came first (search-path order)
    //   pending          waiting for the check of its required programs
    //   safe-mode        the shell started in safe mode: no module is loaded
    readonly property var states: ["loaded", "disabled", "failed", "incompatible", "missing-program",
                                   "duplicate", "pending", "safe-mode"]

    // ---- Small helpers ----

    function _isObject(value) {
        return value !== null && typeof value === "object" && !Array.isArray(value);
    }

    function _isString(value, maxLength) {
        return typeof value === "string" && value.length > 0 && value.length <= (maxLength ?? 1000);
    }

    // An own, enumerable field — never one from the prototype ("constructor", "toString")
    function _has(object, key) {
        return Object.prototype.hasOwnProperty.call(object, key);
    }

    function _get(object, key) {
        return _has(object, key) ? object[key] : undefined;
    }

    // A value as short text for a message: never the whole of a huge string
    function _show(value) {
        let text;
        try {
            text = typeof value === "string" ? JSON.stringify(value) : String(JSON.stringify(value));
        } catch (error) {
            text = "?";
        }
        return text.length > 60 ? text.slice(0, 57) + "…" : text;
    }

    // ---- Paths ----

    // A path made canonical without the file system: absolute, no "." or ".." segments, no
    // repeated or trailing "/". "" when it is not an absolute path. Two spellings of one
    // directory load its singletons twice (plan §2: "a//b" does, "a/./b" does not, a symlink
    // does): the launcher resolves symlinks (realpath), this takes care of the rest.
    function canonicalPath(path) {
        if (typeof path !== "string" || !path.startsWith("/") || path.includes("\0"))
            return "";
        const parts = [];
        for (const part of path.split("/")) {
            if (part === "" || part === ".")
                continue;
            if (part === "..")
                parts.pop();
            else
                parts.push(part);
        }
        return "/" + parts.join("/");
    }

    // H2S_SHELL_MODULES (colon-separated) or a list given to the host: the canonical module
    // directories, in order, each once; what was not an absolute path is reported
    function moduleDirectories(value) {
        const list = typeof value === "string" ? value.split(":") : Array.isArray(value) ? value : [];
        const directories = [];
        const ignored = [];
        for (const entry of list) {
            if (entry === "" || entry === undefined || entry === null)
                continue;
            const canonical = canonicalPath(entry);
            if (canonical === "" || canonical === "/") {
                ignored.push(String(entry));
                continue;
            }
            if (!directories.includes(canonical))
                directories.push(canonical);
        }
        return { directories: directories, ignored: ignored };
    }

    // A file of a module, as given in its manifest: "" when fine, else why not
    function pathProblem(path) {
        if (typeof path !== "string" || path === "")
            return "not a file name";
        if (path.length > 300)
            return "too long";
        if (path.startsWith("/"))
            return "an absolute path";
        if (!/^[A-Za-z0-9_][A-Za-z0-9_./-]*$/.test(path))
            return "has characters a module file name may not have";
        if (path.split("/").some(part => part === ".." || part === "." || part === ""))
            return "leaves the module's directory or is not a plain path";
        if (!path.endsWith(".qml"))
            return "not a .qml file";
        return "";
    }

    // The file:// URL of a module's file. Only what a URL cannot hold as it is is escaped,
    // so that one file always gets one spelling
    function fileUrl(directory, relative) {
        const path = canonicalPath(directory + "/" + relative);
        return "file://" + path.replace(/%/g, "%25").replace(/#/g, "%23").replace(/\?/g, "%3F");
    }

    // ---- API versions ----

    // "major.minor" → { major, minor }, or null
    function parseApi(value) {
        if (typeof value !== "string")
            return null;
        const match = /^(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})$/.exec(value);
        return match ? { major: Number(match[1]), minor: Number(match[2]) } : null;
    }

    // Whether a module asking for API `wanted` runs on a shell with API `shell`
    // → { compatible, reason }
    function apiCompatibility(wanted, shell) {
        const module = parseApi(wanted);
        const have = parseApi(shell);
        if (!module)
            return { compatible: false, reason: "its API version " + _show(wanted) + " is not \"major.minor\"" };
        if (!have)
            return { compatible: false, reason: "the shell's API version " + _show(shell) + " is not \"major.minor\"" };
        if (module.major !== have.major)
            return { compatible: false, reason: "written for module API " + wanted + "; the shell has " + shell
                     + (module.major > have.major ? " (a newer shell is needed)" : " (the module needs updating)") };
        if (module.minor > have.minor)
            return { compatible: false, reason: "needs module API " + wanted + "; the shell has " + shell + " (a newer shell is needed)" };
        return { compatible: true, reason: "" };
    }

    // ---- Namespaces ----

    function validId(id) {
        return typeof id === "string" && idPattern.test(id) && !reservedIds.includes(id);
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
        "settingsPages", "settings", "facts", "slots", "requires", "setupHints", "tests"]

    // A list field: its entries (at most maxEntries), or [] with an error when it is not a list
    function _list(raw, field, errors) {
        const value = _get(raw, field);
        if (value === undefined)
            return [];
        if (!Array.isArray(value)) {
            errors.push(field + ": not a list (ignored)");
            return [];
        }
        if (value.length > maxEntries) {
            errors.push(field + ": " + value.length + " entries, only the first " + maxEntries + " are read");
            return value.slice(0, maxEntries);
        }
        return value;
    }

    // Each entry of a list checked by `check(entry, where)`, which returns the entry to keep
    // or a string (why it is dropped); fields an entry has beyond `known` are warned about
    function _entries(raw, field, known, check, errors, warnings) {
        const kept = [];
        _list(raw, field, errors).forEach((entry, index) => {
            const where = field + "[" + index + "]";
            if (!_isObject(entry)) {
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
                    warnings.push(where + ": unknown field " + _show(key) + " (ignored)");
            }
            kept.push(result);
        });
        return kept;
    }

    // A file field of an entry → { path } (path "" when absent and not required) or
    // { error }
    function _file(entry, field, required) {
        const value = _get(entry, field);
        if (value === undefined)
            return required ? { error: field + " is missing" } : { path: "" };
        const problem = pathProblem(value);
        return problem === "" ? { path: value } : { error: field + " " + _show(value) + ": " + problem };
    }

    function _checkWidget(id, entry) {
        const type = _get(entry, "type");
        if (!isOwnName(id, type))
            return "type " + _show(type) + " is not \"" + id + "\" or \"" + id + ".<name>\"";
        const name = _get(entry, "name");
        if (!_isString(name, 100))
            return "name is missing or not a short text";
        const widget = _file(entry, "widget", true);
        if (widget.error)
            return widget.error;
        const result = { type: type, name: name, widget: widget.path };
        const popup = _get(entry, "popup");
        if (popup !== undefined) {
            if (!isOwnName(id, popup))
                return "popup " + _show(popup) + " is not \"" + id + "\" or \"" + id + ".<name>\"";
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
        const multiple = _get(entry, "multiple");
        if (multiple !== undefined && typeof multiple !== "boolean")
            return "multiple is not true or false";
        result.multiple = multiple === true;
        return result;
    }

    function _checkPage(id, entry) {
        const pageId = _get(entry, "id");
        if (!isOwnName(id, pageId))
            return "id " + _show(pageId) + " is not \"" + id + "\" or \"" + id + ".<name>\"";
        const label = _get(entry, "label");
        if (!_isString(label, 100))
            return "label is missing or not a short text";
        const component = _file(entry, "component", true);
        if (component.error)
            return component.error;
        const tab = _get(entry, "tab") ?? "behaviour";
        if (!settingsTabs.includes(tab))
            return "tab " + _show(tab) + " is not one of " + settingsTabs.join(", ");
        const result = { id: pageId, label: label, component: component.path, tab: tab };
        const parent = _get(entry, "parent");
        if (parent !== undefined) {
            if (typeof parent !== "string" || !/^[a-z][a-z0-9_]{0,40}$/.test(parent))
                return "parent " + _show(parent) + " is not the id of a group of pages";
            result.parent = parent;
        }
        return result;
    }

    function _isNumber(value) {
        return typeof value === "number" && isFinite(value);
    }

    function _checkSetting(id, entry) {
        const key = _get(entry, "key");
        if (!isOwnSettingKey(id, key))
            return "key " + _show(key) + " is not mod." + id + ".<name> (a module's settings live under mod." + id + ")";
        const label = _get(entry, "label");
        if (!_isString(label, 200))
            return key + ": label is missing or not a short text";
        const type = _get(entry, "type");
        if (!settingTypes.includes(type))
            return key + ": type " + _show(type) + " is not one of " + settingTypes.join(", ");
        if (!_has(entry, "default"))
            return key + ": no default";
        const value = entry["default"];
        const result = { key: key, label: label, type: type, "default": value, group: "mod." + id };
        for (const field of ["min", "max"]) {
            const bound = _get(entry, field);
            if (bound === undefined)
                continue;
            if (!_isNumber(bound))
                return key + ": " + field + " is not a number";
            result[field] = bound;
        }
        if (type === "bool" && typeof value !== "boolean")
            return key + ": the default is not true or false";
        if (type === "number" || type === "slider" || type === "interval") {
            if (!_isNumber(value))
                return key + ": the default is not a number";
            if ((result.min !== undefined && value < result.min) || (result.max !== undefined && value > result.max))
                return key + ": the default is outside min..max";
        }
        if (type === "string" && typeof value !== "string")
            return key + ": the default is not a text";
        if (type === "stringList" && !(Array.isArray(value) && value.every(item => typeof item === "string")))
            return key + ": the default is not a list of texts";
        if (type === "enum") {
            const options = _get(entry, "options");
            if (!Array.isArray(options) || options.length === 0 || options.length > 100)
                return key + ": an enum needs options";
            const kept = [];
            for (const option of options) {
                const optionValue = _isObject(option) ? _get(option, "value") : undefined;
                const optionLabel = _isObject(option) ? _get(option, "label") : undefined;
                if (!["string", "number", "boolean"].includes(typeof optionValue) || !_isString(optionLabel, 200))
                    return key + ": an option is not { value, label }";
                kept.push({ value: optionValue, label: optionLabel });
            }
            if (!kept.some(option => option.value === value))
                return key + ": the default is not one of the options";
            result.options = kept;
        }
        const group = _get(entry, "group");
        if (group !== undefined) {
            if (!isOwnSettingKey(id, group) && group !== "mod." + id)
                return key + ": group " + _show(group) + " is not mod." + id + " or under it";
            result.group = group;
        }
        for (const field of ["hint", "suffix"]) {
            const text = _get(entry, field);
            if (text === undefined)
                continue;
            if (typeof text !== "string" || text.length > 500)
                return key + ": " + field + " is not a short text";
            result[field] = text;
        }
        const global = _get(entry, "global");
        if (global !== undefined && typeof global !== "boolean")
            return key + ": global is not true or false";
        if (global === true)
            result.global = true;
        return result;
    }

    function _checkFact(id, entry) {
        const fact = _get(entry, "fact");
        if (!isOwnFact(id, fact))
            return "fact " + _show(fact) + " is not " + id + ".<name> (a module's facts live under " + id + ".)";
        const label = _get(entry, "label");
        if (!_isString(label, 200))
            return fact + ": label is missing or not a short text";
        const type = _get(entry, "type");
        if (!factTypeNames.includes(type))
            return fact + ": type " + _show(type) + " is not one of " + factTypeNames.join(", ");
        const result = { fact: fact, label: label, type: type };
        if (type === "enum") {
            const options = _get(entry, "options");
            if (!Array.isArray(options) || options.length === 0 || options.length > 100
                    || !options.every(option => _isString(option, 200)))
                return fact + ": an enum needs options, a list of texts";
            result.options = options.slice();
        }
        return result;
    }

    function _checkSlot(entry) {
        const slot = _get(entry, "slot");
        if (typeof slot !== "string" || slot.length > 100 || !/^[a-z][A-Za-z0-9]*(\.[a-z][A-Za-z0-9]*)*$/.test(slot))
            return "slot " + _show(slot) + " is not a slot's name (dotted, such as network.vpn.row)";
        const component = _file(entry, "component", true);
        if (component.error)
            return component.error;
        return { slot: slot, component: component.path };
    }

    // Reads module.json's text. Never throws. → {
    //   valid        the required fields are there and fine (the module can be considered)
    //   id, name, version, api, description, main ("" for none)
    //   widgets, settingsPages, settings, facts, slots   the entries kept, checked
    //   programs, setupHints, tests
    //   unknownFields   names of top-level fields this shell does not know (kept in raw)
    //   raw          the parsed object as written, or null
    //   errors, warnings
    // }
    function parseManifest(text) {
        const result = {
            valid: false, id: "", name: "", version: "", api: "", description: "", main: "",
            widgets: [], settingsPages: [], settings: [], facts: [], slots: [],
            programs: [], setupHints: [], tests: [], unknownFields: [], raw: null,
            errors: [], warnings: []
        };
        const errors = result.errors;
        const warnings = result.warnings;
        if (typeof text !== "string") {
            errors.push("module.json could not be read");
            return result;
        }
        if (text.length > maxManifestBytes) {
            errors.push("module.json is too large (" + text.length + " bytes; at most " + maxManifestBytes + ")");
            return result;
        }
        let raw;
        try {
            raw = JSON.parse(text);
        } catch (error) {
            errors.push("module.json is not valid JSON: " + String(error.message ?? error).slice(0, 200));
            return result;
        }
        if (!_isObject(raw)) {
            errors.push("module.json is not a JSON object");
            return result;
        }
        result.raw = raw;

        // Required
        const id = _get(raw, "id");
        if (id === undefined)
            errors.push("missing required field \"id\"");
        else if (typeof id !== "string" || !idPattern.test(id))
            errors.push("id " + _show(id) + " is not a module id (a lowercase letter, then lowercase letters, digits, _ or -; at most 32)");
        else if (reservedIds.includes(id))
            errors.push("id " + _show(id) + " is reserved for the shell");
        else
            result.id = id;
        const name = _get(raw, "name");
        if (name === undefined)
            errors.push("missing required field \"name\"");
        else if (!_isString(name, 100))
            errors.push("name is not a short text");
        else
            result.name = name;
        const version = _get(raw, "version");
        if (version === undefined)
            errors.push("missing required field \"version\"");
        else if (typeof version !== "string" || !/^[0-9A-Za-z][0-9A-Za-z.+~-]{0,63}$/.test(version))
            errors.push("version " + _show(version) + " is not a version (such as \"1.2.0\")");
        else
            result.version = version;
        const api = _get(raw, "api");
        if (api === undefined)
            errors.push("missing required field \"api\"");
        else if (!parseApi(api))
            errors.push("api " + _show(api) + " is not \"major.minor\"");
        else
            result.api = api;
        const main = _get(raw, "main");
        if (main !== undefined) {
            const problem = pathProblem(main);
            if (problem !== "")
                errors.push("main " + _show(main) + ": " + problem);
            else
                result.main = main;
        }
        const description = _get(raw, "description");
        if (description !== undefined) {
            if (typeof description === "string" && description.length <= 1000)
                result.description = description;
            else
                warnings.push("description is not a text of at most 1000 characters (ignored)");
        }
        result.valid = errors.length === 0;
        // Without a usable id the namespaces cannot be checked: nothing more is read
        if (result.id === "")
            return result;

        const moduleId = result.id;
        result.widgets = _entries(raw, "widgets", ["type", "name", "widget", "popup", "popupPanel", "settings", "multiple"],
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

        const requires = _get(raw, "requires");
        if (requires !== undefined) {
            if (!_isObject(requires)) {
                errors.push("requires: not an object (ignored)");
            } else {
                for (const key of Object.keys(requires)) {
                    if (key !== "programs")
                        warnings.push("requires: unknown field " + _show(key) + " (ignored)");
                }
                _list(requires, "programs", errors).forEach((program, index) => {
                    if (typeof program !== "string" || !/^[A-Za-z0-9_][A-Za-z0-9_.+-]{0,63}$/.test(program))
                        errors.push("requires.programs[" + index + "]: " + _show(program) + " is not a program's name (dropped)");
                    else if (!result.programs.includes(program))
                        result.programs.push(program);
                });
            }
        }
        _list(raw, "setupHints", errors).forEach((hint, index) => {
            if (typeof hint !== "string" || hint.length === 0 || hint.length > 1000)
                errors.push("setupHints[" + index + "]: not a text of at most 1000 characters (dropped)");
            else
                result.setupHints.push(hint);
        });
        _list(raw, "tests", errors).forEach((test, index) => {
            const problem = pathProblem(test);
            if (problem !== "")
                errors.push("tests[" + index + "]: " + _show(test) + ": " + problem + " (dropped)");
            else if (!result.tests.includes(test))
                result.tests.push(test);
        });

        for (const key of Object.keys(raw)) {
            if (!_topFields.includes(key)) {
                result.unknownFields.push(key);
                warnings.push("unknown field " + _show(key) + " (kept; a newer shell may know it)");
            }
        }
        return result;
    }

    // Marks every entry after the first with the same `field` as repeated, with an error
    function _dropRepeated(entries, field, list, errors) {
        const seen = [];
        for (const entry of entries) {
            if (seen.includes(entry[field])) {
                entry._repeated = true;
                errors.push(list + ": " + _show(entry[field]) + " is listed twice (the second dropped)");
            } else {
                seen.push(entry[field]);
            }
        }
    }

    // The module's files the host should check imports of: main and every component its
    // entries name, each once
    function manifestFiles(manifest) {
        const files = [];
        const add = file => {
            if (typeof file === "string" && file !== "" && !files.includes(file))
                files.push(file);
        };
        add(manifest?.main);
        for (const widget of manifest?.widgets ?? []) {
            add(widget.widget);
            add(widget.popupPanel);
            add(widget.settings);
        }
        for (const page of manifest?.settingsPages ?? [])
            add(page.component);
        for (const slot of manifest?.slots ?? [])
            add(slot.component);
        return files;
    }

    // The QML files a qmldir names (its types and singletons), relative to its directory;
    // plugins, imports and other directives are skipped
    function qmldirFiles(text) {
        const files = [];
        if (typeof text !== "string")
            return files;
        for (const rawLine of text.slice(0, maxHeaderBytes).split("\n")) {
            const words = rawLine.replace(/#.*$/, "").trim().split(/\s+/);
            if (words[0] === "singleton" || words[0] === "internal")
                words.shift();
            if (words.length < 2 || !/^[A-Z]/.test(words[0]))
                continue;
            const file = words[words.length - 1];
            if (pathProblem(file) === "" && !files.includes(file))
                files.push(file);
        }
        return files;
    }

    // ---- The import check (a warning, never a refusal) ----

    // The imports at the top of a QML file: [{ name, directory }] — `name` a module name
    // (QtQuick.Layouts) or, for a quoted import, the quoted text with `directory` true. Read
    // as Quickshell's scanner reads them: line by line until the first line with a "{".
    function importsOf(text) {
        const imports = [];
        if (typeof text !== "string")
            return imports;
        const header = text.slice(0, maxHeaderBytes).replace(/\/\*[\s\S]*?\*\//g, " ");
        for (const rawLine of header.split("\n")) {
            // A line comment, not a "//" inside a quoted import ("file:///…")
            const line = rawLine.replace(/^((?:[^"\/]|"[^"]*"|\/(?!\/))*)\/\/.*$/, "$1").trim();
            if (line.includes("{"))
                break;
            for (const statement of line.split(";")) {
                const match = /^import\s+(?:"([^"]*)"|([A-Za-z_][A-Za-z0-9_.]*))/.exec(statement.trim());
                if (!match)
                    continue;
                imports.push(match[1] !== undefined ? { name: match[1], directory: true } : { name: match[2], directory: false });
            }
        }
        return imports;
    }

    // An import a module may make: an allowed module, or a directory inside its own
    function importAllowed(entry) {
        if (entry.directory) {
            const path = entry.name;
            return path !== "" && !path.includes(":") && !path.startsWith("/")
                && !path.split("/").includes("..");
        }
        return allowedImports.includes(entry.name)
            || allowedImportPrefixes.some(prefix => entry.name === prefix || entry.name.startsWith(prefix + "."));
    }

    // The warnings for one file of a module: one per import outside the allowlist
    function importWarnings(file, text) {
        return importsOf(text).filter(entry => !importAllowed(entry)).map(entry =>
            file + " imports " + (entry.directory ? "\"" + entry.name + "\"" : entry.name)
            + ", outside what modules may import (" + allowedImports.concat(allowedImportPrefixes.map(prefix => prefix + "*")).join(", ")
            + ", the module's own directory)");
    }

    // ---- Several modules ----

    // Search-path precedence: `candidates` in search order, each { directory, id } (id ""
    // when the manifest had none). → one entry per candidate: { winner, shadowedBy } — the
    // first with an id wins, a later one with the same id is shadowed by the winner's
    // directory. One without an id is never shadowed and shadows nothing.
    function precedence(candidates) {
        const owners = new Map();
        return (candidates ?? []).map(candidate => {
            const id = candidate?.id ?? "";
            if (id === "")
                return { winner: true, shadowedBy: "" };
            if (owners.has(id))
                return { winner: false, shadowedBy: owners.get(id) };
            owners.set(id, candidate.directory);
            return { winner: true, shadowedBy: "" };
        });
    }

    // The state of one module, from what is known of it (see `states`). `facts`:
    //   valid, compatible, duplicate, safeMode, enabled  booleans
    //   settingsKnown      the config (which modules are off) has been read; false: pending
    //   programsKnown      the check of requires.programs has answered (true when none)
    //   missingPrograms    the ones not found
    //   mainError          why its main could not be created ("" for none)
    function stateOf(facts) {
        if (!facts?.valid)
            return "failed";
        if (facts.duplicate)
            return "duplicate";
        if (!facts.compatible)
            return "incompatible";
        if (facts.safeMode)
            return "safe-mode";
        if (facts.settingsKnown === false)
            return "pending";
        if (!facts.enabled)
            return "disabled";
        if (!facts.programsKnown)
            return "pending";
        if ((facts.missingPrograms ?? []).length > 0)
            return "missing-program";
        if (facts.mainError)
            return "failed";
        return "loaded";
    }

    // A module's contributions count only while it is loaded
    function contributes(state) {
        return state === "loaded";
    }

    // The contributions of the loaded modules merged into the lists the core's registries
    // read, every file an absolute file:// URL, every entry marked with its module. Stable:
    // modules by id, each one's entries in manifest order — not in search-path order, which
    // differs from one machine to the next. `modules`: [{ id, directory, manifest }].
    // → { widgetEntries, settingsPages, settingEntries, factTypes, slots: { name: [...] } }
    function merge(modules) {
        const result = { widgetEntries: [], settingsPages: [], settingEntries: [], factTypes: [], slots: ({}) };
        const sorted = (modules ?? []).filter(module => module && typeof module.id === "string" && module.manifest)
            .slice().sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
        const slotMap = new Map();
        for (const module of sorted) {
            const url = file => file ? fileUrl(module.directory, file) : "";
            for (const widget of module.manifest.widgets ?? []) {
                const entry = { module: module.id, type: widget.type, name: widget.name, widget: url(widget.widget),
                                multiple: widget.multiple === true };
                if (widget.popup)
                    entry.popup = widget.popup;
                if (widget.popupPanel)
                    entry.popupPanel = url(widget.popupPanel);
                if (widget.settings)
                    entry.settings = url(widget.settings);
                result.widgetEntries.push(entry);
            }
            for (const page of module.manifest.settingsPages ?? [])
                result.settingsPages.push(Object.assign({}, page, { module: module.id, component: url(page.component) }));
            for (const setting of module.manifest.settings ?? [])
                result.settingEntries.push(Object.assign({}, setting, { module: module.id }));
            for (const fact of module.manifest.facts ?? [])
                result.factTypes.push(Object.assign({}, fact, { module: module.id }));
            for (const slot of module.manifest.slots ?? []) {
                if (!slotMap.has(slot.slot))
                    slotMap.set(slot.slot, []);
                slotMap.get(slot.slot).push({ module: module.id, slot: slot.slot, component: url(slot.component) });
            }
        }
        // A plain object for QML, built without the prototype's names ever mattering: slot
        // names are checked dotted words, and are looked up with slotContributions()
        const slots = Object.create(null);
        for (const [name, entries] of slotMap)
            slots[name] = entries;
        result.slots = slots;
        return result;
    }

    // The contributions to one slot, from merge()'s `slots`
    function slotContributions(slots, name) {
        if (!slots || typeof name !== "string" || !Object.prototype.hasOwnProperty.call(slots, name))
            return [];
        return slots[name];
    }

    // One module's status, as the host keeps it and `qs ipc call modules list` prints it.
    // Every field plain data; nothing the module itself computed (no secrets).
    function statusOf(record) {
        const manifest = record?.manifest ?? null;
        const state = typeof record?.state === "string" ? record.state : "failed";
        return {
            id: manifest?.id ?? "",
            name: manifest?.name ?? "",
            version: manifest?.version ?? "",
            api: manifest?.api ?? "",
            description: manifest?.description ?? "",
            directory: record?.directory ?? "",
            state: state,
            enabled: record?.enabled !== false,
            errors: (record?.errors ?? []).slice(),
            warnings: (record?.warnings ?? []).slice(),
            missingPrograms: (record?.missingPrograms ?? []).slice(),
            setupHints: state === "missing-program" ? (manifest?.setupHints ?? []).slice() : [],
            shadowedBy: record?.shadowedBy ?? ""
        };
    }
}
