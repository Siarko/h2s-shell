pragma Singleton

import Quickshell
import QtQuick

// The shell's own files in /etc, where /etc is the machine's own (tests/EtcFilesRulesTest.qml):
// which file each change kind writes, the root step that writes, removes or puts one back,
// and what its reply means. The I/O is distributions/EtcFiles.qml's.
//
// The root step is scripts/root/etc-files.sh after replace-lib.sh and replace-file.sh
// (`scriptFiles`), files in the shell's tree the shell reads and hands as text to the
// system's /bin/sh through its runs as administrator (PrivilegedRuns.startShell): never run by
// path, every run asks the password. Its files (`files`) and their backups' folders are
// fixed in it, one per change kind, under the folder its first argument names — "" for the
// system, the only one it takes as root —; it refuses before changing anything when the file
// changed since the shell read it (its sha256, or that there was none), the file is a link,
// a folder written in is a link, not root's or writable by others, the text is not one the
// shell writes (`marker` first, at most `maxBytes`, a line break last) or not the bytes the
// shell computed, or another run holds the kind's lock. It keeps the file it replaces as a
// backup (`<file name>.<UTC time>`, `.absent` for none; every one kept) and says what is in
// force.
//
// Never overriding what the user set: a file the shell did not write (no marker) is
// replaced only when the request says so (`replace`), after the user was told. Pure.
Singleton {
    id: root

    // Each change kind's file, as fixed in etc-files.sh
    readonly property var files: ({
        "sleep.hibernateDelay": "/etc/systemd/sleep.conf.d/h2s-shell.conf"
    })
    // Where each kind's backups are: <backupsDirectory>/<kind>
    readonly property string backupsDirectory: "/var/lib/h2s-shell/backup"
    // The root step's files in scripts/root/, joined in this order (RootScriptRules.script)
    readonly property var scriptFiles: ["replace-lib.sh", "replace-file.sh", "etc-files.sh"]
    // The first line of every file the shell writes starts with it
    readonly property string marker: "# Written by h2s-shell"
    readonly property int maxBytes: 65536

    // What the prompt says each kind's run is for
    readonly property var _subjects: ({
        "sleep.hibernateDelay": "the time before hibernating"
    })

    // Why a run was not started, or what the root step refused, by code
    readonly property var texts: ({
        // Before the run
        kind: "Not a file the shell writes.",
        text: "Not a text the shell writes.",
        unchanged: "Nothing to change.",
        unread: "The file could not be read.",
        other: "The file was changed outside the shell: not replaced without asking.",
        noUndo: "There is no change of the shell's to undo.",
        backupName: "Not a backup of this file.",
        paths: "Not a place the shell writes files to.",
        busy: "A change is already being saved.",
        script: "The shell's script for this could not be read.",
        start: "The change could not be started.",
        // By the root step
        arguments: "The request was not valid.",
        system: "The folder is not there.",
        owner: "A folder written in is not root's alone: nothing changed.",
        lock: "The change could not be kept to one at a time: nothing changed.",
        link: "The file is a link: not changed.",
        changed: "The file changed since it was read: read it again.",
        unreadable: "The file could not be read.",
        backup: "The backup could not be made: nothing changed.",
        nobackup: "That backup is not there.",
        write: "The new file could not be written: nothing changed.",
        hash: "The file written was not the one asked for: nothing changed."
    })

    readonly property string _stampPattern: "[0-9]{8}T[0-9]{6}Z(-[1-9])?(\\.absent)?"

    function refusal(code) {
        return { code, text: texts[code] ?? texts.arguments };
    }

    function _refused(code) {
        return { argv: null, expected: null, refusal: refusal(code) };
    }

    function knows(kind) {
        return typeof kind === "string" && Object.prototype.hasOwnProperty.call(files, kind);
    }

    function isHash(value) {
        return typeof value === "string" && /^[0-9a-f]{64}$/.test(value);
    }

    // The kind's file under `base` ("" for the system's), or "" for a kind it does not know
    function fileOf(kind, base) {
        return knows(kind) ? String(base ?? "") + files[kind] : "";
    }

    // The kind's backups' folder under `base`
    function backupsOf(kind, base) {
        return knows(kind) ? String(base ?? "") + backupsDirectory + "/" + kind : "";
    }

    // Whether `name` is a backup of the kind's file as the root step names them
    function validBackup(kind, name) {
        if (!knows(kind) || typeof name !== "string")
            return false;
        const fileName = files[kind].slice(files[kind].lastIndexOf("/") + 1);
        return new RegExp("^" + fileName.replace(/[.-]/g, "\\$&") + "\\." + _stampPattern + "$").test(name);
    }

    // Whether a text is one the shell writes: the marker first, a line break last, at most
    // maxBytes (UTF-8), and no control character but tabs and line breaks
    function validText(text) {
        return typeof text === "string" && text.startsWith(marker) && text.endsWith("\n")
            && _utf8Length(text) <= maxBytes && !/[\u0000-\u0008\u000b-\u001f\u007f]/.test(text);
    }

    function _utf8Length(text) {
        let length = 0;
        for (const character of text) {
            const code = character.codePointAt(0);
            length += code < 0x80 ? 1 : code < 0x800 ? 2 : code < 0x10000 ? 3 : 4;
        }
        return length;
    }

    // Whether a file's text is one the shell wrote (its marker first)
    function ours(text) {
        return typeof text === "string" && text.startsWith(marker);
    }

    // The file as read (PamStackRules.filesAnswer's answer for its path: { text }, { absent },
    // { unreadable }, or nothing) → { state ("text", "absent" or "unknown"), text, sha256
    // ("absent" for none, "" unknown), ours }
    function inForce(answer) {
        if (typeof answer?.text === "string")
            return { state: "text", text: answer.text, sha256: PamEditRules.sha256(answer.text), ours: ours(answer.text) };
        if (answer?.absent === true)
            return { state: "absent", text: null, sha256: "absent", ours: false };
        return { state: "unknown", text: null, sha256: "", ours: false };
    }

    // Whether the folder the places are under may be written: "" when it may, else "paths".
    // `live`: the run goes to the system's pkexec, so only the system's ("" ); a stand-in's
    // run is under a plain absolute folder outside /etc, /usr and /var — the script checks the
    // same
    function baseRefusal(base, live) {
        if (live === true)
            return base === "" ? "" : "paths";
        if (!RootScriptRules.plainPath(base))
            return "paths";
        return ["/etc", "/usr", "/var"].some(top => base === top || base.startsWith(top + "/")) ? "paths" : "";
    }

    // What the prompt says the run is for
    function what(mode, kind) {
        const subject = _subjects[kind] ?? "a system file";
        return mode === "undo" ? "Undo the change to " + subject
            : mode === "remove" ? "Go back to the system's " + subject.replace(/^the /, "")
            : "Change " + subject;
    }

    // The run's first words → { argv, refusal: null } or a refusal
    function _start(shell, kind, base, live, scripts) {
        if (typeof shell !== "string" || !shell.startsWith("/"))
            return _refused("arguments");
        if (!knows(kind))
            return _refused("kind");
        const pathProblem = baseRefusal(base, live);
        if (pathProblem !== "")
            return _refused(pathProblem);
        const script = RootScriptRules.script(scripts);
        if (script === "")
            return _refused("script");
        return { argv: [shell, "-c", script, "sh", base], refusal: null };
    }

    // The file as the shell read it (inForce's answer) → its sha256 or "absent", or "" when
    // it was not read
    function _currentOf(current) {
        if (current?.state === "text" && isHash(current.sha256))
            return current.sha256;
        return current?.state === "absent" ? "absent" : "";
    }

    // The root step that writes `request.text` as the kind's file: `request` { kind, text,
    // current (inForce's answer for the file as read), replace (true: the user was told the
    // file is not the shell's) }; `scripts` the texts of scriptFiles as read. → { argv
    // ([shell, "-c", script, "sh", base, "write", kind, sha256, current, text]), expected (for
    // reply), refusal (null or { code, text }) }
    function writeArgv(shell, request, base, live, scripts) {
        const kind = request?.kind;
        const start = _start(shell, kind, base, live, scripts);
        if (start.refusal !== null)
            return start;
        if (!validText(request?.text))
            return _refused("text");
        const current = _currentOf(request?.current);
        if (current === "")
            return _refused("unread");
        const want = PamEditRules.sha256(request.text);
        if (current === want)
            return _refused("unchanged");
        if (current !== "absent" && request.current.ours !== true && request?.replace !== true)
            return _refused("other");
        return {
            argv: start.argv.concat(["write", kind, want, current, request.text]),
            expected: { mode: "write", kind, sha256: want, before: current, after: want },
            refusal: null
        };
    }

    // The root step that removes the kind's file: `request` { kind, current, replace } as
    // writeArgv's. → as writeArgv
    function removeArgv(shell, request, base, live, scripts) {
        const kind = request?.kind;
        const start = _start(shell, kind, base, live, scripts);
        if (start.refusal !== null)
            return start;
        const current = _currentOf(request?.current);
        if (current === "")
            return _refused("unread");
        if (current === "absent")
            return _refused("unchanged");
        if (request.current.ours !== true && request?.replace !== true)
            return _refused("other");
        return {
            argv: start.argv.concat(["remove", kind, current]),
            expected: { mode: "remove", kind, sha256: "absent", before: current, after: "absent" },
            refusal: null
        };
    }

    // The root step that puts a backup back: `request` { kind, from (the outcome of the run
    // being undone: its backup and the sha256 it left in force) }. → as writeArgv
    function undoArgv(shell, request, base, live, scripts) {
        const kind = request?.kind;
        const start = _start(shell, kind, base, live, scripts);
        if (start.refusal !== null)
            return start;
        const from = request?.from;
        if (from === null || typeof from !== "object" || from.ok !== true || from.kind !== kind)
            return _refused("noUndo");
        if (!validBackup(kind, from.backup))
            return _refused("backupName");
        const current = from.sha256;
        if (current !== "absent" && !isHash(current))
            return _refused("unread");
        return {
            argv: start.argv.concat(["undo", kind, from.backup, current]),
            expected: { mode: "undo", kind, sha256: "", before: current, after: "" },
            refusal: null
        };
    }

    // The root step's reply (PrivilegedRules' result) for what writeArgv / removeArgv /
    // undoArgv expected → { ok, quiet, mode, kind, sha256 (in force now; "absent" for no
    // file), backup (the backup made), refused (the root step's code), error, file ("done"
    // when ok; otherwise "" here — EtcFiles reads the file again and sets afterFailure's
    // answer) }. ok only when its last line, on stdout or stderr, says it did what was asked,
    // for that kind, with the expected hash.
    function reply(result, expected) {
        const outcome = { ok: false, quiet: false, mode: String(expected?.mode ?? ""), kind: String(expected?.kind ?? ""), sha256: "", backup: "",
                          refused: "", error: "", file: "" };
        const word = { write: "written", remove: "removed", undo: "restored" }[expected?.mode] ?? "";
        const lastOf = text => String(text ?? "").trim().split("\n").pop().trim();
        const done = line => {
            const said = /^(written|removed|restored) (\S+) ([0-9a-f]{64}|absent) (\S+)$/.exec(line);
            return said !== null && word !== "" && said[1] === word && said[2] === outcome.kind && validBackup(said[2], said[4])
                && (expected.sha256 === "" || said[3] === expected.sha256) ? said : null;
        };
        // The line comes after the change only, so it counts whatever the exit
        const said = done(lastOf(result?.stdout)) ?? done(lastOf(result?.stderr));
        if (said !== null)
            return Object.assign(outcome, { ok: true, sha256: said[3], backup: said[4], file: "done" });
        return Object.assign(outcome, RootScriptRules.failure(result, texts));
    }

    // What a run that did not say it was done left, the file read again afterwards (inForce's
    // answer) → "unchanged", "done" (what the run was to leave), "other" or "unknown" (not read)
    function afterFailure(current, expected) {
        const found = _currentOf(current);
        if (found === "")
            return "unknown";
        if (found === expected?.before)
            return "unchanged";
        if ((expected?.after ?? "") !== "" && found === expected.after)
            return "done";
        return "other";
    }
}
