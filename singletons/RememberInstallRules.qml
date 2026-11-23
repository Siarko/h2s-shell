pragma Singleton

import Quickshell
import QtQuick

// Installing the remembered administrator authorization on Arch, removing it and undoing
// either (tests/RememberInstallRulesTest.qml): which files change, the one root step's words
// and its reply. The files are polkit's rules file of the shell (RememberRules.rulePath) and,
// only while the setting is longer than the length polkitd has without it, the polkitd.conf
// that sets it (RememberRules.confPath, first in polkitd's order).
//
// The root step is `applyScript`, a fixed script in the shell's code run by the system's
// /bin/sh through the shell's runs as administrator (PrivilegedRuns.startShell): nothing is
// loaded from a file. Its places (the rules folder, the conf folder, the backups, the
// system's systemctl) and the owner the folders must have are written into the script text,
// never handed as arguments; its arguments are checked inside it — each file's operation
// from a fixed list, hashes as 64 hex digits, a backup by its exact stamp. It refuses before
// changing anything when either file changed since the shell read it (its sha256, or that
// there was none), is a link, the bytes it would write are not the ones the shell made, a
// folder it writes in is missing, a link, not the owner's or writable by others, or another
// run holds the backups' lock. It writes each new file beside the old one (mode 0644),
// copies both files as they were to the backups under one stamp (`<file name>.<UTC time>`,
// `.absent` for no file; 0600 in a 0700 folder; every backup kept, no name taken twice),
// renames the new files into place, tells polkitd to read its conf again when the conf
// changed (SIGHUP to polkit.service's main process: polkitd reads polkitd.conf only at its
// start and on SIGHUP; it reads a changed rules file by itself), and prints what is in force
// — on stderr as well, which the shell still gets when stdout is gone. Each file is flushed
// to disk before it is renamed or linked, and the folder after.
//
// Undo puts back the two backups of one stamp, only while both files are what that run left.
// A rules file or a polkitd.conf not written by the shell is replaced or removed only when
// the request says so (`replace`: "Replace…"); otherwise Install leaves such a conf as it is.
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
        systemctl: "/usr/bin/systemctl",
        // Who must own the folders written in (root; a suite's stand-in: the user)
        owner: 0
    })

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

    // The root step's script for these places ("" for places that are not plain absolute
    // paths). Its arguments ($0 is "sh"):
    //   apply <rule op> <rule current> <rule sha256 | -> <rule text>
    //         <conf op> <conf current> <conf sha256 | -> <conf text>
    //   undo  <stamp> <rule current> <conf current>
    // an op: write (the sha256 and text of the new file), remove or keep (`-` and an empty
    // text); a current: the file's sha256 as the shell read it, or `absent`. Its last line on
    // success, on stdout and stderr: `applied|restored <rule sha256 | absent> <conf sha256 |
    // absent> <stamp> <hup | nohup | none>` (polkitd told, telling it failed, the conf
    // unchanged); a refusal: `refused <code>` on stderr, exit 3.
    function applyScript(paths) {
        if (pathsRefusal(paths, false) !== "" && pathsRefusal(paths, true) !== "")
            return "";
        const quoted = RootScriptRules.quoted;
        return RootScriptRules.header
            + "rules=" + quoted(paths.rules) + "; conf=" + quoted(paths.conf) + "; backups=" + quoted(paths.backups)
            + "; systemctl=" + quoted(paths.systemctl) + "; owner=" + paths.owner + "\n"
            + "rule_name=" + quoted(ruleName) + "; conf_name=" + quoted(confName) + "\n"
            + "rule_temporary=; conf_temporary=; backup_temporary=\n"
            + "trap 'for leftover in \"$rule_temporary\" \"$conf_temporary\" \"$backup_temporary\"; do [ -z \"$leftover\" ] || rm -f -- \"$leftover\"; done' EXIT\n"
            + RootScriptRules.functions
            // One file's request: op, current, sha256, text
            + "check_request() {\n"
            + "  case \"$1\" in\n"
            + "  write) is_hash \"$3\" || refuse arguments;;\n"
            + "  remove|keep) [ \"$3\" = - ] && [ -z \"$4\" ] || refuse arguments;;\n"
            + "  *) refuse arguments;;\n"
            + "  esac\n"
            + "  [ \"$2\" = absent ] || is_hash \"$2\" || refuse arguments\n"
            + "  if [ \"$1\" = remove ] && [ \"$2\" = absent ]; then refuse arguments; fi\n"
            + "}\n"
            // A new file beside its target: mode 0644, the bytes checked (against $2 when
            // given), flushed; its hash left in $got
            + "seal() {\n"
            + "  chmod 0644 -- \"$1\" || refuse write\n"
            + "  got=$(hash_of \"$1\") || refuse write\n"
            + "  if [ -n \"$2\" ] && [ \"$got\" != \"$2\" ]; then refuse hash; fi\n"
            + "  sync -- \"$1\" || refuse write\n"
            + "}\n"
            // A stamp no backup of either file has
            + "taken() {\n"
            + "  for name in \"$rule_name\" \"$conf_name\"; do\n"
            + "    for path in \"$backups/$name.$1\" \"$backups/$name.$1.absent\"; do\n"
            + "      if [ -e \"$path\" ] || [ -L \"$path\" ]; then return 0; fi\n"
            + "    done\n"
            + "  done\n"
            + "  return 1\n"
            + "}\n"
            // One file as it is (checked before) into the backups under $stamp; ln fails on a
            // name that is there
            + "backup_one() {\n"
            + "  suffix=\n"
            + "  if [ \"$3\" = absent ]; then suffix=.absent; fi\n"
            + "  backup_temporary=$(mktemp -- \"$backups/.new.XXXXXX\") || refuse backup\n"
            + "  if [ \"$3\" != absent ]; then cat -- \"$1\" > \"$backup_temporary\" || refuse backup; fi\n"
            + "  chmod 0600 -- \"$backup_temporary\" || refuse backup\n"
            + "  sync -- \"$backup_temporary\" || refuse backup\n"
            + "  ln -- \"$backup_temporary\" \"$backups/$2.$stamp$suffix\" 2> /dev/null || refuse backup\n"
            + "  rm -f -- \"$backup_temporary\"; backup_temporary=\n"
            + "}\n"
            // Both files as they are, under one stamp
            + "make_backups() {\n"
            + "  base=$(date -u +%Y%m%dT%H%M%SZ)\n"
            + "  stamp=$base; count=0\n"
            + "  while taken \"$stamp\"; do\n"
            + "    count=$((count + 1)); [ \"$count\" -le 9 ] || refuse backup\n"
            + "    stamp=\"$base-$count\"\n"
            + "  done\n"
            + "  backup_one \"$rule_target\" \"$rule_name\" \"$rule_current\"\n"
            + "  backup_one \"$conf_target\" \"$conf_name\" \"$conf_current\"\n"
            + "  sync -- \"$backups\" || refuse backup\n"
            + "}\n"
            // One file into place: op, the new file, the target, its folder. After the first
            // file changed a failure is no longer "nothing changed"
            + "placed=\n"
            + "put() {\n"
            + "  case \"$1\" in\n"
            + "  write) mv -fT -- \"$2\" \"$3\" || { [ -z \"$placed\" ] || refuse partial; refuse write; };;\n"
            + "  remove) rm -f -- \"$3\" || { [ -z \"$placed\" ] || refuse partial; refuse write; };;\n"
            + "  *) return 0;;\n"
            + "  esac\n"
            + "  placed=1\n"
            + "  sync -- \"$4\" 2> /dev/null || :\n"
            + "}\n"
            + "[ $# -ge 1 ] || refuse arguments\n"
            + "mode=$1; shift\n"
            + "for dir in \"$rules\" \"$conf\"; do\n"
            + "  if [ -L \"$dir\" ] || [ ! -d \"$dir\" ]; then refuse system; fi\n"
            + "  safe_dir \"$dir\"\n"
            + "done\n"
            + "rule_target=$rules/$rule_name; conf_target=$conf/$conf_name\n"
            + "prepare_backups\n"
            + RootScriptRules.lock
            + "case \"$mode\" in\n"
            + "apply)\n"
            + "  [ $# -eq 8 ] || refuse arguments\n"
            + "  rule_op=$1; rule_current=$2; rule_want=$3; rule_text=$4\n"
            + "  conf_op=$5; conf_current=$6; conf_want=$7; conf_text=$8\n"
            + "  check_request \"$rule_op\" \"$rule_current\" \"$rule_want\" \"$rule_text\"\n"
            + "  check_request \"$conf_op\" \"$conf_current\" \"$conf_want\" \"$conf_text\"\n"
            + "  [ \"$rule_op\" != keep ] || [ \"$conf_op\" != keep ] || refuse arguments\n"
            + "  check_current \"$rule_target\" \"$rule_current\"\n"
            + "  check_current \"$conf_target\" \"$conf_current\"\n"
            + "  rule_after=$rule_current; conf_after=$conf_current\n"
            + "  if [ \"$rule_op\" = write ]; then\n"
            + "    rule_temporary=$(mktemp -- \"$rules/.h2s-shell.XXXXXX\") || refuse write\n"
            + "    printf '%s' \"$rule_text\" > \"$rule_temporary\" || refuse write\n"
            + "    seal \"$rule_temporary\" \"$rule_want\"; rule_after=$got\n"
            + "  elif [ \"$rule_op\" = remove ]; then rule_after=absent; fi\n"
            + "  if [ \"$conf_op\" = write ]; then\n"
            + "    conf_temporary=$(mktemp -- \"$conf/.h2s-shell.XXXXXX\") || refuse write\n"
            + "    printf '%s' \"$conf_text\" > \"$conf_temporary\" || refuse write\n"
            + "    seal \"$conf_temporary\" \"$conf_want\"; conf_after=$got\n"
            + "  elif [ \"$conf_op\" = remove ]; then conf_after=absent; fi\n"
            + "  kind=applied;;\n"
            + "undo)\n"
            + "  [ $# -eq 3 ] || refuse arguments\n"
            + "  stamp_given=$1; rule_current=$2; conf_current=$3\n"
            + "  stamp_pattern='[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z'\n"
            + "  case \"$stamp_given\" in $stamp_pattern|$stamp_pattern-[1-9]) ;; *) refuse arguments;; esac\n"
            + "  [ \"$rule_current\" = absent ] || is_hash \"$rule_current\" || refuse arguments\n"
            + "  [ \"$conf_current\" = absent ] || is_hash \"$conf_current\" || refuse arguments\n"
            // Each file's backup of that stamp: a copy, or a record of no file
            + "  for name in \"$rule_name\" \"$conf_name\"; do\n"
            + "    copy=$backups/$name.$stamp_given\n"
            + "    if [ -f \"$copy\" ] && [ ! -L \"$copy\" ]; then :\n"
            + "    elif [ -f \"$copy.absent\" ] && [ ! -L \"$copy.absent\" ]; then :\n"
            + "    else refuse nobackup; fi\n"
            + "  done\n"
            + "  check_current \"$rule_target\" \"$rule_current\"\n"
            + "  check_current \"$conf_target\" \"$conf_current\"\n"
            + "  rule_op=keep; conf_op=keep; rule_after=$rule_current; conf_after=$conf_current\n"
            + "  copy=$backups/$rule_name.$stamp_given\n"
            + "  if [ -f \"$copy\" ] && [ ! -L \"$copy\" ]; then\n"
            + "    rule_temporary=$(mktemp -- \"$rules/.h2s-shell.XXXXXX\") || refuse write\n"
            + "    cat -- \"$copy\" > \"$rule_temporary\" || refuse write\n"
            + "    seal \"$rule_temporary\" ''; rule_after=$got\n"
            + "    if [ \"$got\" != \"$rule_current\" ]; then rule_op=write; fi\n"
            + "  elif [ \"$rule_current\" != absent ]; then rule_op=remove; rule_after=absent; fi\n"
            + "  copy=$backups/$conf_name.$stamp_given\n"
            + "  if [ -f \"$copy\" ] && [ ! -L \"$copy\" ]; then\n"
            + "    conf_temporary=$(mktemp -- \"$conf/.h2s-shell.XXXXXX\") || refuse write\n"
            + "    cat -- \"$copy\" > \"$conf_temporary\" || refuse write\n"
            + "    seal \"$conf_temporary\" ''; conf_after=$got\n"
            + "    if [ \"$got\" != \"$conf_current\" ]; then conf_op=write; fi\n"
            + "  elif [ \"$conf_current\" != absent ]; then conf_op=remove; conf_after=absent; fi\n"
            + "  kind=restored;;\n"
            + "*) refuse arguments;;\n"
            + "esac\n"
            + "make_backups\n"
            + "put \"$rule_op\" \"$rule_temporary\" \"$rule_target\" \"$rules\"\n"
            + "if [ \"$rule_op\" = write ]; then rule_temporary=; fi\n"
            + "put \"$conf_op\" \"$conf_temporary\" \"$conf_target\" \"$conf\"\n"
            + "if [ \"$conf_op\" = write ]; then conf_temporary=; fi\n"
            // polkitd reads its conf only at its start and on SIGHUP
            + "reload=none\n"
            + "if [ \"$conf_op\" != keep ]; then\n"
            + "  if \"$systemctl\" kill -s HUP --kill-whom=main polkit.service >&2; then reload=hup; else reload=nohup; fi\n"
            + "fi\n"
            + "say \"$kind $rule_after $conf_after $stamp $reload\"\n";
    }

    function _currentOf(text) {
        if (typeof text === "string")
            return PamEditRules.sha256(text);
        return text === undefined ? "absent" : null;
    }

    // The words of one file's part: op, current, sha256, text
    function _part(op, current, text) {
        return op === "write" ? ["write", current, PamEditRules.sha256(text), text] : [op, current, "-", ""];
    }

    function _plan(shell, paths, live, rule, conf) {
        const words = ["apply"].concat(_part(rule.op, rule.current, rule.text), _part(conf.op, conf.current, conf.text));
        const after = part => part.op === "write" ? PamEditRules.sha256(part.text) : part.op === "remove" ? "absent" : part.current;
        return {
            argv: [shell, "-c", applyScript(paths), "sh"].concat(words),
            expected: {
                mode: "apply",
                before: { rule: rule.current, conf: conf.current },
                after: { rule: after(rule), conf: after(conf) },
                reload: conf.op !== "keep"
            },
            refusal: null
        };
    }

    // The common checks of install and remove → { refusal code | "", rule: { text, current,
    // state }, conf: { text, current, state } }
    function _read(shell, request, paths, live) {
        const failed = code => ({ refusal: code });
        if (typeof shell !== "string" || !shell.startsWith("/"))
            return failed("arguments");
        const pathProblem = pathsRefusal(paths, live);
        if (pathProblem !== "")
            return failed(pathProblem);
        const facts = Object.assign({}, request?.facts ?? {}, { system: "arch" });
        if (RememberRules.ruleText(facts) === "")
            return failed("facts");
        const confs = request?.confs ?? {};
        const ruleText = request?.rule, confText = confs[RememberRules.confPath];
        // A file not read (null) makes its state unknown
        const state = RememberRules.state({ rule: ruleText, confs }, facts);
        if (state.rule === "unknown" || state.conf === "unknown")
            return failed("unread");
        return {
            refusal: "", facts, confs,
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

    // What the prompt says the run is for
    function what(mode) {
        return mode === "remove" ? "Stop remembering the administrator password"
            : mode === "undo" ? "Undo the change to the remembered administrator password"
            : "Remember the administrator password";
    }

    // The root step for Install (and Install again). `request`: { facts { user, timeout,
    // program } (RememberRules.ruleText's), minutes (the setting), rule (the rules file's
    // text: undefined for none, null when it could not be read), confs (the polkitd.conf
    // files' texts by RememberRules.confPaths, as the reader gives them), replace (true:
    // a file not written by the shell is replaced) }. The rule is written unless it is
    // already the one these facts make; the conf is written when the setting needs one,
    // removed when it is the shell's and not needed, and left alone when not the shell's
    // unless `replace`. → { argv ([shell, "-c", script, "sh", words…]), expected (for
    // reply), refusal (null or { code, text }) }
    function installArgv(shell, request, paths, live) {
        const read = _read(shell, request, paths, live);
        if (read.refusal !== "")
            return _refused(read.refusal);
        const minutes = request?.minutes;
        if (!Number.isInteger(minutes) || minutes < 1 || RememberRules.confText(minutes * 60) === "")
            return _refused("setting");
        const replace = request?.replace === true;
        if (read.rule.state === "changed" && !replace)
            return _refused("changed");
        const ruleWant = RememberRules.ruleText(read.facts);
        const rule = { op: read.rule.text === ruleWant ? "keep" : "write", current: read.rule.current, text: ruleWant };
        const confWant = confFor(minutes, read.confs);
        const conf = { op: "keep", current: read.conf.current, text: confWant };
        if (read.conf.state !== "changed" || replace) {
            if (confWant !== "")
                conf.op = read.conf.text === confWant ? "keep" : "write";
            else
                conf.op = read.conf.current === "absent" ? "keep" : "remove";
        }
        if (rule.op === "keep" && conf.op === "keep")
            return _refused(read.conf.state === "changed" && !replace ? "changed" : "unchanged");
        return _plan(shell, paths, live, rule, conf);
    }

    // The root step for Remove: `request` as installArgv's without minutes. The rule file goes
    // (one not written by the shell only with `replace`), and the conf when it is the
    // shell's; a conf not written by the shell stays. → as installArgv
    function removeArgv(shell, request, paths, live) {
        const read = _read(shell, request, paths, live);
        if (read.refusal !== "")
            return _refused(read.refusal);
        if (read.rule.state === "changed" && request?.replace !== true)
            return _refused("changed");
        const rule = { op: read.rule.current === "absent" ? "keep" : "remove", current: read.rule.current, text: "" };
        const conf = { op: read.conf.state === "ours" ? "remove" : "keep", current: read.conf.current, text: "" };
        if (rule.op === "keep" && conf.op === "keep")
            return _refused("unchanged");
        return _plan(shell, paths, live, rule, conf);
    }

    // The root step for Undo: `request` { stamp (the backup the run's reply gave), rule, conf
    // (what that run left: its reply's sha256 of each, or "absent") }. The root step puts the
    // backups of that stamp back only while both files are still what the run left.
    // → as installArgv
    function undoArgv(shell, request, paths, live) {
        if (typeof shell !== "string" || !shell.startsWith("/"))
            return _refused("arguments");
        const pathProblem = pathsRefusal(paths, live);
        if (pathProblem !== "")
            return _refused(pathProblem);
        if (!validStamp(request?.stamp))
            return _refused("backupName");
        const current = value => value === "absent" || PamApplyRules.isHash(value);
        if (!current(request?.rule) || !current(request?.conf))
            return _refused("unread");
        return {
            argv: [shell, "-c", applyScript(paths), "sh", "undo", request.stamp, request.rule, request.conf],
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
