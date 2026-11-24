pragma Singleton

import Quickshell
import QtQuick

// NetworkManager's connectivity check address as a change the distribution makes
// (IntegrationRules' "network.connectivityUri"; tests/ConnectivityRulesTest.qml): the address
// itself, the shell's file for it, the setting as NetworkManager merges its configuration
// files, and what Settings → Network → Overview offers for it. Pure.
//
// NetworkManager reads, later files overriding earlier ones (NetworkManager.conf(5)):
// /usr/lib/NetworkManager/conf.d/*.conf (the distribution's packages), then
// /run/NetworkManager/conf.d/*.conf, then /etc/NetworkManager/NetworkManager.conf, then
// /etc/NetworkManager/conf.d/*.conf, each folder by name; a name in a later folder hides the
// same name in an earlier one. Last, NetworkManager-intern.conf, which holds only what was set
// over D-Bus — the address cannot be (its property is read-only), so it is not read.
// scripts/nm-config-files.sh prints the files in that order.
Singleton {
    id: root

    readonly property string kind: "network.connectivityUri"
    // The NixOS option that sets it (the line to copy)
    readonly property string nixosOption: "networking.networkmanager.settings.connectivity.uri"
    // The first line of the shell's file
    readonly property string header: "# Written by h2s-shell (Settings > System > Network)"
    // Where the distribution's packages put their defaults: a setting there is the system's
    // own address, not one anybody set
    readonly property string packageDirectory: "/usr/lib/NetworkManager/conf.d/"
    readonly property string configDirectory: "/etc/NetworkManager/conf.d/"
    // The longest value shown in a line (it comes from a file outside the shell)
    readonly property int shownLength: 120

    // An address for the check: http(s), a host, nothing that could break out of its line in
    // the configuration file (spaces, quotes, newlines)
    function isUri(text) {
        return /^https?:\/\/[A-Za-z0-9.-]+(:\d+)?(\/[^\s"'\\]*)?$/.test(String(text ?? ""));
    }

    // The shell's file for an address (etc-files.sh writes nothing else for the kind)
    function text(uri) {
        return header + "\n[connectivity]\nuri=" + uri + "\n";
    }

    // Whether `given` is exactly the shell's file for the address in it
    function shellText(given) {
        if (typeof given !== "string")
            return false;
        const found = /^uri=(.*)\n$/m.exec(given);
        return found !== null && isUri(found[1]) && text(found[1]) === given;
    }

    // Whether NetworkManager reads `path` after the shell's own file: only a file of its
    // conf.d folder in /etc whose name sorts after it; a path it does not know counts as after
    // (nothing is promised over it)
    function readAfterOwn(path) {
        const given = String(path ?? "");
        const own = EtcFilesRules.files[kind];
        const ownName = own.slice(own.lastIndexOf("/") + 1);
        if (given === "/etc/NetworkManager/NetworkManager.conf")
            return false;
        const placed = /^\/(usr\/lib|run|etc)\/NetworkManager\/conf\.d\/([^/]+\.conf)$/.exec(given);
        if (placed === null)
            return true;
        return placed[1] === "etc" && placed[2] > ownName;
    }

    // The address as NetworkManager merges it, from nm-config-files.sh's output (its files in
    // the order it reads them: `file<TAB><path><TAB>text`, the lines each after a "|", then
    // `end<TAB><path>`; `file<TAB><path><TAB>unreadable`; `unknown<TAB><why>`; `done` last) →
    // { state ("set": a file sets it; "default": none does, or only the distribution's
    // packages; "unknown": a file not read, or the output not understood), value (the address
    // set, "" for an empty one; null unless "set"), from (the file whose setting is in force,
    // "" for none) }
    function setting(output) {
        const unknown = { state: "unknown", value: null, from: "" };
        if (typeof output !== "string")
            return unknown;
        const lines = output.split("\n");
        if (lines.length > 0 && lines[lines.length - 1] === "")
            lines.pop();
        let value = null, from = "", open = null, body = [], finished = false;
        for (const line of lines) {
            if (finished)
                return unknown;
            if (open !== null) {
                if (line.startsWith("|")) {
                    body.push(line.slice(1));
                    continue;
                }
                if (line !== "end\t" + open)
                    return unknown;
                const found = _uriIn(body);
                if (found !== null) {
                    value = found;
                    from = open;
                }
                open = null;
                body = [];
                continue;
            }
            const fields = line.split("\t");
            if (line === "done")
                finished = true;
            else if (fields[0] === "file" && fields.length === 3 && fields[1].startsWith("/") && fields[2] === "text")
                open = fields[1];
            else
                return unknown;
        }
        if (!finished || open !== null)
            return unknown;
        if (value === null || from.startsWith(packageDirectory))
            return { state: "default", value: null, from };
        return { state: "set", value, from };
    }

    // The last `uri` of the [connectivity] group in a file's lines (GKeyFile's reading:
    // leading blanks ignored, `#` comments, a group repeated is the same group), or null
    function _uriIn(lines) {
        let group = "", found = null;
        for (const raw of lines) {
            const line = raw.replace(/^\s+/, "");
            if (line === "" || line.startsWith("#"))
                continue;
            const header = /^\[([^\]]*)\]\s*$/.exec(line);
            if (header !== null) {
                group = header[1];
                continue;
            }
            const pair = /^([^=]*)=(.*)$/.exec(line);
            if (group === "connectivity" && pair !== null && pair[1].trim() === "uri")
                found = pair[2].trim();
        }
        return found;
    }

    // What the connectivity check's address row offers, its labels and effects in one answer.
    // `given` { field (the address typed, trimmed), current (NetworkManager's address in use,
    // "" for none), capability (the distribution's for the kind: IntegrationRules.capability's),
    // snippet (plan's line to copy for the field, "" for none), inForce (readInForce's answer;
    // null before one or while a change runs), busy ("apply" or "undo" while one runs, else
    // ""), undoable (a change of the shell's in this run that Undo puts back) } →
    // { hint (the line under the field), save, copy, anyway, undo }:
    //   save    { shown, button ("none", "plain": acts on the click, "ask": on a second click
    //           after its question), label, question, tooltip, available, request }
    //   copy    { shown, label, available, text }
    //   anyway  { shown, hint, button, label, question, available, request } — writing the
    //           file where the system's configuration makes /etc (the user's choice, warned)
    //   undo    { shown, label, available }
    // A request is { uri ("" removes the shell's file), current (readInForce's `file`: what the
    // change is checked against), replace (the user was told that file is not exactly the
    // shell's), anyway }.
    //
    // A setting in another file is the user's or the system's: named with its value; read
    // after the shell's file, a write could not win over it and is not offered; read before
    // it, the write asks first (warn, never forbid). The shell's own file changed outside it
    // is replaced or removed only on a second click too. Nothing is offered while what is in
    // force is not known.
    function offer(given) {
        const field = typeof given?.field === "string" ? given.field : "";
        const current = typeof given?.current === "string" ? given.current : "";
        const capability = given?.capability ?? {};
        const busy = typeof given?.busy === "string" && given.busy !== "";
        const path = EtcFilesRules.files[kind];
        const problem = field !== "" && !isUri(field);
        const changed = field !== current && !problem;
        const removing = field === "";
        const applied = capability.mode === "apply";
        const copied = capability.mode === "copy" || capability.mode === "declare";
        const guard = _guard(given?.inForce ?? null, removing, path, removing ? "Default" : applied ? "Save" : "Write anyway");
        const request = guard.current === undefined ? null : { uri: field, current: guard.current, replace: guard.replace, anyway: !applied };
        const writes = { button: guard.button, question: guard.question, available: changed && !busy && guard.available, request };
        const answer = {
            hint: "",
            save: Object.assign({ shown: applied, label: removing && current !== "" ? "Default" : "Save",
                                  tooltip: removing ? "Back to the distribution's address (none on some)" : "" }, writes),
            copy: { shown: copied, label: "Copy for configuration.nix", available: field !== "" && !problem,
                    text: typeof given?.snippet === "string" ? given.snippet : "" },
            anyway: Object.assign({ shown: copied && capability.anyway === true, label: "Write anyway",
                                    hint: "Add the copied line to your configuration.nix and rebuild — or write NetworkManager's file here, outside the system's configuration:" },
                                  writes),
            undo: { shown: applied && capability.undo === true && given?.undoable === true, label: "Undo", available: !busy }
        };
        if (!applied)
            answer.save.available = false;
        if (!answer.anyway.shown)
            answer.anyway.available = false;
        if (problem) {
            answer.hint = "An http:// or https:// address, without spaces or quotes.";
            return answer;
        }
        const base = applied ? "The address it fetches now and then; saved in " + path + "." : "The address it fetches now and then.";
        const reason = capability.mode === "unavailable" && capability.known === true && typeof capability.reason === "string" ? capability.reason : "";
        const writing = applied || answer.anyway.shown;
        answer.hint = [base, writing ? guard.line : "", reason].filter(part => part !== "").join(" ");
        return answer;
    }

    // What is in force allows of a write (or a removal, `removing`): { button, question,
    // available, current (the file to check against; undefined: none to act on), replace,
    // line (what to say) }. `word` is the button's label in the line
    function _guard(inForce, removing, path, word) {
        const none = { button: "none", question: "", available: false, current: undefined, replace: false, line: "" };
        if (inForce === null)
            return Object.assign({}, none, { button: "plain" });
        const file = inForce.file ?? null;
        const readable = (inForce.state === "set" || inForce.state === "default") && file !== null && typeof file === "object"
            && (file.state === "text" || file.state === "absent");
        if (!readable)
            return Object.assign({}, none, { line: "NetworkManager's configuration could not be read." });
        const elsewhere = typeof inForce.elsewhere === "string" ? inForce.elsewhere : "";
        const shown = value => value === "" ? "no address" : value.length > shownLength ? value.slice(0, shownLength) + "…" : value;
        const setThere = elsewhere === "" ? ""
            : "Set in " + elsewhere + ": " + (inForce.state === "set" ? shown(String(inForce.value ?? "")) : "the default");
        if (elsewhere !== "" && inForce.afterOwn !== false && !removing)
            return Object.assign({}, none, { line: setThere + "; it is read after the shell's file." });
        const edited = file.state === "text" && file.ours !== true;
        const parts = [];
        if (setThere !== "")
            parts.push(setThere + (inForce.afterOwn === true ? "; it is read after the shell's file." : "."));
        if (edited)
            parts.push(path + " was changed outside the shell: " + word + (removing ? " removes it." : " replaces it."));
        // Removing: another file's setting then applies, which overrides nothing of the user's
        const asks = edited || (elsewhere !== "" && !removing);
        return {
            button: asks ? "ask" : "plain",
            question: edited ? (removing ? "Remove?" : "Replace?") : asks ? "Use the shell's value instead?" : "",
            available: !(removing && file.state === "absent"),
            current: file,
            replace: edited,
            line: parts.join(" ")
        };
    }
}
