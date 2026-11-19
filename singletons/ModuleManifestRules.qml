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
//                 kept, and shows nowhere). A slot whose view is converted to anchors is
//                 read as its anchor (ModuleRules.slotAliases) and listed in the module's
//                 deprecations.
//   anchors       optional list (API 1.20) of elements at the places the shell's views offer:
//                 { at, place, component } — at a place's path (ModuleRules.anchorPathProblem:
//                 <surface>.<view>[.<block>]…), place one of before, after, prepend, append,
//                 component a file of the module. The places this shell offers and the
//                 placements each takes are ModuleRules.anchorTable: another one is an error
//                 in the module's status (the rest of the module loads, that element shows
//                 nowhere). The same three twice: the second is dropped, with an error.
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
//   icon          optional (API 1.26): the module's icon, one of
//                   { "glyph": "…" }   one character (a code point) of the shell's icon
//                                      font: a private-use character (glyphRanges), not
//                                      one of the shell's status marks (reservedGlyphs) nor
//                                      another lock or no-entry sign of the font
//                                      (lookalikeGlyphs); drawn in its place's text colour
//                   { "svg": "icon.svg", "colors": "theme" | "own" }   an SVG file of at
//                                      most maxSvgBytes; painted in the place's text colour
//                                      (a one-colour drawing follows the theme), or in its
//                                      own colours with "colors": "own"
//                   { "image": "icon.png" }   a PNG or WebP file of at most maxImageBytes,
//                                      in its own colours
//                 A file is a path inside the module's directory (iconPathProblem), taken
//                 through the file check like every file the manifest names; its content is
//                 read only to refuse external references (iconContentProblem: an SVG that
//                 refers outside itself, a picture whose first bytes are not its name's
//                 type). It is drawn, never run. A wrong icon is an
//                 error in the module's status and no icon; with none the shell shows the
//                 first letter of the module's name (components/ModuleIcon.qml).
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
// leading "/", ending in .qml (an icon's in .svg, .png or .webp). Any other field is kept (in `raw`) and reported as a warning,
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
        "settingsPages", "settings", "facts", "slots", "anchors", "requires", "optionalPrograms", "testPrograms", "setupHints", "tests",
        "exports", "uses", "icon"]

    // ---- The icon (API 1.26) ----

    readonly property int maxSvgBytes: 64 * 1024
    readonly property int maxImageBytes: 256 * 1024
    // The shell's own status marks, never a module's icon: PrivilegedMark's lock and no-entry
    // sign (tests/ModuleRulesTest.qml holds the two to it)
    readonly property var reservedGlyphs: ["\uf023", "\uf05e"]
    // The other locks and no-entry signs of the shell's icon font (JetBrainsMono Nerd Font,
    // Nerd Fonts 3.x): every glyph whose name in the font is a lock of its own ("…-lock",
    // "…-lock_*", "…-unlock*") or a no-entry sign ("fa-ban", "oct-blocked", "oct-no_entry",
    // "md-block_helper", "md-cancel"), read from the font's glyph names. A module's icon next
    // to a control must not pass for the shell's mark that the control asks for a password.
    // Glyphs that only carry a small lock (a folder with a lock) are not listed.
    readonly property var lookalikeGlyphs: [
        0xe672, 0xea75, 0xeb74, 0xebe7, 0xf09c, 0xf13e, 0xf2fc, 0xf456, 0xf479, 0xf4f4, 0xf52a,
        0xf00ad, 0xf033e, 0xf033f, 0xf0340, 0xf0341, 0xf05fb, 0xf06ea, 0xf073a, 0xf0773, 0xf08b2,
        0xf08ee, 0xf08ef, 0xf097f, 0xf0fc6, 0xf0fc7, 0xf139a, 0xf139b, 0xf139c, 0xf15d1, 0xf15d2,
        0xf1671, 0xf1672, 0xf16a8, 0xf16a9, 0xf16aa, 0xf16ab, 0xf16ac, 0xf16ad, 0xf16ae, 0xf16af,
        0xf16b0, 0xf16b1, 0xf16b2, 0xf16b3, 0xf16b4
    ]
    // Unicode's private-use ranges, where the icon font's glyphs lie: an icon is taken only
    // from there. An ordinary character (a letter, an emoji — drawn in its own colours, deaf
    // to the theme — a combining mark, a variation selector) is not an icon
    readonly property var glyphRanges: [[0xe000, 0xf8ff], [0xf0000, 0xffffd], [0x100000, 0x10fffd]]
    // The file name endings each kind of file takes
    readonly property var iconEndings: ({ svg: [".svg"], image: [".png", ".webp"] })

    // Why `text` is not a glyph ("" when it is one): one code point (an icon above U+FFFF is
    // two UTF-16 units), not white space, not a control, format or lone surrogate
    // character, a private-use character (glyphRanges), neither a status mark of the shell's
    // nor a lock or no-entry sign of the icon font (lookalikeGlyphs)
    function glyphProblem(text) {
        if (typeof text !== "string" || text === "")
            return "not a character";
        const points = ModuleRules.codePoints(text);
        if (points.length !== 1)
            return "is " + points.length + " characters, not one";
        const code = points[0].codePointAt(0);
        if (/^\s$/.test(text))
            return "is white space";
        if (code < 0x20 || (code >= 0x7f && code <= 0x9f))
            return "is a control character";
        if ((code >= 0xd800 && code <= 0xdfff) || _formatCharacter(code))
            return "is a format character";
        if (!glyphRanges.some(range => code >= range[0] && code <= range[1]))
            return "is not an icon of the icon font (a private-use character)";
        if (reservedGlyphs.includes(text))
            return "is one of the shell's status marks";
        if (lookalikeGlyphs.includes(code))
            return "looks like one of the shell's status marks (a lock or a no-entry sign)";
        return "";
    }

    // Unicode's format characters (category Cf), written out: the engine's expressions know
    // no Unicode categories
    function _formatCharacter(code) {
        const ranges = [[0xad, 0xad], [0x600, 0x605], [0x61c, 0x61c], [0x6dd, 0x6dd], [0x70f, 0x70f], [0x890, 0x891],
                        [0x8e2, 0x8e2], [0x180e, 0x180e], [0x200b, 0x200f], [0x202a, 0x202e], [0x2060, 0x2064],
                        [0x2066, 0x206f], [0xfeff, 0xfeff], [0xfff9, 0xfffb], [0x110bd, 0x110bd], [0x110cd, 0x110cd],
                        [0x13430, 0x1343f], [0x1bca0, 0x1bca3], [0x1d173, 0x1d17a], [0xe0001, 0xe0001], [0xe0020, 0xe007f]];
        return ranges.some(range => code >= range[0] && code <= range[1]);
    }

    // An icon's file, as given in the manifest: "" when fine, else why not — a plain path
    // inside the module's directory, as a QML file's, ending as its kind's (iconEndings)
    function iconPathProblem(path, kind) {
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
        const endings = iconEndings[kind] ?? [];
        if (!endings.some(ending => path.toLowerCase().endsWith(ending)))
            return "not a " + endings.join(" or ") + " file";
        return "";
    }

    // How many of a picture's first bytes the file check reads (its real type)
    readonly property int iconMagicBytes: 16

    // Why an icon file's content is refused ("" when it is fine): what the file check read
    // of it (ModuleFileRules.iconCheck) — an SVG's text (svgProblem), a picture's first bytes
    // in hex (pictureProblem). Not read: refused (a failed read is never "fine")
    function iconContentProblem(icon, content) {
        if (!icon || (icon.kind !== "svg" && icon.kind !== "image"))
            return "";
        if (typeof content !== "string")
            return "could not be read";
        return icon.kind === "svg" ? svgProblem(content) : pictureProblem(icon.file, content);
    }

    // A picture's first bytes (hex) against its name's ending: an image plugin is chosen by
    // the content, so a ".png" holding an SVG, a TIFF or a PDF would be drawn as that
    function pictureProblem(file, hex) {
        const bytes = String(hex ?? "").trim().toLowerCase();
        if (!/^[0-9a-f]*$/.test(bytes))
            return "could not be read";
        const name = String(file ?? "").toLowerCase();
        if (name.endsWith(".png"))
            return bytes.startsWith("89504e470d0a1a0a") ? "" : "is not a PNG picture";
        if (name.endsWith(".webp"))
            return bytes.startsWith("52494646") && bytes.slice(16, 24) === "57454250" ? "" : "is not a WebP picture";
        return "is not a .png or .webp file";
    }

    // Why an SVG's text is refused ("" when it is fine). The SVG renderer follows references
    // out of the file — an <image> by relative or absolute path, through any image plugin
    // (a FIFO there blocks every asynchronous Image of the shell) — so a file with any
    // external reference is refused; the text is read for nothing else. It must be UTF-8 text
    // (an XML declaration naming another encoding is refused: a text in UTF-16 or UTF-7
    // hides what it says from this check) starting, after an optional byte order mark, white
    // space, the XML declaration and comments, with <svg; and it holds none of: a document
    // type or entity declaration (<!DOCTYPE, <!ENTITY), a processing instruction other than
    // the declaration (<?xml-stylesheet), an <image>, <foreignObject> or <script> element, an
    // href not starting with "#", a url( not followed by "#", an @import, a backslash (a CSS
    // escape could spell any of them). Character references (&#x75;) are decoded and the
    // text checked again; matching ignores case. A harmless text that only looks like one
    // ("url" in a title) is refused too: refusing is the safe side.
    function svgProblem(text) {
        if (typeof text !== "string")
            return "could not be read";
        if (/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f\ufffd]/.test(text))
            return "is not UTF-8 text";
        let rest = text.replace(/^\ufeff/, "").replace(/^\s+/, "");
        const declaration = /^<\?xml(\s[^?>]*)?\?>/.exec(rest);
        if (declaration) {
            const encoding = /\bencoding\s*=\s*["']([^"']*)["']/i.exec(declaration[0]);
            if (encoding && !/^utf-?8$/i.test(encoding[1]))
                return "is not UTF-8 text (the XML declaration names " + ModuleRules.show(encoding[1].slice(0, 20)) + ")";
            rest = rest.slice(declaration[0].length);
        }
        for (let comment = /^\s*<!--[\s\S]*?-->/.exec(rest); comment; comment = /^\s*<!--[\s\S]*?-->/.exec(rest))
            rest = rest.slice(comment[0].length);
        if (!/^\s*<svg[\s>\/]/.test(rest))
            return "is not an SVG drawing (it does not start with <svg>)";
        const decoded = rest.replace(/&#x([0-9a-f]+);?/gi, (whole, hex) => _fromCode(parseInt(hex, 16)))
            .replace(/&#([0-9]+);?/g, (whole, decimal) => _fromCode(parseInt(decimal, 10)));
        for (const body of [rest, decoded]) {
            const problem = _svgReference(body);
            if (problem !== "")
                return "refers to something outside it (" + problem + ")";
        }
        return "";
    }

    function _fromCode(code) {
        return code > 0 && code <= 0x10ffff && !(code >= 0xd800 && code <= 0xdfff) ? String.fromCodePoint(code) : "\ufffd";
    }

    // The first external reference in an SVG's text after its start, named ("" none)
    function _svgReference(body) {
        if (/<!(?!--|\[CDATA\[)/i.test(body))
            return "a document type or entity declaration";
        if (/<\?/.test(body))
            return "a processing instruction";
        const element = /<([\w.-]+:)?(image|foreignobject|script)(?=[\s>\/])/i.exec(body);
        if (element)
            return "<" + element[2].toLowerCase() + ">";
        // What follows each "href", wherever it stands (an attribute's name, prefixed or not)
        if (body.split(/href/i).slice(1).some(after => !/^\s*=\s*["']#/.test(after)))
            return "an href not starting with #";
        return _cssReference(body);
    }

    function _cssReference(body) {
        if (body.includes("\\"))
            return "a backslash";
        if (/@import/i.test(body))
            return "@import";
        if (body.split(/url/i).slice(1).some(after => !/^\(\s*["']?#/.test(after)))
            return "a url( not starting with #";
        return "";
    }

    // The manifest's `icon`, checked → { kind: "glyph" | "svg" | "image", glyph, file,
    // colors: "theme" | "own" } or null (none, or wrong: an error then)
    function readIcon(raw, errors, warnings) {
        const given = ModuleRules.get(raw, "icon");
        if (given === undefined)
            return null;
        if (!ModuleRules.isObject(given)) {
            errors.push("icon: not an object such as { \"glyph\": \"…\" }, { \"svg\": \"icon.svg\" } or { \"image\": \"icon.png\" } (no icon)");
            return null;
        }
        const kinds = ["glyph", "svg", "image"].filter(kind => ModuleRules.get(given, kind) !== undefined);
        if (kinds.length !== 1) {
            errors.push("icon: " + (kinds.length === 0 ? "names none" : "names " + kinds.join(" and ")) + " of glyph, svg and image; one (no icon)");
            return null;
        }
        const kind = kinds[0];
        for (const key of Object.keys(given)) {
            if (key !== kind && !(kind === "svg" && key === "colors"))
                warnings.push("icon: unknown field " + ModuleRules.show(key) + " (ignored)");
        }
        const value = given[kind];
        if (kind === "glyph") {
            const problem = glyphProblem(value);
            if (problem !== "") {
                errors.push("icon: the glyph " + ModuleRules.show(value) + " " + (problem.startsWith("not ") ? "is " : "") + problem + " (no icon)");
                return null;
            }
            return { kind: "glyph", glyph: value, file: "", colors: "theme" };
        }
        const problem = iconPathProblem(value, kind);
        if (problem !== "") {
            errors.push("icon: " + kind + " " + ModuleRules.show(value) + ": " + problem + " (no icon)");
            return null;
        }
        let colors = kind === "svg" ? "theme" : "own";
        if (kind === "svg" && ModuleRules.get(given, "colors") !== undefined) {
            const asked = given.colors;
            if (asked !== "theme" && asked !== "own") {
                errors.push("icon: colors " + ModuleRules.show(asked) + " is not \"theme\" or \"own\" (no icon)");
                return null;
            }
            colors = asked;
        }
        return { kind: kind, glyph: "", file: value, colors: colors };
    }

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

    // One entry of `anchors`: { at, place, component } or why it is dropped. Only its form:
    // whether this shell offers the place is ModuleMergeRules.anchorErrors' (an error there,
    // the entry kept and shown nowhere)
    function _checkAnchor(entry) {
        const at = ModuleRules.get(entry, "at");
        const problem = ModuleRules.anchorPathProblem(at);
        if (problem !== "")
            return "at: " + problem;
        const place = ModuleRules.get(entry, "place");
        if (!ModuleRules.anchorPlacements.includes(place))
            return "place " + ModuleRules.show(place) + " is not one of " + ModuleRules.anchorPlacements.join(", ");
        const component = _file(entry, "component", true);
        if (component.error)
            return component.error;
        return { at: at, place: place, component: component.path };
    }

    // The manifest's `anchors`, checked: [{ at, place, component }] in manifest order. The
    // same three twice: the second dropped with an error — a module's file at one place is
    // what keeps its element alive across changes
    function readAnchors(raw, errors, warnings) {
        const kept = [];
        for (const entry of _entries(raw, "anchors", ["at", "place", "component"], entry => _checkAnchor(entry), errors, warnings)) {
            if (kept.some(other => other.at === entry.at && other.place === entry.place && other.component === entry.component)) {
                errors.push("anchors: " + ModuleRules.show(entry.component) + " is named twice for " + ModuleRules.show(entry.at) + ", "
                            + ModuleRules.show(entry.place) + " (the second is ignored)");
                continue;
            }
            kept.push(entry);
        }
        return kept;
    }

    // Reads module.json's text. Never throws. → {
    //   valid        the required fields are there and fine (the module can be considered)
    //   id, name, version, api, description, main ("" for none)
    //   widgets, settingsPages, settings, facts, slots, anchors   the entries kept, checked
    //   programs, optionalPrograms, testPrograms ("" for none, else without a trailing "/"),
    //   setupHints, tests
    //   exports      (1.18) { version } or null; uses (1.18) [{ id, version }]
    //   icon         (1.26) { kind, glyph, file, colors } or null (readIcon)
    //   unknownFields   names of top-level fields this shell does not know (kept in raw)
    //   raw          the parsed object as written, or null
    //   errors, warnings
    // }
    function parseManifest(text) {
        const result = {
            valid: false, id: "", name: "", version: "", api: "", description: "", main: "",
            widgets: [], settingsPages: [], settings: [], facts: [], slots: [], anchors: [],
            programs: [], optionalPrograms: [], testPrograms: "", setupHints: [], tests: [], unknownFields: [], raw: null,
            exports: null, uses: [], icon: null,
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
        // Fields of a newer API than the manifest asks for: read all the same, and said —
        // the module is written against an API that does not have them
        const asked = ModuleRules.parseApi(result.api);
        for (const [field, minor] of [["exports", 18], ["uses", 18], ["anchors", 20], ["icon", 26]]) {
            if (asked && (asked.major < 1 || (asked.major === 1 && asked.minor < minor)) && ModuleRules.get(raw, field) !== undefined)
                warnings.push(field + ": a field of API 1." + minor + ", the manifest asks for API " + result.api + " (read all the same)");
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
        result.anchors = readAnchors(raw, errors, warnings);
        result.icon = readIcon(raw, errors, warnings);
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
