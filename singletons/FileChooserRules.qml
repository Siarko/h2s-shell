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
    // is plain text on one line: control and format characters dropped, white space folded,
    // at most titleMaxLength characters. `startDirectory`: an absolute path ("/" ends
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
    // titleMaxLength characters (by code point, an emoji never cut in half)
    function cleanTitle(text) {
        if (typeof text !== "string")
            return "";
        const kept = PrivilegedRules.characters(text.replace(/\s+/g, " "))
            .filter(character => !PrivilegedRules.unprintableCode(character.codePointAt(0))).join("");
        return PrivilegedRules.characters(kept.trim()).slice(0, titleMaxLength).join("").trim();
    }

    // An absolute path without its trailing "/" ("/" stays); anything else ""
    function cleanDirectory(path) {
        if (typeof path !== "string" || !path.startsWith("/") || pathProblem(path) !== "")
            return "";
        const trimmed = path.replace(/\/+$/, "");
        return trimmed === "" ? "/" : trimmed;
    }

    // "" for a path the shell takes, else why not: too long, or a control character in it
    function pathProblem(path) {
        if (path.length > pathMaxLength)
            return "longer than " + pathMaxLength + " characters";
        if (/[\u0000-\u001f\u007f]/.test(path))
            return "it holds a control character";
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

    // The result handed to `done`, frozen, `paths` too: { paths, cancelled, blocked, error }
    function result(fields) {
        const paths = Array.isArray(fields?.paths) ? fields.paths.map(path => String(path)) : [];
        return Object.freeze({
            paths: Object.freeze(paths),
            cancelled: fields?.cancelled === true,
            blocked: blockedReasons.includes(fields?.blocked) ? fields.blocked : "",
            error: typeof fields?.error === "string" ? fields.error : ""
        });
    }

    // A local directory as the URL a dialog starts in ("" for none): each part of the path
    // percent-encoded, so a "#" or "?" in a name stays part of it
    function folderUrl(path) {
        if (typeof path !== "string" || !path.startsWith("/"))
            return "";
        return "file://" + path.split("/").map(part => encodeURIComponent(part)).join("/");
    }

    // A file: URL as an absolute path, or "" when it is not a local file
    function pathOf(url) {
        const text = String(url ?? "");
        if (!text.startsWith("file:///"))
            return "";
        let path;
        try {
            path = decodeURIComponent(text.slice("file://".length));
        } catch (error) {
            return "";
        }
        return path.startsWith("/") && pathProblem(path) === "" ? path : "";
    }

    // What an accepted dialog chose (`urls`: its selected URLs) → a result. A mode that
    // takes one keeps the first; the same path twice is kept once. A URL that is not a
    // local file, or nothing chosen, is an `error` with no paths: the module never gets
    // half a choice.
    function accepted(urls, mode) {
        const list = Array.from(urls ?? []).map(url => String(url));
        const paths = [];
        for (const url of list) {
            const path = pathOf(url);
            if (path === "")
                return result({ error: "the dialog returned something that is not a local file" });
            if (!paths.includes(path))
                paths.push(path);
        }
        if (paths.length === 0)
            return result({ error: "the dialog returned nothing" });
        return result({ paths: mode === "openMany" ? paths : paths.slice(0, 1) });
    }

    // A test kit's answer (ModuleTestKit.answerChooser) for the open call's mode →
    // { result, problem }: absolute paths as strings, one for "open" and "folder", at least
    // one. A wrong answer is the suite's mistake: `problem` says it and nothing is answered.
    function testAnswer(paths, mode) {
        if (!Array.isArray(paths) || paths.length === 0)
            return { result: null, problem: "the answer must be a list of at least one path" };
        if (mode !== "openMany" && paths.length > 1)
            return { result: null, problem: "mode \"" + mode + "\" chooses one path, not " + paths.length };
        for (const path of paths) {
            if (typeof path !== "string" || !path.startsWith("/") || pathProblem(path) !== "")
                return { result: null, problem: "not an absolute path: " + ModuleRules.show(path) };
        }
        return { result: accepted(paths.map(path => folderUrl(path)), mode), problem: "" };
    }
}
