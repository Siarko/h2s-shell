pragma Singleton

import Quickshell
import QtQuick

// The module system's decisions about a module's QML text (ModuleRules.qml has the
// overview): what a file's root object declares, and the import check. Pure, checked by
// tests/ModuleRulesTest.qml.
Singleton {
    id: root

    // What a module's QML may import without a warning (a warning by the owner's
    // decision): these modules, anything under the prefixes, and its own directory
    readonly property var allowedImports: ["Quickshell", "Quickshell.Io", "qs.api", "qs.components"]
    readonly property var allowedImportPrefixes: ["QtQuick", "QtQml"]
    // Allowed imports that are an old way: the name → what a module uses instead. Listed
    // among the module's `deprecations` (importDeprecations), never a warning.
    readonly property var deprecatedImports: ({ "qs.components": "the elements of qs.api" })
    // (API 1.19) Imports that reach into the shell or another module: the shell's singletons
    // (`qs.singletons` and below) and a directory outside the module's own. An error in the
    // module's status (importErrors), not a warning; the module still loads.
    readonly property var reachingImportPrefixes: ["qs.singletons"]

    // (API 1.19) The old ways of reaching another module or the shell's host in a module's
    // code, each listed among its `deprecations` (codeDeprecations) and removed with the
    // shell's next tightening: { what, pattern (matched against codeText: comments and
    // strings do not count), use, removed (the API that removed it, when it is gone) }. `module.host` is found where the handle is named
    // `module` (not `$module` or `my_module`; or a handle comes straight from Api.moduleAt):
    // QML cannot notice a read of a
    // property, so a handle kept under another name is not found.
    readonly property var deprecatedCode: [
        { what: "Api.module(id)", pattern: /(?:^|[^\w$])Api\s*\.\s*module\s*\(/,
          use: "`Api.moduleStatus(id)` for another module's state, and its `exports` through `uses`" },
        { what: "module.host", pattern: /(?:^|[^\w$])(?:module|moduleAt\s*\((?:[^()]|\([^()]*\))*\))\s*\??\.\s*host\b/,
          use: "the handle's own properties and qs.api (in a suite, ModuleTestKit)", removed: "1.36" }
    ]

    // ---- What a module file's root object declares ----
    //
    // The core hands a module's objects `module` (and a slot's `context`, a page's `editIndex`)
    // as initial properties, only when the file's root object declares them: a Loader warns
    // about an initial property its item does not have. Read from the text the import check
    // reads anyway.

    // The writable properties the root object of a QML file declares directly (not a nested
    // object's; not readonly ones), by name. `module` counts only as `property var module`
    // and `opener` only as `property var opener` (objects; another type would make the Loader
    // warn and drop them — modulePropertyWarning and openerPropertyWarning say so in the
    // module's status). Never throws.
    //
    // A pragmatic reader, not a QML parser: it skips what codeText leaves out (comments,
    // strings, template literals' text, regex literals where one can start), so their braces
    // do not count. Not handled: a regex literal after anything else (`)` then `/` is division)
    // — such a file may lose its initial properties (it is then given none, and its `module`
    // comes from Api.moduleAt). `code`: codeText(text), when the caller has it already.
    function rootProperties(text, code) {
        const rootText = _rootText(text, code);
        const names = [];
        const pattern = /(?:^|[\s;])((?:required|default|readonly)\s+)*property\s+([A-Za-z_][\w.]*(?:<[\w.]+>)?)\s+([A-Za-z_]\w*)/g;
        let match;
        while ((match = pattern.exec(rootText)) !== null) {
            if (/\breadonly\s+property/.test(match[0]) || names.includes(match[3]))
                continue;
            if (varOnlyProperties.includes(match[3]) && match[2] !== "var")
                continue;
            names.push(match[3]);
        }
        return names;
    }

    // The properties the core gives only as `property var <name>`
    readonly property var varOnlyProperties: ["module", "opener"]

    // A warning when a file's root object declares `module` in a way that never gets the
    // handle (readonly, or a type other than var); "" otherwise
    function modulePropertyWarning(file, text, code) {
        return _varPropertyWarning(file, text, code, "module", "the module's handle");
    }

    // The same for a popup panel's `opener` (the widget that opened it)
    function openerPropertyWarning(file, text, code) {
        return _varPropertyWarning(file, text, code, "opener", "the widget that opened it");
    }

    function _varPropertyWarning(file, text, code, name, given) {
        const pattern = new RegExp("(?:^|[\\s;])((?:required|default|readonly)\\s+)*property\\s+([A-Za-z_][\\w.]*(?:<[\\w.]+>)?)\\s+" + name + "\\b", "g");
        const rootText = _rootText(text, code);
        let match;
        while ((match = pattern.exec(rootText)) !== null) {
            if (/\breadonly\s+property/.test(match[0]) || match[2] !== "var")
                return file + ": its root declares `" + match[0].trim() + "` — only `property var " + name + "` is given " + given;
        }
        return "";
    }

    // The text of a QML file's root object at depth 1: comments, strings and regex literals
    // blanked (codeText; `code` when the caller has it), nested objects reduced to ";"
    function _rootText(text, code) {
        const source = typeof code === "string" ? code : codeText(text);
        const parts = [];
        let depth = 0;
        // Where the run of depth-1 text being read started
        let start = -1;
        for (let i = 0; i < source.length; i++) {
            const character = source.charCodeAt(i);
            if (character !== 123 && character !== 125)     // "{", "}"
                continue;
            if (start >= 0)
                parts.push(source.slice(start, i));
            start = -1;
            if (character === 123) {
                depth++;
                if (depth === 2)
                    parts.push(";");
            } else {
                depth--;
            }
            if (depth === 1)
                start = i + 1;
        }
        if (start >= 0)
            parts.push(source.slice(start));
        return parts.join("");
    }

    // A QML or JavaScript file's text without what is not code: a line comment dropped, each
    // block comment, string, regular-expression literal and template literal's text one space
    // (so their braces and words do not count); the code inside a template's `${…}` is kept
    // (nested braces, strings and templates followed). Never throws; "" for anything but a
    // string.
    //
    // A "/" starts a regex literal where a value cannot end: at the start, after one of
    // ( , = : [ ! & | ? { } ; > (so after `=>` too), or after a keyword that takes an operand
    // (regexKeywords) that is not a property name (`x.in`). An unterminated string or regex
    // ends at its line's end — a string spans lines only after a "\" — so a misread costs
    // one line, not the rest of the file.
    function codeText(text) {
        if (typeof text !== "string")
            return "";
        const source = text.slice(0, ModuleFileRules.maxFileBytes);
        const length = source.length;
        // Pieces joined once at the end: a megabyte grown a character at a time is slow
        const parts = [];
        // Where the code not copied yet starts
        let copied = 0;
        // The last significant character outside comments and strings ("a" for a word, a
        // number's digit, a string's end), and the word it ended, if any: where a "/" starts
        // a regex literal rather than divides
        let last = "";
        let lastWord = "";
        // Per `${…}` open: its depth of braces of its own
        const substitutions = [];
        const skip = (from, to, replacement) => {
            if (from > copied)
                parts.push(source.slice(copied, from));
            parts.push(replacement);
            copied = to;
        };
        // A template's text from `start` (after its "`" or a substitution's "}") to its end
        // or its next "${": the index after it
        const templateText = start => {
            let j = start;
            while (j < length) {
                const character = source.charCodeAt(j);
                if (character === 92) {                 // "\"
                    j += 2;
                    continue;
                }
                if (character === 96) {                 // "`"
                    last = "a";
                    lastWord = "";
                    return j + 1;
                }
                if (character === 36 && source.charCodeAt(j + 1) === 123) {   // "${"
                    substitutions.push(0);
                    last = "{";
                    lastWord = "";
                    return j + 2;
                }
                j++;
            }
            return length;
        };
        let i = 0;
        while (i < length) {
            const code = source.charCodeAt(i);
            // White space: copied, changes nothing
            if (code === 32 || code === 10 || code === 9 || code === 13 || code === 12 || code === 11 || code === 160) {
                i++;
                continue;
            }
            // A word: an identifier or keyword
            if ((code >= 97 && code <= 122) || (code >= 65 && code <= 90) || code === 95 || code === 36 || code > 127) {
                let j = i + 1;
                while (j < length) {
                    const inner = source.charCodeAt(j);
                    if ((inner >= 97 && inner <= 122) || (inner >= 65 && inner <= 90) || (inner >= 48 && inner <= 57)
                            || inner === 95 || inner === 36 || inner > 127)
                        j++;
                    else
                        break;
                }
                lastWord = last === "." ? "" : source.slice(i, j);
                last = "a";
                i = j;
                continue;
            }
            const character = source[i];
            const next = source[i + 1];
            if (character === "/" && next === "/") {
                const end = source.indexOf("\n", i);
                skip(i, end < 0 ? length : end, "");
                i = end < 0 ? length : end;
                continue;
            }
            if (character === "/" && next === "*") {
                const end = source.indexOf("*/", i + 2);
                const to = end < 0 ? length : end + 2;
                skip(i, to, " ");
                i = to;
                continue;
            }
            if (character === "/" && (last === "" || "(,=:[!&|?{};>".includes(last) || (lastWord !== "" && regexKeywords.includes(lastWord)))) {
                let j = i + 1;
                let inClass = false;
                while (j < length && source[j] !== "\n" && (inClass || source[j] !== "/")) {
                    if (source[j] === "\\")
                        j++;
                    else if (source[j] === "[")
                        inClass = true;
                    else if (source[j] === "]")
                        inClass = false;
                    j++;
                }
                // Past its closing "/" (its flags are a word that follows), or at the line's end
                const to = j < length && source[j] === "/" ? j + 1 : j;
                skip(i, to, " ");
                i = to;
                last = "a";
                lastWord = "";
                continue;
            }
            if (character === "\"" || character === "'") {
                let j = i + 1;
                while (j < length && source[j] !== character && source[j] !== "\n") {
                    if (source[j] === "\\")
                        j++;
                    j++;
                }
                const to = j < length && source[j] === character ? j + 1 : j;
                skip(i, to, " ");
                i = to;
                last = "a";
                lastWord = "";
                continue;
            }
            if (character === "`") {
                const to = templateText(i + 1);
                skip(i, to, " ");
                i = to;
                continue;
            }
            if (substitutions.length > 0) {
                if (character === "{") {
                    substitutions[substitutions.length - 1]++;
                } else if (character === "}") {
                    if (substitutions[substitutions.length - 1] === 0) {
                        // The substitution's end: its template's text goes on
                        substitutions.pop();
                        const to = templateText(i + 1);
                        skip(i, to, " ");
                        i = to;
                        continue;
                    }
                    substitutions[substitutions.length - 1]--;
                }
            }
            last = character;
            lastWord = "";
            i++;
        }
        if (copied < length)
            parts.push(source.slice(copied));
        return parts.join("");
    }

    // The keywords after which a "/" starts a regex literal (their operand follows)
    readonly property var regexKeywords: ["return", "typeof", "case", "in", "of", "delete", "void", "throw",
        "instanceof", "new", "else", "do", "yield", "await"]

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

    // ---- The import check (a warning or an error, never a refusal) ----

    // The imports at the top of a QML file: [{ name, directory }] — `name` a module name
    // (QtQuick.Layouts) or, for a quoted import, the quoted text with `directory` true. Read
    // as Quickshell's scanner reads them: line by line until the first line with a "{",
    // whose statements before the "{" are read too (`import qs.components; Item {}`). A
    // JavaScript file's `.import` lines count the same (`.import qs.singletons as S`; a quoted
    // one names a file, judged as a directory is: inside the module's own or not).
    function importsOf(text) {
        const imports = [];
        if (typeof text !== "string")
            return imports;
        const header = text.slice(0, ModuleRules.maxHeaderBytes).replace(/\/\*[\s\S]*?\*\//g, " ");
        for (const rawLine of header.split("\n")) {
            // A line comment, not a "//" inside a quoted import ("file:///…")
            const line = rawLine.replace(/^((?:[^"\/]|"[^"]*"|\/(?!\/))*)\/\/.*$/, "$1").trim();
            const brace = line.indexOf("{");
            for (const statement of (brace >= 0 ? line.slice(0, brace) : line).split(";")) {
                const match = /^\.?import\s+(?:"([^"]*)"|([A-Za-z_][A-Za-z0-9_.]*))/.exec(statement.trim());
                if (!match)
                    continue;
                imports.push(match[1] !== undefined ? { name: match[1], directory: true } : { name: match[2], directory: false });
            }
            if (brace >= 0)
                break;
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

    // How many import warnings one file gives at most, and one module (the rest are
    // counted: cappedLines). A header of repeated imports would otherwise give thousands.
    readonly property int maxImportWarningsPerFile: 5
    readonly property int maxImportWarnings: 50

    // A file's or an import's name in a message: at most 80 characters, cut with "…" (a
    // listed file may have a path of thousands)
    function nameLabel(name) {
        const text = String(name ?? "");
        return text.length > 80 ? text.slice(0, 79) + "…" : text;
    }

    // `lines`, at most `cap` of them: past it, the first cap and "… and <n> more"
    function cappedLines(lines, cap) {
        const list = lines ?? [];
        if (list.length <= cap)
            return list.slice();
        return list.slice(0, cap).concat(["… and " + (list.length - cap) + " more"]);
    }

    // The warnings for one file of a module: one per import outside the allowlist (those that
    // reach into the shell or another module are errors instead: importErrors), at most
    // maxImportWarningsPerFile. A test suite (`isTest`: listed in the manifest's tests) may
    // also import qs.tests — the shell's TestCase, which tests/run-modules.sh provides and the
    // running shell does not: a module's own file importing it would pass its suites and fail
    // in the shell.
    function importWarnings(file, text, isTest) {
        return cappedLines(importsOf(text).filter(entry => !importAllowed(entry, file) && !importReaches(entry, file)
                                                   && !(isTest === true && !entry.directory && entry.name === "qs.tests")).map(entry =>
            nameLabel(file) + " imports " + (entry.directory ? "\"" + nameLabel(entry.name) + "\"" : nameLabel(entry.name))
            + ", outside what modules may import (" + allowedImports.concat(allowedImportPrefixes.map(prefix => prefix + "*")).join(", ")
            + ", the module's own directory)"), maxImportWarningsPerFile);
    }

    // An import that reaches into the shell or another module (reachingImportPrefixes, or a
    // directory outside the module's own: importAllowed refuses it)
    function importReaches(entry, file) {
        if (entry.directory)
            return !importAllowed(entry, file);
        return reachingImportPrefixes.some(prefix => entry.name === prefix || entry.name.startsWith(prefix + "."));
    }

    // The errors for one file of a module: one per import that reaches into the shell or
    // another module (importReaches), at most maxImportWarningsPerFile
    function importErrors(file, text) {
        return cappedLines(importsOf(text).filter(entry => importReaches(entry, file)).map(entry =>
            nameLabel(file) + " imports " + (entry.directory
                ? "\"" + nameLabel(entry.name) + "\", outside the module's directory: another module is used through `uses`"
                : nameLabel(entry.name) + ", the shell's own: a module reaches the shell through qs.api")), maxImportWarningsPerFile);
    }

    // The deprecations for a module's code (`texts`: { file: text }): one line per old way of
    // deprecatedCode it uses, saying where — the file, or how many files. In the order of
    // deprecatedCode. `known`: { file: codeText(text) } for the files the caller has it of.
    function codeDeprecations(texts, known) {
        const lines = [];
        const codes = {};
        for (const file of Object.keys(texts ?? {}))
            codes[file] = typeof known?.[file] === "string" ? known[file] : codeText(texts[file]);
        for (const old of deprecatedCode) {
            const files = Object.keys(codes).filter(file => old.pattern.test(codes[file]));
            if (files.length === 0)
                continue;
            const where = old.what + " (in " + (files.length === 1 ? nameLabel(files[0]) : files.length + " files") + ")";
            // One already removed reads as gone, not as going
            lines.push(old.removed ? where + ": gone since API " + old.removed + "; use " + old.use : ModuleRules.deprecation(where, old.use));
        }
        return lines;
    }

    // The deprecations for a module's files (`texts`: { file: text }): one line per
    // deprecated import, saying where it is — the file, or how many files
    // (ModuleRules.deprecation). In the order of `deprecatedImports`.
    function importDeprecations(texts) {
        const lines = [];
        for (const name of Object.keys(deprecatedImports)) {
            const files = Object.keys(texts ?? {}).filter(file =>
                importsOf(texts[file]).some(entry => !entry.directory && entry.name === name));
            if (files.length === 0)
                continue;
            lines.push(ModuleRules.deprecation("import " + name + " (in " + (files.length === 1 ? nameLabel(files[0]) : files.length + " files") + ")",
                deprecatedImports[name]));
        }
        return lines;
    }
}
