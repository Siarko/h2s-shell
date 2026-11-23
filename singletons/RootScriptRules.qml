pragma Singleton

import Quickshell
import QtQuick

// What the shell's root scripts share: where they are and the text handed to pkexec (every
// one: PamApplyRules, RememberInstallRules, HibernateRules); for the ones that replace system
// files (the first two), the places a run may write and how a run that did not say it was done
// is read. The scripts themselves are files in the shell's tree (scripts/root/), never text
// built in QML; replace-lib.sh, the functions of the ones that replace system files, is joined
// before each one's own. Pure.
Singleton {
    id: root

    // Where the root scripts are, under the shell's tree; never run by path, read as text
    readonly property string directory: "scripts/root"

    // The text handed to pkexec for the files' texts, in order (a library first): joined as
    // they are, or "" when one could not be read (not a string, empty, or not ending in a line
    // break) — the run is then refused
    function script(texts) {
        if (!Array.isArray(texts) || texts.length === 0)
            return "";
        if (texts.some(text => typeof text !== "string" || text === "" || !text.endsWith("\n")))
            return "";
        return texts.join("");
    }

    // An absolute path of plain names: no space, no quote, no `.` or `..` part
    function plainPath(path) {
        return typeof path === "string" && /^(\/[A-Za-z0-9._-]+)+$/.test(path)
            && !path.split("/").some(part => part === "." || part === "..");
    }

    // The folder the places `names` of `paths` are under, each the same path below it as in
    // `livePaths` ("" for the system's own places), or null when they are not
    function base(paths, names, livePaths) {
        if (paths === null || typeof paths !== "object" || names.some(name => !plainPath(paths[name])))
            return null;
        const first = paths[names[0]], tail = livePaths[names[0]];
        if (!first.endsWith(tail))
            return null;
        const under = first.slice(0, first.length - tail.length);
        return names.every(name => paths[name] === under + livePaths[name]) ? under : null;
    }

    // Whether the places `names` of `paths` may be written: "" when they may, else "paths".
    // The script's places are fixed in its file, under the folder its first argument names
    // (base): `live`, the run goes to the system's pkexec, so exactly `livePaths` (base "");
    // a stand-in's run is under a scratch folder outside /etc, /usr and /var — the script
    // checks the same.
    function placesRefusal(paths, names, livePaths, live) {
        const under = base(paths, names, livePaths);
        if (under === null)
            return "paths";
        if (live === true)
            return under === "" ? "" : "paths";
        const system = ["/etc", "/usr", "/var"];
        return plainPath(under) && !system.some(top => under === top || under.startsWith(top + "/")) ? "" : "paths";
    }

    // A run that did not say it was done (PrivilegedRules' result) → { quiet } for a prompt
    // dismissed, a run refused, cancelled or blocked (said elsewhere, or the user's choice);
    // else { refused (the script's code), error (its text in `texts`, else texts.arguments) }
    // for its refusal line; else { error } — the reason for the log and the page, on one line
    function failure(result, texts) {
        if (result?.dismissed === true || result?.refused === true || result?.cancelled === true || (result?.blocked ?? "") !== "")
            return { quiet: true };
        const stderr = String(result?.stderr ?? "").trim().split("\n").map(line => line.trim());
        const refusedLine = stderr.slice().reverse().find(line => /^refused [a-z]+$/.test(line));
        if (refusedLine !== undefined) {
            const code = refusedLine.slice("refused ".length);
            return { refused: code, error: texts?.[code] ?? texts?.arguments ?? "" };
        }
        const reason = String(result?.error || stderr.pop() || (result?.ok === true ? "an answer that is not the one asked for" : ""))
            .replace(/[\u0000-\u001f\u007f]+/g, " ").trim();
        return { error: reason !== "" ? reason.slice(0, 200) : "exit code " + (result?.code ?? -1) };
    }
}
