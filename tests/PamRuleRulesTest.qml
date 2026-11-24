import QtQuick
import qs.singletons

// PamRuleRules: rows, control words, details and every refusal and warning code, on lists
// built here
TestCase {
    suiteName: "PamRuleRules"

    function run() {
        const rules = PamRuleRules;
        const row = (id, method, control, details) => ({ id, method, control: control ?? "sufficient", details: details ?? {} });
        const fingerprint = (id, control, details) => row(id, "fingerprint", control, Object.assign({ timeout: 10, tries: 3 }, details ?? {}));
        const key = (id, control) => row(id, "securityKey", control, { pin: false, cue: true });
        const password = (id, control, counted) => row(id, "password", control, { counted: counted === true });
        const raw = (id, text) => ({ id, method: "raw", control: "", details: { text } });
        const fixed = rules.fixedRow();
        // The module directories as the distributions' facts have them (handed in by the
        // page): Arch's, unless the case names its own; NixOS's with what its integration
        // says of "pam.rules" (only libpam's own modules by bare name, and its words), nixos()
        const archModules = ["/usr/lib/security/", "/lib/security/", "/usr/lib64/security/", "/lib64/security/"];
        const nixosModules = ["/run/current-system/sw/lib/security/"];
        const arch = (more) => {
            const facts = Object.assign({ service: "sudo", fingerprint: "ready", securityKey: "ready",
                                          faillockPresent: true, faillock: { deny: 3, failInterval: 900, unlockTime: 600 },
                                          otherService: [rules.fixedRow()] }, more ?? {});
            if (!("moduleDirectories" in (more ?? {})))
                facts.moduleDirectories = archModules;
            return facts;
        };
        const nixos = (more) => Object.assign({ moduleDirectories: nixosModules, bareModules: "libpam",
                                                texts: { modulePath: "Needs the module's full path on NixOS." } }, more ?? {});
        const codes = (rows, facts) => rules.codes(rules.check(rows, facts));
        const has = (rows, facts, code) => codes(rows, facts).includes(code);

        // --- control words ---
        assertEqual(rules.controls.map(control => control.word).join(" "), "sufficient required requisite optional", "the four words, in order");
        assertEqual(rules.defaultControl, "sufficient", "a new row is sufficient");
        assertEqual(rules.explanation("requisite"), "Must pass. If it fails, you are refused at once.", "a word's explanation");
        assertEqual(rules.explanation("include"), "", "no explanation for another word");
        assertEqual(rules.controlsFor("raw").join(" "), "sufficient required requisite optional", "a raw line: all four words");
        for (const method of ["fingerprint", "securityKey", "password"])
            assertEqual(rules.controlsFor(method).join(" "), "sufficient required requisite", method + ": no optional");
        assertEqual(rules.controlsFor("system").length + rules.controlsFor("smartcard").length, 0, "no words for the fixed row or an unknown method");
        assert(rules.controlAllowed("raw", "optional") && !rules.controlAllowed("password", "optional")
               && rules.controlAllowed("password", "requisite"), "a word allowed for a method");
        assertEqual(rules.explanation("sufficient"), "If this passes, you are in. If not, the next row is tried.", "sufficient explained");
        assert(rules.explanation("optional").startsWith("Its result is ignored"), "optional: its result ignored");

        // --- methods and details ---
        let made = rules.newRow("fingerprint", [row("r1", "password")]);
        assertEqual(JSON.stringify(made), JSON.stringify({ id: "r2", method: "fingerprint", control: "sufficient", details: { timeout: 10, tries: 3 } }),
                    "a new fingerprint row: an unused id, defaults");
        assertEqual(JSON.stringify(rules.newRow("securityKey", []).details), "{\"pin\":false,\"cue\":true}", "a key: no PIN, cue on");
        assertEqual(rules.newRow("password", []).details.counted, false, "a password row is not counted by default");
        assertEqual(rules.newRow("system", []), null, "the fixed row is not added as a new row");
        assertEqual(rules.offeredMethods({ fingerprint: "ready", securityKey: "unknown" }).join(" "), "fingerprint password raw",
                    "a method offered only when ready; the raw line last");
        assertEqual(rules.detailOffered("password", "counted", { faillockPresent: false }), false, "counting offered only with pam_faillock");
        assertEqual(rules.countsChip(password("r1", "sufficient", true)) + "/" + rules.countsChip(fingerprint("r2")) + "/" + rules.countsChip(raw("r3", "x")),
                    "Counted/Not counted/Not checked", "the counting chips");
        assertEqual(rules.faillockSummary({ deny: 3, failInterval: 900, unlockTime: 600 }), "Counts: 3 wrong in 15 min lock 10 min", "faillock in words");
        assertEqual(rules.faillockSummary(null), "Counts: not known", "… not known");

        // --- the fixed row ---
        let list = [fingerprint("r1"), fixed];
        assertEqual(rules.insertRow(list, password("r2"), 5).map(item => item.id).join(" "), "r1 r2 system", "nothing goes below the fixed row");
        assertEqual(rules.insertRow(list, rules.fixedRow(), 0).length, 2, "a second fixed row is not inserted");
        assertEqual(rules.moveRow(list, 1, 0).map(item => item.id).join(" "), "r1 system", "the fixed row does not move");
        assertEqual(rules.moveRow([fingerprint("r1"), password("r2"), fixed], 0, 2).map(item => item.id).join(" "), "r2 r1 system", "a row moves only above it");
        assertEqual(rules.removeRow(list, "system").length, 2, "the fixed row is not removed without being asked for");
        assertEqual(rules.removeRow(list, "system", true).map(item => item.id).join(" "), "r1", "… removed explicitly");
        assertEqual(rules.restoreFixedRow([fingerprint("r1")]).map(item => item.id).join(" "), "r1 system", "put back, last");
        assertEqual(rules.changeRow(list, "system", { control: "optional" })[1].control, "", "the fixed row is not edited");
        assertEqual(rules.changeRow(list, "r1", { details: { timeout: 20 } })[0].details.tries, 3, "a detail changed, the others kept");
        assertEqual(list[0].details.timeout, 10, "edits copy: the list handed in is not changed");

        // --- one list or two ---
        let lists = rules.listsFor({ split: false, shared: list });
        assert(rules.sameRows(lists["sudo"], lists["polkit-1"]), "a shared list serves both");
        let split = rules.splitLists(list);
        assert(split.split && rules.sameRows(split.sudo, split.polkit), "split: both start as the shared list");
        assertEqual(rules.joinLists(split.sudo, split.polkit).asks, false, "joining equal lists asks nothing");
        let joined = rules.joinLists([password("r1"), fixed], list);
        assert(joined.asks && joined.shared[0].method === "password", "joining different lists asks; sudo's list wins");
        assert(rules.sameRows([row("a", "fingerprint", "sufficient", {})], [fingerprint("b")]), "ids and unset defaults do not make lists differ");

        // --- the plan's examples ---
        assertEqual(codes([fingerprint("r1")], arch()).join(" "), "W1", "only a reader: a warning");
        assert(has([fingerprint("r1")], arch({ fingerprint: "absent" }), "R1"), "no password anywhere and the reader not ready: refused");
        assert(has([raw("r1", "auth sufficient pam_permit.so"), fixed], arch(), "R9"), "raw auth sufficient pam_permit.so: refused");

        // --- every refusal ---
        assert(has([key("r1")], arch({ securityKey: "unknown" }), "R1"), "R1: an unknown method is not ready");
        assert(!has([key("r1")], arch(), "R1"), "R1 not: a ready key");
        assert(!has([password("r1")], arch({ fingerprint: "absent" }), "R1"), "R1 not: a password row");
        assert(has([password("r1", "optional")], arch({ fingerprint: "absent" }), "R1"), "R1: an optional row alone decides nothing");
        assert(has([fingerprint("r1", "optional")], arch(), "R1"), "R1: … an optional reader alone");
        assert(has([raw("r1", "auth optional pam_unix.so")], arch(), "R1"), "R1: a raw optional line decides nothing");
        assert(has([password("r1", "optional")], arch({ otherService: [password("p1", "optional")] }), "R5"),
               "R5: optional passwords alone in both services");
        assert(!has([raw("r1", "auth sufficient pam_unix.so")], arch(), "R1"), "R1 not: a raw pam_unix line is a password");
        assert(has([raw("r1", "auth sufficient pam_ldap.so")], arch(), "R1"), "R1: an unknown module is no way in");
        assert(has([fingerprint("r1", "required"), fixed], arch({ fingerprint: "absent" }), "R2"), "R2: a required reader not ready");
        assert(has([raw("r1", "auth requisite pam_u2f.so cue"), fixed], arch({ securityKey: "unknown" }), "R2"), "R2: … a raw key line too");
        assert(!has([fingerprint("r1", "sufficient"), fixed], arch({ fingerprint: "absent" }), "R2"), "R2 not: sufficient");
        assertEqual(codes([], arch()).join(" "), "R3", "R3: no rows");
        assert(!has([fixed], arch(), "R3"), "R3 not: the fixed row alone");
        assert(has([fingerprint("r1", "sufficient", { timeout: 601 }), fixed], arch(), "R4"), "R4: timeout above 600");
        assert(has([fingerprint("r1", "sufficient", { timeout: 0 }), fixed], arch(), "R4"), "R4: timeout 0");
        assert(has([fingerprint("r1", "sufficient", { timeout: -2 }), fixed], arch(), "R4"), "R4: a negative timeout other than -1");
        assert(has([fingerprint("r1", "sufficient", { tries: -2 }), fixed], arch(), "R4"), "R4: … tries");
        assert(!has([fingerprint("r1", "sufficient", { timeout: -1, tries: -1 }), fixed], arch(), "R4"), "R4 not: -1, no limit");
        assertEqual(rules.check([fingerprint("r1", "sufficient", { timeout: 601 }), fixed], arch()).refusals[0].text,
                    "Timeout must be 1–600 s, or no limit.", "the range's text names no limit");
        for (const method of ["fingerprint", "securityKey", "password"]) {
            const made = rules.newRow(method, []);
            made.control = "optional";
            const found = rules.check([made, fixed], arch()).refusals.find(refusal => refusal.code === "R4");
            assertEqual(found?.text, rules.texts.R4optional, "R4: an own " + method + " row cannot be optional");
        }
        assert(!has([raw("r1", "auth optional pam_env.so"), fixed], arch(), "R4"), "R4 not: a raw optional line");
        assert(has([fingerprint("r1", "sufficient", { tries: 0 }), fixed], arch(), "R4"), "R4: tries below 1");
        assert(has([fingerprint("r1", "sufficient", { tries: 2.5 }), fixed], arch(), "R4"), "R4: tries not whole");
        assert(has([row("r1", "smartcard"), fixed], arch(), "R4"), "R4: an unknown method");
        assert(has([row("r1", "password", "include"), fixed], arch(), "R4"), "R4: an unknown word");
        assert(has([row("r1", "securityKey", "sufficient", { cue: false }), fixed], arch(), "R4"), "R4: cue cannot be turned off");
        assert(has([password("r1", "sufficient", true), fixed], arch({ faillockPresent: false }), "R4"), "R4: counted where nothing counts");
        assert(has([fixed, fingerprint("r1")], arch(), "R4"), "R4: the fixed row not last");
        assert(!has([fingerprint("r1", "sufficient", { timeout: 1, tries: 20 }), password("r2", "required", true), fixed], arch(), "R4")
               && !has([fingerprint("r1", "sufficient", { timeout: 600 }), fixed], arch(), "R4"), "R4 not: the range's ends");
        let both = arch({ otherService: [fingerprint("p1")] });
        assert(has([fingerprint("r1")], both, "R5"), "R5: neither service keeps a password");
        assert(has([fingerprint("r1")], arch({ otherService: null }), "R5"), "R5: the other service not known counts as none");
        assert(!has([fingerprint("r1")], arch(), "R5"), "R5 not: the other keeps the system's password");
        assert(!has([fingerprint("r1"), fixed], both, "R5"), "R5 not: this one keeps it");
        assert(has([fixed], arch({ changedByHand: true }), "R6"), "R6: changed by hand");
        assert(!has([fixed], arch({ changedByHand: false }), "R6"), "R6 not: as written");
        const store = "/nix/store/" + "0123456789abcdfghijklmnpqrsvwxyz";
        assert(has([raw("r1", "auth sufficient /home/user/pam_evil.so"), fixed], arch(), "W12"), "W12: a module from the home");
        assert(has([raw("r1", "auth sufficient /usr/lib/security/../../../tmp/x.so"), fixed], arch(), "W12"), "W12: … through ..");
        assert(has([raw("r1", "auth sufficient lib/../../tmp/x.so"), fixed], arch(), "W12"), "W12: … a relative path");
        assert(has([raw("r1", "auth sufficient /nix/store/abc-pam_ldap/../../../home/u/x.so"), fixed], arch(nixos()), "W12"),
               "W12: … out of the store through ..");
        assert(rules.check([raw("r1", "auth sufficient /home/user/pam_evil.so"), fixed], arch()).refusals.length === 0,
               "a module from another place is allowed: a warning, no refusal");
        assert(has([raw("r1", "auth sufficient /nix/store/abc-pam_ldap/lib/security/pam_ldap.so"), fixed], arch(), "W11"), "W11: a store path on Arch");
        assert(!has([raw("r1", "auth sufficient /usr/lib/security/pam_ldap.so"), fixed], arch(), "W12")
               && !has([raw("r1", "auth sufficient /usr/lib/security/pam_ldap.so"), fixed], arch(), "W11"), "W11/W12 not: the system's folder");
        assert(!has([raw("r1", "auth sufficient /run/current-system/sw/lib/security/pam_ldap.so"), fixed], arch(nixos()), "W12"),
               "W12 not: the system profile on NixOS");
        assert(has([raw("r1", "auth sufficient /usr/lib/security/pam_ldap.so"), fixed], arch(nixos()), "W12"),
               "W12: Arch's folder on NixOS");
        assert(has([raw("r1", "auth sufficient /usr/lib/security/pam_ldap.so"), fixed], arch({ moduleDirectories: [] }), "W12")
               && has([raw("r1", "auth sufficient /usr/lib/security/pam_ldap.so"), fixed], arch({ moduleDirectories: undefined }), "W12"),
               "W12: the distribution's module folders not known — every path warns, none taken for the system's");
        assert(!has([raw("r1", "auth sufficient /opt/pam/pam_ldap.so"), fixed], arch({ moduleDirectories: ["/opt/pam/"] }), "W12"),
               "W12 not: a folder the facts name, whatever it is");
        assert(has([raw("r1", "auth sufficient /opt/pamx/pam_ldap.so"), fixed], arch({ moduleDirectories: ["/opt/pam"] }), "W12"),
               "W12: a folder named without its \"/\" is no place (it would take /opt/pamx for /opt/pam)");
        assert(has([raw("r1", "auth sufficient /nix/store/abc-evil/lib/security/pam_unix.so"), fixed], arch(nixos()), "W11"),
               "W11: any other store path on NixOS, whatever its file is called");
        assert(has([raw("r1", "auth sufficient /nix/store/abc-evil/lib/security/pam_unix.so")], arch(nixos({ otherService: [] })), "R1"),
               "… and it is no password (anyone can add to the store): no way in");
        assert(has([raw("r1", "auth sufficient /nix/store/abc-evil/lib/security/pam_ldap.so"), fixed], arch(nixos()), "W4"),
               "… not checked either: W4");
        let placed = rules.check([raw("r1", "auth sufficient " + store + "-pam_ldap-186/lib/security/pam_ldap.so"), fixed], arch(nixos()))
            .warnings.find(warning => warning.code === "W11");
        assertEqual(placed.text, "A path in the Nix store changes with an update or a garbage collection: use ${pkgs.pam_ldap} instead.",
                    "W11 names the package where the path says it");
        placed = rules.check([raw("r1", "auth sufficient /nix/store/abc-pam_ldap/lib/security/pam_ldap.so"), fixed], arch(nixos()))
            .warnings.find(warning => warning.code === "W11");
        assertEqual(placed.text, rules.texts.W11, "… and none where it does not (no hash)");
        assertEqual(rules.storePackage(store + "-linux-pam-1.6.1/lib/security/pam_unix.so"), "linux-pam", "a package's name: up to the version");
        assertEqual(rules.storePackage(store + "-pam_u2f/lib/security/pam_u2f.so"), "pam_u2f", "… no version");
        assertEqual(rules.storePackage("/nix/store/short-pam_u2f/lib/security/pam_u2f.so"), "", "… not a store path's name: none");
        assert(has([raw("r1", "auth required /nix/store/abc-x/lib/security/pam_deny.so"), password("r2"), fixed], arch(), "R1"),
               "R1: a pam_deny from another place is judged by its name (a name may refuse, never trust)");
        assert(has([raw("r1", "auth sufficient /nix/store/abc-linux-pam-1.7.2/lib/security/pam_permit.so"), fixed], arch(nixos()), "R9")
               && has([raw("r1", "auth sufficient /etc/pam_permit.so"), fixed], arch(), "R9"), "R9: pam_permit from another place, by its name");
        assert(!has([raw("r1", "auth sufficient /home/u/pam_unix.so")], arch({ otherService: [] }), "R9")
               && has([raw("r1", "auth sufficient /home/u/pam_unix.so")], arch({ otherService: [] }), "R1"), "… while pam_unix from another place is no password");
        for (const passes of ["alwaysok", "userpresence=0", "userpresence=00", "userpresence=-0", "userpresence=1 userpresence=0"])
            assert(has([raw("r1", "auth sufficient pam_u2f.so cue " + passes), fixed], arch(), "R9"), "R9: pam_u2f with " + passes);
        for (const passes of ["nouserok", "[nouserok]"])
            assert(has([raw("r1", "auth required pam_u2f.so cue " + passes), password("r2")], arch(), "R9"),
                   "R9: pam_u2f with " + passes + " on a required line nothing else asks beside (PAM_IGNORE no answer, the permit lets in)");
        for (const asks of ["userpresence=1", "userpresence=2", "userpresence=0 userpresence=1"])
            assert(!has([raw("r1", "auth sufficient pam_u2f.so cue " + asks), fixed], arch(), "R9"), "R9 not: pam_u2f " + asks + " (the last one decides; only 0 is off)");
        for (const passes of ["db=/etc/users unknown_ok", "db=/etc/users UNKNOWN_OK", "db=/etc/users DB=/tmp/users", "db=/etc/users [db=/tmp/x]"])
            assert(has([raw("r1", "auth sufficient pam_userdb.so " + passes), fixed], arch(), "R9"), "R9: pam_userdb " + passes);
        assert(!has([raw("r1", "auth sufficient pam_userdb.so DB=/etc/users"), fixed], arch(), "R9"), "R9 not: pam_userdb DB= under /etc");
        for (const bad of ["account required pam_unix.so", "auth sufficient", "auth include system-auth", "@include common-auth",
                           "auth required pam_unix.so\nauth sufficient pam_permit.so", "auth [sucess=done] pam_unix.so"])
            assert(has([raw("r1", bad), fixed], arch(), "R8"), "R8: " + JSON.stringify(bad));
        assert(has([raw("r1", "auth sufficient pam_ldap.so"), fixed], arch(nixos()), "R8"), "R8: a bare module name on NixOS");
        assertEqual(rules.rawLine("auth sufficient pam_fprintd.so", nixos()).refusal.text, "Needs the module's full path on NixOS.",
                    "… with the integration's text");
        assertEqual(rules.rawLine("auth sufficient pam_fprintd.so", nixos({ texts: {} })).refusal.text, "Needs the module's full path.",
                    "… or the general one");
        assertEqual(rules.rawLine("auth sufficient pam_ldap.so", { bareModules: "" }).refusal, null, "… not where libpam finds any module by name");
        assert(!has([raw("r1", "auth required pam_env.so"), fixed], arch(nixos()), "R8"), "R8 not: libpam's own module by name on NixOS");
        assert(!has([raw("r1", "-auth [success=done default=ignore] pam_ldap.so use_first_pass"), fixed], arch(), "R8"), "R8 not: a bracketed auth line");
        assert(has([raw("r1", "auth [success=done default=ignore] pam_permit.so"), fixed], arch(), "R9"), "R9: success=done");
        assert(has([raw("r1", "auth [default=done default=bad] pam_permit.so"), fixed], arch(), "R9"), "R9: the first default is libpam's (done)");
        assert(has([raw("r1", "auth required pam_permit.so"), fingerprint("r2")], arch(), "R9"), "R9: nothing after it decides");
        assert(has([raw("r1", "auth sufficient pam_rootok.so"), fixed], arch({ service: "polkit-1" }), "R9"), "R9: pam_rootok for polkit");
        assert(has([raw("r1", "auth sufficient pam_rootok.so"), fixed], arch(), "R9"), "R9: pam_rootok for sudo too: it asks for no credential");
        assert(!has([raw("r1", "auth required pam_permit.so"), fixed], arch(), "R9"), "R9 not: the fixed row decides after it");
        assert(!has([raw("r1", "auth required pam_permit.so"), password("r2", "required")], arch(), "R9")
               && has([raw("r1", "auth required pam_permit.so"), password("r2", "required")], arch(), "W22"),
               "W22, not R9: a required line that asks for nothing beside a required password row (the password still asks)");
        assertEqual(rules.check([raw("r1", "auth required pam_permit.so"), password("r2", "required")], arch()).warnings.find(found => found.code === "W22")?.text,
                    "This line asks for nothing: only the other rows decide.", "… its text");
        assert(has([raw("r1", "auth required pam_permit.so"), password("r2")], arch(), "R9"),
               "R9: required beside only a sufficient password row (nothing else must pass: the permit closing keeps its pass)");
        assert(!has([raw("r1", "auth [success=ok default=ignore] pam_usertype.so isregular"), fixed], arch(), "R9")
               && has([raw("r1", "auth [success=ok default=ignore] pam_usertype.so isregular"), fixed], arch(), "W22"),
               "W22, not R9: ok on success above the fixed row (the system's rules still decide)");
        assert(!has([raw("r1", "auth optional pam_permit.so"), fixed], arch(), "W22"), "W22 not: an optional line decides nothing");
        for (const lets of ["auth sufficient pam_succeed_if.so uid >= 0", "auth sufficient pam_localuser.so", "auth sufficient pam_shells.so",
                            "auth sufficient pam_wheel.so trust",
                            "auth sufficient pam_listfile.so sense=allow item=user file=/etc/x onerr=fail", "auth [default=done] pam_access.so"])
            assert(has([raw("r1", lets), fixed], arch(), "R9"), "R9: a module that asks for no credential lets in: " + lets);
        assert(!has([raw("r1", "auth sufficient pam_userdb.so db=/etc/x"), fixed], arch(), "R9"), "R9 not: pam_userdb asks for a credential");
        assert(!has([raw("r1", "auth sufficient pam_ldap.so"), fixed], arch(), "R9"), "R9 not: an unknown module (W4)");
        assert(!has([raw("r1", "auth optional pam_succeed_if.so uid >= 0"), fixed], arch(), "R9"), "R9 not: optional cannot let in");
        // Credential modules made to pass by their arguments
        assert(!has([raw("r1", "auth sufficient pam_u2f.so cue nouserok"), fixed], arch(), "R9")
               && !has([raw("r1", "auth sufficient pam_u2f.so cue nouserok"), fixed], arch(), "W21"),
               "R9 not: a sufficient nouserok line (PAM_IGNORE: the next row is tried)");
        assert(has([raw("r1", "auth sufficient pam_u2f.so userpresence=0"), fixed], arch(), "R9"), "R9: pam_u2f userpresence=0");
        assert(!has([raw("r1", "auth sufficient pam_u2f.so cue"), fixed], arch(), "R9"), "R9 not: pam_u2f as it is");
        assert(!has([raw("r1", "auth optional pam_u2f.so nouserok"), fixed], arch(), "R9"), "R9 not: nouserok on a line that cannot let in");
        assert(has([raw("r1", "auth sufficient pam_userdb.so db=/home/user/db"), fixed], arch(), "R9"), "R9: pam_userdb with a database outside /etc");

        // W15–W21: a key line whose own check pam_u2f's settings void
        const settings = more => Object.assign({ known: true, alwaysok: false, nouserok: false, touchOff: false, interactive: false }, more ?? {});
        const machine = (rows, conf) => arch({ u2f: { rows: settings(rows), conf: settings(conf) } });
        const warned = (rows, facts) => rules.check(rows, facts).warnings.filter(found => /^W(1[5-79]|2[01])$/.test(found.code))
            .map(found => found.code + "@" + found.row).sort().join(" ");
        const textOf = (rows, facts, code) => rules.check(rows, facts).warnings.find(found => found.code === code)?.text ?? "";
        assertEqual(warned([key("r1"), fixed], machine({ alwaysok: true })), "W15@0", "W15: an own key row with the system's alwaysok, sufficient");
        assert(!has([key("r1"), fixed], machine({ alwaysok: true }), "R9"), "… a warning, never a refusal: the setting is the system's");
        assertEqual(textOf([key("r1"), fixed], machine({ alwaysok: true }), "W15"),
                    "This row lets anyone in without a key: the system's pam_u2f settings have alwaysok.", "… its text");
        assertEqual(warned([key("r1", "required"), password("r2")], machine({ alwaysok: true })), "W15@0", "W15: required, the permit closing keeps its pass");
        assertEqual(warned([key("r1", "required"), fixed], machine({ alwaysok: true })), "W19@0",
                    "W19: required above the fixed row: no longer asks for a key, the other rows decide");
        assertEqual(textOf([key("r1", "requisite"), fixed], machine({ alwaysok: true }), "W19"),
                    "This row no longer asks for a key: the system's pam_u2f settings have alwaysok. Only the other rows decide.", "… requisite too, its text");
        assertEqual(warned([key("r1"), fixed], machine({ touchOff: true })), "W16@0", "W16: an own key row with userpresence=0");
        assertEqual(textOf([key("r1"), fixed], machine({ touchOff: true }), "W16"),
                    "While a key is plugged in, any program may pass this row without a touch: the system's pam_u2f settings have userpresence=0.", "… its text");
        assertEqual(warned([key("r1", "required"), fixed], machine({ touchOff: true })), "W20@0", "W20: required above the fixed row");
        assert(!has([row("r1", "securityKey", "sufficient", { pin: "yes", cue: true }), fixed], machine({ alwaysok: true }), "W15"),
               "W15 not: a row already refused (R4) is not judged further");
        assertEqual(warned([key("r1"), fixed], machine()) + warned([key("r1", "required"), fixed], machine()), "",
                    "nothing with settings that ask for a key and a touch");
        for (const control of ["sufficient", "required", "requisite"]) {
            assertEqual(warned([key("r1", control), password("r2")], machine({ nouserok: true })) + warned([key("r1", control), fixed], machine({ nouserok: true })), "",
                        "nouserok on an own " + control + " row: nothing (written with ignore=bad, PAM_IGNORE fails it)");
        }
        assert(has([key("r1"), fixed], arch({ u2f: { rows: settings({ known: false }), conf: settings() } }), "W18")
               && has([key("r1", "required"), fixed], arch({ u2f: { rows: settings({ known: false }), conf: settings() } }), "W18"),
               "W18: the system's settings could not be read, whatever the control");
        assertEqual(warned([key("r1"), fixed], arch()) + (has([key("r1"), fixed], arch(), "W18") ? "W18" : ""), "", "no u2f facts yet: nothing said");
        assertEqual(warned([raw("r1", "auth sufficient pam_u2f.so cue"), fixed], machine({}, { alwaysok: true })), "W15@0",
                    "W15: a raw pam_u2f line by pam_u2f.conf's alwaysok");
        assertEqual(warned([raw("r1", "auth required pam_u2f.so cue"), fixed], machine({}, { alwaysok: true })), "W19@0", "W19: … required above the fixed row");
        assertEqual(warned([raw("r1", "auth sufficient pam_u2f.so cue"), fixed], machine({ alwaysok: true }, {})), "",
                    "… a raw line is not judged by the own row's settings");
        assert(has([raw("r1", "auth sufficient pam_u2f.so cue conf=/etc/other.conf"), fixed], machine({}, { alwaysok: true }), "W18")
               && warned([raw("r1", "auth sufficient pam_u2f.so cue conf=/etc/other.conf"), fixed], machine({}, { alwaysok: true })) === "",
               "W18: a raw line with a settings file of its own (not read)");
        assertEqual(warned([raw("r1", "auth sufficient pam_u2f.so cue alwaysok"), fixed], machine({}, { alwaysok: true })), "",
                    "… a line its own words let in is R9's, not a warning");
        assertEqual(warned([raw("r1", "auth required pam_u2f.so cue nouserok"), fixed], arch()), "W21@0",
                    "W21: a raw plain required nouserok above the fixed row (PAM_IGNORE is no answer), without u2f facts too");
        assertEqual(textOf([raw("r1", "auth required pam_u2f.so cue nouserok"), fixed], arch(), "W21"),
                    "A user without a registered key skips this row: this line has nouserok. Only the other rows decide.", "… its text names the line");
        assertEqual(warned([raw("r1", "auth required pam_u2f.so cue alwaysok"), fixed], arch()), "W19@0", "W19: a raw required alwaysok above the fixed row");
        assertEqual(warned([raw("r1", "auth [success=ok new_authtok_reqd=ok ignore=bad default=bad] pam_u2f.so cue nouserok"), fixed], arch()), "",
                    "W21 not: ignore=bad fails the line for a user without a key");
        assertEqual(warned([raw("r1", "auth required pam_u2f.so cue"), password("r2")], machine({}, { nouserok: true })), "W17@0",
                    "W17: pam_u2f.conf's nouserok on a raw plain required line the permit closes");
        assertEqual(warned([raw("r1", "auth required pam_u2f.so cue"), fixed], machine({}, { nouserok: true })), "W21@0", "W21: … above the fixed row");
        assertEqual(warned([raw("r1", "auth optional pam_u2f.so cue"), fixed], machine({}, { alwaysok: true, nouserok: true })), "",
                    "nothing for a line that decides nothing");
        assertEqual(warned([key("r1", "required"), password("r2", "required")], machine({ alwaysok: true })), "W19@0",
                    "W19, not W15: a required password row still asks beside a required key row the permit closes");
        assertEqual(warned([key("r1", "required"), key("r2", "required")], machine({ alwaysok: true })), "W15@0 W15@1",
                    "W15: two required key rows both voided: neither still asks, anyone gets in");
        assertEqual(warned([key("r1", "required"), raw("r2", "auth required pam_permit.so")], machine({ alwaysok: true })), "W15@0",
                    "W15: a required row that asks for nothing does not count as asking");
        assertEqual(warned([raw("r1", "auth [success=ok default=ignore] pam_u2f.so cue"), fixed], machine({}, { alwaysok: true })), "W19@0",
                    "W19: a raw ok-on-success line above the fixed row (the system's rules still decide)");
        assertEqual(textOf([raw("r1", "auth sufficient pam_u2f.so cue conf=/etc/other.conf"), fixed], machine(), "W18"),
                    "This line reads its own settings file (conf=), which the checks do not read: they cannot tell whether it needs a key and a touch.",
                    "W18: its own text for a line with conf=");
        assert(!has([raw("r1", "auth [success=ok new_authtok_reqd=ok ignore=bad default=bad] pam_u2f.so cue nouserok")], arch({ otherService: [] }), "R9"),
               "R9 not: nouserok on a line whose ignore=bad fails a user without a key");
        assertEqual(warned([raw("r1", "auth [success=ok ignore=ok default=bad] pam_u2f.so cue nouserok"), fixed], arch()), "",
                    "W21 not: ignore=ok (in auth PAM_IGNORE then stays the result, a failure)");
        assert(!has([raw("r1", "auth [success=ok ignore=done default=bad] pam_u2f.so cue nouserok"), password("r2", "required")], arch(), "R9"),
               "R9 not: … nor ignore=done");
        assert(has([raw("r1", "auth required pam_u2f.so cue nouserok"), password("r2", "sufficient")], arch(), "R9"),
               "R9: a plain required nouserok without the fixed row (PAM_IGNORE no answer, the permit lets in)");
        assertEqual(textOf([key("r1"), fixed], arch({ u2f: { rows: settings({ known: false }), conf: settings() } }), "W18"), rules.texts.W18,
                    "W18: an own row's text names the system's settings");
        const cleanRaw = raw("r2", "auth required pam_u2f.so cue");
        assertEqual(warned([key("r1", "required"), cleanRaw], machine({ alwaysok: true }, {})), "W19@0",
                    "W19: a raw key line the settings leave asking still asks beside a voided own key row");
        assertEqual(warned([raw("r1", "auth required pam_u2f.so cue"), key("r2", "required")], machine({}, { alwaysok: true })), "W19@0",
                    "… and an own key row the settings leave asking beside a voided raw one");
        for (const line of ["auth [success=ok default=ignore] pam_u2f.so cue alwaysok", "auth required pam_u2f.so cue alwaysok"]) {
            const rows = [raw("r1", line), password("r2", "required")];
            assert(!has(rows, arch(), "R9") && !has(rows, arch(), "W22") && warned(rows, arch()) === "W19@0", "W19, not R9 or W22, beside a required password row: " + line);
        }
        const aloneRows = [raw("r1", "auth required pam_u2f.so cue alwaysok"), password("r2")];
        assert(has(aloneRows, arch(), "R9") && warned(aloneRows, arch()) === "", "R9, not a warning, where nothing else must pass");
        const okRows = [raw("r1", "auth [success=ok default=ignore] pam_u2f.so cue alwaysok"), password("r2")];
        assert(!has(okRows, arch(), "R9") && warned(okRows, arch()) === "", "… ok on success before the deny closing decides nothing: neither");
        // Rows that do not ask for the others
        const conf = more => arch({ u2f: { rows: settings(), conf: settings(more) } });
        assertEqual(warned([raw("r1", "auth required pam_u2f.so cue"), raw("r2", "auth required pam_u2f.so cue")], conf({ nouserok: true })), "W17@0 W17@1",
                    "W17 on both: two raw key lines whose nouserok lets a user without a key past each");
        assertEqual(warned([raw("r1", "auth required pam_u2f.so cue"), raw("r2", "auth required pam_u2f.so cue")], conf({ touchOff: true })), "W16@0 W16@1",
                    "W16 on both: neither asks for a touch");
        assertEqual(warned([key("r1", "required"), password("r2", "required")], machine({ touchOff: true })), "W20@0",
                    "W20: a required password row still asks");
        // A wrong credential fails the stack only where its code (auth_err, else default) is bad or die
        assert(has([raw("r1", "auth [success=ok ignore=bad default=ignore] pam_unix.so")], arch({ fingerprint: "absent", otherService: [] }), "R1"),
               "R1: a pam_unix line whose wrong password is ignored does not fail the stack: the deny closing, nobody in");
        assertEqual(rules.closingOf([raw("r1", "auth [success=ok ignore=bad default=ignore] pam_unix.so")], arch()), "deny",
                    "… its closing is the deny, never the permit that would let a wrong password in");
        assertEqual(rules.closingOf([raw("r1", "auth [success=ok auth_err=die default=ignore] pam_unix.so")], arch()), "permit",
                    "… auth_err=die fails it: the permit closing");
        assert(has([raw("r1", "auth sufficient pam_userdb.so"), fixed], arch(), "R9"), "R9: pam_userdb without a database");
        assert(has([raw("r1", "auth sufficient pam_userdb.so db=/etc/../home/u/db"), fixed], arch(), "R9"), "R9: … through ..");
        assert(has([raw("r1", "auth sufficient pam_unix.so nullok"), fixed], arch(), "W9"), "W9: pam_unix nullok");
        assert(!has([raw("r1", "auth sufficient pam_unix.so nullok"), fixed], arch(), "R9"), "… only a warning");
        assert(!has([raw("r1", "auth sufficient pam_unix.so"), fixed], arch(), "W9"), "W9 not: without nullok");
        // ok on success decides only where the closing line keeps the result
        assert(has([raw("r1", "auth [success=ok default=ignore] pam_unix.so")], arch({ fingerprint: "absent" }), "R1"),
               "R1: ok on success before the deny closing lets nobody in");
        assert(!has([raw("r1", "auth [success=ok default=bad] pam_unix.so")], arch({ fingerprint: "absent" }), "R1"),
               "R1 not: a bracketed bad picks the permit closing, which keeps the ok");
        assertEqual(rules.closingOf([raw("r1", "auth [success=ok default=bad] pam_unix.so")], {}), "permit", "a bracketed bad: the permit closing");
        assertEqual(rules.closingOf([raw("r1", "auth [success=ok default=ignore] pam_unix.so"), fingerprint("r2")], {}), "deny", "no row that fails: the deny closing");
        assertEqual(rules.closingOf([fingerprint("r1"), fixed], {}), "system", "the fixed row: the system's lines");
        assert(!has([raw("r1", "auth [success=ok default=ignore] pam_unix.so"), fixed], arch({ fingerprint: "absent" }), "R1"),
               "R1 not: ok beside the fixed row");
        // Nobody in
        assert(has([raw("r1", "auth requisite pam_deny.so"), fixed], arch(), "R1"), "R1: a raw pam_deny that fails");
        assert(!has([raw("r1", "auth optional pam_deny.so"), fixed], arch(), "R1"), "R1 not: an optional pam_deny");
        assert(has([raw("r1", "auth sufficient pam_unix.so use_first_pass")], arch({ fingerprint: "absent" }), "R1"),
               "R1: use_first_pass with no password asked above");
        assert(has([raw("r1", "auth sufficient pam_unix.so use_first_pass"), fixed], arch(), "W10"), "W10: … a warning");
        assert(!has([raw("r1", "auth required pam_unix.so"), raw("r2", "auth sufficient pam_unix.so use_first_pass")],
                    arch({ fingerprint: "absent" }), "W10"), "W10 not: a password asked above");
        // A trailing backslash would join the next line of the file (the system's include) to this one
        for (const joined of ["auth optional pam_permit.so \\", "auth optional pam_permit.so \\  # why", "auth sufficient pam_unix.so a\\b"])
            assert(has([raw("r1", joined), fixed], arch(), "R8"), "R8: a backslash outside brackets: " + JSON.stringify(joined));
        assert(!has([raw("r1", "auth required pam_exec.so [a\\]b]"), fixed], arch(), "R8"), "R8 not: an escaped bracket inside a bracketed word");
        for (const jump of ["auth [success=ok default=9] pam_unix.so", "auth [auth_err=3 default=ignore] pam_ldap.so",
                            "auth [success=done default=reset] pam_unix.so"])
            assert(has([raw("r1", jump), fixed], arch(), "R8"), "R8: a jump or reset: " + jump);

        // --- every warning ---
        assert(!has([fingerprint("r1"), fixed], arch(), "W1"), "W1 not: the fixed row is a password");
        assert(!has([fingerprint("r1")], arch({ fingerprint: "absent" }), "W1"), "W1 not when refused: no way in at all");
        assert(has([fingerprint("r1", "required"), fixed], arch(), "W2"), "W2: a required reader");
        assert(has([key("r1", "requisite"), fixed], arch(), "W2"), "W2: a requisite key");
        assert(!has([fingerprint("r1", "sufficient"), fixed], arch(), "W2"), "W2 not: sufficient");
        let result = rules.check([password("r1", "sufficient", true), fingerprint("r2"), fixed], arch());
        let found = result.warnings.find(warning => warning.code === "W3");
        assert(found !== undefined && found.row === 0 && found.id === "r1", "W3: a counted password above a reader, on its row");
        assertEqual(found.text, "An empty Enter to reach the reader counts as a wrong password (3 lock you out for 10 min).", "… with the numbers");
        assert(!has([password("r1", "sufficient", false), fingerprint("r2"), fixed], arch(), "W3"), "W3 not: uncounted");
        assert(!has([fingerprint("r2"), password("r1", "sufficient", true), fixed], arch(), "W3"), "W3 not: the reader above it");
        assert(has([raw("r1", "auth sufficient pam_ldap.so"), fixed], arch(), "W4"), "W4: a module the checks do not know");
        assert(!has([raw("r1", "auth sufficient pam_unix.so try_first_pass"), fixed], arch(), "W4"), "W4 not: a raw pam_unix line");
        assert(!has([raw("r1", "auth sufficient pam_ldap.so"), fixed], arch(nixos()), "W4"), "W4 not: a refused line");
        // W13: an unknown module's required line where nothing below decides
        result = rules.check([password("r1", "sufficient"), raw("r2", "auth required /usr/lib/security/pam_ldap.so")], arch());
        found = result.warnings.find(warning => warning.code === "W13");
        assert(found !== undefined && found.row === 1 && found.id === "r2", "W13: a raw required line of an unknown module, no fixed row, on its row");
        assertEqual(found.text, "If pam_ldap.so answers that it does not apply to someone, the list ends without a refusal and lets them in. "
                    + "Add the row \"Password (as the system)\", or make sure pam_ldap.so refuses users it does not know.", "… naming the module");
        assert(result.refusals.length === 0, "… a warning, not a refusal");
        assert(has([password("r1"), raw("r2", "auth requisite pam_ldap.so")], arch(), "W13"), "W13: requisite too");
        assert(has([password("r1"), raw("r2", "auth required /home/u/pam_unix.so")], arch(), "W13"), "W13: a module from outside, whatever its name");
        assert(!has([raw("r1", "auth required pam_ldap.so"), fixed], arch(), "W13"), "W13 not: the fixed row decides below");
        assert(!has([password("r1"), raw("r2", "auth sufficient pam_ldap.so")], arch(), "W13"), "W13 not: sufficient");
        assert(!has([password("r1"), raw("r2", "auth [success=ok default=bad] pam_ldap.so")], arch(), "W13"), "W13 not: a bracketed control that fails on ignore");
        assert(!has([password("r1"), raw("r2", "auth [success=ok ignore=die default=ignore] pam_ldap.so")], arch(), "W13"), "W13 not: … ignore=die");
        assert(has([password("r1"), raw("r2", "auth [success=ok ignore=ignore default=bad] pam_ldap.so")], arch(), "W13"),
               "W13: a bracketed control that fails but lets ignore pass");
        assert(!has([password("r1"), raw("r2", "auth [success=ok auth_err=die] pam_ldap.so")], arch(), "W13"),
               "W13 not: ignore not named and no default is bad in libpam");
        for (const action of ["ok", "done"])
            assert(!has([password("r1"), raw("r2", "auth [success=ok ignore=" + action + " default=bad] pam_ldap.so")], arch(), "W13"),
                   "W13 not: ignore=" + action + " (in auth PAM_IGNORE then stays the result, a failure)");
        assert(!has([password("r1"), raw("r2", "auth required pam_unix.so")], arch(), "W13"), "W13 not: a module the shell knows");
        assert(!has([password("r1"), raw("r2", "auth required pam_ldap.so")], arch(nixos()), "W13"), "W13 not: a refused line");
        // W14: no time limit on a reader above a password
        const endless = fingerprint("r1", "sufficient", { timeout: -1 });
        result = rules.check([endless, fixed], arch());
        found = result.warnings.find(warning => warning.code === "W14");
        assert(found !== undefined && found.row === 0, "W14: an unlimited reader above the system's password, on its row");
        assertEqual(found.text, "Waits for the finger until it is touched or the prompt is cancelled: the password is asked only after that.", "… its text");
        assert(has([endless, password("r2", "required")], arch(), "W14"), "W14: … above an own password row");
        assert(has([endless, raw("r2", "auth sufficient pam_unix.so")], arch(), "W14"), "W14: … above a raw password line");
        assert(!has([fingerprint("r1", "sufficient", { timeout: 600 }), fixed], arch(), "W14"), "W14 not: a time limit");
        assert(!has([password("r1", "required"), endless], arch(), "W14"), "W14 not: the password above it");
        assert(!has([fingerprint("r1", "required", { timeout: -1 }), fixed], arch(), "W14"), "W14 not: a required reader (both are asked anyway)");
        assert(!has([endless, key("r2")], arch(), "W14"), "W14 not: no password below");
        assert(!has([fingerprint("r1", "sufficient", { tries: -1 }), fixed], arch(), "W14"), "W14 not: unlimited tries only");
        result = rules.check([fingerprint("r1"), fingerprint("r2"), fixed], arch());
        assertEqual(result.warnings.filter(warning => warning.code === "W6").map(warning => warning.id).join(" "), "r2", "W6: the second of two");
        assert(has([password("r1", "required"), raw("r2", "auth sufficient pam_unix.so"), fixed], arch(), "W6"), "W6: a raw line of the same method");
        assert(!has([fingerprint("r1"), key("r2"), fixed], arch(), "W6"), "W6 not: two methods");
        assert(has([password("r1", "sufficient"), fixed], arch(), "W7"), "W7: a sufficient password above the fixed row");
        assert(!has([password("r1", "sufficient")], arch(), "W7"), "W7 not: without the fixed row");
        assert(!has([password("r1", "required"), fixed], arch(), "W7"), "W7 not: required");
        assert(has([fingerprint("r1"), fixed], arch({ sharedApplyStopped: true, otherService: [fixed] }), "W8"), "W8: a shared Apply stopped between the two");
        assert(!has([fingerprint("r1"), fixed], arch({ sharedApplyStopped: true, otherService: [fingerprint("x"), fixed] }), "W8"), "W8 not: the lists agree");
        assert(!has([fingerprint("r1"), fixed], arch({ otherService: [fixed] }), "W8"), "W8 not: lists split on purpose");

        // --- the items ---
        result = rules.check([fingerprint("r1", "required"), fixed], arch({ fingerprint: "absent", changedByHand: true }));
        assertEqual(JSON.stringify(result.refusals.concat(result.risks).map(refusal => [refusal.code, refusal.row, refusal.id])),
                    JSON.stringify([["R6", -1, ""], ["R2", 0, "r1"]]), "each item names its row, −1 for the list");

        // --- risks: written once confirmed, never refused; what cannot be written is refused ---
        const kinds = (rows, facts) => {
            const checked = rules.check(rows, facts);
            const say = list => list.map(found => found.code).filter((code, i, all) => all.indexOf(code) === i).sort().join(" ");
            return "refused: " + say(checked.refusals) + " / risks: " + say(checked.risks);
        };
        assertEqual(kinds([fingerprint("r1")], arch({ fingerprint: "absent", otherService: [] })), "refused:  / risks: R1 R5", "R1, R5: risks, not refusals");
        assertEqual(kinds([raw("r1", "auth required pam_deny.so"), fixed], arch()), "refused:  / risks: R1", "R1 (a raw pam_deny): a risk");
        assertEqual(kinds([fingerprint("r1", "required"), fixed], arch({ fingerprint: "absent" })), "refused:  / risks: R2", "R2: a risk");
        assertEqual(kinds([], arch()), "refused:  / risks: R3", "R3: a risk");
        assertEqual(kinds([raw("r1", "auth sufficient pam_permit.so"), fixed], arch()), "refused:  / risks: R9", "R9: a risk");
        assertEqual(kinds([fingerprint("r1", "sufficient", { tries: 21 }), fixed], arch()), "refused: R4 / risks: ", "R4: still refused");
        assertEqual(kinds([fixed], arch({ changedByHand: true })), "refused: R6 / risks: ", "R6: still refused");
        assertEqual(kinds([raw("r1", "account required pam_unix.so"), fixed], arch()), "refused: R8 / risks: ", "R8: still refused");
        assertEqual(kinds([], arch({ changedByHand: true })), "refused: R6 / risks: R3", "an empty list changed by hand: both");
        assert(rules.codes({ refusals: [], risks: [{ code: "R9" }], warnings: [{ code: "W1" }] }).join(" ") === "R9 W1", "codes take the risks too");
        assertEqual(rules.rawLine("-auth [success=done default=ignore] pam_ldap.so", {}).reads, "-auth · [success=done default=ignore] · pam_ldap.so",
                    "what a raw line reads as");
        assertEqual(codes([fingerprint("r1"), fixed], arch()).length, 0, "a reader above the system's password: nothing to say");

        // --- edges (tests/mutate.sh) ---
        assert(!has([fingerprint("r1", "sufficient", { tries: 1 }), fixed], arch(), "R4"), "R4 not: one try");
        assert(has([fingerprint("r1", "sufficient", { tries: 21 }), fixed], arch(), "R4"), "R4: tries above 20");
        assert(rules.detailOffered("fingerprint", "timeout", { faillockPresent: false }), "a reader's detail is offered without pam_faillock");
        assert(!rules.detailOffered("fingerprint", "pin", {}) && !rules.detailOffered("fingerprint", "counted", { faillockPresent: true }),
               "… a detail the method does not have is not");
        assertEqual(["0", "30", "60", "90", "3600", "5400", "7200"].map(seconds => rules.duration(seconds)).join(" / "),
                    "0 s / 30 s / 1 min / 90 s / 1 h / 90 min / 2 h", "durations: whole hours, whole minutes, else seconds");
        assertEqual(rules.faillockSummary({ deny: 0, failInterval: 900, unlockTime: 600 }), "Counts: off", "faillock off");
        assertEqual(rules.faillockSummary({ deny: 3, failInterval: 900, unlockTime: 0 }), "Counts: 3 wrong in 15 min lock until reset", "… until reset");
        assert(!rules.countedHint(null).includes("(") && !rules.countedHint({ deny: 0, failInterval: 60, unlockTime: 0 }).includes("("),
               "the counting hint without numbers where nothing counts");
        assert(rules.countedHint({ deny: 1, failInterval: 60, unlockTime: 0 }).includes("(1 wrong in 1 min lock until reset)"), "… with them where it does");
        assertEqual(rules.nextId([]), "r1", "the first id");
        assert(!rules.canMove(fixed) && rules.canMove(fingerprint("r1")) && !rules.canEdit(fixed) && rules.canEdit(password("r1")),
               "only the fixed row cannot be moved or edited");
        assertEqual(rules.insertRow([fixed], password("r2"), 5).map(item => item.id).join(" "), "r2 system", "a row goes above the fixed row in first place");
        assertEqual(rules.insertRow(list, password("r2"), 0).map(item => item.id).join(" "), "r2 r1 system", "a row inserted at the top");
        const three = [fingerprint("r1"), password("r2"), fixed];
        for (const from of [-1, 3])
            assertEqual(rules.moveRow(three, from, 0).map(item => item.id).join(" "), "r1 r2 system", "nothing moves from outside the list: " + from);
        assertEqual(rules.moveRow(three, 1, 0).map(item => item.id).join(" "), "r2 r1 system", "a row moved to the top");
        assertEqual(rules.removeRow(three, "r1").map(item => item.id).join(" "), "r2 system", "the first row removed, only it");
        let changed = rules.changeRow(three, "r2", { control: "required" });
        assert(changed[1].control === "required" && changed[0].control === "sufficient", "the word of the row named changed, only its");
        changed = rules.changeRow(three, "r1", { details: { timeout: 20 } });
        assert(changed[0].details.timeout === 20 && changed[0].control === "sufficient", "a detail changed, the word kept");
        assertEqual(rules.changeRow([raw("r1", "auth sufficient pam_unix.so")], "r1", { control: "required" })[0].control, "", "a raw line takes no word");
        assert(rules.sameRows([Object.assign(raw("a", "x"), { control: "required" })], [raw("b", "x")]), "a raw line's word does not count");
        assert(!rules.sameRows([password("a", "sufficient")], [password("b", "required")]), "a row's word does");
        lists = rules.listsFor({ split: true, sudo: [password("r1")], polkit: [fingerprint("r1")] });
        assert(lists["sudo"][0].method === "password" && lists["polkit-1"][0].method === "fingerprint", "split: each service its own list");
        assertEqual(rules.otherService("sudo") + " " + rules.otherService("polkit-1"), "polkit-1 sudo", "the other service");
        assertEqual(joined.split, false, "joined: not split");
        const longLine = text => text + " #" + "x".repeat(rules.maxRawLength - text.length - 2);
        assertEqual(rules.rawLine(longLine("auth sufficient pam_unix.so"), {}).refusal, null, "a raw line of the longest length");
        assertEqual(rules.rawLine(longLine("auth sufficient pam_unix.so") + "x", {}).reads, "Too long", "… one more character is too long");
        assertEqual(rules.closingOf([row("r1", "smartcard")], {}), "deny", "an unknown row fails nothing: the deny closing");
        assert(has([fingerprint("r1"), raw("r2", "auth sufficient pam_unix.so use_first_pass")], arch(), "W10"),
               "W10: a reader above is no password asked");
        assert(!has([fixed, raw("r1", "auth required pam_permit.so")], arch(), "R9"), "R9 not: the fixed row present, even first");
        assert(has([raw("r1", "auth sufficient /home/u/pam_permit.so"), fixed], arch(), "W12")
               && has([raw("r1", "auth sufficient /home/u/pam_permit.so"), fixed], arch(), "R9"), "R9: a module from another place is refused by its name");
        assert(!has([raw("r1", "auth sufficient pam_ldap.so"), raw("r2", "auth sufficient pam_krb5.so"), fixed], arch(), "W6"),
               "W6 not: two lines the checks do not know");
        for (const unknown of [null, { deny: 0, failInterval: 60, unlockTime: 0 }]) {
            const text = rules.check([password("r1", "sufficient", true), fingerprint("r2"), fixed], arch({ faillock: unknown }))
                .warnings.find(warning => warning.code === "W3").text;
            assertEqual(text, rules.texts.W3, "W3 without numbers: " + JSON.stringify(unknown));
        }
        found = rules.check([password("r1", "sufficient", true), fingerprint("r2"), fixed], arch({ faillock: { deny: 1, failInterval: 60, unlockTime: 0 } }))
            .warnings.find(warning => warning.code === "W3");
        assertEqual(found.text, "An empty Enter to reach the reader counts as a wrong password (1 lock you out until reset).", "W3: one, until reset");
        const listWide = [rules.check([], arch()), rules.check([fingerprint("r1")], arch({ fingerprint: "absent", otherService: null })),
                          rules.check([fingerprint("r1")], arch({ sharedApplyStopped: true, otherService: [password("p1")] }))];
        const items = listWide.reduce((all, result) => all.concat(result.refusals, result.risks, result.warnings), []).filter(item => ["R1", "R3", "R5", "W1", "W8"].includes(item.code));
        assertEqual(items.map(item => item.code).filter((code, i, all) => all.indexOf(code) === i).sort().join(" "), "R1 R3 R5 W1 W8", "(each list-wide code made)");
        assert(items.every(item => item.row === -1 && item.id === ""), "list-wide items name row −1: " + JSON.stringify(items.map(item => [item.code, item.row])));

        // A password row with an unknown word decides nothing, even where the permit closes
        const unknownWord = [password("r1", "bogus"), fingerprint("r2", "required")];
        assertEqual(codes(unknownWord, arch()).join(" "), "R4 W1 W2", "a password row with an unknown word: refused, and no password in the list");
        // The fixed row first is still the fixed row for W13 (its place is R4's)
        assertEqual(codes([fixed, raw("r2", "auth required pam_ldap.so")], arch()).includes("W13"), false, "the fixed row first: no W13");
        // A raw key line refused for its place is not judged for what it lets in
        const bareKey = [raw("r1", "auth sufficient pam_u2f.so alwaysok"), fixed];
        assertEqual(codes(bareKey, arch(nixos())).join(" "), "R8", "NixOS: a bare pam_u2f with alwaysok is refused for its name, nothing more");
    }
}
