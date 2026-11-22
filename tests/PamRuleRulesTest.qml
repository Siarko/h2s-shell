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
        const arch = (more) => Object.assign({ system: "arch", service: "sudo", fingerprint: "ready", securityKey: "ready",
                                               faillockPresent: true, faillock: { deny: 3, failInterval: 900, unlockTime: 600 },
                                               otherService: [rules.fixedRow()] }, more ?? {});
        const codes = (rows, facts) => rules.codes(rules.check(rows, facts));
        const has = (rows, facts, code) => codes(rows, facts).includes(code);

        // --- control words ---
        assertEqual(rules.controls.map(control => control.word).join(" "), "sufficient required requisite optional", "the four words, in order");
        assertEqual(rules.defaultControl, "sufficient", "a new row is sufficient");
        assertEqual(rules.explanation("requisite"), "Must pass. A failure ends it at once.", "a word's explanation");
        assertEqual(rules.explanation("include"), "", "no explanation for another word");

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
        assert(!has([raw("r1", "auth sufficient pam_unix.so")], arch(), "R1"), "R1 not: a raw pam_unix line is a password");
        assert(has([raw("r1", "auth sufficient pam_ldap.so")], arch(), "R1"), "R1: an unknown module is no way in");
        assert(has([fingerprint("r1", "required"), fixed], arch({ fingerprint: "absent" }), "R2"), "R2: a required reader not ready");
        assert(has([raw("r1", "auth requisite pam_u2f.so cue"), fixed], arch({ securityKey: "unknown" }), "R2"), "R2: … a raw key line too");
        assert(!has([fingerprint("r1", "sufficient"), fixed], arch({ fingerprint: "absent" }), "R2"), "R2 not: sufficient");
        assertEqual(codes([], arch()).join(" "), "R3", "R3: no rows");
        assert(!has([fixed], arch(), "R3"), "R3 not: the fixed row alone");
        assert(has([fingerprint("r1", "sufficient", { timeout: 121 }), fixed], arch(), "R4"), "R4: timeout above 120");
        assert(has([fingerprint("r1", "sufficient", { tries: 0 }), fixed], arch(), "R4"), "R4: tries below 1");
        assert(has([fingerprint("r1", "sufficient", { tries: 2.5 }), fixed], arch(), "R4"), "R4: tries not whole");
        assert(has([row("r1", "smartcard"), fixed], arch(), "R4"), "R4: an unknown method");
        assert(has([row("r1", "password", "include"), fixed], arch(), "R4"), "R4: an unknown word");
        assert(has([row("r1", "securityKey", "sufficient", { cue: false }), fixed], arch(), "R4"), "R4: cue cannot be turned off");
        assert(has([password("r1", "sufficient", true), fixed], arch({ faillockPresent: false }), "R4"), "R4: counted where nothing counts");
        assert(has([fixed, fingerprint("r1")], arch(), "R4"), "R4: the fixed row not last");
        assert(!has([fingerprint("r1", "sufficient", { timeout: 5, tries: 10 }), password("r2", "required", true), fixed], arch(), "R4"),
               "R4 not: the range's ends");
        let both = arch({ otherService: [fingerprint("p1")] });
        assert(has([fingerprint("r1")], both, "R5"), "R5: neither service keeps a password");
        assert(has([fingerprint("r1")], arch({ otherService: null }), "R5"), "R5: the other service not known counts as none");
        assert(!has([fingerprint("r1")], arch(), "R5"), "R5 not: the other keeps the system's password");
        assert(!has([fingerprint("r1"), fixed], both, "R5"), "R5 not: this one keeps it");
        assert(has([fixed], arch({ changedByHand: true }), "R6"), "R6: changed by hand");
        assert(!has([fixed], arch({ changedByHand: false }), "R6"), "R6 not: as written");
        assert(has([raw("r1", "auth sufficient /home/user/pam_evil.so"), fixed], arch(), "R7"), "R7: a module from the home");
        assert(has([raw("r1", "auth sufficient /usr/lib/security/../../../tmp/x.so"), fixed], arch(), "R7"), "R7: … through ..");
        assert(has([raw("r1", "auth sufficient lib/../../tmp/x.so"), fixed], arch(), "R7"), "R7: … a relative path");
        assert(has([raw("r1", "auth sufficient /nix/store/abc-pam_ldap/lib/security/pam_ldap.so"), fixed], arch(), "R7"), "R7: a store path on Arch");
        assert(!has([raw("r1", "auth sufficient /usr/lib/security/pam_ldap.so"), fixed], arch(), "R7"), "R7 not: the system's folder");
        assert(!has([raw("r1", "auth sufficient /nix/store/abc-pam_ldap/lib/security/pam_ldap.so"), fixed], arch({ system: "nixos" }), "R7"),
               "R7 not: the store on NixOS");
        for (const bad of ["account required pam_unix.so", "auth sufficient", "auth include system-auth", "@include common-auth",
                           "auth required pam_unix.so\nauth sufficient pam_permit.so", "auth [sucess=done] pam_unix.so"])
            assert(has([raw("r1", bad), fixed], arch(), "R8"), "R8: " + JSON.stringify(bad));
        assert(has([raw("r1", "auth sufficient pam_ldap.so"), fixed], arch({ system: "nixos" }), "R8"), "R8: a bare module name on NixOS");
        assertEqual(rules.rawLine("auth sufficient pam_fprintd.so", { system: "nixos" }).refusal.text, "Needs the module's full path on NixOS.",
                    "… with its text");
        assert(!has([raw("r1", "auth required pam_env.so"), fixed], arch({ system: "nixos" }), "R8"), "R8 not: libpam's own module by name on NixOS");
        assert(!has([raw("r1", "-auth [success=done default=ignore] pam_ldap.so use_first_pass"), fixed], arch(), "R8"), "R8 not: a bracketed auth line");
        assert(has([raw("r1", "auth [success=done default=ignore] pam_permit.so"), fixed], arch(), "R9"), "R9: success=done");
        assert(has([raw("r1", "auth required pam_permit.so"), fingerprint("r2")], arch(), "R9"), "R9: nothing after it decides");
        assert(has([raw("r1", "auth sufficient pam_rootok.so"), fixed], arch({ service: "polkit-1" }), "R9"), "R9: pam_rootok for polkit");
        assert(!has([raw("r1", "auth sufficient pam_rootok.so"), fixed], arch(), "R9"), "R9 not: pam_rootok for sudo");
        assert(!has([raw("r1", "auth required pam_permit.so"), fixed], arch(), "R9"), "R9 not: the fixed row decides after it");
        assert(!has([raw("r1", "auth required pam_permit.so"), password("r2", "required")], arch(), "R9"), "R9 not: a required password after it");

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
        assert(!has([raw("r1", "auth sufficient /home/u/x.so"), fixed], arch(), "W4"), "W4 not: a refused line");
        assert(has([fingerprint("r1", "optional"), fixed], arch(), "W5"), "W5: an optional row beside a deciding one");
        assert(has([password("r1", "optional")], arch(), "W5"), "W5: … without the fixed row the closing line decides");
        assert(!has([fingerprint("r1", "sufficient"), fixed], arch(), "W5"), "W5 not: no optional row");
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
        assertEqual(JSON.stringify(result.refusals.map(refusal => [refusal.code, refusal.row, refusal.id])),
                    JSON.stringify([["R6", -1, ""], ["R2", 0, "r1"]]), "each item names its row, −1 for the list");
        assertEqual(rules.rawLine("-auth [success=done default=ignore] pam_ldap.so", {}).reads, "-auth · [success=done default=ignore] · pam_ldap.so",
                    "what a raw line reads as");
        assertEqual(codes([fingerprint("r1"), fixed], arch()).length, 0, "a reader above the system's password: nothing to say");
    }
}
