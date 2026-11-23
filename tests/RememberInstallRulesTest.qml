import QtQuick
import qs.singletons

// RememberInstallRules: which files Install, Install again, Remove and Undo change (the rule
// unless it is already the one the facts make; the conf only while the setting is longer than
// polkitd's length without it; a file not the shell's only through `replace`), the root step's
// words, the places a run may write, the reply and what a run that said nothing left
TestCase {
    suiteName: "RememberInstallRules"

    function run() {
        const install = RememberInstallRules;
        const sha = PamEditRules.sha256;
        const live = install.livePaths;
        // A stand-in's places: the system's, under a scratch folder (the script's base)
        const under = base => ({ rules: base + live.rules, conf: base + live.conf, backups: base + live.backups, systemctl: base + live.systemctl });
        const scratch = under("/run/user/1000/t");
        // The texts of the root step's files as read (the shared part first)
        const scripts = ["shared\n", "own\n"];
        const facts = { user: "alex", timeout: "/usr/bin/timeout", program: "/usr/bin/timeout" };
        const rule = RememberRules.ruleText(facts);
        const etc = RememberRules.confPath;
        const vendorPath = "/usr/share/polkit-1/polkitd.conf";
        const vendorConf = "[Polkitd]\n# ExpirationSeconds=300\n";
        const confs = more => Object.assign({ [vendorPath]: vendorConf }, more ?? {});
        const request = more => Object.assign({ facts, minutes: 5, rule: undefined, confs: confs() }, more ?? {});
        const code = plan => plan.refusal?.code ?? "";
        const words = plan => plan.argv.slice(5);

        // ── The places ──
        assertEqual(JSON.stringify(live), JSON.stringify({ rules: "/usr/share/polkit-1/rules.d", conf: "/etc/polkit-1",
                                                           backups: "/var/lib/h2s-shell/polkit-backup", systemctl: "/usr/bin/systemctl" }),
                    "the system's places: polkit's vendor rules folder, /etc/polkit-1, the backups, systemctl (fixed in remember-install.sh too)");
        assertEqual(install.ruleName + " " + install.confName, "40-h2s-shell.rules polkitd.conf", "the files' names");
        assertEqual(install.pathsRefusal(live, true) + "|" + install.pathsRefusal(scratch, false), "|", "the system's places live, scratch ones for a stand-in");
        assertEqual(install.pathsRefusal(scratch, true) + install.pathsRefusal(live, false), "pathspaths", "never the other way round");
        for (const name of ["rules", "conf", "backups", "systemctl"]) {
            assertEqual(install.pathsRefusal(Object.assign({}, scratch, { [name]: "/run/user/1000/u" + live[name] }), false), "paths",
                        "a stand-in's " + name + " under another folder: refused");
            assertEqual(install.pathsRefusal(Object.assign({}, live, { [name]: scratch[name] }), true), "paths", "the live " + name + " elsewhere: refused");
        }
        assertEqual(install.pathsRefusal(under("/usr/x"), false), "paths", "a stand-in under /usr: refused");
        assertEqual(install.pathsRefusal(under("/run/x'y"), false), "paths", "… or under a folder that is not plain");
        assertEqual(JSON.stringify(install.scriptFiles), JSON.stringify(["replace-lib.sh", "remember-install.sh"]), "the shared functions, then the step");
        for (const unread of [null, [], ["shared\n", ""], ["shared\n", 3], ["shared\n", "own"]]) {
            assertEqual(code(install.installArgv("/bin/sh", request(), live, true, unread)), "script", "a file not read: Install refused (" + JSON.stringify(unread) + ")");
            assertEqual(code(install.removeArgv("/bin/sh", request({ rule: RememberRules.ruleText(facts) }), live, true, unread)), "script", "… Remove too");
            assertEqual(code(install.undoArgv("/bin/sh", { stamp: "20261123T101500Z", rule: "absent", conf: "absent" }, live, true, unread)), "script", "… Undo too");
        }
        assertEqual(install.refusal("script").text, "The shell's script for this could not be read.", "… with a plain reason");

        // ── Install where nothing is ──
        let plan = install.installArgv("/bin/sh", request(), live, true, scripts);
        assertEqual(code(plan), "", "Install: the run's words");
        assertEqual(plan.argv.slice(0, 2).concat([plan.argv[3], "[" + plan.argv[4] + "]"]).join(" "), "/bin/sh -c sh []",
                    "the system's shell, the script, the base: \"\" (the system's places)");
        assertEqual(plan.argv[2], "shared\nown\n", "… the script: the files' texts joined, the shared part first");
        assertEqual(install.installArgv("/bin/sh", request(), scratch, false, scripts).argv?.[4], "/run/user/1000/t", "… a stand-in's: its scratch folder");
        assertEqual(JSON.stringify(words(plan)), JSON.stringify(["apply", "write", "absent", sha(rule), "keep", "absent", "-",
                                                                 "alex", "/usr/bin/timeout", "/usr/bin/timeout", "-"]),
                    "the rule written where there was none from its facts (never its text), no conf for the system's own length");
        assertEqual(JSON.stringify(plan.expected), JSON.stringify({ mode: "apply", before: { rule: "absent", conf: "absent" },
                                                                    after: { rule: sha(rule), conf: "absent" }, reload: false }), "… what the reply must say");
        assert(!words(plan).some(word => word.includes("\n")), "no text among the arguments");

        // A longer setting: the conf too
        const conf15 = RememberRules.confText(900);
        plan = install.installArgv("/bin/sh", request({ minutes: 15 }), live, true, scripts);
        assertEqual(JSON.stringify(words(plan).slice(4)), JSON.stringify(["write", "absent", sha(conf15), "alex", "/usr/bin/timeout", "/usr/bin/timeout", "900"]),
                    "15 min: the conf for 900 s");
        assertEqual(plan.expected.reload, true, "… polkitd told");
        assertEqual(words(install.installArgv("/bin/sh", request({ minutes: 4 }), live, true, scripts))[4], "keep", "4 min: shorter, no conf (the shell revokes)");
        assertEqual(words(install.installArgv("/bin/sh", request({ minutes: 5 }), live, true, scripts))[4], "keep", "5 min: the system's own, no conf");
        // The vendor length decides
        const vendor10 = { [vendorPath]: "[Polkitd]\nExpirationSeconds=600\n" };
        assertEqual(words(install.installArgv("/bin/sh", request({ minutes: 10, confs: vendor10 }), live, true, scripts))[4], "keep",
                    "the vendor file says 10 min: 10 is no longer");
        assertEqual(words(install.installArgv("/bin/sh", request({ minutes: 11, confs: vendor10 }), live, true, scripts))[4], "write", "… 11 is");
        assertEqual(words(install.installArgv("/bin/sh", request({ minutes: 5, confs: { [vendorPath]: "[Polkitd]\nExpirationSeconds=x\n" } }), live, true, scripts))[4], "write",
                    "the vendor length unknown: the shell's conf decides");
        assertEqual(words(install.installArgv("/bin/sh", request({ minutes: 1, confs: { "/run/polkit-1/polkitd.conf": "[Polkitd]\nExpirationSeconds=60\n" } }), live, true, scripts))[4],
                    "keep", "a /run conf of 60 s: 1 min is not longer…");
        assertEqual(words(install.installArgv("/bin/sh", request({ minutes: 2, confs: { "/run/polkit-1/polkitd.conf": "[Polkitd]\nExpirationSeconds=60\n" } }), live, true, scripts))[4],
                    "write", "… and 2 min too: written");

        // ── Install again ──
        plan = install.installArgv("/bin/sh", request({ minutes: 15, rule: rule }), live, true, scripts);
        assertEqual(JSON.stringify(words(plan)), JSON.stringify(["apply", "keep", sha(rule), "-", "write", "absent", sha(conf15), "-", "-", "-", "900"]),
                    "the rule in place, the setting grew: only the conf");
        plan = install.installArgv("/bin/sh", request({ minutes: 20, rule: rule, confs: confs({ [etc]: conf15 }) }), live, true, scripts);
        assertEqual(JSON.stringify(words(plan).slice(4, 7).concat(words(plan).slice(10))), JSON.stringify(["write", sha(conf15), sha(RememberRules.confText(1200)), "1200"]),
                    "grew again: our conf replaced");
        plan = install.installArgv("/bin/sh", request({ minutes: 5, rule: rule, confs: confs({ [etc]: conf15 }) }), live, true, scripts);
        assertEqual(JSON.stringify(words(plan).slice(4)), JSON.stringify(["remove", sha(conf15), "-", "-", "-", "-", "-"]), "back to 5 min: our conf removed");
        assertEqual(plan.expected.after.conf + " " + plan.expected.reload, "absent true", "… none left, polkitd told");
        assertEqual(code(install.installArgv("/bin/sh", request({ minutes: 15, rule: rule, confs: confs({ [etc]: conf15 }) }), live, true, scripts)), "unchanged",
                    "all in place: nothing to do");
        assertEqual(code(install.installArgv("/bin/sh", request({ rule: rule }), live, true, scripts)), "unchanged", "… at 5 min too");
        const outdated = RememberRules.ruleText(Object.assign({}, facts, { timeout: "/usr/local/bin/timeout", program: "/usr/local/bin/timeout" }));
        plan = install.installArgv("/bin/sh", request({ rule: outdated }), live, true, scripts);
        assertEqual(JSON.stringify(words(plan).slice(1, 4)), JSON.stringify(["write", sha(outdated), sha(rule)]), "our rule for another timeout: replaced");

        // ── Files not the shell's ──
        const byHand = rule.replace("auth_admin_keep", "yes");
        assertEqual(code(install.installArgv("/bin/sh", request({ rule: byHand }), live, true, scripts)), "changed", "a rule changed by hand: not replaced");
        assertEqual(words(install.installArgv("/bin/sh", request({ rule: byHand, replace: { rule: true } }), live, true, scripts))[1], "write", "… unless replace names the rule");
        assertEqual(code(install.installArgv("/bin/sh", request({ rule: byHand, replace: true }), live, true, scripts)), "changed", "… a bare true replaces nothing");
        assertEqual(code(install.installArgv("/bin/sh", request({ rule: byHand, replace: { conf: true } }), live, true, scripts)), "changed", "… nor the conf's word");
        assertEqual(code(install.installArgv("/bin/sh", request({ rule: "polkit.addRule(function() {});\n" }), live, true, scripts)), "changed",
                    "another file under our name: not replaced");
        const foreign = "[Polkitd]\nExpirationSeconds=60\n";
        plan = install.installArgv("/bin/sh", request({ minutes: 15, confs: confs({ [etc]: foreign }) }), live, true, scripts);
        assertEqual(JSON.stringify(words(plan).slice(1, 2).concat(words(plan).slice(4, 7), words(plan).slice(10))), JSON.stringify(["write", "keep", sha(foreign), "-", "-"]),
                    "a conf not ours: the rule installed, the conf left as it is");
        assertEqual(code(install.installArgv("/bin/sh", request({ minutes: 15, rule: rule, confs: confs({ [etc]: foreign }) }), live, true, scripts)), "changed",
                    "… and with the rule in place: changed, not \"nothing to do\"");
        assertEqual(words(install.installArgv("/bin/sh", request({ minutes: 15, rule: rule, confs: confs({ [etc]: foreign }), replace: { conf: true } }), live, true, scripts))[4],
                    "write", "… replace: ours written");
        assertEqual(words(install.installArgv("/bin/sh", request({ minutes: 5, rule: rule, confs: confs({ [etc]: foreign }), replace: { conf: true } }), live, true, scripts))[4],
                    "remove", "… replace at the system's length: it goes");
        assertEqual(words(install.installArgv("/bin/sh", request({ minutes: 5, rule: byHand, confs: confs({ [etc]: foreign }), replace: { rule: true } }), live, true, scripts)).slice(1, 2)
                    .concat(words(install.installArgv("/bin/sh", request({ minutes: 5, rule: byHand, confs: confs({ [etc]: foreign }), replace: { rule: true } }), live, true, scripts)).slice(4, 5)).join(" "),
                    "write keep", "… the rule named only: a hand-made conf kept");

        // ── Refused before the run ──
        assertEqual(code(install.installArgv("/bin/sh", request({ rule: null }), live, true, scripts)), "unread", "the rules file not read");
        assertEqual(code(install.installArgv("/bin/sh", request({ confs: confs({ [etc]: null }) }), live, true, scripts)), "unread", "the conf not read");
        assertEqual(code(install.installArgv("/bin/sh", request({ facts: Object.assign({}, facts, { user: "a b" }) }), live, true, scripts)), "facts", "no rule for these facts");
        for (const minutes of [0, -1, 1.5, "5", undefined, 1e12])
            assertEqual(code(install.installArgv("/bin/sh", request({ minutes }), live, true, scripts)), "setting", "minutes " + JSON.stringify(minutes) + ": refused");
        assertEqual(install.maxMinutes, 60, "the longest setting: the schema's");
        assertEqual(words(install.installArgv("/bin/sh", request({ minutes: 60 }), live, true, scripts))[10], "3600", "60 min: written");
        assertEqual(code(install.installArgv("/bin/sh", request({ minutes: 61 }), live, true, scripts)), "setting", "… a minute more: refused");
        assertEqual(code(install.installArgv("/bin/sh", request({ facts: Object.assign({}, facts, { program: "/usr/bin/" + "x".repeat(4087) }) }), live, true, scripts)), "",
                    "a path of 4096 characters: the longest the root step takes");
        for (const bad of [{ timeout: "/opt/tools/time\u00e9out" }, { program: "/usr/bin/time:out" }, { program: "/usr/bin/" + "x".repeat(4090) }])
            assertEqual(code(install.installArgv("/bin/sh", request({ facts: Object.assign({}, facts, bad) }), live, true, scripts)), "facts",
                        "a path the root step would not take: refused before " + JSON.stringify(bad).slice(0, 40));
        assertEqual(code(install.installArgv("sh", request(), live, true, scripts)), "arguments", "a shell that is not an absolute path");
        assertEqual(code(install.installArgv("/bin/sh", request(), scratch, true, scripts)), "paths", "scratch places through the system's pkexec");
        assertEqual(code(install.installArgv("/bin/sh", request(), live, false, scripts)), "paths", "the system's places through a stand-in");
        assertEqual(install.installArgv("/bin/sh", request({ facts: Object.assign({}, facts, { system: "nixos" }) }), live, true, scripts).argv[6], "write",
                    "Arch's files whatever the facts say of the system");

        // ── Remove ──
        plan = install.removeArgv("/bin/sh", request({ rule: rule, confs: confs({ [etc]: conf15 }) }), live, true, scripts);
        assertEqual(JSON.stringify(words(plan)), JSON.stringify(["apply", "remove", sha(rule), "-", "remove", sha(conf15), "-", "-", "-", "-", "-"]), "Remove: both ours go");
        assertEqual(JSON.stringify(plan.expected.after) + plan.expected.reload, JSON.stringify({ rule: "absent", conf: "absent" }) + "true", "… none left");
        plan = install.removeArgv("/bin/sh", request({ rule: rule, confs: confs({ [etc]: foreign }) }), live, true, scripts);
        assertEqual(words(plan)[4] + " " + plan.expected.reload, "keep false", "a conf not ours stays");
        assertEqual(words(install.removeArgv("/bin/sh", request({ rule: outdated }), live, true, scripts))[1], "remove", "our outdated rule goes");
        assertEqual(code(install.removeArgv("/bin/sh", request({ rule: byHand }), live, true, scripts)), "changed", "a rule changed by hand: not removed");
        assertEqual(words(install.removeArgv("/bin/sh", request({ rule: byHand, replace: { rule: true } }), live, true, scripts))[1], "remove", "… unless replace names the rule");
        assertEqual(code(install.removeArgv("/bin/sh", request(), live, true, scripts)), "unchanged", "nothing installed: nothing to remove");
        assertEqual(code(install.removeArgv("/bin/sh", request({ confs: confs({ [etc]: foreign }) }), live, true, scripts)), "unchanged", "… a conf not ours is not ours to remove");
        assertEqual(words(install.removeArgv("/bin/sh", request({ confs: confs({ [etc]: conf15 }) }), live, true, scripts)).slice(1, 2).concat([words(install.removeArgv("/bin/sh", request({ confs: confs({ [etc]: conf15 }) }), live, true, scripts))[4]]).join(" "),
                    "keep remove", "our conf left alone: it goes");
        assertEqual(code(install.removeArgv("/bin/sh", request({ rule: null }), live, true, scripts)), "unread", "not read: not removed");

        // ── Undo ──
        plan = install.undoArgv("/bin/sh", { stamp: "20261123T101500Z", rule: sha(rule), conf: "absent" }, live, true, scripts);
        assertEqual(JSON.stringify(words(plan)), JSON.stringify(["undo", "20261123T101500Z", sha(rule), "absent"]), "Undo: the stamp, what the run left");
        assertEqual(JSON.stringify(plan.expected.before), JSON.stringify({ rule: sha(rule), conf: "absent" }), "… before: what the run left");
        assertEqual(code(install.undoArgv("/bin/sh", { stamp: "20261123T101500Z-3", rule: "absent", conf: "absent" }, live, true, scripts)), "", "a counted stamp");
        for (const stamp of ["20261123T101500Z-0", "20261123T101500Z-10", "2026112T101500Z", "20261123T101500Z.absent", "40-h2s-shell.rules.20261123T101500Z",
                             "../20261123T101500Z", "", null])
            assertEqual(code(install.undoArgv("/bin/sh", { stamp, rule: "absent", conf: "absent" }, live, true, scripts)), "backupName", "not a stamp: " + JSON.stringify(stamp));
        assertEqual(code(install.undoArgv("/bin/sh", { stamp: "20261123T101500Z", rule: "x", conf: "absent" }, live, true, scripts)), "unread", "the rule left not known");
        assertEqual(code(install.undoArgv("/bin/sh", { stamp: "20261123T101500Z", rule: "absent" }, live, true, scripts)), "unread", "the conf left not known");
        assertEqual(code(install.undoArgv("/bin/sh", { stamp: "20261123T101500Z", rule: "absent", conf: "absent" }, scratch, true, scripts)), "paths", "scratch places live");
        assertEqual(code(install.undoArgv("sh", { stamp: "20261123T101500Z", rule: "absent", conf: "absent" }, live, true, scripts)), "arguments", "a relative shell");
        assertEqual(install.backupPath(live, install.confName, "20261123T101500Z", true), "/var/lib/h2s-shell/polkit-backup/polkitd.conf.20261123T101500Z.absent",
                    "a backup's path, for the page");

        // ── The reply ──
        const expected = install.installArgv("/bin/sh", request({ minutes: 15 }), live, true, scripts).expected;
        const ran = (stdout, more) => Object.assign({ ok: true, code: 0, stdout, stderr: "", dismissed: false, refused: false, cancelled: false, blocked: "", error: "" }, more ?? {});
        const line = (kind, ruleHash, confHash, stamp, reload) => kind + " " + ruleHash + " " + confHash + " " + stamp + " " + reload + "\n";
        let outcome = install.reply(ran(line("applied", sha(rule), sha(conf15), "20261123T101500Z", "hup")), expected);
        // Ended by the shell's timeout (TERM: 124, KILL after it: 137) before saying it was done
        for (const stopped of [124, 137]) {
            const timedOut = install.reply(ran("", { ok: false, code: stopped, timedOut: true }), expected);
            assertEqual(timedOut.ok + " " + timedOut.quiet + " " + timedOut.error, "false false exit code " + stopped,
                        "stopped by the timeout (" + stopped + "): a failure, said, the files read again");
        }
        assertEqual(JSON.stringify(outcome), JSON.stringify({ ok: true, quiet: false, kind: "applied", rule: sha(rule), conf: sha(conf15), stamp: "20261123T101500Z",
                                                              reload: "hup", refused: "", error: "", files: "done" }), "applied: what is in force, the stamp, polkitd told");
        assertEqual(install.reply(ran(line("applied", sha(rule), sha(conf15), "20261123T101500Z", "nohup")), expected).reload, "nohup",
                    "polkitd not told: still done, said so");
        assertEqual(install.reply(ran(line("applied", sha(rule), sha(conf15), "20261123T101500Z", "none")), expected).ok, false,
                    "the conf changed without a word to polkitd: not this run");
        assertEqual(install.reply(ran(line("applied", sha(rule), "absent", "20261123T101500Z", "hup")), expected).ok, false, "another conf: not ok");
        assertEqual(install.reply(ran(line("applied", sha("x"), sha(conf15), "20261123T101500Z", "hup")), expected).ok, false, "another rule: not ok");
        assertEqual(install.reply(ran(line("restored", sha(rule), sha(conf15), "20261123T101500Z", "hup")), expected).ok, false, "another kind: not ok");
        assertEqual(install.reply(ran(line("applied", sha(rule), sha(conf15), "../x", "hup")), expected).ok, false, "a stamp that is none: not ok");
        assertEqual(install.reply(ran(line("applied", sha(rule), sha(conf15), "20261123T101500Z", "maybe")), expected).ok, false, "an unknown reload word: not ok");
        const ruleOnly = install.installArgv("/bin/sh", request(), live, true, scripts).expected;
        assertEqual(install.reply(ran(line("applied", sha(rule), "absent", "20261123T101500Z", "none")), ruleOnly).ok, true, "the rule alone: no word to polkitd");
        assertEqual(install.reply(ran(line("applied", sha(rule), "absent", "20261123T101500Z", "hup")), ruleOnly).ok, false, "… a word without a change: not this run");
        outcome = install.reply(ran("", { ok: false, code: 141, stderr: line("applied", sha(rule), sha(conf15), "20261123T101500Z", "hup") }), expected);
        assertEqual(outcome.ok + " " + outcome.stamp, "true 20261123T101500Z", "stdout lost, the line on stderr: done");
        assertEqual(install.reply(ran("", { ok: false, code: 1, stderr: line("applied", sha(rule), sha(conf15), "20261123T101500Z", "hup") + "more\n" }), expected).ok, false,
                    "… only as stderr's last line");
        const undoExpected = install.undoArgv("/bin/sh", { stamp: "20261123T101500Z", rule: sha(rule), conf: "absent" }, live, true, scripts).expected;
        outcome = install.reply(ran(line("restored", "absent", "absent", "20261123T101501Z", "none")), undoExpected);
        assertEqual(outcome.ok + " " + outcome.rule + " " + outcome.stamp, "true absent 20261123T101501Z", "restored: whatever the backups held, a new stamp");
        assertEqual(install.reply(ran(line("applied", "absent", "absent", "20261123T101501Z", "none")), undoExpected).ok, false, "… said as applied: not ok");
        outcome = install.reply(ran("", { ok: false, code: 3, stderr: "refused changed\n" }), expected);
        assertEqual(outcome.ok + " " + outcome.refused + " " + outcome.error, "false changed " + install.texts.changed, "a refusal: its code and text");
        assertEqual(install.reply(ran("", { ok: false, code: 3, stderr: "refused weird\n" }), expected).error, install.texts.arguments, "an unknown code: the generic text");
        assertEqual(install.reply(ran(""), expected).error, "an answer that is not the one asked for", "ran, said nothing: not ok");
        assertEqual(install.reply(ran("", { ok: false, code: 1, stderr: "mv: x\u001b[1m\n" }), expected).error, "mv: x [1m", "another failure: its last line, no controls");
        assertEqual(install.reply({ ok: false, code: 2 }, expected).error, "exit code 2", "nothing said: the exit code");
        for (const field of ["dismissed", "refused", "cancelled"]) {
            outcome = install.reply(ran("", { ok: false, [field]: true }), expected);
            assertEqual(outcome.ok + " " + outcome.quiet, "false true", field + ": not ok, quietly");
        }
        assertEqual(install.reply(ran("", { ok: false, blocked: "locked" }), expected).quiet, true, "locked: quietly");

        // ── After a run that said nothing ──
        const text = value => ({ text: value }), absent = { absent: true };
        assertEqual(install.afterFailure({ rule: absent, conf: absent }, expected), "unchanged", "both as before");
        assertEqual(install.afterFailure({ rule: text(rule), conf: text(conf15) }, expected), "done", "both as asked");
        assertEqual(install.afterFailure({ rule: text(rule), conf: absent }, expected), "other", "one of two: other");
        assertEqual(install.afterFailure({ rule: { unreadable: true }, conf: absent }, expected), "unknown", "one not read: unknown");
        assertEqual(install.afterFailure({ rule: absent }, expected), "unknown", "… or missing");
        assertEqual(install.afterFailure({ rule: text(rule), conf: absent }, undoExpected) + " " + install.afterFailure({ rule: absent, conf: absent }, undoExpected),
                    "unchanged other", "an Undo: only before is known");

        // ── What the prompt says ──
        assertEqual([install.what("install"), install.what("remove"), install.what("undo")].join(" | "),
                    "Remember the administrator password | Stop remembering the administrator password | Undo the change to the remembered administrator password",
                    "the run's purpose");
    }
}
