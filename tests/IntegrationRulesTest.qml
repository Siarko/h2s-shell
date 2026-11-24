import QtQuick
import qs.singletons

// IntegrationRules: an integration's table read as capabilities (a kind not defined, not
// named or named wrongly is unavailable with a reason; only an applied kind is tried or
// undone), what a valid answer is, the feature's details, the plan per mode (the sign-in
// rules' files and options included), when apply and undo may start, and what is in force
// from a file read
TestCase {
    suiteName: "IntegrationRules"

    function run() {
        const rules = IntegrationRules;
        const kind = "sleep.hibernateDelay";
        const show = answer => JSON.stringify(answer);
        const unavailable = reason => show({ mode: "unavailable", trial: false, undo: false, inForce: false, anyway: false, reason, known: true });

        assertEqual(show(rules.kinds), show(["sleep.hibernateDelay", "network.connectivityUri", "pam.rules"]), "the change kinds the shell defines");
        assertEqual(show(rules.modes), show(["apply", "declare", "copy", "unavailable"]), "the modes");

        // ── capability ──
        assertEqual(show(rules.capability({ [kind]: { mode: "apply", trial: true, undo: true, inForce: true } }, kind)),
                    show({ mode: "apply", trial: true, undo: true, inForce: true, anyway: false, reason: "", known: true }), "applied, tried, undone, read");
        assertEqual(show(rules.capability({ [kind]: { mode: "apply" } }, kind)), show({ mode: "apply", trial: false, undo: false, inForce: false, anyway: false, reason: "", known: true }),
                    "… each only when said");
        assertEqual(show(rules.capability({ [kind]: { mode: "apply", trial: 1, undo: "yes", inForce: {} } }, kind)),
                    show({ mode: "apply", trial: false, undo: false, inForce: false, anyway: false, reason: "", known: true }), "… said as true only");
        assertEqual(show(rules.capability({ [kind]: { mode: "copy", trial: true, undo: true, inForce: true } }, kind)),
                    show({ mode: "copy", trial: false, undo: false, inForce: true, anyway: false, reason: "", known: true }), "copied: never tried or undone by the shell");
        assertEqual(show(rules.capability({ [kind]: { mode: "declare", undo: true } }, kind)).indexOf('"undo":false') > 0, true, "… nor declared (not yet)");
        assertEqual(rules.capability({ [kind]: { mode: "copy", anyway: true } }, kind).anyway, true, "copied: written anyway when the table says so");
        assertEqual(rules.capability({ [kind]: { mode: "copy", anyway: 1 } }, kind).anyway, false, "… said as true only");
        assertEqual(rules.capability({ [kind]: { mode: "apply", anyway: true } }, kind).anyway, false, "… never where applied (it is applied anyway)");
        assertEqual(show(rules.capability({}, kind)), unavailable(rules.unsupported), "not named: unavailable, not supported");
        assertEqual(show(rules.capability({ [kind]: { mode: "unavailable", reason: "No swap." } }, kind)), unavailable("No swap."), "unavailable with its own reason");
        assertEqual(show(rules.capability({ [kind]: { mode: "unavailable" } }, kind)), unavailable(rules.unsupported), "… or the general one");
        assertEqual(show(rules.capability({ [kind]: { mode: "write" } }, kind)), unavailable(rules.unsupported), "a mode that is none: unavailable");
        assertEqual(show(rules.capability({ "no.kind": { mode: "apply" } }, "no.kind")), unavailable(rules.unsupported), "a kind the shell does not define: unavailable");
        assertEqual(show(rules.capability(null, kind)), unavailable(rules.unsupported), "no table: unavailable");
        assertEqual(show(rules.capability({}, "toString")), unavailable(rules.unsupported), "a name every object has: unavailable");
        assertEqual(show(rules.unknownCapability()), show({ mode: "unavailable", trial: false, undo: false, inForce: false, anyway: false, reason: rules.unknown, known: false }),
                    "while the distribution is not known: unavailable, not known");

        // ── valid ──
        for (const answer of [rules.unknownCapability(), rules.capability({}, kind), rules.capability({ [kind]: { mode: "apply", trial: true, undo: true } }, kind),
                              rules.capability({ [kind]: { mode: "copy" } }, kind)])
            assert(rules.valid(answer), "valid: " + show(answer));
        const good = { mode: "apply", trial: false, undo: true, inForce: true, anyway: false, reason: "", known: true };
        for (const [why, bad] of [["no mode", Object.assign({}, good, { mode: "x" })], ["no mode, nothing else wrong", Object.assign({}, good, { mode: "x", undo: false })], ["unavailable without a reason", { mode: "unavailable", trial: false, undo: false, inForce: false, anyway: false, reason: "", known: true }],
                                  ["unavailable but undone", { mode: "unavailable", trial: false, undo: true, inForce: false, anyway: false, reason: "r", known: true }],
                                  ["unavailable but read", { mode: "unavailable", trial: false, undo: false, inForce: true, anyway: false, reason: "r", known: true }],
                                  ["unavailable but tried", { mode: "unavailable", trial: true, undo: false, inForce: false, anyway: false, reason: "r", known: true }],
                                  ["copied but undone", Object.assign({}, good, { mode: "copy" })], ["copied but tried", Object.assign({}, good, { mode: "copy", undo: false, trial: true })],
                                  ["offered with a reason", Object.assign({}, good, { reason: "r" })], ["offered while not known", Object.assign({}, good, { known: false })],
                                  ["a flag not a boolean", Object.assign({}, good, { undo: 1 })], ["no reason", Object.assign({}, good, { reason: undefined })],
                                  ["applied and written anyway", Object.assign({}, good, { anyway: true })],
                                  ["unavailable but written anyway", { mode: "unavailable", trial: false, undo: false, inForce: false, anyway: true, reason: "r", known: true }],
                                  ["no anyway", Object.assign({}, good, { anyway: undefined })],
                                  ["nothing", null]])
            assert(!rules.valid(bad), "not valid: " + why);
        assert(rules.valid(Object.assign({}, good, { mode: "copy", undo: false, anyway: true })), "valid: copied, written anyway when asked");

        // ── values and plans ──
        assert(rules.validValue(kind, 60) && rules.validValue(kind, 86400), "the delay: a minute to a day");
        for (const wrong of [59, 86401, 600.5, "600", null])
            assert(!rules.validValue(kind, wrong), "… not " + show(wrong));
        assert(!rules.validValue("no.kind", 600), "a kind not defined takes nothing");
        assertEqual(rules.textOf(kind, 600), HibernateRules.dropInText(600), "the drop-in's text");
        assertEqual(rules.textOf("no.kind", 600), "", "… none for another kind");
        const applied = { [kind]: { mode: "apply" } };
        assertEqual(show(rules.plan(applied, kind, 600)), show({ preview: { files: [{ path: "/etc/systemd/sleep.conf.d/h2s-shell.conf", text: HibernateRules.dropInText(600) }],
                                                                     backups: "/var/lib/h2s-shell/backup/" + kind }, refusal: null }),
                    "applied: the file and its text, and where its backups go");
        const copied = { [kind]: { mode: "copy", option: HibernateRules.nixosOption, hint: "Set it there." } };
        assertEqual(show(rules.plan(copied, kind, 600)), show({ preview: { option: HibernateRules.nixosOption, snippet: HibernateRules.nixosOption + " = 600;",
                                                                           hint: "Set it there." }, refusal: null }),
                    "copied: the option, its line, and the integration's hint");
        assertEqual(rules.plan({ [kind]: { mode: "copy", option: "x" } }, kind, 600).preview.hint, "", "… no hint given: none");
        assertEqual(rules.plan(applied, kind, 30).refusal?.code, "value", "a value it does not take: refused");
        assertEqual(show(rules.plan({}, kind, 600)), show({ preview: null, refusal: { code: "unavailable", text: rules.unsupported } }), "unavailable: refused with the reason");

        // ── when apply and undo may start ──
        assertEqual(rules.applyRefusal(rules.capability(applied, kind)), null, "apply: where applied");
        assertEqual(rules.applyRefusal(rules.capability(copied, kind)).code, "mode", "… not where copied");
        assertEqual(rules.applyRefusal(rules.capability(copied, kind), true).code, "mode", "… nor asked anyway where the table does not say so");
        const anyway = { [kind]: { mode: "copy", anyway: true } };
        assertEqual(rules.applyRefusal(rules.capability(anyway, kind), true), null, "… where copied and written anyway, asked so");
        assertEqual(rules.applyRefusal(rules.capability(anyway, kind)).code, "mode", "… not unasked");
        assertEqual(rules.undoRefusal(rules.capability(anyway, kind)).code, "mode", "… and no Undo of it");
        assertEqual(show(rules.applyRefusal(rules.capability({}, kind))), show({ code: "unavailable", text: rules.unsupported }), "… unavailable, with the reason");
        assertEqual(show(rules.applyRefusal(rules.unknownCapability())), show({ code: "unknown", text: rules.unknown }), "… not known");
        assertEqual(rules.undoRefusal(rules.capability({ [kind]: { mode: "apply", undo: true } }, kind)), null, "undo: where applied and undone");
        assertEqual(rules.undoRefusal(rules.capability(applied, kind)).code, "noUndo", "… not without Undo");
        assertEqual(rules.undoRefusal(rules.capability(copied, kind)).code, "mode", "… not where copied");
        assertEqual(rules.undoRefusal(rules.unknownCapability()).code, "unknown", "… not while not known");
        assertEqual(rules.refusal("value").text, "Not a value for this setting.", "plain reasons");
        assertEqual(rules.refusal("x").text, rules.texts.value, "… an unknown code: the value's");

        // ── what is in force ──
        const own = EtcFilesRules.inForce({ text: HibernateRules.dropInText(600) }, kind);
        const merged = (...files) => files.map(([path, body]) => "# " + path + "\n" + body).join("\n");
        const ownPath = "/etc/systemd/sleep.conf.d/h2s-shell.conf";
        assertEqual(show(rules.inForceCommand(kind, "/s")), show(["systemd-analyze", "--no-pager", "cat-config", "systemd/sleep.conf"]),
                    "the delay as systemd merges sleep.conf and its drop-ins");
        assertEqual(rules.inForceCommand("no.kind", "/s"), null, "… none for another kind");
        assertEqual(show(rules.inForceOf(kind, merged(["/usr/lib/systemd/sleep.conf", "[Sleep]\n#HibernateDelaySec=\n"], [ownPath, "[Sleep]\nHibernateDelaySec=600\n"]), own)),
                    show({ state: "set", value: 600, from: ownPath, elsewhere: "", file: own, afterOwn: false, shadowed: null }), "set by the shell's own drop-in: not elsewhere");
        assertEqual(JSON.stringify(rules.inForceOf(kind, merged(["/etc/systemd/sleep.conf", "[Sleep]\nHibernateDelaySec=2h\n"], [ownPath, "[Sleep]\nHibernateDelaySec=600\n"]), own).shadowed),
                    JSON.stringify({ from: "/etc/systemd/sleep.conf", value: 7200 }), "the shell's drop-in in force: the setting it overrides, shown");
        assertEqual(JSON.stringify(rules.inForceOf(kind, merged(["/etc/systemd/sleep.conf", "[Sleep]\nHibernateDelaySec=\n"], [ownPath, "[Sleep]\nHibernateDelaySec=600\n"]), own).shadowed),
                    JSON.stringify({ from: "/etc/systemd/sleep.conf", value: null }), "… systemd's default put back there: that too");
        assertEqual(rules.inForceOf(kind, merged(["/etc/systemd/sleep.conf", "[Sleep]\nHibernateDelaySec=2h\n"], [ownPath, "[Sleep]\nHibernateDelaySec=600\n"],
                                                 ["/etc/systemd/sleep.conf.d/zz.conf", "[Sleep]\nHibernateDelaySec=1h\n"]), own).shadowed, null, "… none when another file wins");
        assertEqual(show(rules.inForceOf(kind, merged(["/etc/systemd/sleep.conf", "[Sleep]\nHibernateDelaySec=2h\n"]), own)),
                    show({ state: "set", value: 7200, from: "/etc/systemd/sleep.conf", elsewhere: "/etc/systemd/sleep.conf", file: own, afterOwn: false, shadowed: null }),
                    "set by another file read before the shell's: in force, set elsewhere (shown, overridden only asked)");
        assertEqual(show(rules.inForceOf(kind, merged([ownPath, "[Sleep]\nHibernateDelaySec=600\n"], ["/etc/systemd/sleep.conf.d/zz.conf", "[Sleep]\nHibernateDelaySec=\n"]), own)),
                    show({ state: "default", value: null, from: "/etc/systemd/sleep.conf.d/zz.conf", elsewhere: "/etc/systemd/sleep.conf.d/zz.conf", file: own, afterOwn: true, shadowed: null }),
                    "systemd's default put back by a later file: that file's setting, read after the shell's");
        assertEqual(show(rules.inForceOf(kind, merged(["/usr/lib/systemd/sleep.conf", "[Sleep]\n#HibernateDelaySec=\n"]), null)),
                    show({ state: "default", value: null, from: "", elsewhere: "", file: null, afterOwn: false, shadowed: null }), "no file sets it: systemd's default, nothing elsewhere; no file of the shell's");
        assertEqual(show(rules.inForceOf(kind, merged(["/etc/systemd/sleep.conf", "[Sleep]\nHibernateDelaySec=soon\n"]), own)),
                    show({ state: "unknown", value: null, from: "", elsewhere: "", file: own, afterOwn: false, shadowed: null }), "a value not understood: unknown");
        assertEqual(show(rules.inForceOf(kind, null, own)), show({ state: "unknown", value: null, from: "", elsewhere: "", file: own, afterOwn: false, shadowed: null }), "not read: unknown, the shell's file still told");
        assertEqual(rules.inForceOf(kind, null, undefined).file, null, "no file of the shell's handed: null");
        assertEqual(rules.inForceOf(kind, null, "text").file, null, "… nor for one that is no answer");
        assertEqual(rules.inForceOf("no.kind", merged([ownPath, "[Sleep]\nHibernateDelaySec=600\n"]), null).state, "unknown", "another kind: unknown");
        assertEqual(show(rules.inForceUnknown()), show({ state: "unknown", value: null, from: "", elsewhere: "", file: null, afterOwn: false, shadowed: null }), "nothing told");
        for (const answer of [rules.inForceUnknown(), rules.inForceOf(kind, merged(["/etc/systemd/sleep.conf", "[Sleep]\nHibernateDelaySec=2h\n"]), own)])
            assert(rules.validInForce(answer), "a valid answer: " + show(answer));
        const set = { state: "set", value: 1, from: "/a", elsewhere: "/a", file: null, afterOwn: true, shadowed: null };
        for (const [why, bad] of [["no state", Object.assign({}, set, { state: "absent" })], ["set without a value", Object.assign({}, set, { value: null })],
                                  ["a value by default", Object.assign({}, set, { state: "default" })], ["elsewhere not where it is from", Object.assign({}, set, { elsewhere: "/b" })],
                                  ["no from", Object.assign({}, set, { from: undefined })], ["a file that is none", Object.assign({}, set, { file: { state: "x" } })],
                                  ["no elsewhere", Object.assign({}, set, { elsewhere: null })], ["nothing", null],
                                  ["no afterOwn", Object.assign({}, set, { afterOwn: undefined })],
                                  ["overridden while set elsewhere", Object.assign({}, set, { afterOwn: false, shadowed: { from: "/b", value: 1 } })],
                                  ["overridden, from nowhere", { state: "set", value: 1, from: "/a", elsewhere: "", file: null, afterOwn: false, shadowed: { from: "", value: 1 } }],
                                  ["overridden, no value", { state: "set", value: 1, from: "/a", elsewhere: "", file: null, afterOwn: false, shadowed: { from: "/b" } }],
                                  ["overridden, from not a path", { state: "set", value: 1, from: "/a", elsewhere: "", file: null, afterOwn: false, shadowed: { from: 5, value: 1 } }],
                                  ["overridden, not an object", { state: "set", value: 1, from: "/a", elsewhere: "", file: null, afterOwn: false, shadowed: "x" }],
                                  ["read after the shell's with nothing elsewhere", Object.assign({}, set, { from: "", elsewhere: "" })],
                                  ["a state that is none, nothing else wrong", { state: "absent", value: null, from: "", elsewhere: "", file: null, afterOwn: false, shadowed: null }],
                                  ["no from, nothing else wrong", { state: "default", value: null, from: undefined, elsewhere: "", file: null, afterOwn: false, shadowed: null }]])
            assert(!rules.validInForce(bad), "not valid: " + why);
        // ── the connectivity check's address ──
        const uri = "network.connectivityUri";
        const address = "http://nmcheck.gnome.org/check_network_status.txt";
        assert(rules.validValue(uri, address) && rules.validValue(uri, "https://a.b:8443/x"), "the address: http(s)");
        assert(rules.validValue(uri, ""), "… or none (the shell's file removed)");
        for (const wrong of ["ftp://a/b", "http://a/b c", 5, null])
            assert(!rules.validValue(uri, wrong), "… not " + show(wrong));
        assertEqual(rules.textOf(uri, address), ConnectivityRules.text(address), "its file's text");
        assertEqual(rules.textOf(uri, ""), "", "… none for no address");
        const ownUri = "/etc/NetworkManager/conf.d/90-h2s-connectivity.conf";
        assertEqual(show(rules.plan({ [uri]: { mode: "apply" } }, uri, address)), show({ preview: { files: [{ path: ownUri, text: ConnectivityRules.text(address) }],
                                                                                           backups: "/var/lib/h2s-shell/backup/" + uri }, refusal: null }),
                    "applied: the shell's conf.d file and its text");
        assertEqual(rules.plan({ [uri]: { mode: "copy", option: "o.p" } }, uri, address).preview.snippet, "o.p = \"" + address + "\";", "copied: the option set to the quoted address");
        assertEqual(rules.plan({ [uri]: { mode: "copy", option: "o.p" } }, uri, "").preview.snippet, "", "… nothing to copy for no address");
        assertEqual(show(rules.inForceCommand(uri, "/s")), show(["/s/scripts/nm-config-files.sh"]), "read from NetworkManager's files, in its order");
        const nm = (...files) => files.map(([path, body]) => "file\t" + path + "\ttext\n" + body.map(line => "|" + line + "\n").join("") + "end\t" + path + "\n").join("") + "done\n";
        const ownFile = EtcFilesRules.inForce({ text: ConnectivityRules.text(address) }, uri);
        const lib = "/usr/lib/NetworkManager/conf.d/20-connectivity.conf";
        assertEqual(show(rules.inForceOf(uri, nm([lib, ["[connectivity]", "uri=http://ping.archlinux.org/nm-check.txt"]]), ownFile)),
                    show({ state: "default", value: null, from: lib, elsewhere: "", file: ownFile, afterOwn: false, shadowed: null }),
                    "set only by the distribution's package: its default, not elsewhere");
        assertEqual(show(rules.inForceOf(uri, nm([lib, ["[connectivity]", "uri=http://a/"]], [ownUri, ["[connectivity]", "uri=" + address]]), ownFile)),
                    show({ state: "set", value: address, from: ownUri, elsewhere: "", file: ownFile, afterOwn: false, shadowed: null }), "set by the shell's own file");
        const main = "/etc/NetworkManager/NetworkManager.conf";
        assertEqual(show(rules.inForceOf(uri, nm([main, ["[connectivity]", "uri=http://mine/"]]), ownFile)),
                    show({ state: "set", value: "http://mine/", from: main, elsewhere: main, file: ownFile, afterOwn: false, shadowed: null }),
                    "set in NetworkManager.conf: elsewhere, read before the shell's file");
        const later = "/etc/NetworkManager/conf.d/99-mine.conf";
        assertEqual(show(rules.inForceOf(uri, nm([ownUri, ["[connectivity]", "uri=" + address]], [later, ["[connectivity]", "uri="]]), ownFile)),
                    show({ state: "set", value: "", from: later, elsewhere: later, file: ownFile, afterOwn: true, shadowed: null }),
                    "emptied by a later conf.d file: elsewhere, read after the shell's");
        assertEqual(show(rules.inForceOf(uri, "file\t" + main + "\tunreadable\ndone\n", ownFile)),
                    show({ state: "unknown", value: null, from: "", elsewhere: "", file: ownFile, afterOwn: false, shadowed: null }), "a file not read: unknown");
        assertEqual(JSON.stringify(rules.inForceOf(uri, nm([main, ["[connectivity]", "uri=http://mine/"]], [ownUri, ["[connectivity]", "uri=" + address]]), ownFile).shadowed),
                    JSON.stringify({ from: main, value: "http://mine/" }), "the shell's file in force: the user's address it overrides, shown");
        assert(rules.validInForce(rules.inForceOf(uri, nm([main, ["[connectivity]", "uri=http://mine/"]], [ownUri, ["[connectivity]", "uri=" + address]]), ownFile)),
               "… a valid answer");
        for (const answer of [rules.inForceOf(uri, nm([later, ["[connectivity]", "uri="]]), null), rules.inForceOf(uri, nm([lib, ["[connectivity]", "uri=http://a/"]]), null)])
            assert(rules.validInForce(answer), "a valid answer: " + show(answer));

        // ── details ──
        const pam = "pam.rules";
        assertEqual(show(rules.details({ [pam]: { mode: "copy", texts: { where: "w", count: 3 }, facts: { bareModules: "libpam" } } }, pam)),
                    show({ texts: { where: "w" }, facts: { bareModules: "libpam" } }), "details: the entry's words (strings only) and facts");
        assertEqual(show(rules.details({ [pam]: { mode: "apply" } }, pam)), show({ texts: {}, facts: {} }), "… none named: none");
        assertEqual(show(rules.details({ [pam]: { mode: "unavailable", texts: { where: "w" }, facts: { a: 1 } } }, pam)), show({ texts: {}, facts: {} }),
                    "… unavailable: none");
        assertEqual(show(rules.details({ [pam]: { mode: "copy", texts: ["w"], facts: [1] } }, pam)), show({ texts: {}, facts: {} }), "… lists are neither");
        const entry = { mode: "copy", option: "programs.h2s-shell.pam", facts: { bareModules: "libpam" } };
        const detailsFacts = rules.details({ [pam]: entry }, pam).facts;
        detailsFacts.bareModules = "x";
        assertEqual(entry.facts.bareModules, "libpam", "… a copy: the table is not changed through it");

        // ── the sign-in rules' plan ──
        const fixed = PamRuleRules.fixedRow();
        const ldap = { id: "r1", method: "raw", control: "", details: { text: "auth sufficient pam_ldap.so" } };
        const vendor = "#%PAM-1.0\n\nauth       include      system-auth\naccount    include      system-auth\n";
        const sudoText = "#%PAM-1.0\nauth\t\tinclude\t\tsystem-auth\naccount\t\tinclude\t\tsystem-auth\n";
        const pamFacts = (service, more) => Object.assign({ service, writes: true, fingerprint: "absent", securityKey: "absent", moduleDirectories: ["/usr/lib/security/"],
                                                             otherService: [fixed], vendorText: vendor }, more ?? {});
        const value = (rows, more) => ({ split: false, "sudo": { rows, facts: pamFacts("sudo", more), currentText: sudoText },
                                         "polkit-1": { rows, facts: pamFacts("polkit-1", more), currentText: null } });
        assert(rules.validValue(pam, value([fixed])), "validValue: the editor's lists");
        for (const bad of [null, "x", { split: 1, "sudo": {}, "polkit-1": {} }, Object.assign(value([fixed]), { "polkit-1": { rows: "r", facts: {} } }),
                           Object.assign(value([fixed]), { "sudo": { rows: [], facts: null } })])
            assert(!rules.validValue(pam, bad), "… not: " + show(bad));
        const pamApplied = rules.plan({ [pam]: { mode: "apply", trial: true, undo: true } }, pam, value([fixed]));
        assertEqual(pamApplied.preview.files.map(file => file.path).join(" ") + " | " + pamApplied.preview.backups,
                    "/etc/pam.d/sudo /etc/pam.d/polkit-1 | /var/lib/h2s-shell/pam-backup", "plan, applied: both services' files, the PAM backups");
        assertEqual(pamApplied.preview.files[0].text, PamEditRules.build(sudoText, [fixed], pamFacts("sudo")).text, "… sudo's file as PamEditRules builds it");
        assertEqual(pamApplied.preview.files[1].text, "", "… no polkit-1 of the shell's: polkit's own file in force (removed)");
        assertEqual(rules.plan({ [pam]: { mode: "apply" } }, pam, value([ldap, fixed], { bareModules: "libpam" })).preview.files.map(file => file.text).join(","),
                    ",", "… rows a check refuses: no files (null)");
        assertEqual(rules.plan({ [kind]: { mode: "apply" } }, kind, 600).preview.backups, "/var/lib/h2s-shell/backup/" + kind, "… an EtcFiles kind: its backups' folder");
        const pamCopied = rules.plan({ [pam]: entry }, pam, value([fixed], { bareModules: "libpam" }));
        assertEqual(pamCopied.preview.snippet, PamEditRules.optionsSnippet("programs.h2s-shell.pam", [fixed], false, pamFacts("sudo", { bareModules: "libpam" })).text,
                    "plan, copied: the module's options under the integration's option");
        assert(pamCopied.preview.snippet.startsWith("programs.h2s-shell.pam = {\n  rules = ["), "… one list for both");
        const splitValue = Object.assign(value([fixed], { bareModules: "libpam" }), { split: true });
        splitValue["polkit-1"] = { rows: [ldap, fixed], facts: pamFacts("polkit-1", { bareModules: "libpam" }), currentText: null };
        assertEqual(rules.plan({ [pam]: entry }, pam, splitValue).preview.snippet, "", "… a list a check refuses (a bare module libpam would not find): nothing to copy");
        splitValue["polkit-1"].rows = [fixed];
        assert(rules.plan({ [pam]: entry }, pam, splitValue).preview.snippet.includes("polkit.rules = ["), "… split: one list per service");
        assertEqual(rules.plan({ [pam]: entry }, pam, "x").refusal.code, "value", "… not the editor's lists: refused");
    }
}
