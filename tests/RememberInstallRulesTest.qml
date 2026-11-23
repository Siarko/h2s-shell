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
        const scratch = { rules: "/run/user/1000/t/rules.d", conf: "/run/user/1000/t/polkit-1", backups: "/run/user/1000/t/lib/polkit-backup",
                          systemctl: "/run/user/1000/t/systemctl", owner: 1000 };
        const facts = { user: "alex", timeout: "/usr/bin/timeout", program: "/usr/bin/timeout" };
        const rule = RememberRules.ruleText(facts);
        const etc = RememberRules.confPath;
        const vendorPath = "/usr/share/polkit-1/polkitd.conf";
        const vendorConf = "[Polkitd]\n# ExpirationSeconds=300\n";
        const confs = more => Object.assign({ [vendorPath]: vendorConf }, more ?? {});
        const request = more => Object.assign({ facts, minutes: 5, rule: undefined, confs: confs() }, more ?? {});
        const code = plan => plan.refusal?.code ?? "";
        const words = plan => plan.argv.slice(4);

        // ── The places ──
        assertEqual(JSON.stringify(live), JSON.stringify({ rules: "/usr/share/polkit-1/rules.d", conf: "/etc/polkit-1",
                                                           backups: "/var/lib/h2s-shell/polkit-backup", systemctl: "/usr/bin/systemctl", owner: 0 }),
                    "the system's places: polkit's vendor rules folder, /etc/polkit-1, the backups, systemctl, root");
        assertEqual(install.ruleName + " " + install.confName, "40-h2s-shell.rules polkitd.conf", "the files' names");
        assertEqual(install.pathsRefusal(live, true) + "|" + install.pathsRefusal(scratch, false), "|", "the system's places live, scratch ones for a stand-in");
        assertEqual(install.pathsRefusal(scratch, true) + install.pathsRefusal(live, false), "pathspaths", "never the other way round");
        for (const name of ["rules", "conf", "backups", "systemctl"]) {
            assertEqual(install.pathsRefusal(Object.assign({}, scratch, { [name]: "/usr/x" }), false), "paths", "a stand-in's " + name + " under /usr: refused");
            assertEqual(install.pathsRefusal(Object.assign({}, live, { [name]: scratch[name] }), true), "paths", "the live " + name + " elsewhere: refused");
        }
        assertEqual(install.pathsRefusal(Object.assign({}, live, { owner: 1000 }), true), "paths", "live: owned by root only");
        assertEqual(install.applyScript({ rules: "/x'y", conf: "/c", backups: "/b", systemctl: "/s", owner: 0 }), "", "no script for places that are not plain");
        assert(install.applyScript(live).includes("rules='/usr/share/polkit-1/rules.d'; conf='/etc/polkit-1'; backups='/var/lib/h2s-shell/polkit-backup'; systemctl='/usr/bin/systemctl'; owner=0\n"),
               "the places and the owner written into the script");
        assert(install.applyScript(live).includes("rule_name='40-h2s-shell.rules'; conf_name='polkitd.conf'; max_seconds=3600\n"), "… the files' names too");
        assert(install.applyScript(live).startsWith("set -eu; umask 077;"), "… private files unless chmod says otherwise");

        // ── Install where nothing is ──
        let plan = install.installArgv("/bin/sh", request(), live, true);
        assertEqual(code(plan), "", "Install: the run's words");
        assertEqual(plan.argv.slice(0, 2).concat([plan.argv[3]]).join(" "), "/bin/sh -c sh", "the system's shell and the script");
        assertEqual(plan.argv[2], install.applyScript(live), "… the fixed script for the system's places");
        assertEqual(JSON.stringify(words(plan)), JSON.stringify(["apply", "write", "absent", sha(rule), "keep", "absent", "-",
                                                                 "alex", "/usr/bin/timeout", "/usr/bin/timeout", "-"]),
                    "the rule written where there was none from its facts (never its text), no conf for the system's own length");
        assertEqual(JSON.stringify(plan.expected), JSON.stringify({ mode: "apply", before: { rule: "absent", conf: "absent" },
                                                                    after: { rule: sha(rule), conf: "absent" }, reload: false }), "… what the reply must say");
        assert(!words(plan).some(word => word.includes("\n")), "no text among the arguments");

        // A longer setting: the conf too
        const conf15 = RememberRules.confText(900);
        plan = install.installArgv("/bin/sh", request({ minutes: 15 }), live, true);
        assertEqual(JSON.stringify(words(plan).slice(4)), JSON.stringify(["write", "absent", sha(conf15), "alex", "/usr/bin/timeout", "/usr/bin/timeout", "900"]),
                    "15 min: the conf for 900 s");
        assertEqual(plan.expected.reload, true, "… polkitd told");
        assertEqual(words(install.installArgv("/bin/sh", request({ minutes: 4 }), live, true))[4], "keep", "4 min: shorter, no conf (the shell revokes)");
        assertEqual(words(install.installArgv("/bin/sh", request({ minutes: 5 }), live, true))[4], "keep", "5 min: the system's own, no conf");
        // The vendor length decides
        const vendor10 = { [vendorPath]: "[Polkitd]\nExpirationSeconds=600\n" };
        assertEqual(words(install.installArgv("/bin/sh", request({ minutes: 10, confs: vendor10 }), live, true))[4], "keep",
                    "the vendor file says 10 min: 10 is no longer");
        assertEqual(words(install.installArgv("/bin/sh", request({ minutes: 11, confs: vendor10 }), live, true))[4], "write", "… 11 is");
        assertEqual(words(install.installArgv("/bin/sh", request({ minutes: 5, confs: { [vendorPath]: "[Polkitd]\nExpirationSeconds=x\n" } }), live, true))[4], "write",
                    "the vendor length unknown: the shell's conf decides");
        assertEqual(words(install.installArgv("/bin/sh", request({ minutes: 1, confs: { "/run/polkit-1/polkitd.conf": "[Polkitd]\nExpirationSeconds=60\n" } }), live, true))[4],
                    "keep", "a /run conf of 60 s: 1 min is not longer…");
        assertEqual(words(install.installArgv("/bin/sh", request({ minutes: 2, confs: { "/run/polkit-1/polkitd.conf": "[Polkitd]\nExpirationSeconds=60\n" } }), live, true))[4],
                    "write", "… and 2 min too: written");

        // ── Install again ──
        plan = install.installArgv("/bin/sh", request({ minutes: 15, rule: rule }), live, true);
        assertEqual(JSON.stringify(words(plan)), JSON.stringify(["apply", "keep", sha(rule), "-", "write", "absent", sha(conf15), "-", "-", "-", "900"]),
                    "the rule in place, the setting grew: only the conf");
        plan = install.installArgv("/bin/sh", request({ minutes: 20, rule: rule, confs: confs({ [etc]: conf15 }) }), live, true);
        assertEqual(JSON.stringify(words(plan).slice(4, 7).concat(words(plan).slice(10))), JSON.stringify(["write", sha(conf15), sha(RememberRules.confText(1200)), "1200"]),
                    "grew again: our conf replaced");
        plan = install.installArgv("/bin/sh", request({ minutes: 5, rule: rule, confs: confs({ [etc]: conf15 }) }), live, true);
        assertEqual(JSON.stringify(words(plan).slice(4)), JSON.stringify(["remove", sha(conf15), "-", "-", "-", "-", "-"]), "back to 5 min: our conf removed");
        assertEqual(plan.expected.after.conf + " " + plan.expected.reload, "absent true", "… none left, polkitd told");
        assertEqual(code(install.installArgv("/bin/sh", request({ minutes: 15, rule: rule, confs: confs({ [etc]: conf15 }) }), live, true)), "unchanged",
                    "all in place: nothing to do");
        assertEqual(code(install.installArgv("/bin/sh", request({ rule: rule }), live, true)), "unchanged", "… at 5 min too");
        const outdated = RememberRules.ruleText(Object.assign({}, facts, { timeout: "/usr/local/bin/timeout", program: "/usr/local/bin/timeout" }));
        plan = install.installArgv("/bin/sh", request({ rule: outdated }), live, true);
        assertEqual(JSON.stringify(words(plan).slice(1, 4)), JSON.stringify(["write", sha(outdated), sha(rule)]), "our rule for another timeout: replaced");

        // ── Files not the shell's ──
        const byHand = rule.replace("auth_admin_keep", "yes");
        assertEqual(code(install.installArgv("/bin/sh", request({ rule: byHand }), live, true)), "changed", "a rule changed by hand: not replaced");
        assertEqual(words(install.installArgv("/bin/sh", request({ rule: byHand, replace: true }), live, true))[1], "write", "… unless replace");
        assertEqual(code(install.installArgv("/bin/sh", request({ rule: "polkit.addRule(function() {});\n" }), live, true)), "changed",
                    "another file under our name: not replaced");
        const foreign = "[Polkitd]\nExpirationSeconds=60\n";
        plan = install.installArgv("/bin/sh", request({ minutes: 15, confs: confs({ [etc]: foreign }) }), live, true);
        assertEqual(JSON.stringify(words(plan).slice(1, 2).concat(words(plan).slice(4, 7), words(plan).slice(10))), JSON.stringify(["write", "keep", sha(foreign), "-", "-"]),
                    "a conf not ours: the rule installed, the conf left as it is");
        assertEqual(code(install.installArgv("/bin/sh", request({ minutes: 15, rule: rule, confs: confs({ [etc]: foreign }) }), live, true)), "changed",
                    "… and with the rule in place: changed, not \"nothing to do\"");
        assertEqual(words(install.installArgv("/bin/sh", request({ minutes: 15, rule: rule, confs: confs({ [etc]: foreign }), replace: true }), live, true))[4],
                    "write", "… replace: ours written");
        assertEqual(words(install.installArgv("/bin/sh", request({ minutes: 5, rule: rule, confs: confs({ [etc]: foreign }), replace: true }), live, true))[4],
                    "remove", "… replace at the system's length: it goes");

        // ── Refused before the run ──
        assertEqual(code(install.installArgv("/bin/sh", request({ rule: null }), live, true)), "unread", "the rules file not read");
        assertEqual(code(install.installArgv("/bin/sh", request({ confs: confs({ [etc]: null }) }), live, true)), "unread", "the conf not read");
        assertEqual(code(install.installArgv("/bin/sh", request({ facts: Object.assign({}, facts, { user: "a b" }) }), live, true)), "facts", "no rule for these facts");
        for (const minutes of [0, -1, 1.5, "5", undefined, 1e12])
            assertEqual(code(install.installArgv("/bin/sh", request({ minutes }), live, true)), "setting", "minutes " + JSON.stringify(minutes) + ": refused");
        assertEqual(install.maxMinutes, 60, "the longest setting: the schema's");
        assertEqual(words(install.installArgv("/bin/sh", request({ minutes: 60 }), live, true))[10], "3600", "60 min: written");
        assertEqual(code(install.installArgv("/bin/sh", request({ minutes: 61 }), live, true)), "setting", "… a minute more: refused");
        assert(install.applyScript(live).includes("; max_seconds=3600\n"), "… the root step's own bound");
        assertEqual(code(install.installArgv("/bin/sh", request({ facts: Object.assign({}, facts, { program: "/usr/bin/" + "x".repeat(4087) }) }), live, true)), "",
                    "a path of 4096 characters: the longest the root step takes");
        for (const bad of [{ timeout: "/opt/tools/time\u00e9out" }, { program: "/usr/bin/time:out" }, { program: "/usr/bin/" + "x".repeat(4090) }])
            assertEqual(code(install.installArgv("/bin/sh", request({ facts: Object.assign({}, facts, bad) }), live, true)), "facts",
                        "a path the root step would not take: refused before " + JSON.stringify(bad).slice(0, 40));
        assertEqual(code(install.installArgv("sh", request(), live, true)), "arguments", "a shell that is not an absolute path");
        assertEqual(code(install.installArgv("/bin/sh", request(), scratch, true)), "paths", "scratch places through the system's pkexec");
        assertEqual(code(install.installArgv("/bin/sh", request(), live, false)), "paths", "the system's places through a stand-in");
        assertEqual(install.installArgv("/bin/sh", request({ facts: Object.assign({}, facts, { system: "nixos" }) }), live, true).argv[5], "write",
                    "Arch's files whatever the facts say of the system");

        // ── Remove ──
        plan = install.removeArgv("/bin/sh", request({ rule: rule, confs: confs({ [etc]: conf15 }) }), live, true);
        assertEqual(JSON.stringify(words(plan)), JSON.stringify(["apply", "remove", sha(rule), "-", "remove", sha(conf15), "-", "-", "-", "-", "-"]), "Remove: both ours go");
        assertEqual(JSON.stringify(plan.expected.after) + plan.expected.reload, JSON.stringify({ rule: "absent", conf: "absent" }) + "true", "… none left");
        plan = install.removeArgv("/bin/sh", request({ rule: rule, confs: confs({ [etc]: foreign }) }), live, true);
        assertEqual(words(plan)[4] + " " + plan.expected.reload, "keep false", "a conf not ours stays");
        assertEqual(words(install.removeArgv("/bin/sh", request({ rule: outdated }), live, true))[1], "remove", "our outdated rule goes");
        assertEqual(code(install.removeArgv("/bin/sh", request({ rule: byHand }), live, true)), "changed", "a rule changed by hand: not removed");
        assertEqual(words(install.removeArgv("/bin/sh", request({ rule: byHand, replace: true }), live, true))[1], "remove", "… unless replace");
        assertEqual(code(install.removeArgv("/bin/sh", request(), live, true)), "unchanged", "nothing installed: nothing to remove");
        assertEqual(code(install.removeArgv("/bin/sh", request({ confs: confs({ [etc]: foreign }) }), live, true)), "unchanged", "… a conf not ours is not ours to remove");
        assertEqual(words(install.removeArgv("/bin/sh", request({ confs: confs({ [etc]: conf15 }) }), live, true)).slice(1, 2).concat([words(install.removeArgv("/bin/sh", request({ confs: confs({ [etc]: conf15 }) }), live, true))[4]]).join(" "),
                    "keep remove", "our conf left alone: it goes");
        assertEqual(code(install.removeArgv("/bin/sh", request({ rule: null }), live, true)), "unread", "not read: not removed");

        // ── Undo ──
        plan = install.undoArgv("/bin/sh", { stamp: "20261123T101500Z", rule: sha(rule), conf: "absent" }, live, true);
        assertEqual(JSON.stringify(words(plan)), JSON.stringify(["undo", "20261123T101500Z", sha(rule), "absent"]), "Undo: the stamp, what the run left");
        assertEqual(JSON.stringify(plan.expected.before), JSON.stringify({ rule: sha(rule), conf: "absent" }), "… before: what the run left");
        assertEqual(code(install.undoArgv("/bin/sh", { stamp: "20261123T101500Z-3", rule: "absent", conf: "absent" }, live, true)), "", "a counted stamp");
        for (const stamp of ["20261123T101500Z-0", "20261123T101500Z-10", "2026112T101500Z", "20261123T101500Z.absent", "40-h2s-shell.rules.20261123T101500Z",
                             "../20261123T101500Z", "", null])
            assertEqual(code(install.undoArgv("/bin/sh", { stamp, rule: "absent", conf: "absent" }, live, true)), "backupName", "not a stamp: " + JSON.stringify(stamp));
        assertEqual(code(install.undoArgv("/bin/sh", { stamp: "20261123T101500Z", rule: "x", conf: "absent" }, live, true)), "unread", "the rule left not known");
        assertEqual(code(install.undoArgv("/bin/sh", { stamp: "20261123T101500Z", rule: "absent" }, live, true)), "unread", "the conf left not known");
        assertEqual(code(install.undoArgv("/bin/sh", { stamp: "20261123T101500Z", rule: "absent", conf: "absent" }, scratch, true)), "paths", "scratch places live");
        assertEqual(code(install.undoArgv("sh", { stamp: "20261123T101500Z", rule: "absent", conf: "absent" }, live, true)), "arguments", "a relative shell");
        assertEqual(install.backupPath(live, install.confName, "20261123T101500Z", true), "/var/lib/h2s-shell/polkit-backup/polkitd.conf.20261123T101500Z.absent",
                    "a backup's path, for the page");

        // ── The reply ──
        const expected = install.installArgv("/bin/sh", request({ minutes: 15 }), live, true).expected;
        const ran = (stdout, more) => Object.assign({ ok: true, code: 0, stdout, stderr: "", dismissed: false, refused: false, cancelled: false, blocked: "", error: "" }, more ?? {});
        const line = (kind, ruleHash, confHash, stamp, reload) => kind + " " + ruleHash + " " + confHash + " " + stamp + " " + reload + "\n";
        let outcome = install.reply(ran(line("applied", sha(rule), sha(conf15), "20261123T101500Z", "hup")), expected);
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
        const ruleOnly = install.installArgv("/bin/sh", request(), live, true).expected;
        assertEqual(install.reply(ran(line("applied", sha(rule), "absent", "20261123T101500Z", "none")), ruleOnly).ok, true, "the rule alone: no word to polkitd");
        assertEqual(install.reply(ran(line("applied", sha(rule), "absent", "20261123T101500Z", "hup")), ruleOnly).ok, false, "… a word without a change: not this run");
        outcome = install.reply(ran("", { ok: false, code: 141, stderr: line("applied", sha(rule), sha(conf15), "20261123T101500Z", "hup") }), expected);
        assertEqual(outcome.ok + " " + outcome.stamp, "true 20261123T101500Z", "stdout lost, the line on stderr: done");
        assertEqual(install.reply(ran("", { ok: false, code: 1, stderr: line("applied", sha(rule), sha(conf15), "20261123T101500Z", "hup") + "more\n" }), expected).ok, false,
                    "… only as stderr's last line");
        const undoExpected = install.undoArgv("/bin/sh", { stamp: "20261123T101500Z", rule: sha(rule), conf: "absent" }, live, true).expected;
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
