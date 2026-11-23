pragma Singleton

import Quickshell
import QtQuick

// Writing a PAM file on Arch, and undoing it (tests/PamApplyRulesTest.qml): the one root
// step that follows a passed trial (PamTrialRules), and its reply. One service per run.
//
// The root step is scripts/root/pam-apply.sh after replace-lib.sh and replace-file.sh
// (`scriptFiles`, the second shared with EtcFiles' root step), files in
// the shell's tree that the shell reads and hands as text to the system's /bin/sh through its
// runs as administrator (PrivilegedRuns.startShell): never run by path, every run asks the
// password. Its places (the PAM folder, the vendor folder, the backups) are fixed in the file,
// under the folder its first argument names — "" for the system, the only one it takes as
// root —; its other arguments are checked inside it — the service from a fixed list, hashes
// as 64 hex digits, included files as names (no path), a backup by its exact pattern. It
// refuses before changing anything when:
// - the bytes it would write are not the ones the trial passed (sha256 of the written temp
//   file against the candidate's, before the rename);
// - the service's file changed since the shell read it (its sha256, or that there was none);
// - a file the rules include changed since the trial (each name looked up as libpam would:
//   the PAM folder, then the vendor folder; its sha256 against the trial's copy);
// - for a removal, the vendor file is not the text the trial passed;
// - the service's file is a link, or a folder is; a folder it writes in (the PAM folder,
//   the backups and the folder holding them) is not root's or others may write in it;
// - another run holds the backups' lock (flock, never waited for).
// It writes the new file beside the old one in the PAM folder (mode 0644) and checks it,
// copies the current file to the backups (`<service>.<UTC time>`, `.absent` when there was
// none; every backup kept), renames the new file into place, and prints what is in force —
// on stderr as well, which the shell still gets when stdout is gone. Each file is flushed to
// disk before it is renamed or linked, and the folder after.
//
// What is left to the user: a file the rules include by absolute path outside the PAM
// folders cannot be looked up by name as root, so rules that include one are not written.
// Pure: texts and states are handed in, nothing is read or written.
Singleton {
    id: root

    // Where the files are on Arch; a suite's stand-in runs use folders of its own
    readonly property var livePaths: ({
        system: "/etc/pam.d",
        vendor: "/usr/lib/pam.d",
        backups: "/var/lib/h2s-shell/pam-backup"
    })

    // The root step's files in scripts/root/, joined in this order (RootScriptRules.script)
    readonly property var scriptFiles: ["replace-lib.sh", "replace-file.sh", "pam-apply.sh"]

    // Why a run was not started, or what the root step refused, by code
    readonly property var texts: ({
        // Before the run
        service: "Unknown service.",
        built: "The new rules could not be made.",
        unchanged: "Nothing to change.",
        unread: "The file could not be read.",
        notTried: "The new rules were not tried: try them first.",
        places: "The trial read other folders than the ones written.",
        outside: "The new rules include a file outside the PAM folders: it cannot be checked before the write.",
        backupName: "Not a backup of this service.",
        paths: "Not a place the shell writes PAM files to.",
        busy: "A change is already being saved.",
        script: "The shell's script for this could not be read.",
        // By the root step
        arguments: "The request was not valid.",
        system: "The PAM folder is not there.",
        owner: "A folder written in is not root's alone: nothing changed.",
        lock: "The change could not be kept to one at a time: nothing changed.",
        link: "The file is a link: not changed.",
        changed: "The file changed since it was read: read it again.",
        unreadable: "The file could not be read.",
        included: "A file the rules include changed since the trial: try again.",
        vendor: "polkit's own file changed since the trial: try again.",
        backup: "The backup could not be made: nothing changed.",
        nobackup: "That backup is not there.",
        write: "The new file could not be written: nothing changed.",
        hash: "The file written was not the one tried: nothing changed."
    })

    // A backup's name: the service, the UTC time, a counter for a second one in the same
    // second, `.absent` when the service had no file
    readonly property string _stampPattern: "[0-9]{8}T[0-9]{6}Z(-[1-9])?(\\.absent)?"

    function refusal(code) {
        return { code, text: texts[code] ?? texts.arguments };
    }

    function _refused(code) {
        return { argv: null, expected: null, refusal: refusal(code) };
    }

    function isHash(value) {
        return typeof value === "string" && /^[0-9a-f]{64}$/.test(value);
    }

    // Whether `name` is a backup of `service` as the root step names them
    function validBackup(service, name) {
        return PamRuleRules.services.includes(service) && typeof name === "string"
            && new RegExp("^" + service.replace(/[.-]/g, "\\$&") + "\\." + _stampPattern + "$").test(name);
    }

    // A backup's full path, for the page: a repair from a console is one `cp` (or an `rm`
    // for a backup of no file)
    function backupPath(paths, name) {
        return String(paths?.backups ?? "") + "/" + String(name ?? "");
    }

    // Whether the places may be written: "" when they may, else a refusal code. `live`: the
    // run goes to the system's pkexec, so only livePaths; a stand-in's run never touches
    // /etc, /usr or /var.
    readonly property var _placeNames: ["system", "vendor", "backups"]

    function pathsRefusal(paths, live) {
        return RootScriptRules.placesRefusal(paths, _placeNames, livePaths, live);
    }

    // The run's first words: the shell, the script, its base (the folder the places are
    // under) → { argv, refusal: null } or a refusal
    function _start(shell, paths, live, scripts) {
        if (typeof shell !== "string" || !shell.startsWith("/"))
            return _refused("arguments");
        const pathProblem = pathsRefusal(paths, live);
        if (pathProblem !== "")
            return _refused(pathProblem);
        const script = RootScriptRules.script(scripts);
        if (script === "")
            return _refused("script");
        return { argv: [shell, "-c", script, "sh", RootScriptRules.base(paths, _placeNames, livePaths)], refusal: null };
    }

    // What the trial must have passed for a build (PamEditRules.build's answer): its text,
    // or for a removal of our polkit-1 the vendor file that is then in force. → { text,
    // remove } or null when the build made nothing
    function candidate(built, vendorText) {
        if (built?.ok !== true)
            return null;
        if (built.remove === true)
            return typeof vendorText === "string" ? { text: vendorText, remove: true } : null;
        return typeof built.text === "string" ? { text: built.text, remove: false } : null;
    }

    // What the prompt says the run is for
    function what(mode, service) {
        const target = service === "sudo" ? "sudo" : "administrator prompts";
        return mode === "undo" ? "Undo the change to the sign-in rules for " + target
            : "Change the sign-in rules for " + target;
    }

    // The root step for Apply. `request`: { service, built (PamEditRules.build's answer),
    // currentText (the service's file the build was made from; polkit: null when there was
    // none), vendorText (polkit's vendor file), trial (PamTrialRules' state) }. The trial
    // must have passed for this exact candidate, or — one trial for a shared list — for the
    // other service's candidate whose auth lines are the same (PamTrialRules.sameAuthLines,
    // the files this one includes all among those the trial read). `scripts`: the texts of
    // scriptFiles as read. → { argv ([shell, "-c", script, "sh", base, words…]), expected (for
    // applyReply), refusal (null or { code, text }) }
    function applyArgv(shell, request, paths, live, scripts) {
        const start = _start(shell, paths, live, scripts);
        if (start.refusal !== null)
            return start;
        const service = String(request?.service ?? "");
        if (!PamRuleRules.services.includes(service))
            return _refused("service");
        const chosen = candidate(request?.built, request?.vendorText);
        if (chosen === null)
            return _refused("built");
        if (chosen.remove && service !== "polkit-1")
            return _refused("built");
        const currentText = request?.currentText;
        let current;
        if (typeof currentText === "string")
            current = PamEditRules.sha256(currentText);
        else if (service === "polkit-1" && (currentText === null || currentText === undefined))
            current = "absent";
        else
            return _refused("unread");
        const want = PamEditRules.sha256(chosen.text);
        if (chosen.remove ? current === "absent" : current === want)
            return _refused("unchanged");
        // The trial
        const trial = request?.trial;
        if (trial?.phase !== "passed" || typeof trial.candidate !== "string")
            return _refused("notTried");
        const directories = Array.isArray(trial.directories) ? trial.directories.map(dir => String(dir).replace(/\/+$/, "")) : [];
        if (directories.length !== 2 || directories[0] !== paths.system || directories[1] !== paths.vendor)
            return _refused("places");
        const step = PamTrialRules.stagingStep(service, chosen.text, trial.answers ?? {}, directories, false);
        if (step.refusal !== null || step.pending.length > 0)
            return _refused("notTried");
        // The same service: this exact text. The other one: the same auth lines
        if (trial.service === service ? trial.candidate !== chosen.text : !PamTrialRules.sameAuthLines(trial.stack, step.stack))
            return _refused("notTried");
        // Every file the stack read must be one the root step can look up again: the
        // service's own (the candidate) or an included name
        const answers = trial.answers ?? {};
        const found = step.files.slice(1).map(file => PamStackRules.candidates(file.name, directories)
                                                   .find(path => typeof answers[path]?.text === "string"));
        const own = directories[0] + "/" + service;
        if (step.stack.files.some(path => path !== own && !found.includes(path)))
            return _refused("outside");
        const includes = [];
        for (const file of step.files.slice(1))
            includes.push(file.name, PamEditRules.sha256(file.text));
        const words = chosen.remove ? ["remove", service, want, current].concat(includes)
            : ["write", service, want, current, chosen.text].concat(includes);
        return {
            argv: start.argv.concat(words),
            expected: { mode: chosen.remove ? "remove" : "write", service, sha256: want, before: current, after: chosen.remove ? "absent" : want },
            refusal: null
        };
    }

    // The root step for Undo: `request` { service, backup (the name the apply's reply gave),
    // currentSha256 (what that apply left in force: its reply's sha256, "absent" after a
    // removal) }. No trial: the backup is the state that was in force. → as applyArgv
    function undoArgv(shell, request, paths, live, scripts) {
        const start = _start(shell, paths, live, scripts);
        if (start.refusal !== null)
            return start;
        const service = String(request?.service ?? "");
        if (!PamRuleRules.services.includes(service))
            return _refused("service");
        if (!validBackup(service, request?.backup))
            return _refused("backupName");
        const current = request?.currentSha256;
        if (current !== "absent" && !isHash(current))
            return _refused("unread");
        return {
            argv: start.argv.concat(["undo", service, request.backup, current]),
            expected: { mode: "undo", service, sha256: "", before: current, after: "" },
            refusal: null
        };
    }

    // The root step's reply (PrivilegedRules' result: ok, code, stdout, stderr, dismissed,
    // refused, cancelled, blocked, error) for what applyArgv / undoArgv expected → { ok,
    // quiet (a prompt dismissed, a run refused or cancelled: said elsewhere, or the user's
    // choice), kind (written / removed / restored), service, sha256 (what is in force in the
    // PAM folder now; "absent" for no file there), backup (the backup made), refused (the
    // root step's code), error (for the log and the page), file ("done" when ok; otherwise
    // "" here — PamApply reads the file again and sets afterFailure's answer) }. ok only when
    // its last line, on stdout or stderr, says it did what was asked, for that service, with
    // the expected hash.
    function applyReply(result, expected) {
        const outcome = { ok: false, quiet: false, kind: "", service: String(expected?.service ?? ""), sha256: "", backup: "", refused: "", error: "", file: "" };
        const words = { write: "written", remove: "removed", undo: "restored" };
        const kind = words[expected?.mode] ?? "";
        const lastOf = text => String(text ?? "").trim().split("\n").pop().trim();
        const done = line => {
            const said = /^(written|removed|restored) (sudo|polkit-1) ([0-9a-f]{64}|absent) (\S+)$/.exec(line);
            return said !== null && kind !== "" && said[1] === kind && said[2] === outcome.service && validBackup(said[2], said[4])
                && (expected.sha256 === "" || said[3] === expected.sha256) && (kind !== "written" || said[3] !== "absent") ? said : null;
        };
        // The line comes after the change only, so it counts whatever the exit: a stdout
        // closed under it ends the run with an error after the change was made
        const said = done(lastOf(result?.stdout)) ?? done(lastOf(result?.stderr));
        if (said !== null) {
            return Object.assign(outcome, {
                ok: true, kind, sha256: kind === "removed" ? "absent" : said[3], backup: said[4], file: "done"
            });
        }
        return Object.assign(outcome, RootScriptRules.failure(result, texts));
    }

    // What a run that did not say it was done left in the PAM folder, the service's file read
    // again afterwards (`answer`: PamStackRules.filesAnswer's for its path: { text },
    // { absent }, { unreadable }, or nothing) against what applyArgv / undoArgv expected →
    // "unchanged" (as before the run), "done" (what the run was to leave), "other" (neither:
    // read it again and show it) or "unknown" (not read)
    function afterFailure(answer, expected) {
        let found;
        if (typeof answer?.text === "string")
            found = PamEditRules.sha256(answer.text);
        else if (answer?.absent === true)
            found = "absent";
        else
            return "unknown";
        if (found === expected?.before)
            return "unchanged";
        if ((expected?.after ?? "") !== "" && found === expected.after)
            return "done";
        return "other";
    }

    // Whether the service's file in the PAM folder, read again (`text`: null / undefined
    // when there is none), is what the run left in force
    function inForce(text, outcome) {
        if (outcome?.ok !== true)
            return false;
        if (outcome.sha256 === "absent")
            return text === null || text === undefined;
        return typeof text === "string" && PamEditRules.sha256(text) === outcome.sha256;
    }
}
