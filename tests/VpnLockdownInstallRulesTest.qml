import QtQuick
import qs.singletons
import qs.singletons.network

// VpnLockdownInstallRules: the states of the files at the install's places, what the page
// offers for them, the root step's words for Install, Remove and Undo (what each writes,
// replaces and refuses), its reply and what a run that did not say it was done left. Pure.
TestCase {
    suiteName: "VpnLockdownInstallRules"

    function run() {
        const rules = VpnLockdownInstallRules;
        const sha = PamEditRules.sha256;
        const show = answer => JSON.stringify(answer);
        const script = "#!/bin/sh\n# h2s-vpn-lockdown — test\nVERSION=4\n";
        const older = "#!/bin/sh\n# h2s-vpn-lockdown — test\nVERSION=3\n";
        const scripts = ["lib\n", "step\n"];
        const live = rules.livePaths;
        const base = "/scratch";
        const paths = { script: base + live.script, rule: base + live.rule, backups: base + live.backups };
        const rule = rules.ruleText("alex", paths.script);
        const request = (current, more) => Object.assign({ user: "alex", script, current, replace: {} }, more ?? {});

        // ── the rule and the script ──
        assertEqual(rule, VpnLockdownRules.lockdownPolkitRule("alex", ['"' + paths.script + '"']), "the rule: the polkit rule for the user and the script's place");
        assert(rule.startsWith(rules.ruleMarker + "\n"), "… behind the shell's marker");
        const longest = rules.scriptStart + "x\nVERSION=4\n";
        assert(rules.validScript(longest + "#".repeat(rules.maxBytes - longest.length)) && !rules.validScript(longest + "#".repeat(rules.maxBytes - longest.length + 1)),
               "scripts: the longest the root step takes, and one byte more");
        assert(rules.validUser("alex") && rules.validUser("_a-1") && !rules.validUser("a b") && !rules.validUser("a\"") && !rules.validUser("-a")
               && !rules.validUser("") && !rules.validUser("a".repeat(33)) && !rules.validUser(null), "users the root step takes: names, nothing to quote");
        assertEqual(rules.ruleText("a\"b", "/x"), "", "… no rule for another");
        assert(rules.validScript(script) && !rules.validScript("#!/bin/bash\n# h2s-vpn-lockdown x\nVERSION=4\n") && !rules.validScript("#!/bin/sh\n# h2s-vpn-lockdown x\n")
               && !rules.validScript(script + "x".repeat(rules.maxBytes)) && !rules.validScript(null), "scripts it takes: the shell's start, a version, within the size");

        // ── states and offers ──
        assertEqual(show(rules.states(request({ script: undefined, rule: undefined }), paths)), show({ script: "absent", rule: "absent" }), "states: none there");
        assertEqual(show(rules.states(request({ script, rule }), paths)), show({ script: "ours", rule: "ours" }), "states: exactly the shell's");
        assertEqual(show(rules.states(request({ script: older, rule: rules.ruleText("bob", paths.script) }), paths)), show({ script: "older", rule: "older" }),
                    "states: the shell's, another version or user");
        assertEqual(show(rules.states(request({ script: "#!/bin/sh\necho mine\n", rule: "// mine\n" }), paths)), show({ script: "changed", rule: "changed" }),
                    "states: not written by the shell");
        assertEqual(show(rules.states(request({ script: null, rule: 3 }), paths)), show({ script: "unknown", rule: "unknown" }), "states: not read");
        assertEqual(show(rules.offer({ script: "absent", rule: "absent" })), show({ install: { label: "Install…", asks: false, replace: {} }, remove: false }), "offer: Install");
        assertEqual(show(rules.offer({ script: "older", rule: "ours" })), show({ install: { label: "Install again…", asks: false, replace: {} }, remove: true }),
                    "offer: Install again, and Remove");
        assertEqual(rules.offer({ script: "absent", rule: "ours" }).install.label, "Install again…", "offer: Install again, the rule there alone");
        assertEqual(show(rules.offer({ script: "ours", rule: "ours" })), show({ install: null, remove: true }), "offer: nothing to install");
        assertEqual(show(rules.offer({ script: "changed", rule: "absent" })),
                    show({ install: { label: "Replace…", asks: true, replace: { script: true, rule: false } }, remove: false }), "offer: Replace, asked, the foreign file only");
        assertEqual(show(rules.offer({ script: "unknown", rule: "ours" })), show({ install: null, remove: false }), "offer: nothing while a file was not read");

        // ── Install ──
        const fresh = rules.installArgv("/bin/sh", request({}), paths, false, scripts);
        assertEqual(fresh.refusal, null, "Install: planned");
        assertEqual(show(fresh.argv), show(["/bin/sh", "-c", "lib\nstep\n", "sh", base, "apply", "write", "absent", sha(script), "write", "absent", sha(rule), "alex", script]),
                    "… the root step's text, the base, both written: the user and the script's text, never the rule's");
        assertEqual(show(fresh.expected), show({ mode: "apply", before: { script: "absent", rule: "absent" }, after: { script: sha(script), rule: sha(rule) } }), "… what it expects");
        const again = rules.installArgv("/bin/sh", request({ script: older, rule }), paths, false, scripts);
        assertEqual(show(again.argv.slice(5)), show(["apply", "write", sha(older), sha(script), "keep", sha(rule), "-", "-", script]),
                    "Install again: the older script replaced, the rule kept (no user handed)");
        assertEqual(rules.installArgv("/bin/sh", request({ script, rule }), paths, false, scripts).refusal.code, "unchanged", "Install: nothing to change — refused");
        assertEqual(rules.installArgv("/bin/sh", request({ script, rule: "// mine\n" }), paths, false, scripts).refusal.code, "changed", "Install: a rule not the shell's — refused");
        assertEqual(rules.installArgv("/bin/sh", request({ script, rule: "// mine\n" }, { replace: { script: true } }), paths, false, scripts).refusal.code, "changed",
                    "… replacing the other file does not replace it");
        assertEqual(show(rules.installArgv("/bin/sh", request({ script, rule: "// mine\n" }, { replace: { rule: true } }), paths, false, scripts).argv.slice(5)),
                    show(["apply", "keep", sha(script), "-", "write", sha("// mine\n"), sha(rule), "alex", "-"]), "… replaced when named");
        assertEqual(rules.installArgv("/bin/sh", request({ script, rule: "// mine\n" }, { replace: { rule: "yes" } }), paths, false, scripts).refusal.code, "changed",
                    "… named in so many words only");
        const mine = "#!/bin/sh\necho mine\n";
        assertEqual(rules.installArgv("/bin/sh", request({ script: mine, rule }), paths, false, scripts).refusal.code, "changed", "Install: a script not the shell's — refused");
        assertEqual(rules.installArgv("/bin/sh", request({ script: mine, rule }, { replace: { rule: true } }), paths, false, scripts).refusal.code, "changed",
                    "… replacing the rule does not replace it");
        assertEqual(show(rules.installArgv("/bin/sh", request({ script: mine, rule }, { replace: { script: true } }), paths, false, scripts).argv.slice(5)),
                    show(["apply", "write", sha(mine), sha(script), "keep", sha(rule), "-", "-", script]), "… replaced when named");
        assertEqual(rules.installArgv("/bin/sh", request({ script: null, rule }), paths, false, scripts).refusal.code, "unread", "Install: a file not read — refused");
        assertEqual(rules.installArgv("/bin/sh", request({}, { user: "a b" }), paths, false, scripts).refusal.code, "facts", "Install: a user the rule cannot name — refused");
        assertEqual(rules.installArgv("/bin/sh", request({}, { script: "echo\n" }), paths, false, scripts).refusal.code, "script", "Install: not the shell's script — refused");
        assertEqual(rules.installArgv("/bin/sh", request({}), paths, false, ["lib\n", ""]).refusal.code, "script", "Install: a root step file not read — refused");
        assertEqual(rules.installArgv("sh", request({}), paths, false, scripts).refusal.code, "arguments", "Install: a shell not by its path — refused");
        assertEqual(rules.installArgv("/bin/sh", request({}), paths, true, scripts).refusal.code, "paths", "Install: the system's runner, scratch places — refused");
        assertEqual(rules.installArgv("/bin/sh", request({}), live, false, scripts).refusal.code, "paths", "Install: a stand-in, the system's places — refused");
        assertEqual(rules.installArgv("/bin/sh", request({}), live, true, scripts).argv[4], "", "Install: the system's runner, the system's places — base \"\"");
        assertEqual(rules.installArgv("/bin/sh", request({}), { script: paths.script, rule: "/etc/x.rules", backups: paths.backups }, false, scripts).refusal.code, "paths",
                    "Install: places not all under one base — refused");

        // ── Remove ──
        assertEqual(show(rules.removeArgv("/bin/sh", request({ script: older, rule }), paths, false, scripts).argv.slice(5)),
                    show(["apply", "remove", sha(older), "-", "remove", sha(rule), "-", "-", "-"]), "Remove: the shell's files go");
        assertEqual(show(rules.removeArgv("/bin/sh", request({ script, rule: "// mine\n" }, { replace: { rule: true } }), paths, false, scripts).argv.slice(5)),
                    show(["apply", "remove", sha(script), "-", "keep", sha("// mine\n"), "-", "-", "-"]), "Remove: a rule not the shell's stays, even asked to replace it");
        assertEqual(rules.removeArgv("/bin/sh", request({ script: "#!/bin/sh\n", rule: undefined }), paths, false, scripts).refusal.code, "changed", "Remove: only another's file there — refused");
        assertEqual(rules.removeArgv("/bin/sh", request({}), paths, false, scripts).refusal.code, "unchanged", "Remove: nothing there — refused");
        assertEqual(rules.removeArgv("/bin/sh", request({ script, rule: null }), paths, false, scripts).refusal.code, "unread", "Remove: a file not read — refused");

        assertEqual(rules.removeArgv("sh", request({ script, rule }), paths, false, scripts).refusal.code, "arguments", "Remove: a shell not by its path — refused");
        assertEqual(rules.removeArgv("/bin/sh", request({ script, rule }), live, false, scripts).refusal.code, "paths", "Remove: a stand-in, the system's places — refused");

        // ── Undo ──
        const stamp = "20261124T101500Z";
        assertEqual(show(rules.undoArgv("/bin/sh", { stamp, script: sha(script), rule: "absent" }, paths, false, scripts).argv.slice(5)),
                    show(["undo", stamp, sha(script), "absent"]), "Undo: the stamp and what that run left");
        assertEqual(rules.undoArgv("/bin/sh", { stamp: "../x", script: "absent", rule: "absent" }, paths, false, scripts).refusal.code, "backupName", "Undo: not a stamp — refused");
        assertEqual(rules.undoArgv("/bin/sh", { stamp, script: "x", rule: "absent" }, paths, false, scripts).refusal.code, "unread", "Undo: not a sha256 — refused");
        assertEqual(rules.undoArgv("sh", { stamp, script: "absent", rule: "absent" }, paths, false, scripts).refusal.code, "arguments", "Undo: a shell not by its path — refused");
        assert(rules.validStamp(stamp + "-3") && !rules.validStamp(stamp + "-0") && !rules.validStamp(stamp + "x"), "stamps: the time, a counter 1 to 9");

        // ── the reply ──
        const said = "applied " + sha(script) + " " + sha(rule) + " " + stamp;
        assertEqual(show(rules.reply({ ok: true, stdout: said + "\n", stderr: said + "\n" }, fresh.expected)),
                    show({ ok: true, quiet: false, kind: "applied", script: sha(script), rule: sha(rule), stamp, refused: "", error: "", files: "done" }), "reply: done");
        assert(rules.reply({ ok: false, stdout: "", stderr: said + "\n" }, fresh.expected).ok, "reply: the line on stderr counts, whatever the exit");
        assert(!rules.reply({ ok: true, stdout: "applied absent " + sha(rule) + " " + stamp + "\n" }, fresh.expected).ok, "reply: other hashes — not this run");
        assert(!rules.reply({ ok: true, stdout: "restored " + sha(script) + " " + sha(rule) + " " + stamp + "\n" }, fresh.expected).ok, "reply: another kind — not this run");
        assert(!rules.reply({ ok: true, stdout: "applied " + sha(script) + " " + sha(rule) + " now\n" }, fresh.expected).ok, "reply: not a stamp — not this run");
        assert(rules.reply({ ok: true, stdout: "restored absent absent " + stamp + "\n" }, { mode: "undo", before: {}, after: null }).ok, "reply: Undo, whatever it restored");
        assertEqual(show(rules.reply({ ok: false, code: 3, stderr: "refused changed\n" }, fresh.expected)).indexOf('"refused":"changed"') > 0, true, "reply: a refusal by its code");
        assertEqual(rules.reply({ ok: false, code: 3, stderr: "refused changed\n" }, fresh.expected).error, rules.texts.changed, "… its text");
        assertEqual(rules.reply({ ok: false, code: 126, dismissed: true }, fresh.expected).quiet, true, "reply: a prompt dismissed — quiet");

        // ── after a run that did not say ──
        const before = { script: { absent: true }, rule: { absent: true } };
        assertEqual(rules.afterFailure(before, fresh.expected), "unchanged", "after: both as before");
        assertEqual(rules.afterFailure({ script: { text: script }, rule: { text: rule } }, fresh.expected), "done", "after: both as the run was to leave them");
        assertEqual(rules.afterFailure({ script: { text: script }, rule: { absent: true } }, fresh.expected), "other", "after: neither");
        assertEqual(rules.afterFailure({ script: { unreadable: true }, rule: { absent: true } }, fresh.expected), "unknown", "after: not read");
    }
}
