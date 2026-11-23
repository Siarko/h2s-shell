import QtQuick
import qs.singletons

// PamApplyRules: when the root step may run (a passed trial for this exact candidate, or a
// shared list's other service with the same auth lines; the trial's places; every file it
// read one the root step can look up by name), its words (the candidate's hash, the file it
// replaces, the included names and their hashes; a polkit removal checked against the
// vendor file), the places a run may write, Undo's words, backup names, and the reply
TestCase {
    suiteName: "PamApplyRules"

    function run() {
        const apply = PamApplyRules;
        const edit = PamEditRules;
        const live = apply.livePaths;
        const dirs = [live.system, live.vendor];
        const fixed = PamRuleRules.fixedRow();
        const fingerprint = (id, control) => ({ id, method: "fingerprint", control: control ?? "sufficient", details: { timeout: 10, tries: 3 } });
        const password = id => ({ id, method: "password", control: "sufficient", details: { counted: false } });
        const systemAuth = "auth required pam_faillock.so preauth\nauth [success=1 default=bad] pam_unix.so try_first_pass\n"
            + "auth [default=die] pam_faillock.so authfail\nauth optional pam_permit.so\naccount required pam_unix.so\n";
        const archSudo = "#%PAM-1.0\nauth\t\tinclude\t\tsystem-auth\naccount\t\tinclude\t\tsystem-auth\nsession\t\tinclude\t\tsystem-auth\n";
        const vendorPolkit = "#%PAM-1.0\n\nauth       include      system-auth\naccount    include      system-auth\n"
            + "password   include      system-auth\nsession    include      system-auth\n";
        const facts = service => ({ system: "arch", service, fingerprint: "ready", securityKey: "ready", faillockPresent: true,
                                    faillock: { deny: 3, failInterval: 900, unlockTime: 600 },
                                    otherService: [password("o1"), fixed], vendorText: vendorPolkit });
        const answers = { "/etc/pam.d/system-auth": { text: systemAuth } };
        // A trial as PamTrialRules leaves it once PAM let the user in
        const passed = (service, text, read, directories) => {
            const where = directories ?? dirs;
            const step = PamTrialRules.stagingStep(service, text, read ?? answers, where, false);
            return Object.assign(PamTrialRules.initialState(), {
                phase: "passed", trial: 1, service, candidate: text, directories: where, answers: read ?? answers, stack: step.stack
            });
        };
        const code = plan => plan.refusal?.code ?? "";
        // The texts of the root step's files as read (the shared part first)
        const scripts = ["shared\n", "own\n"];

        const sudoBuilt = edit.build(archSudo, [fingerprint("r1"), fixed], facts("sudo"));
        assert(sudoBuilt.ok && typeof sudoBuilt.text === "string", "the sudo fixture builds");
        const sudoTrial = passed("sudo", sudoBuilt.text);
        const sudoRequest = more => Object.assign({ service: "sudo", built: sudoBuilt, currentText: archSudo, trial: sudoTrial }, more ?? {});

        // ── Apply: the words ──
        let plan = apply.applyArgv("/bin/sh", sudoRequest(), live, true, scripts);
        assertEqual(code(plan), "", "a passed trial of this candidate: the run's words");
        assertEqual(JSON.stringify(plan.argv.slice(0, 2).concat(plan.argv.slice(3))), JSON.stringify([
            "/bin/sh", "-c", "sh", "", "write", "sudo", edit.sha256(sudoBuilt.text), edit.sha256(archSudo), sudoBuilt.text,
            "system-auth", edit.sha256(systemAuth)]),
                    "the system's shell, the script, then: the base (\"\": the system's places), write, the service, the candidate's hash, the file's hash, the text, each included name and its hash");
        assertEqual(plan.argv[2], "shared\nown\n", "… the script: the files' texts joined, the shared part first");
        assertEqual(JSON.stringify(apply.scriptFiles), JSON.stringify(["replace-lib.sh", "pam-apply.sh"]), "… the shared functions, then the PAM step");
        for (const unread of [null, [], ["shared\n", ""], ["shared\n", null], ["shared", "own\n"], ["shared\n"].concat([undefined])])
            assertEqual(code(apply.applyArgv("/bin/sh", sudoRequest(), live, true, unread)), "script", "a file not read: refused (" + JSON.stringify(unread) + ")");
        assertEqual(apply.refusal("script").text, "The shell's script for this could not be read.", "… with a plain reason");
        assertEqual(JSON.stringify(plan.expected), JSON.stringify({ mode: "write", service: "sudo", sha256: edit.sha256(sudoBuilt.text),
                                                                    before: edit.sha256(archSudo), after: edit.sha256(sudoBuilt.text) }),
                    "… what the reply must say");
        assert(!plan.argv.slice(4).some(word => word.startsWith("/")), "no path among the arguments");
        assertEqual(plan.argv[4], "", "… the places are the script's own, under \"\"");

        // ── Apply: refused before the run ──
        assertEqual(code(apply.applyArgv("/bin/sh", sudoRequest({ trial: Object.assign({}, sudoTrial, { phase: "failed" }) }), live, true, scripts)), "notTried",
                    "a trial that failed: not written");
        assertEqual(code(apply.applyArgv("/bin/sh", sudoRequest({ trial: Object.assign({}, sudoTrial, { phase: "running" }) }), live, true, scripts)), "notTried",
                    "… one still running");
        assertEqual(code(apply.applyArgv("/bin/sh", sudoRequest({ trial: PamTrialRules.initialState() }), live, true, scripts)), "notTried", "… none");
        assertEqual(code(apply.applyArgv("/bin/sh", sudoRequest({ trial: null }), live, true, scripts)), "notTried", "… no trial at all");
        const otherBuilt = edit.build(archSudo, [fingerprint("r1", "required"), fixed], facts("sudo"));
        assertEqual(code(apply.applyArgv("/bin/sh", sudoRequest({ built: otherBuilt }), live, true, scripts)), "notTried",
                    "the trial passed for another text: not written");
        assertEqual(code(apply.applyArgv("/bin/sh", sudoRequest({ trial: passed("sudo", sudoBuilt.text + "#\n") }), live, true, scripts)), "notTried",
                    "… even one comment apart");
        assertEqual(code(apply.applyArgv("/bin/sh", sudoRequest({ trial: passed("sudo", sudoBuilt.text, answers, ["/etc/pam.d", "/elsewhere"]) }), live, true, scripts)),
                    "places", "a trial that read other folders than the ones written");
        assertEqual(code(apply.applyArgv("/bin/sh", sudoRequest({ trial: Object.assign({}, sudoTrial, { directories: dirs.concat(["/third"]) }) }), live, true, scripts)),
                    "places", "… or a third folder");
        assertEqual(code(apply.applyArgv("/bin/sh", sudoRequest({ trial: Object.assign({}, sudoTrial, { answers: {} }) }), live, true, scripts)), "notTried",
                    "a trial without the files it included: not known what it ran");
        assertEqual(code(apply.applyArgv("/bin/sh", sudoRequest({ built: { ok: false, text: null, remove: false } }), live, true, scripts)), "built",
                    "a build that was refused");
        assertEqual(code(apply.applyArgv("/bin/sh", sudoRequest({ service: "login" }), live, true, scripts)), "service", "a service the shell never writes");
        assertEqual(code(apply.applyArgv("/bin/sh", sudoRequest({ currentText: null }), live, true, scripts)), "unread", "sudo's file not read");
        assertEqual(code(apply.applyArgv("/bin/sh", sudoRequest({ currentText: sudoBuilt.text }), live, true, scripts)), "unchanged",
                    "the file is already the candidate: nothing to do");
        assertEqual(code(apply.applyArgv("sh", sudoRequest(), live, true, scripts)), "arguments", "a shell that is not an absolute path");

        // Absolute includes: read where they are, so not looked up by name as root
        const absoluteText = sudoBuilt.text.replace("auth\t\tinclude\t\tsystem-auth", "auth include /opt/pam/extra");
        const absoluteAnswers = Object.assign({ "/opt/pam/extra": { text: "auth required pam_permit.so\n" } }, answers);
        assertEqual(code(apply.applyArgv("/bin/sh", sudoRequest({ built: { ok: true, text: absoluteText, remove: false },
                                                                trial: passed("sudo", absoluteText, absoluteAnswers) }), live, true, scripts)),
                    "outside", "rules that include a file by absolute path: not written, said why");
        const nestedText = sudoBuilt.text.replace("auth\t\tinclude\t\tsystem-auth", "auth include system-login");
        const nestedAnswers = Object.assign({ "/etc/pam.d/system-login": { text: "auth include system-auth\n" } }, answers);
        plan = apply.applyArgv("/bin/sh", sudoRequest({ built: { ok: true, text: nestedText, remove: false }, trial: passed("sudo", nestedText, nestedAnswers) }),
                               live, true, scripts);
        assertEqual(plan.argv?.slice(10).join(" "), "system-login " + edit.sha256("auth include system-auth\n") + " system-auth " + edit.sha256(systemAuth),
                    "includes inside included files: every name with its hash");
        const vendorOnly = { "/etc/pam.d/system-auth": { absent: true }, "/usr/lib/pam.d/system-auth": { text: systemAuth } };
        plan = apply.applyArgv("/bin/sh", sudoRequest({ trial: passed("sudo", sudoBuilt.text, vendorOnly) }), live, true, scripts);
        assertEqual(code(plan) + " " + plan.argv?.slice(10).join(" "), " system-auth " + edit.sha256(systemAuth),
                    "a name found in the vendor folder: by name, the root step looks it up the same way");

        // ── The places ──
        // A stand-in's places: the system's, under a scratch folder (the script's base)
        const under = (base, paths) => ({ system: base + paths.system, vendor: base + paths.vendor, backups: base + paths.backups });
        const scratch = under("/run/user/1000/t", live);
        assertEqual(JSON.stringify(live), JSON.stringify({ system: "/etc/pam.d", vendor: "/usr/lib/pam.d", backups: "/var/lib/h2s-shell/pam-backup" }),
                    "the system's places (fixed in pam-apply.sh too)");
        assertEqual(apply.pathsRefusal(live, true), "", "the system's places, for the system's pkexec");
        assertEqual(apply.pathsRefusal(scratch, true), "paths", "… nothing else for it");
        assertEqual(apply.pathsRefusal(scratch, false), "", "a stand-in's run: scratch places");
        assertEqual(apply.pathsRefusal(live, false), "paths", "… never the system's");
        for (const top of ["/etc", "/usr", "/var"])
            assertEqual(apply.pathsRefusal(under(top + "/x", live), false), "paths", "… nothing under " + top);
        assertEqual(apply.pathsRefusal(under("/var", live), false), "paths", "… nor under /var itself");
        assertEqual(apply.pathsRefusal(Object.assign({}, scratch, { backups: "/run/user/1000/u/var/lib/h2s-shell/pam-backup" }), false), "paths",
                    "… all under one folder");
        assertEqual(apply.pathsRefusal(Object.assign({}, scratch, { backups: "/run/user/1000/t/backups" }), false), "paths", "… each where the script has it");
        assertEqual(apply.pathsRefusal(under("/run/user/1000/..", live), false), "paths", "no .. in a place");
        assertEqual(apply.pathsRefusal(under("/run/user/1000/a b", live), false), "paths", "… nor a space");
        assertEqual(apply.pathsRefusal(under("relative", live), false), "paths", "… nor a relative path");
        assertEqual(apply.pathsRefusal(Object.assign({}, scratch, { vendor: undefined }), false), "paths", "… each place given");
        assertEqual(apply.pathsRefusal(Object.assign({}, scratch, { system: 5 }), false), "paths", "… each a path");
        assertEqual(apply.pathsRefusal(null, false), "paths", "… places given");
        assertEqual(code(apply.applyArgv("/bin/sh", sudoRequest(), scratch, true, scripts)), "paths", "Apply to scratch places through the system's pkexec: refused");
        plan = apply.applyArgv("/bin/sh", sudoRequest({ trial: passed("sudo", sudoBuilt.text, { "/run/user/1000/t/etc/pam.d/system-auth": { text: systemAuth } },
                                                                    [scratch.system, scratch.vendor]) }), scratch, false, scripts);
        assertEqual(code(plan) + " " + plan.argv?.[4], " /run/user/1000/t", "a stand-in's run: its base the first argument");

        // ── polkit: our file written, then removed ──
        const polkitBuilt = edit.build(null, [fingerprint("r1"), fixed], facts("polkit-1"));
        const polkitRequest = more => Object.assign({ service: "polkit-1", built: polkitBuilt, currentText: null, vendorText: vendorPolkit,
                                                      trial: passed("polkit-1", polkitBuilt.text) }, more ?? {});
        plan = apply.applyArgv("/bin/sh", polkitRequest(), live, true, scripts);
        assertEqual(plan.argv?.slice(5, 9).join(" "), "write polkit-1 " + edit.sha256(polkitBuilt.text) + " absent",
                    "polkit without a file of ours: written where there was none");
        assertEqual(apply.applyArgv("/bin/sh", polkitRequest({ currentText: undefined }), live, true, scripts).argv?.[8], "absent",
                    "… no file given at all: the same");
        assertEqual(code(apply.applyArgv("/bin/sh", polkitRequest({ currentText: 5 }), live, true, scripts)), "unread", "… a file that is no text: not read");
        const removal = edit.build(polkitBuilt.text, [fixed], facts("polkit-1"));
        assert(removal.ok && removal.remove, "the fixture: back to the system's rows removes our polkit-1");
        assertEqual(JSON.stringify(apply.candidate(removal, vendorPolkit)), JSON.stringify({ text: vendorPolkit, remove: true }),
                    "a removal's candidate: the vendor file that is then in force");
        assertEqual(apply.candidate(removal, null), null, "… none without the vendor file");
        assertEqual(JSON.stringify(apply.candidate(polkitBuilt, vendorPolkit)), JSON.stringify({ text: polkitBuilt.text, remove: false }),
                    "a write's candidate: the text built");
        plan = apply.applyArgv("/bin/sh", polkitRequest({ built: removal, currentText: polkitBuilt.text, trial: passed("polkit-1", vendorPolkit) }), live, true, scripts);
        assertEqual(code(plan), "", "a removal after a trial of the vendor file");
        assertEqual(JSON.stringify(plan.argv.slice(5)), JSON.stringify(["remove", "polkit-1", edit.sha256(vendorPolkit), edit.sha256(polkitBuilt.text),
                                                                       "system-auth", edit.sha256(systemAuth)]),
                    "… remove, the vendor file's hash, our file's hash, the included names: no text");
        assertEqual(plan.expected.mode + " " + plan.expected.sha256, "remove " + edit.sha256(vendorPolkit), "… the reply must name the vendor file");
        assertEqual(code(apply.applyArgv("/bin/sh", polkitRequest({ built: removal, currentText: polkitBuilt.text }), live, true, scripts)), "notTried",
                    "a removal after a trial of our own file, not the vendor's: not done");
        assertEqual(code(apply.applyArgv("/bin/sh", polkitRequest({ built: removal, currentText: null, trial: passed("polkit-1", vendorPolkit) }), live, true, scripts)),
                    "unchanged", "nothing of ours to remove");
        assertEqual(code(apply.applyArgv("/bin/sh", sudoRequest({ built: removal, vendorText: vendorPolkit, trial: passed("sudo", vendorPolkit) }), live, true, scripts)),
                    "built", "a removal is polkit's only");

        // ── One trial for a shared list ──
        plan = apply.applyArgv("/bin/sh", polkitRequest({ trial: sudoTrial }), live, true, scripts);
        assertEqual(code(plan), "", "polkit's candidate with sudo's auth lines: sudo's trial covers it");
        assertEqual(plan.argv.slice(5, 7).join(" ") + " " + plan.argv[9], "write polkit-1 " + polkitBuilt.text, "… polkit's own text written");
        const polkitRequired = edit.build(null, [fingerprint("r1", "required"), fixed], facts("polkit-1"));
        assertEqual(code(apply.applyArgv("/bin/sh", polkitRequest({ built: polkitRequired, trial: sudoTrial }), live, true, scripts)), "notTried",
                    "other auth lines: sudo's trial does not cover polkit");
        const polkitExtra = polkitBuilt.text.replace("auth       include      system-auth", "auth include polkit-extra");
        assertEqual(code(apply.applyArgv("/bin/sh", polkitRequest({ built: { ok: true, text: polkitExtra, remove: false }, trial: sudoTrial }), live, true, scripts)),
                    "notTried", "polkit includes a file sudo's trial never read: no cover");
        const sudoOwnInclude = sudoBuilt.text.replace("auth\t\tinclude\t\tsystem-auth", "auth include sudo-extra");
        const extra = Object.assign({ "/etc/pam.d/sudo-extra": { text: systemAuth } }, answers);
        assertEqual(code(apply.applyArgv("/bin/sh", polkitRequest({ trial: passed("sudo", sudoOwnInclude, extra) }), live, true, scripts)), "",
                    "another file name with the same lines: the same auth lines, covered (polkit's own includes checked by the root step)");
        const atText = "-auth sufficient pam_fprintd.so\n@include system-auth\n";
        assertEqual(code(apply.applyArgv("/bin/sh", polkitRequest({ built: { ok: true, text: atText, remove: false }, trial: passed("sudo", atText) }), live, true, scripts)),
                    "notTried", "the same lines through @include: each its own trial");

        // ── Undo ──
        plan = apply.undoArgv("/bin/sh", { service: "sudo", backup: "sudo.20261123T101500Z", currentSha256: edit.sha256(sudoBuilt.text) }, live, true, scripts);
        assertEqual(JSON.stringify(plan.argv.slice(3)), JSON.stringify(["sh", "", "undo", "sudo", "sudo.20261123T101500Z", edit.sha256(sudoBuilt.text)]),
                    "Undo: the backup's name and what the apply left in force");
        assertEqual(plan.argv[2], "shared\nown\n", "… the same script");
        assertEqual(code(apply.undoArgv("/bin/sh", { service: "sudo", backup: "sudo.20261123T101500Z", currentSha256: "absent" }, live, true, ["shared\n"])),
                    "", "… (the texts handed in are what is joined)");
        assertEqual(code(apply.undoArgv("/bin/sh", { service: "sudo", backup: "sudo.20261123T101500Z", currentSha256: "absent" }, live, true, [""])),
                    "script", "… an Undo with a file not read: refused");
        assertEqual(code(apply.undoArgv("/bin/sh", { service: "polkit-1", backup: "polkit-1.20261123T101500Z-2.absent", currentSha256: "absent" }, live, true, scripts)),
                    "", "a backup of no file, a second in that second; nothing in force now");
        for (const name of ["../sudo.20261123T101500Z", "polkit-1.20261123T101500Z", "sudo.20261123T101500", "sudo.20261123T101500Z-0",
                            "sudo.20261123T101500Z.absent.x", "sudo.2026112T101500Z", "/var/lib/h2s-shell/pam-backup/sudo.20261123T101500Z", "", null])
            assertEqual(code(apply.undoArgv("/bin/sh", { service: "sudo", backup: name, currentSha256: "absent" }, live, true, scripts)), "backupName",
                        "not a backup of sudo: " + JSON.stringify(name));
        assertEqual(code(apply.undoArgv("/bin/sh", { service: "sudo", backup: "sudo.20261123T101500Z", currentSha256: "x" }, live, true, scripts)), "unread",
                    "what is in force not known");
        assertEqual(code(apply.undoArgv("/bin/sh", { service: "login", backup: "login.20261123T101500Z", currentSha256: "absent" }, live, true, scripts)), "service",
                    "a service the shell never writes");
        assertEqual(code(apply.undoArgv("/bin/sh", { service: "sudo", backup: "sudo.20261123T101500Z", currentSha256: "absent" }, scratch, true, scripts)), "paths",
                    "scratch places through the system's pkexec");
        assertEqual(code(apply.undoArgv("sh", { service: "sudo", backup: "sudo.20261123T101500Z", currentSha256: "absent" }, live, true, scripts)), "arguments",
                    "Undo with a shell that is not an absolute path");
        assertEqual(apply.backupPath(live, "sudo.20261123T101500Z"), "/var/lib/h2s-shell/pam-backup/sudo.20261123T101500Z", "a backup's path, for the page");

        // ── The reply ──
        const hash = edit.sha256(sudoBuilt.text);
        const expected = { mode: "write", service: "sudo", sha256: hash };
        const ran = (stdout, more) => Object.assign({ ok: true, code: 0, stdout, stderr: "", dismissed: false, refused: false, cancelled: false, blocked: "", error: "" }, more ?? {});
        let outcome = apply.applyReply(ran("written sudo " + hash + " sudo.20261123T101500Z\n"), expected);
        assertEqual(JSON.stringify(outcome), JSON.stringify({ ok: true, quiet: false, kind: "written", service: "sudo", sha256: hash,
                                                              backup: "sudo.20261123T101500Z", refused: "", error: "", file: "done" }), "written: the hash in force and the backup");
        assertEqual(apply.applyReply(ran("written sudo " + edit.sha256("x") + " sudo.20261123T101500Z\n"), expected).ok, false, "another hash: not ok");
        assertEqual(apply.applyReply(ran("written polkit-1 " + hash + " polkit-1.20261123T101500Z\n"), expected).ok, false, "another service: not ok");
        assertEqual(apply.applyReply(ran("restored sudo " + hash + " sudo.20261123T101500Z\n"), expected).ok, false, "another kind: not ok");
        assertEqual(apply.applyReply(ran("written sudo " + hash + " ../x\n"), expected).ok, false, "a backup name that is none: not ok");
        assertEqual(apply.applyReply(ran(""), expected).error, "an answer that is not the one asked for", "ran, said nothing: not ok, said so");
        assertEqual(apply.applyReply(ran("written sudo " + hash + " sudo.20261123T101500Z\n", { ok: false, code: 141 }), expected).ok, true,
                    "the line, then a failed exit: done (said only after the change)");
        outcome = apply.applyReply(ran("", { ok: false, code: 141, stderr: "written sudo " + hash + " sudo.20261123T101500Z\n" }), expected);
        assertEqual(outcome.ok + " " + outcome.backup, "true sudo.20261123T101500Z", "stdout lost, the line on stderr: done");
        assertEqual(apply.applyReply(ran("", { ok: false, code: 1, stderr: "written sudo " + hash + " sudo.20261123T101500Z\nmore\n" }), expected).ok, false,
                    "… only as stderr's last line");
        assertEqual(apply.applyReply(ran("x\n", { stderr: "written sudo " + edit.sha256("x") + " sudo.20261123T101500Z\n" }), expected).ok, false,
                    "… with the hash asked for");
        outcome = apply.applyReply(ran("", { ok: false, code: 3, stderr: "refused included\n" }), expected);
        assertEqual(outcome.ok + " " + outcome.refused + " " + outcome.error, "false included " + apply.texts.included, "a refusal: its code and text");
        outcome = apply.applyReply(ran("", { ok: false, code: 1, stderr: "mv: cannot move\n" }), expected);
        assertEqual(outcome.refused + "|" + outcome.error, "|mv: cannot move", "another failure: its last line");
        assertEqual(apply.applyReply(ran("", { ok: false, code: 2 }), expected).error, "exit code 2", "… nothing said: the exit code");
        assertEqual(apply.applyReply({ ok: false }, expected).error, "exit code -1", "… no exit code either: -1");
        for (const field of ["dismissed", "refused", "cancelled"])
            assertEqual(JSON.stringify([apply.applyReply(ran("", { ok: false, [field]: true }), expected)].map(item => [item.ok, item.quiet])),
                        "[[false,true]]", field + ": not ok, quietly");
        assertEqual(apply.applyReply(ran("", { ok: false, blocked: "locked" }), expected).quiet, true, "locked: quietly");
        outcome = apply.applyReply(ran("removed polkit-1 " + edit.sha256(vendorPolkit) + " polkit-1.20261123T101500Z\n"),
                                   { mode: "remove", service: "polkit-1", sha256: edit.sha256(vendorPolkit) });
        assertEqual(outcome.ok + " " + outcome.kind + " " + outcome.sha256, "true removed absent", "removed: no file of ours in force");
        outcome = apply.applyReply(ran("restored polkit-1 absent polkit-1.20261123T101500Z\n"), { mode: "undo", service: "polkit-1", sha256: "" });
        assertEqual(outcome.ok + " " + outcome.sha256 + " " + outcome.backup, "true absent polkit-1.20261123T101500Z", "restored a backup of no file");
        assertEqual(apply.applyReply(ran("written sudo absent sudo.20261123T101500Z\n"), { mode: "write", service: "sudo", sha256: "" }).ok, false,
                    "a write that leaves no file: not ok");

        // ── After a run that did not say it was done ──
        const writeExpected = { mode: "write", service: "sudo", sha256: hash, before: edit.sha256(archSudo), after: hash };
        assertEqual(apply.afterFailure({ text: archSudo }, writeExpected), "unchanged", "the file read again as before");
        assertEqual(apply.afterFailure({ text: sudoBuilt.text }, writeExpected), "done", "… the file asked for");
        assertEqual(apply.afterFailure({ text: "x" }, writeExpected), "other", "… another one");
        assertEqual(apply.afterFailure({ absent: true }, writeExpected), "other", "… none");
        assertEqual(apply.afterFailure({ unreadable: true }, writeExpected) + " " + apply.afterFailure(undefined, writeExpected), "unknown unknown",
                    "not read: unknown");
        const removeExpected = { mode: "remove", service: "polkit-1", sha256: edit.sha256(vendorPolkit), before: hash, after: "absent" };
        assertEqual(apply.afterFailure({ absent: true }, removeExpected), "done", "a removal: no file is what was asked for");
        const undoExpected = { mode: "undo", service: "sudo", sha256: "", before: hash, after: "" };
        assertEqual(apply.afterFailure({ text: archSudo }, undoExpected) + " " + apply.afterFailure({ text: sudoBuilt.text }, undoExpected), "other unchanged",
                    "an Undo: the backup's hash is not known, so anything new is other");
        assertEqual(apply.undoArgv("/bin/sh", { service: "sudo", backup: "sudo.20261123T101500Z", currentSha256: hash }, live, true, scripts).expected.before, hash,
                    "Undo's expected: what is in force before");
        plan = apply.applyArgv("/bin/sh", polkitRequest({ built: removal, currentText: polkitBuilt.text, trial: passed("polkit-1", vendorPolkit) }), live, true, scripts);
        assertEqual(plan.expected.before + " " + plan.expected.after, edit.sha256(polkitBuilt.text) + " absent", "a removal's expected: ours, then none");

        // ── In force ──
        assertEqual(apply.inForce(sudoBuilt.text, { ok: true, sha256: hash }), true, "the file read again is the one written");
        assertEqual(apply.inForce(archSudo, { ok: true, sha256: hash }), false, "… another one");
        assertEqual(apply.inForce(null, { ok: true, sha256: "absent" }) + " " + apply.inForce("x", { ok: true, sha256: "absent" }), "true false",
                    "no file after a removal");
        assertEqual(apply.inForce(sudoBuilt.text, { ok: false, sha256: hash }), false, "a failed run leaves nothing to compare");

        // ── What the prompt says ──
        assertEqual(apply.what("apply", "sudo") + " | " + apply.what("undo", "polkit-1"),
                    "Change the sign-in rules for sudo | Undo the change to the sign-in rules for administrator prompts", "the run's purpose");
    }
}
