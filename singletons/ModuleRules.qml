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

    // The module API this shell offers, "major.minor" — published as Api.version (qs.api).
    // Kept here, not in api/, so that the host (qs.singletons) never imports qs.api: qs.api
    // imports qs.singletons, and the two importing each other would be a cycle. Adding to
    // the API (a slot, a function, a manifest field) bumps the minor; changing or removing
    // anything bumps the major. docs/plans/modules.md, "Module API 1.0", is the surface.
    readonly property string apiVersion: "1.3"

    // ---- The slots the core offers (API 1.0; the VPN ones since 1.1) ----
    //
    // A slot is a place in a panel the core owns where modules may put content
    // (components/ModuleSlot.qml). Each contribution is built in a guard of its own, with
    // the context below as its `context` property (passed again only when its value
    // changes) and the module's handle as `module`. Adding a slot bumps the API's minor.
    //
    // NEVER a slot on the lock screen, the screensaver or anything under singletons/lock:
    // nothing foreign is drawn or run there (docs/plans/modules.md §4, item 1).
    // tests/ModuleRegistriesTest.qml checks that no file there names ModuleSlot.
    readonly property var slotTable: [
        { name: "network.popup.sections", since: "1.0",
          where: "the network popup (panels/NetworkPanel.qml), under the VPN, Ethernet and Wi-Fi sections, above the network list",
          context: "{ slot, wifiEnabled: bool, wifiConnected: bool, ethernetConnected: bool }" },
        { name: "notifications.popup.top", since: "1.0",
          where: "the notifications popup (panels/NotificationPanel.qml), above the list",
          context: "{ slot, count: the number of notifications in the list }" },
        { name: "settings.general.bottom", since: "1.0",
          where: "Settings → Behaviour → General, at the end of the page",
          context: "{ slot, editIndex: the profile being edited (for SettingEditor) }" },
        // The VPN provider seam's three (docs/plans/tailscale.md §3; VpnManager.extrasFor and
        // pageOf ask here first): one contribution per provider, the one of the module whose
        // id is the provider's providerId — a module's provider uses its module id
        // (`VpnProvider { providerId: module.moduleId }`). A provider that is no module's keeps
        // its own rowExtras, cardExtras and pageUrl.
        { name: "network.vpn.row", since: "1.1",
          where: "the network popup's VPN section (panels/network/VpnSection.qml), under the row of each VPN of the module's provider",
          context: "{ slot, vpnId, entryId, vpn, provider, otherVpnsUp: [names of the other VPNs up] }" },
        { name: "network.vpn.card", since: "1.1",
          where: "Settings → System → Network → VPN, on the card of each VPN of the module's provider, while the card is open",
          context: "{ slot, vpnId, entryId, vpn, provider, otherVpnsUp, open: bool }" },
        { name: "network.vpn.page", since: "1.1",
          where: "a page over Settings → System → Network → VPN, opened from the card's \"Settings…\", in the core's frame (Back, title, scrolling)",
          context: "{ slot, vpnId, entryId, vpn, provider, otherVpnsUp, close: function }" }
    ]
    readonly property var slotNames: slotTable.map(entry => entry.name)

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
        "wallpapers", "widget", "widgets", "window", "workspaces",
        // IPC targets of the core (a module's IpcHandler targets are <id> or <id>.<name>),
        // including the test seams' and the VPN branch's fake provider's
        "tablet", "locktest", "shelltest", "fakevpn",
        // Settings page ids and popup keys of the core that are module-id shaped
        "bar_appearance", "controls", "popups", "network_ethernet", "network_overview", "network_vpn",
        "network_wifi", "notifications_appearance", "other_appearance", "widgets_appearance", "tray-menu"
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
        const presetDefaults = _get(entry, "presetDefaults");
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
        if (!_isObject(value))
            return "not an object";
        const keys = Object.keys(value);
        if (keys.length > 50)
            return "more than 50 keys";
        for (const key of keys) {
            if (!/^[A-Za-z_][A-Za-z0-9_]{0,63}$/.test(key) || key === "__proto__")
                return "the key " + _show(key) + " is not a name";
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

    // ---- The file check (part of the format, enforced before anything is loaded) ----
    //
    // Every file a module names — main, each entry's components, its tests, what its qmldir
    // lists — must resolve, symlinks followed, to a regular file inside the module's canonical
    // directory, of at most maxFileBytes. The host asks a process (a FIFO opened by
    // Qt.createComponent would block the GUI thread for as long as it has no writer; a link
    // can lead anywhere) before it reads or loads any of them. An entry whose file fails is
    // dropped with an error; a failing main or qmldir file fails the module (every file of
    // the module imports its directory, so a broken qmldir breaks them all).

    readonly property int maxFileBytes: 1024 * 1024

    // The files of a module the check looks at: { file, kind } — kind "main", "entry",
    // "test" or "qmldir"; each file once (the first kind wins)
    function filesToCheck(manifest, qmldirText) {
        const files = [];
        const add = (file, kind) => {
            if (typeof file === "string" && file !== "" && !files.some(entry => entry.file === file))
                files.push({ file: file, kind: kind });
        };
        add(manifest?.main, "main");
        for (const file of manifestFiles(manifest))
            add(file, "entry");
        for (const file of qmldirFiles(qmldirText))
            add(file, "qmldir");
        for (const file of manifest?.tests ?? [])
            add(file, "test");
        return files;
    }

    // The check's shell script: arguments in triples (cap, directory, file); prints, per
    // triple, the file's text — each line prefixed "<index>:" — then "<index>\tok", or only
    // "<index>\t<why not>". By index, so no path is echoed back and parsed. The texts come
    // out of this process because reading is what can block (a mount that answers stat and
    // then hangs on read): the host reads no module file on the GUI thread — manifest, qmldir
    // and the texts for the import and property checks all come from here, under the host's
    // checkTimeoutMs, and a triple without its "ok" line when the deadline kills the process
    // counts as failed. The "ok" comes after the text, so a text cut short is never whole.
    readonly property string fileCheckScript: "i=0; "
        + "while [ $# -ge 3 ]; do cap=$1; dir=$2; file=$3; shift 3; "
        + "real_dir=$(realpath -e -- \"$dir\" 2>/dev/null) || real_dir=$dir; "
        + "if [ ! -e \"$dir/$file\" ] && [ ! -L \"$dir/$file\" ]; then printf '%s\\tdoes not exist\\n' $i; "
        + "elif ! real=$(realpath -e -- \"$dir/$file\" 2>/dev/null); then printf '%s\\tis a broken or looping link\\n' $i; "
        + "else case \"$real\" in \"$real_dir\"/*) "
        + "if [ ! -f \"$real\" ]; then printf '%s\\tis not a regular file\\n' $i; "
        + "else size=$(stat -c %s -- \"$real\" 2>/dev/null) || size=-1; "
        + "if [ \"$size\" -ge 0 ] && [ \"$size\" -le \"$cap\" ]; then "
        + "{ head -c \"$cap\" -- \"$real\"; echo; } | sed \"s/^/$i:/\"; printf '%s\\tok\\n' $i; "
        + "else printf '%s\\tis larger than %s bytes\\n' $i \"$cap\"; fi; fi ;; "
        + "*) printf '%s\\tleaves the module directory through a link\\n' $i ;; esac; fi; "
        + "i=$((i+1)); done"

    // The check's output lines → { index: "ok" | why not }
    function parseFileCheck(lines) {
        const result = {};
        for (const line of lines ?? []) {
            const match = /^([0-9]+)\t(.*)$/.exec(String(line));
            if (match)
                result[match[1]] = match[2].slice(0, 200);
        }
        return result;
    }

    // The texts in the check's output lines → { index: text }, only of the files it answered
    // "ok" for (a text without its "ok" may be cut short)
    function fileTexts(lines) {
        const answered = parseFileCheck(lines);
        const parts = {};
        for (const line of lines ?? []) {
            const match = /^([0-9]+):/.exec(String(line));
            if (!match)
                continue;
            (parts[match[1]] = parts[match[1]] ?? []).push(String(line).slice(match[0].length));
        }
        const texts = {};
        for (const index of Object.keys(answered)) {
            // The script adds one line break after the text, so that a last line without one
            // is still a line of its own: joining the lines drops it again
            if (answered[index] === "ok")
                texts[index] = (parts[index] ?? []).join("\n");
        }
        return texts;
    }

    // A manifest without the entries whose files failed the check. `bad`: { file: why }.
    // → { manifest (a copy), errors, fatal: "" or why the module fails }
    function withoutBadFiles(manifest, bad, qmldirText) {
        const errors = [];
        const failing = file => typeof file === "string" && file !== "" && _has(bad ?? {}, file);
        const why = file => file + " " + bad[file];
        let fatal = "";
        if (failing(manifest?.main))
            fatal = "main " + why(manifest.main);
        for (const file of qmldirFiles(qmldirText)) {
            if (fatal === "" && failing(file))
                fatal = "qmldir names " + why(file);
        }
        const copy = Object.assign({}, manifest ?? {});
        const keep = (list, files, what) => (list ?? []).filter(entry => {
            const broken = files(entry).find(failing);
            if (broken !== undefined)
                errors.push(what(entry) + ": " + why(broken) + " (dropped)");
            return broken === undefined;
        });
        copy.widgets = keep(manifest?.widgets, entry => [entry.widget, entry.popupPanel, entry.settings], entry => "widget " + entry.type);
        copy.settingsPages = keep(manifest?.settingsPages, entry => [entry.component], entry => "settings page " + entry.id);
        copy.slots = keep(manifest?.slots, entry => [entry.component], entry => "slot " + entry.slot);
        copy.tests = (manifest?.tests ?? []).filter(file => {
            if (failing(file))
                errors.push("test " + why(file) + " (dropped)");
            return !failing(file);
        });
        return { manifest: copy, errors: errors, fatal: fatal };
    }

    // ---- The start guard (crash loops the launcher cannot see) ----
    //
    // Quickshell restarts a crashed shell in place — the same process, exec'd again — unless
    // it crashed within 10 s of starting; the launcher sees only processes, so it misses a
    // module that crashes the shell later, and `launch.sh -d` has no supervisor at all. So the
    // shell counts those relaunches itself: before any module is loaded the host runs
    // startGuardScript on $XDG_RUNTIME_DIR/h2s-shell-module-starts, which holds
    // "<identity> <count>". The identity is "<pid>:<crash>" — the shell's pid, and the
    // coredump pid Quickshell's crash handler put in the environment it exec'd the relaunch
    // with (__QUICKSHELL_CRASH_DUMP_PID, still readable in /proc/<pid>/environ after
    // Quickshell unsets it), "" for a process not relaunched after a crash. So:
    //   no crash marker                  a fresh process (a launch, a --restart, a launcher
    //                                    restart — which the launcher counts): 0
    //   the same identity as stored      a reload of the same relaunched process: unchanged
    //   the same pid, another crash      one more relaunch after a crash: count + 1
    // A start that lives guardClearMs writes its count back to 0. An orderly quit needs
    // nothing (the next start is a fresh process) — and could not do anything: Quickshell
    // stops all JavaScript before it tears a generation down. guardLimit or more: safe mode.
    readonly property int guardLimit: 2
    // The same window as the launcher's quick deaths (scripts/launch.sh: 30 s), so the two
    // counters tell one story: a start that lived 30 s was not a crash loop
    readonly property int guardClearMs: 30000

    // The guard's shell script: arguments the file and an identity to use instead of the
    // process's own ("" — the suites give one). Refuses anything but a plain file (a link, a
    // FIFO: "refused <identity>"), prints "<count> <identity>", writes the same (atomically)
    readonly property string startGuardScript: "file=$1; identity=$2; "
        + "if [ -z \"$identity\" ]; then "
        + "crash=$(tr '\\000' '\\n' < /proc/$PPID/environ 2>/dev/null | sed -n 's/^__QUICKSHELL_CRASH_DUMP_PID=//p' | head -n 1 | tr -cd 0-9); "
        + "identity=\"$PPID:$crash\"; fi; "
        + "if [ -L \"$file\" ] || { [ -e \"$file\" ] && [ ! -f \"$file\" ]; }; then echo \"refused $identity\"; exit 0; fi; "
        + "stored=; old=0; if [ -f \"$file\" ]; then line=$(head -c 80 -- \"$file\" | head -n 1); stored=${line%% *}; "
        + "old=$(printf '%s' \"${line#* }\" | tr -cd 0-9 | cut -c1-4); fi; old=${old:-0}; "
        + "case \"$identity\" in *:) count=0 ;; *) "
        + "if [ \"$stored\" = \"$identity\" ]; then count=$old; "
        + "elif [ \"${stored%%:*}\" = \"${identity%%:*}\" ]; then count=$((old + 1)); else count=1; fi ;; esac; "
        + "echo \"$count $identity\"; "
        + "printf '%s %s\\n' \"$identity\" \"$count\" > \"$file.$$\" && mv -f -- \"$file.$$\" \"$file\""

    // Writes a start's count back to 0 once it has lived guardClearMs: arguments the file and
    // the identity (only a plain file, or none, is written)
    readonly property string guardClearScript: "file=$1; "
        + "if [ -L \"$file\" ] || { [ -e \"$file\" ] && [ ! -f \"$file\" ]; }; then exit 0; fi; "
        + "printf '%s 0\\n' \"$2\" > \"$file.$$\" && mv -f -- \"$file.$$\" \"$file\""

    // What the guard's output means → { safeMode, count, identity, reason }. Garbage, nothing
    // (the script failed) or "refused": counts as 0 — the guard must never be what keeps
    // modules off for good.
    function startGuard(output) {
        const text = String(output ?? "").trim();
        const match = /^([0-9]{1,4}) ([0-9]*:[0-9]*)$/.exec(text);
        if (!match)
            return { safeMode: false, count: 0, identity: "", reason: text.startsWith("refused") ? "the start counter is not a plain file: not counted" : "" };
        const count = Number(match[1]);
        return {
            safeMode: count >= guardLimit, count: count, identity: match[2],
            reason: count >= guardLimit ? "Quickshell relaunched the shell after a crash " + count + " times in a row, none living "
                + guardClearMs / 1000 + " s (a module may crash it): safe mode" : ""
        };
    }

    // ---- What a module file's root object declares ----
    //
    // The core hands a module's objects `module` (and a slot's `context`, a page's `editIndex`)
    // as initial properties, only when the file's root object declares them: a Loader warns
    // about an initial property its item does not have. Read from the text the import check
    // reads anyway.

    // The writable properties the root object of a QML file declares directly (not a nested
    // object's; not readonly ones), by name. `module` counts only as `property var module`
    // (the handle is an object; another type would make the Loader warn and drop it —
    // modulePropertyWarning says so in the module's status). Never throws.
    //
    // A pragmatic reader, not a QML parser: it skips comments, strings and template literals,
    // and a regular-expression literal where one can start (after one of ( , = : [ ! & | ? { } ;
    // or `return`), so their braces do not count. Not handled: a regex literal after
    // anything else (`x = a / b / c` is division; `)` then `/` too) — such a file may lose its
    // initial properties (it is then given none, and its `module` comes from Api.moduleAt).
    function rootProperties(text) {
        const rootText = _rootText(text);
        const names = [];
        const pattern = /(?:^|[\s;])((?:required|default|readonly)\s+)*property\s+([A-Za-z_][\w.]*(?:<[\w.]+>)?)\s+([A-Za-z_]\w*)/g;
        let match;
        while ((match = pattern.exec(rootText)) !== null) {
            if (/\breadonly\s+property/.test(match[0]) || names.includes(match[3]))
                continue;
            if (match[3] === "module" && match[2] !== "var")
                continue;
            names.push(match[3]);
        }
        return names;
    }

    // A warning when a file's root object declares `module` in a way that never gets the
    // handle (readonly, or a type other than var); "" otherwise
    function modulePropertyWarning(file, text) {
        const pattern = /(?:^|[\s;])((?:required|default|readonly)\s+)*property\s+([A-Za-z_][\w.]*(?:<[\w.]+>)?)\s+module\b/g;
        const rootText = _rootText(text);
        let match;
        while ((match = pattern.exec(rootText)) !== null) {
            if (/\breadonly\s+property/.test(match[0]) || match[2] !== "var")
                return file + ": its root declares `" + match[0].trim() + "` — only `property var module` is given the module's handle";
        }
        return "";
    }

    // The text of a QML file's root object at depth 1: comments, strings and regex literals
    // blanked, nested objects reduced to ";"
    function _rootText(text) {
        if (typeof text !== "string")
            return "";
        const source = text.slice(0, maxFileBytes);
        let depth = 0;
        let rootText = "";
        // The last significant character outside comments and strings, and the word before
        // it: where a "/" starts a regex literal rather than divides
        let last = "";
        let lastWord = "";
        for (let i = 0; i < source.length; i++) {
            const character = source[i];
            const next = source[i + 1];
            if (/\s/.test(character)) {
                if (depth === 1)
                    rootText += character;
                continue;
            }
            // Comments and strings are skipped whole
            if (character === "/" && next !== "/" && next !== "*"
                    && (last === "" || "(,=:[!&|?{};".includes(last) || lastWord === "return")) {
                let j = i + 1;
                let inClass = false;
                while (j < source.length && source[j] !== "\n" && (inClass || source[j] !== "/")) {
                    if (source[j] === "\\")
                        j++;
                    else if (source[j] === "[")
                        inClass = true;
                    else if (source[j] === "]")
                        inClass = false;
                    j++;
                }
                i = j;
                last = "/";
                lastWord = "";
                if (depth === 1)
                    rootText += " ";
                continue;
            }
            const wordMatch = /[A-Za-z_$]/.test(character) ? /^[A-Za-z_$][\w$]*/.exec(source.slice(i, i + 64)) : null;
            if (wordMatch) {
                if (depth === 1)
                    rootText += wordMatch[0];
                i += wordMatch[0].length - 1;
                last = "a";
                lastWord = wordMatch[0];
                continue;
            }
            lastWord = "";
            if (character === "/" && next === "/") {
                const end = source.indexOf("\n", i);
                i = end < 0 ? source.length : end - 1;
                continue;
            }
            if (character === "/" && next === "*") {
                const end = source.indexOf("*/", i + 2);
                i = end < 0 ? source.length : end + 1;
                continue;
            }
            if (character === "\"" || character === "'" || character === "`") {
                let j = i + 1;
                while (j < source.length && source[j] !== character) {
                    if (source[j] === "\\")
                        j++;
                    j++;
                }
                i = j;
                last = "a";
                if (depth === 1)
                    rootText += " ";
                continue;
            }
            last = character;
            if (character === "{") {
                depth++;
                if (depth === 2)
                    rootText += ";";
                continue;
            }
            if (character === "}") {
                depth--;
                continue;
            }
            if (depth === 1)
                rootText += character;
        }
        return rootText;
    }

    // Of `wanted` ({ name: value }), the ones the root object declares (`declared`, from
    // rootProperties)
    function initialProperties(declared, wanted) {
        const result = {};
        for (const key of Object.keys(wanted ?? {})) {
            if ((declared ?? []).includes(key))
                result[key] = wanted[key];
        }
        return result;
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
    // (`file`: the importing file, relative to the module's directory — a quoted import is
    // resolved from the file's own directory: tests/T.qml importing ".." is the module's)
    function importAllowed(entry, file) {
        if (entry.directory) {
            const path = entry.name;
            if (path === "" || path.includes(":") || path.startsWith("/"))
                return false;
            const parts = String(file ?? "").split("/").slice(0, -1);
            for (const part of path.split("/")) {
                if (part === "..") {
                    if (parts.length === 0)
                        return false;
                    parts.pop();
                } else if (part !== "" && part !== ".") {
                    parts.push(part);
                }
            }
            return true;
        }
        return allowedImports.includes(entry.name)
            || allowedImportPrefixes.some(prefix => entry.name === prefix || entry.name.startsWith(prefix + "."));
    }

    // The warnings for one file of a module: one per import outside the allowlist. A test
    // suite (`isTest`: listed in the manifest's tests) may also import qs.tests — the shell's
    // TestCase, which tests/run-modules.sh provides and the running shell does not: a module's
    // own file importing it would pass its suites and fail in the shell.
    function importWarnings(file, text, isTest) {
        return importsOf(text).filter(entry => !importAllowed(entry, file) && !(isTest === true && !entry.directory && entry.name === "qs.tests")).map(entry =>
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
    //   filesChecked       the check of the module's files has answered (false: pending)
    //   guardKnown         the start guard has answered (false: pending; see startGuard)
    function stateOf(facts) {
        // module.json not answered yet (the file check reads it): pending
        if (facts?.manifestRead === false)
            return "pending";
        if (!facts?.valid)
            return "failed";
        if (facts.duplicate)
            return "duplicate";
        if (!facts.compatible)
            return "incompatible";
        if (facts.filesChecked === false)
            return "pending";
        if (facts.mainFileError)
            return "failed";
        if (facts.guardKnown === false)
            return "pending";
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
                if (widget.presetDefaults)
                    entry.presetDefaults = JSON.parse(JSON.stringify(widget.presetDefaults));
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

    // A manifest's slot contributions to slots this shell does not offer: one warning each
    function unknownSlotWarnings(manifest) {
        return (manifest?.slots ?? []).filter(entry => !slotNames.includes(entry.slot)).map(entry =>
            "slots: " + _show(entry.slot) + " is not a slot this shell offers (module API " + apiVersion
            + "; offered: " + slotNames.join(", ") + ") — " + entry.component + " shows nowhere");
    }

    // ---- The core's registries, merged with the modules' lists (M2) ----
    //
    // Each takes the core's own list and the host's merged list and returns the list the
    // registry publishes. With no module entries the result has the core's entries, in the
    // core's order, unchanged (the suites check it). A module entry that collides with a core
    // one (it cannot, with the namespaces, but the core never depends on that) is dropped.

    // WidgetRegistry.entries: the core's, then the modules' (a type or popup key the core
    // has, or "tray-menu"/"notifications" Popup wires itself, is dropped)
    function mergeWidgetEntries(core, modules) {
        const coreList = Array.isArray(core) ? core : [];
        const types = coreList.map(entry => entry.type);
        const popups = coreList.filter(entry => entry.popup).map(entry => entry.popup).concat(["tray-menu", "notifications"]);
        const added = [];
        for (const entry of Array.isArray(modules) ? modules : []) {
            if (!entry || types.includes(entry.type) || (entry.popup && popups.includes(entry.popup)))
                continue;
            types.push(entry.type);
            if (entry.popup)
                popups.push(entry.popup);
            added.push(entry);
        }
        return added.length === 0 ? coreList : coreList.concat(added);
    }

    // WidgetPresets.defaults: the core's, plus { type: presetDefaults } of the modules' widgets
    function mergePresetDefaults(core, moduleWidgets) {
        const result = Object.assign({}, core ?? {});
        for (const entry of Array.isArray(moduleWidgets) ? moduleWidgets : []) {
            if (entry?.presetDefaults && !_has(result, entry.type))
                result[entry.type] = entry.presetDefaults;
        }
        return result;
    }

    // SettingsSchema.entries: the core's, then the modules' (a key the core has: dropped).
    // A module entry has the schema's fields and `module`.
    function mergeSettingEntries(core, modules) {
        const coreList = Array.isArray(core) ? core : [];
        const keys = new Set(coreList.map(entry => entry.key));
        const added = (Array.isArray(modules) ? modules : []).filter(entry => entry && !keys.has(entry.key));
        return added.length === 0 ? coreList : coreList.concat(added);
    }

    // ProfileRules.factTypes: the core's, then the modules' (a fact the core has: dropped)
    function mergeFactTypes(core, modules) {
        const coreList = Array.isArray(core) ? core : [];
        const facts = new Set(coreList.map(entry => entry.fact));
        const added = (Array.isArray(modules) ? modules : []).filter(entry => entry && !facts.has(entry.fact));
        return added.length === 0 ? coreList : coreList.concat(added);
    }

    // The group the module pages without a usable parent go under, on the System tab
    readonly property var modulesGroup: ({ id: "modules", label: "Modules", tab: "system", group: true })

    // SettingsWindow.pages: the core's pages with the modules' pages put in. A module page
    // becomes { id, label, tab, url, module, parent? }:
    //   parent a core group → under it, on the group's tab (after the group's own pages);
    //   parent "modules", or a parent the core does not have → under the Modules group
    //     (System tab; the group exists only while it has pages);
    //   no parent → on its tab, after the core's pages.
    // An id the core has is dropped. → { pages, problems: [text] }
    function mergeSettingsPages(corePages, modulePages) {
        const core = Array.isArray(corePages) ? corePages : [];
        const problems = [];
        const ids = new Set(core.map(page => page.id));
        const groups = new Map(core.filter(page => page.group).map(page => [page.id, page.tab]));
        const children = new Map();
        const topLevel = [];
        const underModules = [];
        for (const page of Array.isArray(modulePages) ? modulePages : []) {
            if (!page || typeof page.id !== "string")
                continue;
            if (ids.has(page.id) || page.id === modulesGroup.id) {
                problems.push(page.module + ": settings page " + _show(page.id) + " has the id of a core page (dropped)");
                continue;
            }
            ids.add(page.id);
            const made = { id: page.id, label: page.label, tab: settingsTabs.includes(page.tab) ? page.tab : "behaviour",
                           url: page.component, module: page.module };
            const parent = page.parent ?? "";
            if (parent === "") {
                topLevel.push(made);
            } else if (groups.has(parent)) {
                made.parent = parent;
                made.tab = groups.get(parent);
                if (!children.has(parent))
                    children.set(parent, []);
                children.get(parent).push(made);
            } else {
                if (parent !== modulesGroup.id)
                    problems.push(page.module + ": settings page " + _show(page.id) + ": no group " + _show(parent)
                                  + " — shown under Modules");
                made.parent = modulesGroup.id;
                made.tab = modulesGroup.tab;
                underModules.push(made);
            }
        }
        if (topLevel.length === 0 && underModules.length === 0 && children.size === 0)
            return { pages: core, problems: problems };
        const pages = [];
        core.forEach((page, index) => {
            pages.push(page);
            // A group's module pages after its last own page
            const group = page.group ? page.id : (page.parent ?? "");
            const next = core[index + 1];
            if (group !== "" && children.has(group) && !(next && next.parent === group))
                pages.push(...children.get(group));
        });
        pages.push(...topLevel);
        if (underModules.length > 0)
            pages.push(Object.assign({}, modulesGroup), ...underModules);
        return { pages: pages, problems: problems };
    }

    // ---- Api.openUrl ----

    // The schemes Api.openUrl passes to xdg-open; file: only when asked for ({ allowFile: true })
    readonly property var openUrlSchemes: ["http", "https", "mailto"]

    // Why Api.openUrl refuses a link ("" when it may be opened): it must have a scheme
    // (`scheme:` at the start), the scheme must be http, https or mailto — or file with
    // options.allowFile === true — and the link no longer than 4096, without control
    // characters, not starting with "-"
    function openUrlProblem(url, options) {
        if (typeof url !== "string" || url === "")
            return "empty";
        if (url.length > 4096)
            return "longer than 4096 characters";
        if (/[\u0000-\u001f\u007f]/.test(url))
            return "holds control characters";
        if (url.startsWith("-"))
            return "starts with \"-\"";
        const match = /^([A-Za-z][A-Za-z0-9+.-]*):/.exec(url);
        if (!match)
            return "has no scheme (a bare path is not opened)";
        const scheme = match[1].toLowerCase();
        if (openUrlSchemes.includes(scheme))
            return "";
        if (scheme === "file")
            return options?.allowFile === true ? "" : "a file: link needs { allowFile: true }";
        return "the scheme " + scheme + ": is not opened (only " + openUrlSchemes.join(", ") + ", and file with allowFile)";
    }

    // ---- Facts the core publishes read-only (API 1.3) ----

    // Api.networks: the saved networks this computer joins, from NetworkProfiles' profiles
    // (Nmcli.profiles) and Wi-Fi details (Nmcli.wifiDetails) → [{ id, name, kind, active }].
    // `id` is the profile's UUID — the key system.vpnWithNetworks uses, as names may repeat.
    // Only Wi-Fi (not a hotspot: mode "ap" is this computer's own network) and Ethernet, and
    // not a port of a bridge or bond (the bridge is what joins). `active` only when fully up
    // ("activated"), so a module does not act on a network still connecting. Those active
    // first, then the rest, each in the given order. Garbage is skipped, never thrown on.
    function apiNetworks(profiles, wifiDetails) {
        const details = _isObject(wifiDetails) ? wifiDetails : {};
        const active = [];
        const inactive = [];
        for (const profile of Array.isArray(profiles) ? profiles : []) {
            if (!_isObject(profile) || !_isString(profile.uuid, 200))
                continue;
            if (profile.kind !== "wifi" && profile.kind !== "ethernet")
                continue;
            if (typeof profile.port === "string" && profile.port !== "")
                continue;
            const wifi = _has(details, profile.uuid) ? details[profile.uuid] : null;
            if (profile.kind === "wifi" && _isObject(wifi) && wifi.mode === "ap")
                continue;
            const network = { id: profile.uuid, name: typeof profile.name === "string" ? profile.name : "",
                kind: profile.kind, active: profile.state === "activated" };
            (network.active ? active : inactive).push(network);
        }
        return active.concat(inactive);
    }

    // Api.vpnsUp: the VPNs up now (VpnManager.activeVpns) → [{ name, type, provider }] —
    // `type` "wireguard", "vpn" … or "provider", `provider` the providerId of a provider's VPN
    // ("" for NetworkManager's). In the given order; garbage skipped, never thrown on.
    function apiVpnsUp(activeVpns) {
        const list = [];
        for (const vpn of Array.isArray(activeVpns) ? activeVpns : []) {
            if (!_isObject(vpn))
                continue;
            const type = typeof vpn.type === "string" ? vpn.type : "";
            list.push({ name: typeof vpn.name === "string" ? vpn.name : "", type: type,
                provider: type === "provider" && typeof vpn.provider === "string" ? vpn.provider : "" });
        }
        return list;
    }

    // A JSON text of a list of plain objects → that list, the list and each entry frozen —
    // what Api hands out (a module cannot change the core's copy)
    function frozenRows(text) {
        let rows = [];
        try {
            rows = JSON.parse(text);
        } catch (error) {
            rows = [];
        }
        if (!Array.isArray(rows))
            rows = [];
        return Object.freeze(rows.map(row => Object.freeze(row)));
    }

    // ---- What a module hands the core at run time ----

    // A fact's value checked against its declared type → { ok, value, error }. null and
    // undefined are "not known" (value null: no condition on it holds). Never throws.
    function factValue(type, value, options) {
        if (value === undefined || value === null)
            return { ok: true, value: null, error: "" };
        const bad = what => ({ ok: false, value: null, error: "not " + what + ": " + _show(value) });
        switch (type) {
        case "bool":
            return typeof value === "boolean" ? { ok: true, value: value, error: "" } : bad("true or false");
        case "number":
            return _isNumber(value) ? { ok: true, value: value, error: "" } : bad("a number");
        case "percent":
            return _isNumber(value) && value >= 0 && value <= 100 ? { ok: true, value: value, error: "" } : bad("a number from 0 to 100");
        case "string":
            return typeof value === "string" && value.length <= 200 ? { ok: true, value: value, error: "" } : bad("a text of at most 200 characters");
        case "enum":
            return typeof value === "string" && (options ?? []).includes(value) ? { ok: true, value: value, error: "" }
                : bad("one of " + (options ?? []).join(", "));
        }
        return { ok: false, value: null, error: "the fact's type " + _show(type) + " is unknown" };
    }

    // A module's setting key: its full key ("mod.<id>.<name>") for "<name>" or the full key
    // itself; "" when it is not the module's
    function ownSettingKey(id, key) {
        if (typeof key !== "string")
            return "";
        const full = key.startsWith("mod.") ? key : "mod." + id + "." + key;
        return isOwnSettingKey(id, full) ? full : "";
    }

    // A module's fact name: "<id>.<name>" for "<name>" or the full name; "" when not its
    function ownFactName(id, name) {
        if (typeof name !== "string")
            return "";
        const full = name.startsWith(id + ".") ? name : id + "." + name;
        return isOwnFact(id, full) ? full : "";
    }

    // Whether `value` may be written to a setting declared by `entry` (a schema entry): ""
    // when it may, else why not
    function settingValueProblem(entry, value) {
        if (!entry)
            return "not a declared setting";
        switch (entry.type) {
        case "bool":
            return typeof value === "boolean" ? "" : "not true or false";
        case "number":
        case "slider":
        case "interval":
            if (!_isNumber(value))
                return "not a number";
            if ((entry.min !== undefined && value < entry.min) || (entry.max !== undefined && value > entry.max))
                return "outside " + entry.min + ".." + entry.max;
            return "";
        case "string":
            return typeof value === "string" && value.length <= 10000 ? "" : "not a text (at most 10000 characters)";
        case "stringList":
            return Array.isArray(value) && value.length <= 1000 && value.every(item => typeof item === "string") ? "" : "not a list of texts";
        case "enum":
            return (entry.options ?? []).some(option => option.value === value) ? "" : "not one of the options";
        }
        return "a setting of type " + _show(entry.type) + " cannot be written by a module";
    }

    // The largest store a module may keep (its JSON, ModuleStore)
    readonly property int maxStoreBytes: 1024 * 1024

    // A store's content as JSON text, or null when it is not plain JSON or too large
    function storeText(data) {
        let text;
        try {
            text = JSON.stringify(data ?? {});
        } catch (error) {
            return null;
        }
        return typeof text === "string" && text.length <= maxStoreBytes ? text : null;
    }

    // A store file's text → its object ({} when missing, empty or not a JSON object)
    function parseStore(text) {
        if (typeof text !== "string" || text.trim() === "")
            return {};
        try {
            const parsed = JSON.parse(text);
            return _isObject(parsed) ? parsed : {};
        } catch (error) {
            return {};
        }
    }

    // Whether a slot contribution's context has changed by value: plain data compared as
    // JSON, objects of Qt (a provider, an item) and functions by identity — one level deep,
    // as contexts are written ({ slot, editIndex, provider, close }). Never throws.
    function sameContext(a, b) {
        if (a === b)
            return true;
        if (!_isObject(a) || !_isObject(b))
            return false;
        const keys = Object.keys(a);
        if (keys.length !== Object.keys(b).length)
            return false;
        for (const key of keys) {
            if (!_has(b, key))
                return false;
            const left = a[key];
            const right = b[key];
            if (left === right)
                continue;
            if (typeof left !== "object" || typeof right !== "object" || left === null || right === null
                    || _isQtObject(left) || _isQtObject(right))
                return false;
            let same = false;
            try {
                same = JSON.stringify(left) === JSON.stringify(right);
            } catch (error) {
                same = false;
            }
            if (!same)
                return false;
        }
        return true;
    }

    // An object of Qt's (a QtObject, an Item) rather than plain data
    function _isQtObject(value) {
        try {
            return typeof value.objectName === "string" && typeof value.destroy === "function";
        } catch (error) {
            return true;
        }
    }

    // The identity of a slot contribution, for the slot's ScriptModel
    function contributionKey(contribution) {
        return (contribution?.module ?? "") + "|" + (contribution?.component ?? "");
    }

    // The module whose directory holds `url` (a file:// URL or a path): its index in
    // `directories` (canonical paths), or -1. The deepest directory wins (a module inside
    // another's tree is its own).
    function directoryIndexOf(directories, url) {
        if (typeof url !== "string" && !(url && typeof url.toString === "function"))
            return -1;
        let path = String(url);
        if (path.startsWith("file://"))
            path = path.slice(7);
        try {
            path = decodeURIComponent(path);
        } catch (error) {
            return -1;
        }
        path = canonicalPath(path);
        if (path === "")
            return -1;
        let best = -1;
        (directories ?? []).forEach((directory, index) => {
            if ((path === directory || path.startsWith(directory + "/"))
                    && (best < 0 || directory.length > directories[best].length))
                best = index;
        });
        return best;
    }
}
