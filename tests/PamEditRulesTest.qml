import QtQuick
import qs.singletons

// PamEditRules: rows to the Arch files and back, on fixture texts — sudo with and without
// pam_faillock in system-auth, our polkit-1 over the vendor file, the closing lines, round
// trips (every text parses back through PamStackRules.stack to the same auth lines; adding
// then removing gives the original bytes), a hand-made file taken in, changed-by-hand
// detection, the NixOS snippets
TestCase {
    suiteName: "PamEditRules"

    function run() {
        const edit = PamEditRules;
        const rules = PamRuleRules;
        const row = (id, method, control, details) => ({ id, method, control: control ?? "sufficient", details: details ?? {} });
        const fingerprint = (id, control) => row(id, "fingerprint", control, { timeout: 10, tries: 3 });
        const key = (id, control, pin) => row(id, "securityKey", control, { pin: pin === true, cue: true });
        const password = (id, control, counted) => row(id, "password", control, { counted: counted === true });
        const raw = (id, text) => ({ id, method: "raw", control: "", details: { text } });
        const fixed = rules.fixedRow();

        const archSystemAuth = "#%PAM-1.0\n\n"
            + "auth       required                    pam_faillock.so      preauth\n"
            + "-auth      [success=2 default=ignore]  pam_systemd_home.so\n"
            + "auth       [success=1 default=bad]     pam_unix.so          try_first_pass nullok\n"
            + "auth       [default=die]               pam_faillock.so      authfail\n"
            + "auth       optional                    pam_permit.so\n"
            + "auth       required                    pam_env.so\n"
            + "auth       required                    pam_faillock.so      authsucc\n"
            + "account    required                    pam_unix.so\n";
        const plainSystemAuth = "auth required pam_unix.so try_first_pass nullok\nauth optional pam_permit.so\n";
        const archSudo = "#%PAM-1.0\nauth\t\tinclude\t\tsystem-auth\naccount\t\tinclude\t\tsystem-auth\nsession\t\tinclude\t\tsystem-auth\n";
        const vendorPolkit = "#%PAM-1.0\n\nauth       include      system-auth\naccount    include      system-auth\n"
            + "password   include      system-auth\nsession    include      system-auth\n";
        const files = systemAuth => ({ "/etc/pam.d/system-auth": systemAuth, "/usr/lib/pam.d/polkit-1": vendorPolkit });
        const facts = more => Object.assign({ system: "arch", service: "sudo", fingerprint: "ready", securityKey: "ready",
                                              faillockPresent: true, faillock: { deny: 3, failInterval: 900, unlockTime: 600 },
                                              otherService: [password("o1"), rules.fixedRow()], vendorText: vendorPolkit }, more ?? {});
        const polkit = more => facts(Object.assign({ service: "polkit-1" }, more ?? {}));
        const fields = line => JSON.stringify([line.optional, line.control, line.module, line.args]);
        const pathOf = service => service === "sudo" ? "/etc/pam.d/sudo" : "/etc/pam.d/polkit-1";
        const codes = result => rules.codes(result);
        const that = this;

        // rows → text → (stack, rows); the text's auth lines are our lines, then the file's
        // own as before. Returns the text.
        const roundTrip = (original, list, known, systemAuth, label) => {
            const service = known.service;
            const built = edit.build(original, list, known);
            that.assert(built.ok, label + ": built");
            if (!built.ok) {
                console.error("    refused: " + JSON.stringify(built.refusals));
                return null;
            }
            const before = Object.assign({}, files(systemAuth));
            // What the file holds without our lines: sudo's text as handed in, polkit's vendor file
            if (service === "sudo")
                before[pathOf(service)] = original;
            const after = Object.assign({}, files(systemAuth), { [pathOf(service)]: built.text });
            const read = PamStackRules.stack(service, after);
            const expected = edit.blockLines(list, known).map(text => fields(PamStackRules.parseLine(text.replace(/#.*$/, ""))))
                .concat(PamStackRules.stack(service, before).lines.map(fields));
            that.assert(read.known, label + ": the text parses");
            that.assertEqual(read.lines.map(fields).join("\n"), expected.join("\n"), label + ": parses back to the same auth lines");
            that.assert(rules.sameRows(edit.rows(built.text, service, known), list), label + ": rows → text → rows");
            that.assertEqual(edit.changes(built.text, service).changed, false, label + ": not changed by hand");
            return built.text;
        };

        // --- sha256 ---
        assertEqual(edit.sha256(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256 of nothing");
        assertEqual(edit.sha256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256 of abc");
        assertEqual(edit.sha256("zażółć 🔑"), "7259fff32bcfe68e7eb6bbba674fa226e6f654069cf62ba3c16f290b32591fa7", "… of UTF-8 text");
        assertEqual(edit.sha256("a".repeat(1000)), "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3", "… over several blocks");

        // --- how rows are written ---
        assertEqual(edit.rowLines(fingerprint("r1")).join("|"), "-auth sufficient pam_fprintd.so timeout=10 max-tries=3", "a sufficient reader: -auth");
        assertEqual(edit.rowLines(row("r1", "fingerprint", "sufficient", { timeout: -1, tries: -1 })).join("|"),
                    "-auth sufficient pam_fprintd.so timeout=-1 max-tries=-1", "a reader with no limits: -1");
        assertEqual(edit.countedLines("optional").length, 0, "no counted pattern for optional: an own row never is");
        assertEqual(edit.rowLines(fingerprint("r1", "required")).join("|"),
                    "auth [success=ok new_authtok_reqd=ok ignore=bad default=bad] pam_fprintd.so timeout=10 max-tries=3",
                    "a required reader: plain auth, its word with ignore a failure");
        assertEqual(edit.rowLines(key("r1", "requisite", true)).join("|"),
                    "auth [success=ok new_authtok_reqd=ok ignore=die default=die] pam_u2f.so cue pinverification=1",
                    "a key: cue, the PIN when asked; requisite with ignore ending it");
        assertEqual(edit.rowLines(password("r1", "required")).join("|"), "auth [success=ok new_authtok_reqd=ok ignore=bad default=bad] pam_unix.so try_first_pass",
                    "a required password: the same");
        assertEqual(edit.rowLines(fingerprint("r1", "sufficient")).join("|"), "-auth sufficient pam_fprintd.so timeout=10 max-tries=3",
                    "sufficient stays the plain word");
        assertEqual(edit.rowLines(raw("r1", "auth required pam_ldap.so")).join("|"), "auth required pam_ldap.so", "a raw line stays as typed");
        // A required row that answers PAM_IGNORE fails instead of reaching the permit closing as no answer
        let permitted = edit.blockLines([key("r1", "required", false), password("r2")], facts());
        assert(permitted[0].includes("ignore=bad") && permitted.slice(-2).join("|") === "auth [default=done] pam_permit.so|auth requisite pam_deny.so",
               "with the permit closing, the required row's ignore is a failure: " + JSON.stringify(permitted));
        const parse = text => PamStackRules.parseLine(text);
        assertEqual(edit.controlWord(parse("auth [default=bad ignore=bad new_authtok_reqd=ok success=ok] pam_x.so")), "required",
                    "the written form read back as its word, in any order");
        assertEqual(edit.controlWord(parse("auth [success=ok default=bad] pam_x.so")), "", "another bracketed control: no word");
        assertEqual(edit.controlWord(parse("auth [success=ok new_authtok_reqd=ok ignore=bad default=ignore default=bad] pam_x.so")), "",
                    "a second default does not count: not the required form");
        assertEqual(edit.controlWord(parse("auth requisite pam_x.so")), "requisite", "a plain word: itself");
        const plainWords = edit.adopt("auth required pam_fprintd.so\nauth requisite pam_unix.so try_first_pass\nauth include system-auth\n", "sudo", {});
        assertEqual(plainWords.rows.map(row => row.method + ":" + row.control).join(" "), "fingerprint:required password:requisite system:",
                    "a hand-made file's plain required and requisite are read as rows with those words");
        assertEqual(edit.rowLines(key("r1", "sufficient")).join("|"), "-auth sufficient pam_u2f.so cue", "… no PIN");
        assertEqual(edit.rowLines(password("r1")).join("|"), "auth sufficient pam_unix.so try_first_pass", "an uncounted password");
        assertEqual(edit.rowLines(password("r1", "sufficient", true)).join("|"),
                    "auth required pam_faillock.so preauth|auth [success=done default=ignore] pam_unix.so try_first_pass|auth optional pam_faillock.so authfail",
                    "a counted sufficient password: the fixed pattern");
        assertEqual(edit.rowLines(password("r1", "required", true)).join("|"),
                    "auth required pam_faillock.so preauth|auth [success=1 default=bad] pam_unix.so try_first_pass|auth [default=bad] pam_faillock.so authfail",
                    "… required: the system's shape");
        assertEqual(edit.rowLines(password("r1", "requisite", true))[2], "auth [default=die] pam_faillock.so authfail", "… requisite ends at once");
        assertEqual(edit.rowLines(raw("r1", "auth  sufficient pam_ldap.so # mine")).join("|"), "auth  sufficient pam_ldap.so # mine", "a raw line verbatim");
        assertEqual(edit.rowLines(fixed).length, 0, "the fixed row writes nothing");
        assertEqual(edit.blockLines([fingerprint("r1")], facts()).slice(-1)[0], "auth requisite pam_deny.so", "readers only, no fixed row: the deny closes");
        assertEqual(edit.blockLines([fingerprint("r1", "required"), password("r2")], facts()).slice(-2).join("|"),
                    "auth [default=done] pam_permit.so|auth requisite pam_deny.so",
                    "a required row, no fixed row: the permit keeps a pass, the deny after it a failure");
        assertEqual(edit.blockLines([raw("r1", "auth [success=ok default=bad] pam_unix.so"), fingerprint("r2")], facts()).slice(-2).join("|"),
                    "auth [default=done] pam_permit.so|auth requisite pam_deny.so", "… a raw bad action too");
        // Read back: both lines, or the permit line alone, are the closing; built again, both lines
        const permitRows = [fingerprint("r1", "required"), password("r2")];
        const permitBlock = lines => "#%PAM-1.0\n" + edit.blockText(lines).join("\n") + "\nauth include system-auth\n";
        const permitLines = edit.blockLines(permitRows, facts());
        const readIds = list => (list ?? []).map(item => item.method + ":" + item.control).join(" ");
        assertEqual(readIds(edit.rows(permitBlock(permitLines), "sudo", facts())), "fingerprint:required password:sufficient",
                    "a block ending in the permit and deny lines reads as the rows, no fixed row");
        const onePermit = permitBlock(permitLines.slice(0, -1));
        assertEqual(readIds(edit.rows(onePermit, "sudo", facts())), "fingerprint:required password:sufficient",
                    "… ending in the permit line alone: the same rows");
        assertEqual(edit.changes(onePermit, "sudo").changed, false, "… not changed by hand");
        assertEqual(readIds(edit.adopt(onePermit, "sudo", facts()).rows), "fingerprint:required password:sufficient", "… taken in: the same rows");
        assertEqual(edit.build(onePermit, permitRows, facts()).text, permitBlock(permitLines), "… built again: both lines");
        const denyAlone = permitBlock(permitLines.slice(0, -2).concat(["auth requisite pam_deny.so"]));
        assertEqual(readIds(edit.rows(denyAlone, "sudo", facts())), "fingerprint:required password:sufficient raw: system:",
                    "the deny line alone after rows that need the permit: a raw row, not a closing");

        // --- Arch sudo, system-auth with pam_faillock ---
        let lines = ["-auth sufficient pam_fprintd.so timeout=10 max-tries=3"];
        let built = edit.build(archSudo, [fingerprint("r1"), fixed], facts());
        assertEqual(built.text, "#%PAM-1.0\n# BEGIN h2s-shell " + edit.sha256(lines.join("\n")) + "\n" + lines[0] + "\n# END h2s-shell\n"
                    + "auth\t\tinclude\t\tsystem-auth\naccount\t\tinclude\t\tsystem-auth\nsession\t\tinclude\t\tsystem-auth\n",
                    "sudo: our block at the top of the auth lines, its hash of the lines between");
        assertEqual(PamStackRules.ownBlock(built.text).hash, edit.sha256(PamStackRules.ownBlock(built.text).body), "… the hash read back matches");
        const sudoLists = [
            ["a reader", [fingerprint("r1"), fixed]],
            ["counted password then reader", [password("r1", "sufficient", true), fingerprint("r2"), fixed]],
            ["required key with PIN, counted required password", [key("r1", "required", true), password("r2", "required", true), fixed]],
            ["requisite counted", [password("r1", "requisite", true), fixed]],
            ["a reader with no limits", [row("r1", "fingerprint", "sufficient", { timeout: -1, tries: -1 }), fixed]],
            ["a raw optional line", [raw("r1", "auth optional pam_env.so"), fingerprint("r2"), fixed]],
            ["reader, no fixed row (deny)", [fingerprint("r1")]],
            ["required reader and password, no fixed row (permit)", [fingerprint("r1", "required"), password("r2")]],
            ["raw lines among rows", [raw("r1", "auth sufficient /usr/lib/security/pam_ldap.so use_first_pass # ldap"), key("r2"), fixed]]
        ];
        for (const [label, list] of sudoLists) {
            const text = roundTrip(archSudo, list, facts(), archSystemAuth, "sudo with faillock, " + label);
            if (text === null)
                continue;
            assertEqual(edit.build(text, [rules.fixedRow()], facts()).text, archSudo, "sudo with faillock, " + label + ": removed = the original bytes");
            assertEqual(edit.build(text, list, facts()).text, text, "sudo with faillock, " + label + ": built again = the same text");
        }
        assertEqual(edit.build(archSudo.replace(/\n$/, ""), [fingerprint("r1"), fixed], facts()).ok, true, "a file without a final newline");
        let noNewline = edit.build(archSudo.replace(/\n$/, ""), [fingerprint("r1"), fixed], facts()).text;
        assertEqual(edit.build(noNewline, [fixed], facts()).text, archSudo.replace(/\n$/, ""), "… removed exactly too");
        const noAuth = "#%PAM-1.0\naccount include system-auth";
        assertEqual(edit.build(edit.build(noAuth, [fingerprint("r1")], facts()).text, [fixed], facts()).text, noAuth,
                    "a file without auth lines: the block at the end, removed exactly");
        assertEqual(codes(edit.build(noAuth, [fingerprint("r1"), fixed], facts())).join(" "), "noSystem",
                    "… the fixed row there: refused, nothing would ask the system's password");
        const blockBelow = "auth include system-auth\n" + edit.blockText(["-auth sufficient pam_fprintd.so timeout=10 max-tries=3"]).join("\n") + "\n";
        assertEqual(codes(edit.build(blockBelow, [fingerprint("r1"), fixed], facts())).join(" "), "noSystem",
                    "the system's lines above our block: the fixed row refused");
        assertEqual(edit.build(blockBelow, [fingerprint("r1")], facts()).ok, true, "… without it, the closing line: built");

        // The fixed row taken away and put back: only the closing line goes
        const withoutFixed = edit.build(archSudo, [fingerprint("r1")], facts()).text;
        assert(withoutFixed.includes("auth requisite pam_deny.so\n# END h2s-shell\nauth\t\tinclude"), "no fixed row: the closing line, the include kept unreached");
        assertEqual(edit.build(withoutFixed, [fingerprint("r1"), fixed], facts()).text, built.text, "the fixed row put back: the closing line removed");

        // --- Arch sudo, system-auth without pam_faillock ---
        const plain = facts({ faillockPresent: false, faillock: null });
        roundTrip(archSudo, [password("r1"), fingerprint("r2"), fixed], plain, plainSystemAuth, "sudo without faillock, password then reader");
        let refused = edit.build(archSudo, [password("r1", "sufficient", true), fixed], plain);
        assert(!refused.ok && refused.text === null && codes(refused).includes("R4"), "counting without pam_faillock: refused, no text");

        // --- refusals: no text for rows the checks refuse ---
        assertEqual(codes(edit.build(archSudo, [], facts())).join(" "), "R3", "no rows: R3");
        assert(codes(edit.build(archSudo, [fingerprint("r1", "required"), fixed], facts({ fingerprint: "absent" }))).includes("R2"),
               "a required reader not ready: R2");
        assert(codes(edit.build(archSudo, [raw("r1", "auth sufficient pam_permit.so"), fixed], facts())).includes("R9"), "a raw line letting anyone in: R9");
        assertEqual(codes(edit.build(null, [fingerprint("r1"), fixed], facts())).join(" "), "unread", "sudo not read: refused");
        assertEqual(codes(edit.build(null, [fingerprint("r1"), fixed], polkit({ vendorText: null }))).join(" "), "unread", "polkit's vendor file not read: refused");

        // --- our polkit-1 ---
        const polkitText = roundTrip(null, [fingerprint("r1"), fixed], polkit(), archSystemAuth, "polkit-1, a reader");
        const rest = polkitText.slice(polkitText.indexOf("\n") + 1);
        assertEqual(polkitText.split("\n")[0], "# Written by h2s-shell " + edit.sha256(rest), "polkit-1: our file, its first line the hash of the rest");
        assertEqual(rest, "#%PAM-1.0\n\n# BEGIN h2s-shell " + edit.sha256(lines[0]) + "\n" + lines[0] + "\n# END h2s-shell\n"
                    + vendorPolkit.slice("#%PAM-1.0\n\n".length), "… the vendor file with our block above its auth lines");
        built = edit.build(polkitText, [fixed], polkit());
        assert(built.ok && built.remove && built.text === null, "polkit-1 back to the system's rows: our file removed, the vendor stack again");
        roundTrip(polkitText, [password("r1", "sufficient", true), key("r2"), fixed], polkit(), archSystemAuth, "polkit-1 rewritten");
        roundTrip(null, [fingerprint("r1", "required"), password("r2")], polkit(), archSystemAuth, "polkit-1 without the fixed row");
        assertEqual(JSON.stringify(edit.rows(null, "polkit-1", polkit()).map(item => item.method)), "[\"system\"]", "no /etc/pam.d/polkit-1: the system's rows");
        assertEqual(edit.vendorChanged(polkitText, vendorPolkit), false, "the vendor file as copied");
        assertEqual(edit.vendorChanged(polkitText, vendorPolkit + "auth optional pam_permit.so\n"), true, "polkit's own file changed since");
        assertEqual(edit.state(polkitText, "polkit-1", polkit({ vendorText: vendorPolkit + "auth optional pam_permit.so\n" })).vendorChanged, true, "… the state says so");

        // --- changed by hand ---
        const sudoText = edit.build(archSudo, [fingerprint("r1"), fixed], facts()).text;
        let changed = edit.changes(sudoText.replace("timeout=10", "timeout=20"), "sudo");
        assertEqual(changed.changed + " " + changed.reasons.map(item => item.reason).join(" "), "true hash", "a line in the block edited: the hash does not match");
        assertEqual(changed.reasons[0].line, 2, "… marked at the block");
        assert(codes(edit.build(sudoText.replace("timeout=10", "timeout=20"), [fingerprint("r1"), fixed], facts())).includes("R6"), "… build refuses: R6");
        changed = edit.changes(sudoText.replace("auth\t\tinclude", "auth sufficient pam_u2f.so\nauth\t\tinclude"), "sudo");
        assertEqual(changed.reasons.map(item => item.reason + ":" + item.line).join(" "), "securityKey:5", "a key line outside the block, its line");
        changed = edit.changes(archSudo.replace("auth\t\tinclude", "auth sufficient pam_fprintd.so\nauth\t\tinclude"), "sudo");
        assertEqual(changed.reasons.map(item => item.reason).join(" "), "fingerprint", "a fingerprint line in a file without our block");
        assertEqual(edit.changes(sudoText.replace("# END h2s-shell\n", ""), "sudo").reasons[0].reason, "block", "a block without its end");
        assertEqual(edit.changes(archSudo + "auth sometimes pam_unix.so\n", "sudo").reasons[0].reason, "unparsable", "a line PAM cannot read");
        assertEqual(edit.changes(archSudo, "sudo").changed, false, "the distribution's sudo: not changed");
        assertEqual(edit.changes(vendorPolkit, "polkit-1").reasons[0].reason, "notOurs", "an /etc/pam.d/polkit-1 not written by us");
        assertEqual(edit.changes(polkitText.replace("account    include", "account  include"), "polkit-1").reasons[0].reason, "fileHash",
                    "our polkit-1 changed outside the block");
        assertEqual(edit.changes(null, "sudo").known, false, "a file not read: not known, never fine");
        assertEqual(edit.state(null, "sudo", facts()).rows, null, "… and no rows");

        // --- taking in a hand-made file ---
        const handMade = "#%PAM-1.0\n"
            + "auth  sufficient  pam_ldap.so  use_first_pass   # the directory\n"
            + "-auth sufficient pam_fprintd.so timeout=10 max-tries=3\n"
            + "auth sufficient pam_fprintd.so\n"
            + "auth required pam_faillock.so preauth\nauth [success=done default=ignore] pam_unix.so try_first_pass\nauth optional pam_faillock.so authfail\n"
            + "auth\t\tinclude\t\tsystem-auth\naccount\t\tinclude\t\tsystem-auth\nsession\t\tinclude\t\tsystem-auth\n";
        let found = edit.state(handMade, "sudo", facts());
        assertEqual(found.changed, true, "a hand-made sudo: changed by hand");
        const adopted = edit.adopt(handMade, "sudo", facts());
        assertEqual(adopted.rows.map(item => item.method + (item.method === "raw" ? "(" + item.details.text + ")" : "")).join(", "),
                    "raw(auth  sufficient  pam_ldap.so  use_first_pass   # the directory), fingerprint, raw(auth sufficient pam_fprintd.so), password, system",
                    "taken in: the editor's lines as rows, the rest raw in place, the include as the fixed row");
        assertEqual(adopted.rows[3].details.counted, true, "… the counted pattern as one counted password row");
        assertEqual(adopted.own + "/" + adopted.raw + "/" + adopted.fixed, "2/2/true", "… how many of each");
        assertEqual(JSON.stringify(found.rows), JSON.stringify(adopted.rows), "the state's rows are adopt's");
        assert(!edit.build(handMade, adopted.rows, facts()).ok, "not replaced: build refuses (R6)");
        built = edit.build(handMade, adopted.rows, facts({ replace: adopted.hash }));
        assert(built.ok, "replaced: built");
        const readBack = files(archSystemAuth);
        assertEqual(PamStackRules.stack("sudo", Object.assign({}, readBack, { "/etc/pam.d/sudo": built.text })).lines.map(fields).join("\n"),
                    PamStackRules.stack("sudo", Object.assign({}, readBack, { "/etc/pam.d/sudo": handMade })).lines.map(fields).join("\n"),
                    "adopt then build: the same auth lines in the same order");
        assert(built.text.includes("account\t\tinclude\t\tsystem-auth\nsession\t\tinclude\t\tsystem-auth\n"), "… the other phases' lines kept verbatim");
        assertEqual(PamStackRules.ownBlock(built.text).body.split("\n").length, 6, "… the hand lines moved into our block");
        assertEqual(built.text.split("\n").filter(line => /^-?auth/.test(line)).length, 6 + 1,
                    "… no auth line left outside it but the include");
        assertEqual(edit.changes(built.text, "sudo").changed, false, "… and the file is ours now");
        assert(rules.sameRows(edit.rows(built.text, "sudo", facts()), adopted.rows), "… its rows are the rows taken in");
        // A file with our block and a line added by hand outside it
        const mixed = sudoText.replace("auth\t\tinclude", "-auth sufficient pam_u2f.so cue\nauth\t\tinclude");
        const mixedRows = edit.adopt(mixed, "sudo", facts()).rows;
        assertEqual(mixedRows.map(item => item.method).join(" "), "fingerprint securityKey system", "our block and a hand line: both as rows");
        assertEqual(edit.build(mixed, mixedRows, facts({ replace: edit.adopt(mixed, "sudo", facts()).hash })).text, edit.build(archSudo, [fingerprint("r1"), key("r2"), fixed], facts()).text,
                    "… replaced: one block, the hand line inside it");
        assertEqual(edit.adopt(sudoText.replace("auth\t\tinclude", "auth sufficient pam_u2f.so cue\nauth\t\tinclude"), "sudo", facts()).rows[1].method,
                    "raw", "a key line not in the editor's form (auth, not -auth) stays raw");
        // A hand-made polkit-1 over the vendor file
        const handPolkit = vendorPolkit.replace("auth       include", "auth sufficient /usr/lib/security/pam_ldap.so\nauth       include");
        const polkitAdopted = edit.adopt(handPolkit, "polkit-1", polkit());
        assertEqual(polkitAdopted.rows.map(item => item.method).join(" "), "raw system", "a hand-made polkit-1: the vendor's auth lines as the fixed row");
        built = edit.build(handPolkit, polkitAdopted.rows, polkit({ replace: polkitAdopted.hash }));
        assert(built.ok && PamStackRules.writtenBy(built.text) !== null && !edit.changes(built.text, "polkit-1").changed, "… replaced: our file");
        // A Replace acts only on the text taken in
        assertEqual(codes(edit.build(handMade + "auth optional pam_permit.so\n", adopted.rows, facts({ replace: adopted.hash }))).join(" "), "changed",
                    "the file changed since it was taken in: refused");
        assert(codes(edit.build(handMade, adopted.rows, facts({ replace: true }))).includes("R6"), "a replace without the taken text's hash: R6");
        // After a Replace on polkit-1 the kept lines stay: the next Apply builds from our file
        const keptPolkit = handPolkit + "session    optional     pam_keyinit.so force revoke\n";
        const keptRows = edit.adopt(keptPolkit, "polkit-1", polkit());
        const replaced = edit.build(keptPolkit, keptRows.rows, polkit({ replace: keptRows.hash })).text;
        assertEqual(edit.vendorChanged(replaced, vendorPolkit), false, "after a Replace: the vendor's auth lines as copied");
        assertEqual(edit.vendorChanged(replaced, vendorPolkit.replace("auth       include      system-auth", "auth include system-login")), true,
                    "… the vendor's auth lines changed since: said");
        built = edit.build(replaced, [fingerprint("r1"), fixed], polkit());
        assert(built.ok && built.text.includes("pam_keyinit.so force revoke") && built.text.includes("pam_fprintd.so"),
               "the next Apply keeps the lines a Replace kept");
        built = edit.build(replaced, [fixed], polkit());
        assert(built.ok && !built.remove && built.text.includes("pam_keyinit.so") && PamStackRules.ownBlock(built.text) === null,
               "… back to the system's rows: our file kept without a block, not removed");
        built = edit.build(replaced, [fingerprint("r1"), fixed], polkit({ takeOver: true }));
        assert(built.ok && !built.text.includes("pam_keyinit.so"), "a take-over rebuilds from the vendor file");
        // A fixed row restored with no system's lines below: refused
        const noRun = edit.adopt("auth sufficient pam_unix.so try_first_pass\n", "sudo", facts());
        assertEqual(codes(edit.build("auth sufficient pam_unix.so try_first_pass\n", rules.restoreFixedRow(noRun.rows), facts({ replace: noRun.hash }))).includes("noSystem"),
                    true, "taken in without the system's lines, the fixed row put back: refused");
        // @include: never left out of the rows
        const included = "auth sufficient pam_unix.so try_first_pass\n@include common-auth\naccount required pam_unix.so\n";
        assertEqual(edit.adopt(included, "sudo", facts()).rows.map(item => item.method).join(" "), "password raw",
                    "an @include that is not the system's run: a raw row");
        assert(codes(edit.build(included, edit.adopt(included, "sudo", facts()).rows, facts({ replace: edit.adopt(included, "sudo", facts()).hash }))).includes("R8"),
               "… which the checks refuse: nothing lost silently");
        const debian = facts({ systemLines: { "sudo": ["@include common-auth"] } });
        const debianRows = edit.adopt(included, "sudo", debian);
        assertEqual(debianRows.rows.map(item => item.method).join(" "), "password system", "an @include that is the system's run: the fixed row");
        built = edit.build(included, debianRows.rows, Object.assign({}, debian, { replace: debianRows.hash }));
        assert(built.ok && built.text.endsWith("# END h2s-shell\n@include common-auth\naccount required pam_unix.so\n"), "… kept below our block");
        assertEqual(edit.adopt(included, "polkit-1", Object.assign({}, debian, { service: "polkit-1", vendorText: vendorPolkit })).fixed, false,
                    "systemLines are per service: sudo's do not serve polkit-1");
        // The file's own lines between our block and the system's stay, unless one lets in alone
        const debianSudo = "#%PAM-1.0\nauth       required   pam_env.so readenv=1 user_readenv=0\n@include common-auth\n@include common-account\n"
            + "@include common-session-noninteractive\n";
        built = edit.build(debianSudo, [fingerprint("r1"), fixed], debian);
        assert(built.ok && built.text.includes("# END h2s-shell\nauth       required   pam_env.so"), "an old Debian sudo with pam_env before the include: built");
        assertEqual(edit.adopt(debianSudo, "sudo", debian).rows.map(item => item.method).join(" "), "raw system",
                    "… taken in: pam_env a raw row, the include the fixed row, the other phases' @include kept");
        const homeSudo = "-auth [success=2 default=ignore] pam_systemd_home.so\nauth include system-auth\naccount include system-auth\n";
        assert(edit.build(homeSudo, [fingerprint("r1"), fixed], facts()).ok, "a systemd-home reader before the include: built");
        const lettingIn = "auth sufficient pam_unix.so\nauth include system-auth\n";
        assertEqual(codes(edit.build(lettingIn, [fingerprint("r1"), fixed], facts())).join(" "), "noSystem",
                    "a line between that lets in alone: refused");
        // polkit's system lines include the vendor file's @include
        const debianPolkit = "#%PAM-1.0\n\n@include common-auth\n@include common-account\n@include common-password\n@include common-session-noninteractive\n";
        built = edit.build(null, [fingerprint("r1"), fixed], polkit({ vendorText: debianPolkit }));
        assert(built.ok && built.text.includes("# END h2s-shell\n@include common-auth"), "a Debian-layout vendor polkit-1: built over its @include");
        assertEqual(edit.adopt((built.text ?? "").replace(/^# Written.*\n/, ""), "polkit-1", polkit({ vendorText: debianPolkit })).fixed, true,
                    "… its @include lines are the fixed row");
        // Our polkit-1 built from the vendor file: every line compared
        assertEqual(edit.vendorChanged(polkitText, vendorPolkit.replace("session    include      system-auth", "session    include      system-login")), true,
                    "built from the vendor file: a vendor session line changed is said");
        assertEqual(edit.vendorChanged(replaced, vendorPolkit.replace("session    include      system-auth", "session    include      system-login")), false,
                    "after a Replace: only the auth lines are compared");
        assertEqual(replaced.split("\n")[1], edit.replacedMarker, "… marked under the first line");
        assertEqual(edit.build(replaced, keptRows.rows, polkit({ replace: edit.adopt(replaced, "polkit-1", polkit()).hash })).text.split(edit.replacedMarker).length, 2,
                    "… a second Replace marks it once");
        // No trailing run of the system's lines: no fixed row
        assertEqual(edit.adopt("auth sufficient pam_unix.so try_first_pass\n", "sudo", facts()).rows.map(item => item.method).join(" "), "password",
                    "no system's lines at the end: no fixed row");
        assertEqual(edit.adopt("auth sufficient pam_fprintd.so timeout=601\nauth include system-auth\n", "sudo", facts()).rows[0].method, "raw",
                    "a detail out of range stays raw");
        assertEqual(JSON.stringify(edit.adopt("-auth sufficient pam_fprintd.so timeout=-1 max-tries=-1\nauth include system-auth\n", "sudo", facts()).rows[0]),
                    JSON.stringify({ method: "fingerprint", control: "sufficient", details: { timeout: -1, tries: -1 }, id: "r1" }), "no limit is read as -1");
        assertEqual(edit.adopt("-auth sufficient pam_fprintd.so timeout=-2\nauth include system-auth\n", "sudo", facts()).rows[0].method, "raw",
                    "… another negative value stays raw");
        for (const optional of ["auth optional pam_fprintd.so timeout=10", "-auth optional pam_fprintd.so timeout=10", "auth optional pam_u2f.so cue",
                               "auth optional pam_unix.so try_first_pass"]) {
            const taken = edit.adopt(optional + "\nauth include system-auth\n", "sudo", facts());
            assertEqual(JSON.stringify(taken.rows.map(item => [item.method, item.details.text ?? ""])), JSON.stringify([["raw", optional], ["system", ""]]),
                        "an own module's optional line stays a raw row, kept exactly: " + optional);
        }
        const countedOptional = "auth required pam_faillock.so preauth\nauth [success=1 default=ignore] pam_unix.so try_first_pass\n"
            + "auth optional pam_faillock.so authfail\nauth include system-auth\n";
        assertEqual(edit.adopt(countedOptional, "sudo", facts()).rows.map(item => item.method).join(" "), "raw raw raw system",
                    "… the counted pattern's optional form: raw rows");
        assertEqual(edit.adopt("auth sufficient pam_u2f.so cue authfile=/etc/u2f\nauth include system-auth\n", "sudo", facts()).rows[0].method, "raw",
                    "a key line with its own authfile stays raw");

        // --- NixOS snippets ---
        let snippet = edit.nixosSnippet([fingerprint("r1"), fixed], false, { fingerprint: "ready" });
        assertEqual(snippet.text, "programs.h2s-shell.pam = {\n  rules = [\n"
                    + "    { method = \"fingerprint\"; control = \"sufficient\"; timeout = 10; tries = 3; }\n"
                    + "    { method = \"system\"; }\n  ];\n};\n", "NixOS: one list for both");
        snippet = edit.nixosSnippet({ sudo: [key("r1", "sufficient", true), password("r2", "required"), fixed],
                                      polkit: [raw("r1", "auth sufficient /run/current-system/sw/lib/security/pam_ldap.so use_first_pass"), fixed] },
                                    true, { securityKey: "ready" });
        assertEqual(snippet.text, "programs.h2s-shell.pam = {\n  sudo.rules = [\n"
                    + "    { method = \"securityKey\"; control = \"sufficient\"; pin = true; }\n"
                    + "    { method = \"password\"; control = \"required\"; counted = false; }\n"
                    + "    { method = \"system\"; }\n  ];\n  polkit.rules = [\n"
                    + "    { method = \"raw\"; control = \"sufficient\"; module = \"/run/current-system/sw/lib/security/pam_ldap.so\"; args = [ \"use_first_pass\" ]; }\n"
                    + "    { method = \"system\"; }\n  ];\n};\n", "NixOS: one list per service, a raw line with its full path");
        snippet = edit.nixosSnippet([raw("r1", "-auth sufficient /run/current-system/sw/lib/security/pam_ldap.so"), fixed], false, {});
        assert(!snippet.ok && snippet.text === null && snippet.refusals[0].code === "R8", "NixOS: a -auth raw line cannot be an option");
        snippet = edit.nixosSnippet([row("r1", "fingerprint", "sufficient", { timeout: -1, tries: -1 }), fixed], false, { fingerprint: "ready" });
        assert(snippet.ok && snippet.text.includes("{ method = \"fingerprint\"; control = \"sufficient\"; timeout = -1; tries = -1; }"), "NixOS: no limit is -1");
        snippet = edit.nixosSnippet({ sudo: [], polkit: [fixed] }, true, {});
        assert(!snippet.ok && snippet.refusals.some(item => item.code === "R3" && item.service === "sudo"), "NixOS: an empty list refused, with its service");
        snippet = edit.nixosSnippet([raw("r1", "auth sufficient pam_ldap.so"), fixed], false, {});
        assert(!snippet.ok && snippet.refusals.some(item => item.code === "R8"), "NixOS: a bare third-party module refused");
        snippet = edit.nixosSnippet([raw("r1", "auth sufficient /nix/store/abc-pam_ldap/lib/security/pam_ldap.so"), fixed], false, {});
        assert(snippet.ok && snippet.text.includes("module = \"/nix/store/abc-pam_ldap/lib/security/pam_ldap.so\";")
               && snippet.warnings.some(item => item.code === "W11"), "NixOS: a store path written out is allowed, with a warning");
    }
}
