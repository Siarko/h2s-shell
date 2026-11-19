pragma Singleton

import Quickshell
import QtQuick

// The file chooser's decisions (module API 1.17, singletons/FileChooser.qml does the I/O):
// what a module asked for, whether it may be asked now, and what the dialog's answer becomes.
// Pure, with unit cases in tests/FileChooserRulesTest.qml.
Singleton {
    id: root

    readonly property var modes: ["open", "openMany", "folder"]
    readonly property int titleMaxLength: 60
    readonly property int pathMaxLength: 4096
    // Why a call was refused before any dialog showed (result.blocked)
    readonly property var blockedReasons: ["locked", "busy"]

    // ---- What was asked ----

    // module.chooseFiles's options, read once → { mode, title, startDirectory, problem }.
    // `home`: the directory a chooser starts in when none is given ("" when not known: then
    // the dialog's own). Missing options are the defaults: mode "open", no title. `title`
    // is plain text on one line: control and format characters and "<", ">", "&" dropped,
    // white space folded, at most titleMaxLength characters. `startDirectory`: an absolute path ("/" ends
    // dropped), or "" for `home`. `problem`: "" or what was asked wrongly — then nothing
    // opens and the result's `error` says it.
    function options(given, home) {
        const result = { mode: "open", title: "", startDirectory: cleanDirectory(home), problem: "" };
        if (given === undefined || given === null)
            return result;
        if (typeof given !== "object" || Array.isArray(given)) {
            result.problem = "the options are not an object";
            return result;
        }
        let read;
        try {
            read = { mode: given.mode, title: given.title, startDirectory: given.startDirectory };
        } catch (error) {
            result.problem = "the options could not be read: " + error;
            return result;
        }
        if (read.mode !== undefined && read.mode !== null) {
            if (typeof read.mode !== "string" || !modes.includes(read.mode)) {
                result.problem = "mode must be one of " + modes.join(", ");
                return result;
            }
            result.mode = read.mode;
        }
        if (read.title !== undefined && read.title !== null) {
            if (typeof read.title !== "string") {
                result.problem = "title must be text";
                return result;
            }
            result.title = cleanTitle(read.title);
        }
        if (read.startDirectory !== undefined && read.startDirectory !== null && read.startDirectory !== "") {
            const directory = read.startDirectory;
            if (typeof directory !== "string" || !directory.startsWith("/")) {
                result.problem = "startDirectory must be an absolute path";
                return result;
            }
            if (pathProblem(directory) !== "") {
                result.problem = "startDirectory: " + pathProblem(directory);
                return result;
            }
            result.startDirectory = cleanDirectory(directory);
        }
        return result;
    }

    // A title as the dialog shows it: one line, no control or format characters, at most
    // titleMaxLength characters (by code point, an emoji never cut in half). "<", ">" and "&"
    // are dropped: Qt Quick's own dialog may show the title in a label that reads markup.
    function cleanTitle(text) {
        if (typeof text !== "string")
            return "";
        const kept = PrivilegedRules.characters(text.replace(/[<>&]/g, " ").replace(/\s+/g, " "))
            .filter(character => !PrivilegedRules.unprintableCode(character.codePointAt(0))).join("");
        return PrivilegedRules.characters(kept.trim()).slice(0, titleMaxLength).join("").trim();
    }

    // The title the dialog shows: the module's own, else the module's name (its manifest's,
    // cleaned the same way), so a dialog never opens with no word on whose it is
    function shownTitle(title, moduleName) {
        const own = cleanTitle(title);
        return own !== "" ? own : cleanTitle(moduleName);
    }

    // An absolute path without its trailing "/" ("/" stays); anything else ""
    function cleanDirectory(path) {
        if (typeof path !== "string" || !path.startsWith("/") || pathProblem(path) !== "")
            return "";
        const trimmed = path.replace(/\/+$/, "");
        return trimmed === "" ? "/" : trimmed;
    }

    // "" for a path the shell takes, else why not: too long, a control character in it, or
    // half of a character (a lone surrogate, which no file name can hold)
    function pathProblem(path) {
        if (typeof path !== "string")
            return "not text";
        if (path.length > pathMaxLength)
            return "longer than " + pathMaxLength + " characters";
        if (/[\u0000-\u001f\u007f]/.test(path))
            return "it holds a control character";
        try {
            encodeURIComponent(path);
        } catch (error) {
            return "it holds a broken character";
        }
        return "";
    }

    // ---- Whether it may open now ----

    // `request`: { active (the module is on), locked (the session), busy (a chooser is open,
    // anyone's) } → "off" (the module gets no answer at all), "locked", "busy", or "" (it
    // may open). The module off first: then nothing is called, whatever else holds.
    function refusal(request) {
        if (request?.active !== true)
            return "off";
        if (request.locked === true)
            return "locked";
        if (request.busy === true)
            return "busy";
        return "";
    }

    // ---- The answer ----

    // The result handed to `done`, frozen, `paths` too: { paths, cancelled, blocked, error }.
    // `cancelled` is the user's (or the module's cancel()); a lock that closes an open chooser
    // is `blocked: "locked"`, as when it refuses to open one, so a module can tell the two apart.
    function result(fields) {
        const paths = Array.isArray(fields?.paths) ? fields.paths.map(path => String(path)) : [];
        return Object.freeze({
            paths: Object.freeze(paths),
            cancelled: fields?.cancelled === true,
            blocked: blockedReasons.includes(fields?.blocked) ? fields.blocked : "",
            error: typeof fields?.error === "string" ? fields.error : ""
        });
    }

    // A local directory as the URL a dialog starts in ("" for none, or for a path the shell
    // does not take): each part of the path percent-encoded, so a "#" or "?" in a name stays
    // part of it
    function folderUrl(path) {
        if (typeof path !== "string" || !path.startsWith("/") || pathProblem(path) !== "")
            return "";
        return "file://" + path.split("/").map(part => encodeURIComponent(part)).join("/");
    }

    // A file: URL as an absolute path, or "" when it is not a local file
    function pathOf(url) {
        return localPath(url).path;
    }

    // A file: URL → { path, problem }: the absolute path, or "" and why not (the words an
    // accepted dialog's error uses)
    function localPath(url) {
        const notLocal = { path: "", problem: "the dialog returned something that is not a local file" };
        const text = String(url ?? "");
        if (!text.startsWith("file:///"))
            return notLocal;
        let path;
        try {
            path = decodeURIComponent(text.slice("file://".length));
        } catch (error) {
            return notLocal;
        }
        if (!path.startsWith("/"))
            return notLocal;
        if (/[\u0000-\u001f\u007f]/.test(path))
            return { path: "", problem: "the name chosen holds a line break or another control character" };
        if (pathProblem(path) !== "")
            return { path: "", problem: "the dialog returned a path the shell does not take: " + pathProblem(path) };
        return { path: path, problem: "" };
    }

    // What a folder dialog's Open gives (`selected`: its selectedFolder, `shown`: its
    // currentFolder) → the URL chosen. Qt Quick's own dialog has no folder selected when the
    // one shown has no sub-folders: Open means the folder shown. When it has some, the first
    // is selected as the dialog opens — the same as the user picking it — and is what Open
    // gives until another is picked.
    function folderChosen(selected, shown) {
        const text = String(selected ?? "");
        return text !== "" ? text : String(shown ?? "");
    }

    // What an accepted dialog chose (`urls`: its selected URLs) → a result. A mode that
    // takes one keeps the first; the same path twice is kept once. A URL that is not a
    // local file, or nothing chosen, is an `error` with no paths: the module never gets
    // half a choice.
    function accepted(urls, mode) {
        const list = Array.from(urls ?? []).map(url => String(url));
        const paths = [];
        for (const url of list) {
            const local = localPath(url);
            if (local.problem !== "")
                return result({ error: local.problem });
            if (!paths.includes(local.path))
                paths.push(local.path);
        }
        if (paths.length === 0)
            return result({ error: "the dialog returned nothing" });
        return result({ paths: mode === "openMany" ? paths : paths.slice(0, 1) });
    }

    // A test kit's answer (ModuleTestKit.answerChooser) for the open call's mode →
    // { result, problem }: absolute paths as strings, one for "open" and "folder", at least
    // one. A wrong answer is the suite's mistake: `problem` says it and nothing is answered.
    // Never throws: the list is copied once, and anything odd in it is a problem.
    function testAnswer(paths, mode) {
        let list;
        try {
            list = Array.isArray(paths) ? Array.from(paths) : null;
        } catch (error) {
            return { result: null, problem: "the answer could not be read: " + error };
        }
        if (list === null || list.length === 0)
            return { result: null, problem: "the answer must be a list of at least one path" };
        if (mode !== "openMany" && list.length > 1)
            return { result: null, problem: "mode \"" + mode + "\" chooses one path, not " + list.length };
        for (const path of list) {
            if (typeof path !== "string" || !path.startsWith("/"))
                return { result: null, problem: "not an absolute path: " + ModuleRules.show(path) };
            if (pathProblem(path) !== "")
                return { result: null, problem: "not a path the shell takes (" + pathProblem(path) + "): " + ModuleRules.show(path) };
        }
        return { result: accepted(list.map(path => folderUrl(path)), mode), problem: "" };
    }
}
