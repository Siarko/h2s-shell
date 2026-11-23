import QtQuick
import qs.singletons

// EtcFilesRules: each kind's file and backups, the texts the shell writes, a file not the
// shell's replaced only through `replace`, the root step's words for write, remove and undo,
// the places a run may write, the reply and what a run that said nothing left
TestCase {
    suiteName: "EtcFilesRules"

    function run() {
        const rules = EtcFilesRules;
        const sha = PamEditRules.sha256;
        const kind = "sleep.hibernateDelay";
        const scripts = ["lib\n", "file\n", "own\n"];
        const scratch = "/run/user/1000/t";
        const text = HibernateRules.dropInText(10800);
        const other = "[Sleep]\nHibernateDelaySec=1h\n";
        const absent = { state: "absent", sha256: "absent" };
        const read = content => rules.inForce({ text: content });
        const code = plan => plan.refusal?.code ?? "";

        // ── The places ──
        assertEqual(JSON.stringify(rules.files), JSON.stringify({ "sleep.hibernateDelay": "/etc/systemd/sleep.conf.d/h2s-shell.conf" }),
                    "the files, one per kind: the hibernation delay's drop-in (fixed in etc-files.sh too)");
        assertEqual(rules.fileOf(kind, "") + " " + rules.fileOf(kind, scratch), "/etc/systemd/sleep.conf.d/h2s-shell.conf " + scratch + "/etc/systemd/sleep.conf.d/h2s-shell.conf",
                    "the file under the system's base and a scratch one");
        assertEqual(rules.backupsOf(kind, ""), "/var/lib/h2s-shell/backup/sleep.hibernateDelay", "its backups: per kind");
        assertEqual(rules.fileOf("pam.rules", "") + rules.backupsOf("x", ""), "", "a kind it does not know: no place");
        assert(!rules.knows("toString") && !rules.knows(undefined), "… nor a name every object has");
        assertEqual(JSON.stringify(rules.scriptFiles), JSON.stringify(["replace-lib.sh", "replace-file.sh", "etc-files.sh"]),
                    "the shared functions, the one-file steps, then its own");
        assertEqual(rules.baseRefusal("", true) + "|" + rules.baseRefusal(scratch, false), "|", "the system's base live, a scratch one for a stand-in");
        assertEqual(rules.baseRefusal(scratch, true) + rules.baseRefusal("", false), "pathspaths", "never the other way round");
        for (const wrong of ["/etc/x", "/usr", "/var/tmp/x", "/run/x'y", "/run/../etc", "run/x", "/run/x/"])
            assertEqual(rules.baseRefusal(wrong, false), "paths", "a stand-in under " + wrong + ": refused");
        assertEqual(rules.baseRefusal("/etcx", false), "", "… /etcx is not /etc");

        // ── The texts ──
        assert(rules.validText(text), "the hibernation drop-in is a text the shell writes");
        assert(!rules.validText(other), "a text without the marker: not");
        assert(!rules.validText(text.slice(0, -1)), "… nor one without its last line break");
        assert(!rules.validText(text + "\u0001\n") && !rules.validText(text + "a\rb\n"), "… nor one with a control character");
        assert(rules.validText(text + "a\tb\n"), "… a tab is one");
        assert(rules.validText(rules.marker + "\n" + "x".repeat(rules.maxBytes - rules.marker.length - 2) + "\n"), "… at maxBytes");
        assert(!rules.validText(rules.marker + "\n" + "x".repeat(rules.maxBytes - rules.marker.length - 1) + "\n"), "… over it: not");
        assert(!rules.validText(rules.marker + "\n" + "é".repeat(rules.maxBytes / 2) + "\n"), "… counted in UTF-8 bytes");
        assertEqual(["~", "\u0080", "\u07ff", "\u0800", "\uffff", "\u{10000}", "\u{10ffff}"].map(character => rules._utf8Length(character)).join(" "), "1 2 2 3 3 4 4",
                    "… each character's UTF-8 length, at every boundary");
        assertEqual(JSON.stringify(read(text)), JSON.stringify({ state: "text", text, sha256: sha(text), ours: true }), "a file read: its text, sha256, the shell's");
        assertEqual(read(other).ours, false, "… a file without the marker: not the shell's");
        assertEqual(JSON.stringify(rules.inForce({ absent: true })), JSON.stringify({ state: "absent", text: null, sha256: "absent", ours: false }), "no file");
        for (const unknown of [{ unreadable: true }, null, undefined, {}])
            assertEqual(JSON.stringify(rules.inForce(unknown)), JSON.stringify({ state: "unknown", text: null, sha256: "", ours: false }),
                        "not read: unknown (" + JSON.stringify(unknown) + ")");

        // ── Write ──
        let plan = rules.writeArgv("/bin/sh", { kind, text, current: absent }, "", true, scripts);
        assertEqual(code(plan), "", "write where there is none: the run's words");
        assertEqual(JSON.stringify(plan.argv), JSON.stringify(["/bin/sh", "-c", "lib\nfile\nown\n", "sh", "", "write", kind, sha(text), "absent", text]),
                    "… the system's shell, the files joined, the base \"\", then write, the kind, the sha256, absent, the text");
        assertEqual(JSON.stringify(plan.expected), JSON.stringify({ mode: "write", kind, sha256: sha(text), before: "absent", after: sha(text) }), "… what it expects");
        assertEqual(rules.writeArgv("/bin/sh", { kind, text, current: absent }, scratch, false, scripts).argv[4], scratch, "… a stand-in's base");
        const older = HibernateRules.dropInText(3600);
        plan = rules.writeArgv("/bin/sh", { kind, text, current: read(older) }, "", true, scripts);
        assertEqual(plan.argv?.[8], sha(older), "over the shell's own file: its sha256 as read");
        assertEqual(code(rules.writeArgv("/bin/sh", { kind, text, current: read(text) }, "", true, scripts)), "unchanged", "the same text: nothing to change");
        assertEqual(code(rules.writeArgv("/bin/sh", { kind, text, current: read(other) }, "", true, scripts)), "other",
                    "over a file the shell did not write: refused, never replaced unasked");
        assertEqual(rules.writeArgv("/bin/sh", { kind, text, current: read(other), replace: true }, "", true, scripts).argv?.[8], sha(other),
                    "… with `replace` (the user told): written over it");
        assertEqual(code(rules.writeArgv("/bin/sh", { kind, text, current: read(other), replace: "yes" }, "", true, scripts)), "other", "… only `replace` true");
        for (const unread of [{ state: "unknown", sha256: "" }, null, undefined, { state: "text", sha256: "x" }])
            assertEqual(code(rules.writeArgv("/bin/sh", { kind, text, current: unread }, "", true, scripts)), "unread", "the file not read: refused (" + JSON.stringify(unread) + ")");
        assertEqual(code(rules.writeArgv("/bin/sh", { kind, text: other, current: absent }, "", true, scripts)), "text", "a text the shell does not write: refused");
        assertEqual(code(rules.writeArgv("/bin/sh", { kind: "pam.rules", text, current: absent }, "", true, scripts)), "kind", "a kind it does not know: refused");
        assertEqual(code(rules.writeArgv("sh", { kind, text, current: absent }, "", true, scripts)), "arguments", "a shell that is not absolute: refused");
        assertEqual(code(rules.writeArgv("/bin/sh", { kind, text, current: absent }, scratch, true, scripts)), "paths", "live, a scratch base: refused");
        assertEqual(code(rules.writeArgv("/bin/sh", { kind, text, current: absent }, "", false, scripts)), "paths", "a stand-in, the system's: refused");
        for (const unreadScripts of [null, [], ["lib\n", ""], ["lib\n", "own"]])
            assertEqual(code(rules.writeArgv("/bin/sh", { kind, text, current: absent }, "", true, unreadScripts)), "script", "a script not read: refused");
        assertEqual(rules.refusal("other").text, "The file was changed outside the shell: not replaced without asking.", "… with plain reasons");
        assertEqual(rules.refusal("nonsense").text, rules.texts.arguments, "an unknown code: the request's reason");

        // ── Remove ──
        plan = rules.removeArgv("/bin/sh", { kind, current: read(text) }, "", true, scripts);
        assertEqual(JSON.stringify(plan.argv?.slice(5)), JSON.stringify(["remove", kind, sha(text)]), "remove the shell's file: its sha256 as read");
        assertEqual(JSON.stringify(plan.expected), JSON.stringify({ mode: "remove", kind, sha256: "absent", before: sha(text), after: "absent" }), "… what it expects");
        assertEqual(code(rules.removeArgv("/bin/sh", { kind, current: absent }, "", true, scripts)), "unchanged", "no file: nothing to remove");
        assertEqual(code(rules.removeArgv("/bin/sh", { kind, current: read(other) }, "", true, scripts)), "other", "a file not the shell's: not removed unasked");
        assertEqual(code(rules.removeArgv("/bin/sh", { kind, current: read(other), replace: true }, "", true, scripts)), "", "… with `replace`: removed");
        assertEqual(code(rules.removeArgv("/bin/sh", { kind, current: null }, "", true, scripts)), "unread", "not read: refused");
        assertEqual(code(rules.removeArgv("/bin/sh", { kind: "pam.rules", current: read(text) }, "", true, scripts)), "kind", "a kind it does not know: refused");
        assertEqual(code(rules.removeArgv("/bin/sh", { kind, current: read(text) }, scratch, true, scripts)), "paths", "… and its places checked");

        // ── Undo ──
        const done = { ok: true, kind, sha256: sha(text), backup: "h2s-shell.conf.20261124T101500Z.absent" };
        plan = rules.undoArgv("/bin/sh", { kind, from: done }, "", true, scripts);
        assertEqual(JSON.stringify(plan.argv?.slice(5)), JSON.stringify(["undo", kind, done.backup, sha(text)]), "undo: the backup and what the change left");
        assertEqual(JSON.stringify(plan.expected), JSON.stringify({ mode: "undo", kind, sha256: "", before: sha(text), after: "" }), "… what it expects");
        assertEqual(rules.undoArgv("/bin/sh", { kind, from: Object.assign({}, done, { sha256: "absent", backup: "h2s-shell.conf.20261124T101500Z-2" }) }, "", true, scripts).argv?.[8],
                    "absent", "… of a removal: absent");
        assertEqual(code(rules.undoArgv("/bin/sh", { kind, from: null }, "", true, scripts)), "noUndo", "nothing done: nothing to undo");
        assertEqual(code(rules.undoArgv("/bin/sh", { kind, from: Object.assign({}, done, { ok: false }) }, "", true, scripts)), "noUndo", "… a change that failed");
        assertEqual(code(rules.undoArgv("/bin/sh", { kind, from: Object.assign({}, done, { kind: "x" }) }, "", true, scripts)), "noUndo", "… another kind's");
        for (const name of ["sudo.20261124T101500Z", "h2s-shell.conf.2026", "h2s-shell.conf.20261124T101500Z-10", "../h2s-shell.conf.20261124T101500Z", "h2s-shellxconf.20261124T101500Z"])
            assertEqual(code(rules.undoArgv("/bin/sh", { kind, from: Object.assign({}, done, { backup: name }) }, "", true, scripts)), "backupName", "not its backup: " + name);
        assertEqual(code(rules.undoArgv("/bin/sh", { kind, from: Object.assign({}, done, { sha256: "x" }) }, "", true, scripts)), "unread", "a state that is no hash: refused");
        assertEqual(code(rules.undoArgv("/bin/sh", { kind, from: done }, scratch, true, scripts)), "paths", "… and its places checked");

        assert(rules.validBackup(kind, "h2s-shell.conf.20261124T101500Z"), "a backup of the kind's file");
        assert(!rules.validBackup("pam.rules", "h2s-shell.conf.20261124T101500Z"), "… not of a kind it does not know");
        assert(!rules.validBackup(kind, 20261124) && !rules.validBackup(kind, null), "… nor a name that is no string");

        // ── The prompt ──
        assertEqual(rules.what("write", kind), "Change the time before hibernating", "the prompt: the change");
        assertEqual(rules.what("undo", kind), "Undo the change to the time before hibernating", "… Undo");
        assertEqual(rules.what("remove", kind), "Go back to the system's time before hibernating", "… removal");

        // ── The reply ──
        const expected = rules.writeArgv("/bin/sh", { kind, text, current: absent }, "", true, scripts).expected;
        const result = (stdout, more) => Object.assign({ ok: true, code: 0, stdout, stderr: "", dismissed: false, refused: false, cancelled: false, blocked: "", error: "" }, more ?? {});
        const line = "written " + kind + " " + sha(text) + " h2s-shell.conf.20261124T101500Z.absent";
        let outcome = rules.reply(result("x\n" + line + "\n"), expected);
        assertEqual(JSON.stringify(outcome), JSON.stringify({ ok: true, quiet: false, mode: "write", kind, sha256: sha(text), backup: "h2s-shell.conf.20261124T101500Z.absent",
                                                             refused: "", error: "", file: "done" }), "its last line: done, what is in force, the backup");
        assertEqual(rules.reply(result("", { ok: false, code: 141, stderr: line + "\n" }), expected).ok, true, "… on stderr, whatever the exit");
        assertEqual(rules.reply(result(line.replace("written", "restored")), expected).ok, false, "another mode's word: not done");
        assertEqual(rules.reply(result(line.replace(sha(text), sha(older))), expected).ok, false, "another hash: not done");
        assertEqual(rules.reply(result(line.replace(kind, "pam.rules")), expected).ok, false, "another kind: not done");
        assertEqual(rules.reply(result(line.replace(".absent", "x")), expected).ok, false, "a backup it does not name so: not done");
        assertEqual(rules.reply(result(line + "\nmore"), expected).ok, false, "not the last line: not done");
        const undone = rules.reply(result("restored " + kind + " absent h2s-shell.conf.20261124T101600Z"), plan.expected);
        assertEqual(undone.ok + " " + undone.sha256, "true absent", "undo: whatever is in force after it");
        const removed = rules.removeArgv("/bin/sh", { kind, current: read(text) }, "", true, scripts).expected;
        assertEqual(rules.reply(result("removed " + kind + " absent h2s-shell.conf.20261124T101600Z"), removed).ok, true, "remove: absent in force");
        assertEqual(rules.reply(result("removed " + kind + " " + sha(text) + " h2s-shell.conf.20261124T101600Z"), removed).ok, false, "… not with a file left");
        outcome = rules.reply(result("", { ok: false, code: 3, stderr: "refused changed\n" }), expected);
        assertEqual(outcome.refused + " | " + outcome.error, "changed | " + rules.texts.changed, "a refusal: its code and reason");
        assertEqual(rules.reply(result("", { ok: false, dismissed: true }), expected).quiet, true, "a prompt dismissed: quiet");

        // ── After a failure ──
        assertEqual(rules.afterFailure(absent, expected), "unchanged", "a run cut short, the file as before: unchanged");
        assertEqual(rules.afterFailure(read(text), expected), "done", "… as the run was to leave it: done");
        assertEqual(rules.afterFailure(read(other), expected), "other", "… neither: other");
        assertEqual(rules.afterFailure(rules.inForce({ unreadable: true }), expected), "unknown", "… not read: unknown");
        assertEqual(rules.afterFailure(read(text), plan.expected), "unchanged", "undo cut short, the file as the change left it: unchanged");
        assertEqual(rules.afterFailure(absent, plan.expected), "other", "… anything else: other (an undo expects no one state)");
    }
}
