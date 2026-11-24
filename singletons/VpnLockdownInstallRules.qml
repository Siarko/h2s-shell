pragma Singleton

import Quickshell
import QtQuick
import qs.singletons.network

// Installing the VPN blocking's script and its polkit rule on Arch, removing them and undoing
// either (tests/VpnLockdownInstallRulesTest.qml): which files change, the one root step's words
// and its reply. The files are the script (scripts/h2s-vpn-lockdown as the shell reads it, put
// where root owns it) and the polkit rule letting this user run it without a password, in
// polkit's rules folder that anyone may read — so the shell sees what is there before it asks.
//
// The root step is scripts/root/vpn-lockdown-install.sh after replace-lib.sh (`scriptFiles`),
// files in the shell's tree that the shell reads and hands as text to the system's /bin/sh
// through its runs as administrator (PrivilegedRuns.startShell): never run by path. Its places
// are fixed in the file, under the folder its first argument names — "" for the system, the
// only one it takes as root —; it builds the rule from its own template (only the user is
// handed in, by a fixed pattern) naming the script's fixed place, and writes the script only
// from a text that starts as the shell's script does. It refuses before changing anything when
// either file changed since the shell read it (its sha256, or that there was none), is a link,
// a file it built has not the sha256 the shell computed, a folder it writes in is missing, a
// link, not the owner's or writable by others, or another run holds the backups' lock. Both
// files as they were are kept under one stamp, and Undo of a stamp puts them back while both
// are what that run left.
//
// Never overriding what the user set: a script or rule at those places not written by the
// shell (`state` "changed") is replaced only when the request names it (`replace`), after the
// page showed it and asked; Remove leaves such a file alone. Pure.
Singleton {
    id: root

    // Where the files are on Arch; a suite's stand-in runs use the same places under a scratch
    // folder
    readonly property var livePaths: ({
        script: "/usr/local/libexec/h2s-vpn-lockdown",
        rule: "/usr/share/polkit-1/rules.d/49-h2s-vpn-lockdown.rules",
        backups: "/var/lib/h2s-shell/vpn-lockdown-backup"
    })
    readonly property var _placeNames: ["script", "rule", "backups"]

    // The root step's files in scripts/root/, joined in this order (RootScriptRules.script)
    readonly property var scriptFiles: ["replace-lib.sh", "vpn-lockdown-install.sh"]

    // The first line of the rule the shell writes, and how the shell's script starts (the root
    // step checks the same)
    readonly property string ruleMarker: "// Written by h2s-shell (Settings > System > Network > VPN > Password-free blocking)."
    readonly property string scriptStart: "#!/bin/sh\n# h2s-vpn-lockdown "
    readonly property int maxBytes: 65536

    // Why a run was not started, or what the root step refused, by code
    readonly property var texts: ({
        // Before the run
        facts: "The rule could not be made for this user.",
        script: "The shell's script for this could not be read.",
        unread: "The files could not be read.",
        changed: "Not written by the shell: replace it to go on.",
        unchanged: "Nothing to change.",
        backupName: "Not a backup of these files.",
        paths: "Not a place the shell installs the blocking to.",
        busy: "A change is already being saved.",
        // By the root step
        arguments: "The request was not valid.",
        system: "A folder it goes into is not there.",
        owner: "A folder written in is not root's alone: nothing changed.",
        lock: "The change could not be kept to one at a time: nothing changed.",
        link: "The file is a link: not changed.",
        unreadable: "The file could not be read.",
        backup: "The backup could not be made: nothing changed.",
        nobackup: "That backup is not there.",
        write: "The new file could not be written: nothing changed.",
        partial: "Only one of the two files was changed: look again.",
        start: "The run could not be started.",
        hash: "The file written was not the one made: nothing changed."
    })

    function refusal(code) {
        return { code, text: texts[code] ?? texts.arguments };
    }

    function _refused(code) {
        return { argv: null, expected: null, refusal: refusal(code) };
    }

    // What the prompt says the run is for
    function what(mode) {
        return mode === "remove" ? "Remove the VPN blocking's script"
            : mode === "undo" ? "Undo the change to the VPN blocking's script"
            : "Install the VPN blocking's script";
    }

    // A user name the root step takes for the rule
    function validUser(user) {
        return typeof user === "string" && /^[A-Za-z0-9_][A-Za-z0-9_-]{0,31}$/.test(user);
    }

    // The rule the root step writes for `user`, naming the script at `path`
    function ruleText(user, path) {
        return validUser(user) ? VpnLockdownRules.lockdownPolkitRule(user, ['"' + path + '"']) : "";
    }

    // A script text the root step takes: the shell's script, within the size
    function validScript(text) {
        return typeof text === "string" && text.startsWith(scriptStart) && text.length <= maxBytes && /\nVERSION=[0-9]+\n/.test(text);
    }

    // A file as read (a text; undefined: none; null or anything else: not read) against what
    // the shell would write there → "absent", "ours" (exactly that), "older" (the shell's, but
    // another version or user), "changed" (not the shell's) or "unknown"
    function state(text, want, mark) {
        if (text === undefined)
            return "absent";
        if (typeof text !== "string")
            return "unknown";
        if (text === want)
            return "ours";
        return text.startsWith(mark) ? "older" : "changed";
    }

    // The script's and the rule's states from the files as read: `request` { user, script (the
    // shell's script text), current { script, rule } } → { script, rule }
    function states(request, paths) {
        const current = request?.current ?? {};
        return {
            script: state(current.script, request?.script, scriptStart),
            rule: state(current.rule, ruleText(request?.user, String(paths?.script ?? "")), ruleMarker + "\n")
        };
    }

    // What the page offers for the files' states (`states`' answer), each label with its
    // effect: { install: null (nothing to install, or the files not read) or { label, asks
    // (a question first: a file not written by the shell is replaced), replace (what
    // installArgv is to replace) }, remove (the shell's script or rule is there) }
    function offer(found) {
        const script = found?.script, rule = found?.rule;
        const ours = value => value === "ours" || value === "older";
        const remove = ours(script) || ours(rule);
        if (![script, rule].every(value => ["absent", "ours", "older", "changed"].includes(value)))
            return { install: null, remove: false };
        if (script === "changed" || rule === "changed")
            return { install: { label: "Replace…", asks: true, replace: { script: script === "changed", rule: rule === "changed" } }, remove };
        if (script === "ours" && rule === "ours")
            return { install: null, remove };
        return { install: { label: script === "absent" && rule === "absent" ? "Install…" : "Install again…", asks: false, replace: {} }, remove };
    }

    // Whether the places may be written: "" when they may, else a refusal code
    function pathsRefusal(paths, live) {
        return RootScriptRules.placesRefusal(paths, _placeNames, livePaths, live);
    }

    function _currentOf(text) {
        if (typeof text === "string")
            return PamEditRules.sha256(text);
        return text === undefined ? "absent" : null;
    }

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

    // Which files a request may replace although not written by the shell: { script, rule },
    // true only where said so in so many words
    function replacing(replace) {
        return { script: replace?.script === true, rule: replace?.rule === true };
    }

    function _plan(start, script, rule, user, scriptText) {
        const want = part => part.op === "write" ? PamEditRules.sha256(part.text) : "-";
        const words = ["apply", script.op, script.current, want(script), rule.op, rule.current, want(rule),
                       rule.op === "write" ? user : "-", script.op === "write" ? scriptText : "-"];
        const after = part => part.op === "write" ? PamEditRules.sha256(part.text) : part.op === "remove" ? "absent" : part.current;
        return {
            argv: start.argv.concat(words),
            expected: { mode: "apply", before: { script: script.current, rule: rule.current }, after: { script: after(script), rule: after(rule) } },
            refusal: null
        };
    }

    // The root step for Install (and Install again). `request` { user, script (the shell's
    // script as read now), current { script, rule } (each file's text as read: undefined for
    // none, null when it could not be read), replace { script, rule } }. Each file is written
    // unless it is already the shell's as it would write it; one not written by the shell
    // only with its `replace`. `scripts`: the texts of scriptFiles as read. → { argv ([shell,
    // "-c", script, "sh", base, words…]), expected (for reply), refusal (null or { code, text }) }
    function installArgv(shell, request, paths, live, scripts) {
        const start = _start(shell, paths, live, scripts);
        if (start.refusal !== null)
            return start;
        if (!validUser(request?.user))
            return _refused("facts");
        if (!validScript(request?.script))
            return _refused("script");
        const found = states(request, paths);
        if (found.script === "unknown" || found.rule === "unknown")
            return _refused("unread");
        const replace = replacing(request?.replace);
        if ((found.script === "changed" && !replace.script) || (found.rule === "changed" && !replace.rule))
            return _refused("changed");
        const current = request.current;
        const script = { op: found.script === "ours" ? "keep" : "write", current: _currentOf(current.script), text: request.script };
        const rule = { op: found.rule === "ours" ? "keep" : "write", current: _currentOf(current.rule), text: ruleText(request.user, paths.script) };
        if (script.op === "keep" && rule.op === "keep")
            return _refused("unchanged");
        return _plan(start, script, rule, request.user, request.script);
    }

    // The root step for Remove: `request` as installArgv's (replace not taken). The shell's
    // files go; one not written by the shell stays. → as installArgv
    function removeArgv(shell, request, paths, live, scripts) {
        const start = _start(shell, paths, live, scripts);
        if (start.refusal !== null)
            return start;
        const found = states(request, paths);
        if (found.script === "unknown" || found.rule === "unknown")
            return _refused("unread");
        const ours = value => value === "ours" || value === "older";
        const current = request.current;
        const script = { op: ours(found.script) ? "remove" : "keep", current: _currentOf(current.script), text: "" };
        const rule = { op: ours(found.rule) ? "remove" : "keep", current: _currentOf(current.rule), text: "" };
        if (script.op === "keep" && rule.op === "keep")
            return _refused(found.script === "changed" || found.rule === "changed" ? "changed" : "unchanged");
        return _plan(start, script, rule, "-", "-");
    }

    // A backup stamp as the root step makes them
    function validStamp(stamp) {
        return typeof stamp === "string" && /^[0-9]{8}T[0-9]{6}Z(-[1-9])?$/.test(stamp);
    }

    // The root step for Undo: `request` { stamp, script, rule (what that run left: its reply's
    // sha256 of each, or "absent") } → as installArgv
    function undoArgv(shell, request, paths, live, scripts) {
        const start = _start(shell, paths, live, scripts);
        if (start.refusal !== null)
            return start;
        if (!validStamp(request?.stamp))
            return _refused("backupName");
        const current = value => value === "absent" || PamApplyRules.isHash(value);
        if (!current(request?.script) || !current(request?.rule))
            return _refused("unread");
        return {
            argv: start.argv.concat(["undo", request.stamp, request.script, request.rule]),
            expected: { mode: "undo", before: { script: request.script, rule: request.rule }, after: null },
            refusal: null
        };
    }

    // The root step's reply (PrivilegedRules' result) for what was expected → { ok, quiet,
    // kind ("applied" | "restored"), script, rule (each file's sha256 now, or "absent"), stamp,
    // refused, error, files ("done" when ok; else set from afterFailure by the writer) }. ok
    // only when its last line, on stdout or stderr, says it did what was asked, with the
    // expected hashes.
    function reply(result, expected) {
        const outcome = { ok: false, quiet: false, kind: "", script: "", rule: "", stamp: "", refused: "", error: "", files: "" };
        const kind = { apply: "applied", undo: "restored" }[expected?.mode] ?? "";
        const lastOf = text => String(text ?? "").trim().split("\n").pop().trim();
        const done = line => {
            const said = /^(applied|restored) ([0-9a-f]{64}|absent) ([0-9a-f]{64}|absent) (\S+)$/.exec(line);
            if (said === null || kind === "" || said[1] !== kind || !validStamp(said[4]))
                return null;
            const after = expected.after;
            if (after !== null && (said[2] !== after?.script || said[3] !== after?.rule))
                return null;
            return said;
        };
        const said = done(lastOf(result?.stdout)) ?? done(lastOf(result?.stderr));
        if (said !== null)
            return Object.assign(outcome, { ok: true, kind, script: said[2], rule: said[3], stamp: said[4], files: "done" });
        return Object.assign(outcome, RootScriptRules.failure(result, texts));
    }

    // What a run that did not say it was done left, the two files read again (`answers`
    // { script, rule }: PamStackRules.filesAnswer's each) → "unchanged", "done", "other" or
    // "unknown"
    function afterFailure(answers, expected) {
        const found = {};
        for (const name of ["script", "rule"]) {
            const answer = answers?.[name];
            if (typeof answer?.text === "string")
                found[name] = PamEditRules.sha256(answer.text);
            else if (answer?.absent === true)
                found[name] = "absent";
            else
                return "unknown";
        }
        const same = place => place !== null && typeof place === "object" && found.script === place.script && found.rule === place.rule;
        if (same(expected?.before))
            return "unchanged";
        if (same(expected?.after))
            return "done";
        return "other";
    }
}
