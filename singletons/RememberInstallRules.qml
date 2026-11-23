pragma Singleton

import Quickshell
import QtQuick

// Installing the remembered administrator authorization on Arch, removing it and undoing
// either (tests/RememberInstallRulesTest.qml): which files change, the one root step's words
// and its reply. The files are polkit's rules file of the shell (RememberRules.rulePath) and,
// only while the setting is longer than the length polkitd has without it, the polkitd.conf
// that sets it (RememberRules.confPath, first in polkitd's order).
//
// The root step is scripts/root/remember-install.sh after replace-lib.sh (`scriptFiles`),
// files in the shell's tree that the shell reads and hands as text to the system's /bin/sh
// through its runs as administrator (PrivilegedRuns.startShell): never run by path. Its places
// (the rules folder, the conf folder, the backups, the system's systemctl) are fixed in the
// file, under the folder its first argument names — "" for the system, the only one it takes
// as root —; its other arguments are checked inside it — each file's operation
// from a fixed list, hashes as 64 hex digits, a backup by its exact stamp, the user and the
// paths the rule names and the conf's seconds by fixed patterns. It builds the rule and the
// conf itself from templates in its text, so a run can write nothing but the shell's own rule
// and conf. It refuses before changing anything when either file changed since the shell read
// it (its sha256, or that there was none), is a link, a file it built does not have the
// sha256 the shell computed for the same facts, a folder it writes in is missing, a link, not
// the owner's or writable by others, or another run holds the backups' lock. It writes each new file beside the old one (mode 0644),
// copies both files as they were to the backups under one stamp (`<file name>.<UTC time>`,
// `.absent` for no file; 0600 in a 0700 folder; every backup kept, no name taken twice),
// renames the new files into place, tells polkitd to read its conf again when the conf
// changed (SIGHUP to polkit.service's main process: polkitd reads polkitd.conf only at its
// start and on SIGHUP; it reads a changed rules file by itself), and prints what is in force
// — on stderr as well, which the shell still gets when stdout is gone. Each file is flushed
// to disk before it is renamed or linked, and the folder after.
//
// Each run records in the backups what it left (`run.<stamp>`); Undo puts back the two
// backups of one stamp only while both files are exactly what that record says.
// A rules file or a polkitd.conf not written by the shell is replaced or removed only when
// the request names that file (`replace`: { rule, conf }, "Replace…"); otherwise Install
// leaves such a conf as it is.
// Pure: texts and states are handed in, nothing is read or written.
Singleton {
    id: root

    readonly property string ruleName: _baseName(RememberRules.rulePath)
    readonly property string confName: _baseName(RememberRules.confPath)

    // Where the files are on Arch; a suite's stand-in runs use folders and a systemctl of its own
    readonly property var livePaths: ({
        rules: _dirName(RememberRules.rulePath),
        conf: _dirName(RememberRules.confPath),
        backups: "/var/lib/h2s-shell/polkit-backup",
        systemctl: "/usr/bin/systemctl"
    })

    // The root step's files in scripts/root/, joined in this order (RootScriptRules.script)
    readonly property var scriptFiles: ["replace-lib.sh", "remember-install.sh"]

    readonly property var _placeNames: ["rules", "conf", "backups", "systemctl"]

    // Why a run was not started, or what the root step refused, by code
    readonly property var texts: ({
        // Before the run
        facts: "The rule could not be made for this system.",
        setting: "The length is not a whole number of minutes.",
        unread: "The files could not be read.",
        changed: "Changed outside the shell: replace it to go on.",
        unchanged: "Nothing to change.",
        backupName: "Not a backup of these files.",
        paths: "Not a place the shell writes polkit files to.",
        busy: "A change is already being saved.",
        script: "The shell's script for this could not be read.",
        // By the root step
        arguments: "The request was not valid.",
        system: "polkit's folders are not there.",
        owner: "A folder written in is not root's alone: nothing changed.",
        lock: "The change could not be kept to one at a time: nothing changed.",
        link: "The file is a link: not changed.",
        unreadable: "The file could not be read.",
        backup: "The backup could not be made: nothing changed.",
        nobackup: "That backup is not there.",
        write: "The new file could not be written: nothing changed.",
        partial: "Only one of the two files was changed: read them again.",
        start: "The run could not be started.",
        hash: "The file written was not the one made: nothing changed."
    })

    function _baseName(path) {
        return path.slice(path.lastIndexOf("/") + 1);
    }

    function _dirName(path) {
        return path.slice(0, path.lastIndexOf("/"));
    }

    function refusal(code) {
        return { code, text: texts[code] ?? texts.arguments };
    }

    function _refused(code) {
        return { argv: null, expected: null, refusal: refusal(code) };
    }

    // A backup stamp as the root step makes them: the UTC time, a counter for a second run in
    // the same second
    function validStamp(stamp) {
        return typeof stamp === "string" && /^[0-9]{8}T[0-9]{6}Z(-[1-9])?$/.test(stamp);
    }

    // A backup's full path, for the page: a repair from a console is one `cp` (or an `rm`
    // for a backup of no file)
    function backupPath(paths, name, stamp, absent) {
        return String(paths?.backups ?? "") + "/" + String(name ?? "") + "." + String(stamp ?? "") + (absent === true ? ".absent" : "");
    }

    // Whether the places may be written: "" when they may, else a refusal code (as
    // PamApplyRules.pathsRefusal)
    function pathsRefusal(paths, live) {
        return RootScriptRules.placesRefusal(paths, _placeNames, livePaths, live);
    }

    // The longest setting, in minutes (the schema's bound): the root step writes no longer
    // polkitd length than this
    readonly property int maxMinutes: SettingsSchema.entry("system.rememberAdminMinutes").max

    // A path the root step takes for the rule: absolute, plain characters, not a folder
    function scriptPath(path) {
        return typeof path === "string" && path.length <= 4096 && /^\/[A-Za-z0-9\/._+-]*$/.test(path) && !path.endsWith("/");
    }

    function _currentOf(text) {
        if (typeof text === "string")
            return PamEditRules.sha256(text);
        return text === undefined ? "absent" : null;
    }

    // `rule` { op, current, text, facts }, `conf` { op, current, text, seconds }: the words
    // carry the facts and the seconds, never the texts; the texts give the sha256s the files
    // the root step builds must have
    function _plan(start, rule, conf) {
        const want = part => part.op === "write" ? PamEditRules.sha256(part.text) : "-";
        const writeRule = rule.op === "write", writeConf = conf.op === "write";
        const words = ["apply", rule.op, rule.current, want(rule), conf.op, conf.current, want(conf),
                       writeRule ? rule.facts.user : "-", writeRule ? rule.facts.timeout : "-", writeRule ? rule.facts.program : "-",
                       writeConf ? String(conf.seconds) : "-"];
        const after = part => part.op === "write" ? PamEditRules.sha256(part.text) : part.op === "remove" ? "absent" : part.current;
        return {
            argv: start.argv.concat(words),
            expected: {
                mode: "apply",
                before: { rule: rule.current, conf: conf.current },
                after: { rule: after(rule), conf: after(conf) },
                reload: conf.op !== "keep"
            },
            refusal: null
        };
    }

    // The run's first words: the shell, the script (`scripts`: the texts of scriptFiles as
    // read), its base (the folder the places are under) → { argv, refusal: null } or a refusal
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

    // The common checks of install and remove → { refusal code | "", start (_start's),
    // rule: { text, current, state }, conf: { text, current, state } }
    function _read(shell, request, paths, live, scripts) {
        const failed = code => ({ refusal: code });
        const start = _start(shell, paths, live, scripts);
        if (start.refusal !== null)
            return failed(start.refusal.code);
        const facts = Object.assign({}, request?.facts ?? {}, { system: "arch" });
        if (RememberRules.ruleText(facts) === "" || !scriptPath(facts.timeout) || !scriptPath(facts.program))
            return failed("facts");
        const confs = request?.confs ?? {};
        const ruleText = request?.rule, confText = confs[RememberRules.confPath];
        // A file not read (null) makes its state unknown
        const state = RememberRules.state({ rule: ruleText, confs }, facts);
        if (state.rule === "unknown" || state.conf === "unknown")
            return failed("unread");
        return {
            refusal: "", start, facts, confs,
            rule: { text: ruleText, current: _currentOf(ruleText), state: state.rule },
            conf: { text: confText, current: _currentOf(confText), state: state.conf }
        };
    }

    // The length polkitd has without the shell's conf: what the other conf files give
    // (RememberRules.expirationSeconds; -1 unknown)
    function vendorSeconds(confs) {
        const others = Object.assign({}, confs ?? {});
        delete others[RememberRules.confPath];
        return RememberRules.expirationSeconds(others).seconds;
    }

    // The conf the setting needs: confText for its length when longer than the vendor
    // length (or that is unknown, -1: the shell's conf, first in polkitd's order, decides
    // then); "" when polkitd's own length is enough
    function confFor(minutes, confs) {
        const seconds = minutes * 60;
        return seconds > vendorSeconds(confs) ? RememberRules.confText(seconds) : "";
    }

    // Which files a request may replace although not written by the shell: { rule, conf },
    // true only where said so in so many words (anything else replaces nothing)
    function replacing(replace) {
        return { rule: replace?.rule === true, conf: replace?.conf === true };
    }

    // What the prompt says the run is for
    function what(mode) {
        return mode === "remove" ? "Stop remembering the administrator password"
            : mode === "undo" ? "Undo the change to the remembered administrator password"
            : "Remember the administrator password";
    }

    // The root step for Install (and Install again). `request`: { facts { user, timeout,
    // program } (RememberRules.ruleText's), minutes (the setting), rule (the rules file's
    // text: undefined for none, null when it could not be read), confs (the polkitd.conf
    // files' texts by RememberRules.confPaths, as the reader gives them), replace ({ rule,
    // conf }: each true replaces that file when not written by the shell — only the files
    // the question showed) }. The rule is written unless it is
    // already the one these facts make; the conf is written when the setting needs one,
    // removed when it is the shell's and not needed, and left alone when not the shell's
    // unless `replace.conf`. `scripts`: the texts of scriptFiles as read. → { argv ([shell,
    // "-c", script, "sh", base, words…]), expected (for reply), refusal (null or { code, text }) }
    function installArgv(shell, request, paths, live, scripts) {
        const read = _read(shell, request, paths, live, scripts);
        if (read.refusal !== "")
            return _refused(read.refusal);
        const minutes = request?.minutes;
        if (!Number.isInteger(minutes) || minutes < 1 || minutes > maxMinutes)
            return _refused("setting");
        const replace = replacing(request?.replace);
        if (read.rule.state === "changed" && !replace.rule)
            return _refused("changed");
        const ruleWant = RememberRules.ruleText(read.facts);
        const rule = { op: read.rule.text === ruleWant ? "keep" : "write", current: read.rule.current, text: ruleWant, facts: read.facts };
        const confWant = confFor(minutes, read.confs);
        const conf = { op: "keep", current: read.conf.current, text: confWant, seconds: minutes * 60 };
        if (read.conf.state !== "changed" || replace.conf) {
            if (confWant !== "")
                conf.op = read.conf.text === confWant ? "keep" : "write";
            else
                conf.op = read.conf.current === "absent" ? "keep" : "remove";
        }
        if (rule.op === "keep" && conf.op === "keep")
            return _refused(read.conf.state === "changed" && !replace.conf ? "changed" : "unchanged");
        return _plan(read.start, rule, conf);
    }

    // The root step for Remove: `request` as installArgv's without minutes. The rule file goes
    // (one not written by the shell only with `replace.rule`), and the conf when it is the
    // shell's; a conf not written by the shell stays. → as installArgv
    function removeArgv(shell, request, paths, live, scripts) {
        const read = _read(shell, request, paths, live, scripts);
        if (read.refusal !== "")
            return _refused(read.refusal);
        if (read.rule.state === "changed" && !replacing(request?.replace).rule)
            return _refused("changed");
        const rule = { op: read.rule.current === "absent" ? "keep" : "remove", current: read.rule.current, text: "" };
        const conf = { op: read.conf.state === "ours" ? "remove" : "keep", current: read.conf.current, text: "" };
        if (rule.op === "keep" && conf.op === "keep")
            return _refused("unchanged");
        return _plan(read.start, rule, conf);
    }

    // The root step for Undo: `request` { stamp (the backup the run's reply gave), rule, conf
    // (what that run left: its reply's sha256 of each, or "absent") }. The root step puts the
    // backups of that stamp back only while both files are what that run recorded it left.
    // → as installArgv
    function undoArgv(shell, request, paths, live, scripts) {
        const start = _start(shell, paths, live, scripts);
        if (start.refusal !== null)
            return start;
        if (!validStamp(request?.stamp))
            return _refused("backupName");
        const current = value => value === "absent" || PamApplyRules.isHash(value);
        if (!current(request?.rule) || !current(request?.conf))
            return _refused("unread");
        return {
            argv: start.argv.concat(["undo", request.stamp, request.rule, request.conf]),
            expected: { mode: "undo", before: { rule: request.rule, conf: request.conf }, after: null },
            refusal: null
        };
    }

    // The root step's reply (PrivilegedRules' result) for what installArgv / removeArgv /
    // undoArgv expected → { ok, quiet (a prompt dismissed, a run refused or cancelled), kind
    // ("applied" | "restored"), rule, conf (the sha256 of each file in force now, or
    // "absent"), stamp (the backups made: what Undo takes), reload ("hup": polkitd told to
    // read its conf; "nohup": the conf changed but telling polkitd failed — it keeps the
    // length it had until it starts again; "none": the conf did not change), refused (the
    // root step's code), error (for the log and the page), files ("done" when ok; otherwise
    // "" here — RememberInstall reads the files again and sets afterFailure's answer) }. ok
    // only when its last line, on stdout or stderr, says it did what was asked, with the
    // expected hashes.
    function reply(result, expected) {
        const outcome = { ok: false, quiet: false, kind: "", rule: "", conf: "", stamp: "", reload: "", refused: "", error: "", files: "" };
        const kind = { apply: "applied", undo: "restored" }[expected?.mode] ?? "";
        const lastOf = text => String(text ?? "").trim().split("\n").pop().trim();
        const done = line => {
            const said = /^(applied|restored) ([0-9a-f]{64}|absent) ([0-9a-f]{64}|absent) (\S+) (hup|nohup|none)$/.exec(line);
            if (said === null || kind === "" || said[1] !== kind || !validStamp(said[4]))
                return null;
            const after = expected.after;
            if (after !== null && (said[2] !== after?.rule || said[3] !== after?.conf))
                return null;
            // A changed conf without a word to polkitd, or a word without a change, is not this run
            if (expected.mode === "apply" && (said[5] === "none") === (expected.reload === true))
                return null;
            return said;
        };
        // The line comes after the change only, so it counts whatever the exit
        const said = done(lastOf(result?.stdout)) ?? done(lastOf(result?.stderr));
        if (said !== null)
            return Object.assign(outcome, { ok: true, kind, rule: said[2], conf: said[3], stamp: said[4], reload: said[5], files: "done" });
        return Object.assign(outcome, RootScriptRules.failure(result, texts));
    }

    // What a run that did not say it was done left, the two files read again afterwards
    // (`answers` { rule, conf }: each PamStackRules.filesAnswer's for its path: { text },
    // { absent }, { unreadable }, or nothing) against what the run expected → "unchanged"
    // (both as before the run), "done" (both as the run was to leave them), "other" (neither:
    // read them again and show them) or "unknown" (not read)
    function afterFailure(answers, expected) {
        const found = {};
        for (const name of ["rule", "conf"]) {
            const answer = answers?.[name];
            if (typeof answer?.text === "string")
                found[name] = PamEditRules.sha256(answer.text);
            else if (answer?.absent === true)
                found[name] = "absent";
            else
                return "unknown";
        }
        const same = state => state !== null && typeof state === "object" && found.rule === state.rule && found.conf === state.conf;
        if (same(expected?.before))
            return "unchanged";
        if (same(expected?.after))
            return "done";
        return "other";
    }
}
