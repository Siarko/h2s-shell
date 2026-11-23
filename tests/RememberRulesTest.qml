import QtQuick
import qs.singletons

// RememberRules (singletons/RememberRules.qml): the rule's text for a real timeout and a
// multi-call binary, polkitd.conf's text, the length polkitd resolves from its conf files
// (its order, GLib's key file reading, the values it refuses), what is installed, the kept
// authorizations in `pkcheck --list-temp` output as polkit 127/128 prints it, the shell's own
// revoke time, the NixOS line and the prompt's line.
TestCase {
    suiteName: "RememberRules"

    function run() {
        const rules = RememberRules;
        const json = value => JSON.stringify(value);

        // ---- The rule ----
        const arch = { user: "alex", timeout: "/usr/bin/timeout", program: "/usr/bin/timeout" };
        const nixos = { user: "alex", timeout: "/run/current-system/sw/bin/timeout",
                        program: "/nix/store/0abc-coreutils-full-9.11/bin/coreutils" };
        const archBody = "polkit.addRule(function(action, subject) {\n"
            + "    if (action.id == \"org.freedesktop.policykit.exec\" && subject.user == \"alex\" &&\n"
            + "        action.lookup(\"program\") == \"/usr/bin/timeout\")\n"
            + "        return \"auth_admin_keep\";\n"
            + "});\n";
        // The hash as sha256sum gives it for the body's bytes
        const archText = "// Written by h2s-shell 0343a0eabeee0d23a23643ae48f8d478aa908c4fc279fa594fc877367cc1c39b\n" + archBody;
        assertEqual(rules.ruleText(arch), archText, "Arch: the program alone, the header's hash that of the rest");
        const nixosBody = "polkit.addRule(function(action, subject) {\n"
            + "    if (action.id == \"org.freedesktop.policykit.exec\" && subject.user == \"alex\" &&\n"
            + "        action.lookup(\"program\") == \"/nix/store/0abc-coreutils-full-9.11/bin/coreutils\" &&\n"
            + "        action.lookup(\"command_line\").indexOf(\"/run/current-system/sw/bin/timeout \") == 0)\n"
            + "        return \"auth_admin_keep\";\n"
            + "});\n";
        assertEqual(rules.ruleText(nixos), "// Written by h2s-shell " + PamEditRules.sha256(nixosBody) + "\n" + nixosBody,
                    "a multi-call binary: the command line's first word must be the timeout too");
        assertEqual(rules.ruleText({ user: "alex", timeout: "/usr/local/bin/timeout", program: "/opt/coreutils/bin/timeout" }).includes("command_line"), false,
                    "a resolved file named timeout: the program alone");
        assert(rules.ruleText(Object.assign({}, arch, { user: "bob.smith-2$" })).includes("subject.user == \"bob.smith-2$\""), "a user name with dot, dash and $");
        for (const bad of [{ user: "al\"ex" }, { user: "" }, { user: "-x" }, { user: "a b" }, { user: undefined }, { user: "x".repeat(257) },
                           { timeout: "timeout" }, { timeout: "/usr/bin/time\"out" }, { program: "/usr/bin/x\ny" }, { program: "/usr/bin/" },
                           { program: "/usr/bin/a\\b" }, { timeout: undefined }, { timeout: "/opt/my tools/timeout" }, { program: "/usr/bin/time out" }])
            assertEqual(rules.ruleText(Object.assign({}, arch, bad)), "", "unusable fact " + json(bad) + ": no rule");
        assertEqual(rules.ruleText(null), "", "no facts: no rule");
        assert(rules.validUser("x".repeat(256)), "256 characters: a user name");

        // ---- polkitd.conf ----
        assertEqual(rules.confText(900),
                    "# Written by h2s-shell 0ac8bccb6ee68d61e21f29908fbcb37284225ab5e4f77160a44264f126b02e2c\n[Polkitd]\nExpirationSeconds=900\n",
                    "conf: the header's hash as sha256sum gives it");
        assertEqual(rules.confText(1).endsWith("ExpirationSeconds=1\n"), true, "one second is a length");
        assertEqual(rules.confText(4294967295).endsWith("=4294967295\n"), true, "the largest polkitd takes");
        for (const bad of [0, -5, 1.5, 4294967296, "900", NaN, undefined])
            assertEqual(rules.confText(bad), "", "no conf for " + bad);

        // ---- polkitd's length ----
        const etc = "/etc/polkit-1/polkitd.conf", run = "/run/polkit-1/polkitd.conf", share = "/usr/share/polkit-1/polkitd.conf";
        const vendor = "# Configuration file for the PolicyKit daemon\n\n[Polkitd]\n# ExpirationSeconds=300\n";
        const conf = value => "[Polkitd]\nExpirationSeconds=" + value + "\n";
        const length = files => { const got = rules.expirationSeconds(files); return [got.seconds, got.source, got.reason].join("|"); };
        assertEqual(length({}), "300||default", "no files: polkit's default");
        assertEqual(length({ [share]: vendor }), "300||default", "the vendor file, the key commented out: the default");
        assertEqual(length(undefined), "300||default", "nothing handed in: the default");
        assertEqual(length({ [share]: conf(600) }), "600|" + share + "|file", "the vendor file sets it");
        assertEqual(length({ [etc]: conf(900), [share]: conf(600) }), "900|" + etc + "|file", "/etc first");
        assertEqual(length({ [run]: conf(120), [share]: conf(600) }), "120|" + run + "|file", "/run before /usr/share");
        assertEqual(length({ [etc]: conf(900), [run]: conf(120) }), "900|" + etc + "|file", "/etc before /run");
        assertEqual(length({ [etc]: "[Polkitd]\n", [share]: conf(600) }), "600|" + share + "|file", "a file without the key passes on");
        assertEqual(length({ [etc]: "[Other]\nExpirationSeconds=5\n", [share]: conf(600) }), "600|" + share + "|file", "the key in another group passes on");
        assertEqual(length({ [etc]: "ExpirationSeconds=5\n[Polkitd]\n", [share]: conf(600) }), "600|" + share + "|file",
                    "a key before any group: GLib refuses the file, the next decides");
        assertEqual(length({ [etc]: "Other=1\n[Polkitd]\nExpirationSeconds=7\n", [share]: conf(600) }), "600|" + share + "|file",
                    "a key before any group refuses the file, its own key too");
        assertEqual(length({ [etc]: conf(5) + "junk\n", [share]: conf(600) }), "600|" + share + "|file", "a line GLib cannot read: the file is refused");
        assertEqual(length({ [etc]: "[Polkitd]\n=5\n", [share]: conf(600) }), "600|" + share + "|file", "a line without a key: refused");
        assertEqual(length({ [etc]: "[Polk[itd]\nExpirationSeconds=5\n", [share]: conf(600) }), "600|" + share + "|file", "a broken group line: refused");
        assertEqual(length({ [etc]: "[Polkitd]\nExpir[ationSeconds=5\n", [share]: conf(600) }), "600|" + share + "|file", "a broken key name: refused");
        assertEqual(length({ [etc]: "[Polkitd]\nExpirationSeconds[pl]=5\nOther=1\n", [share]: conf(600) }), "600|" + share + "|file",
                    "a localised key is another key");
        assertEqual(length({ [etc]: "[Polkitd]\nexpirationseconds=5\n", [share]: conf(600) }), "600|" + share + "|file", "names are case-sensitive");
        assertEqual(length({ [etc]: "[Polkitd]\nExpirationSeconds=\\q5\n", [share]: conf(600) }), "600|" + share + "|file",
                    "an escape GLib cannot read: the key is not read, the next decides");
        assertEqual(length({ [etc]: "[Polkitd]\nExpirationSeconds=5\\\n", [share]: conf(600) }), "600|" + share + "|file", "a trailing backslash: not read");
        assertEqual(length({ [etc]: "  # a comment\n\n [Polkitd]  \n\t ExpirationSeconds = 42\r\n" }), "42|" + etc + "|file",
                    "comments, indents, spaces around = and a CRLF line");
        assertEqual(length({ [etc]: "\ufeff[Polkitd]\nExpirationSeconds=5\n", [share]: conf(600) }), "600|" + share + "|file",
                    "a byte order mark: GLib refuses the file");
        assertEqual(length({ [etc]: "[Polkitd]\n\u00a0ExpirationSeconds=5\n", [share]: conf(600) }), "600|" + share + "|file",
                    "a no-break space before the key: not GLib's whitespace, another key");
        assertEqual(length({ [etc]: "[Polkitd]\nExpirationSeconds\u00a0=5\n", [share]: conf(600) }), "600|" + share + "|file",
                    "a no-break space after the key: another key");
        assertEqual(length({ [etc]: conf("\u00a05") }), "-1|" + etc + "|invalid", "a no-break space before the value: refused");
        assertEqual(length({ [etc]: "[Polkitd]\u00a0\nExpirationSeconds=5\n", [share]: conf(600) }), "600|" + share + "|file",
                    "a no-break space after the group: refused");
        assertEqual(length({ [etc]: "[Polkitd]\r\nExpirationSeconds=42\r\n" }), "42|" + etc + "|file", "CRLF lines throughout");
        assertEqual(length({ [etc]: "[Polkitd]\nExpirationSeconds=1\nExpirationSeconds=2\n" }), "2|" + etc + "|file", "a repeated key: the last");
        assertEqual(length({ [etc]: "[Polkitd]\nExpirationSeconds=1\n[Other]\nx=1\n[Polkitd]\nExpirationSeconds=3\n" }), "3|" + etc + "|file",
                    "a repeated group is merged");
        assertEqual(length({ [etc]: "[Polkitd]\nExpirationSeconds=\\s7\n" }), "7|" + etc + "|file", "an escaped leading space: strtoull skips it");
        assertEqual(length({ [etc]: "[Polkitd]\nExpirationSeconds=\\t\\n7\n" }), "7|" + etc + "|file", "escaped tab and newline: skipped too");
        assertEqual(length({ [etc]: conf("+60") }), "60|" + etc + "|file", "a plus sign is taken");
        assertEqual(length({ [etc]: conf("-0") }), "0|" + etc + "|file", "minus zero is zero");
        assertEqual(length({ [etc]: conf(0) }), "0|" + etc + "|file", "zero is a length polkitd takes");
        assertEqual(length({ [etc]: conf("4294967295") }), "4294967295|" + etc + "|file", "G_MAXUINT is taken");
        // A value polkitd refuses stops its search: it keeps the length it had
        for (const bad of ["", "abc", "60s", "600 ", "-5", "4294967296", "99999999999999999999", "6 0", "0x10", "\\r5\\r"])
            assertEqual(length({ [etc]: conf(bad), [share]: conf(600) }), "-1|" + etc + "|invalid", "refused value " + json(bad) + ": unknown, the search stops");
        assertEqual(length({ [etc]: null, [share]: conf(600) }), "-1|" + etc + "|unreadable", "an unreadable file before the deciding one: unknown");
        assertEqual(length({ [etc]: conf(900), [share]: null }), "900|" + etc + "|file", "an unreadable file after the deciding one: no matter");
        assertEqual(length({ [run]: 5 }), "-1|" + run + "|unreadable", "not a text: unknown");

        // ---- What is installed ----
        const confFor = seconds => ({ [etc]: rules.confText(seconds), [share]: vendor });
        const st = (files, facts) => { const got = rules.state(files, facts); return [got.rule, got.conf, got.seconds, got.secondsReason].join("|"); };
        const archFacts = Object.assign({ system: "arch" }, arch);
        const nixosFacts = Object.assign({ system: "nixos" }, nixos);
        assertEqual(st({ rule: undefined, confs: { [share]: vendor } }, archFacts), "none|none|300|default", "Arch, nothing installed");
        assertEqual(st({ rule: archText, confs: { [share]: vendor } }, archFacts), "ours|none|300|default", "Arch, the rule installed");
        assertEqual(st({ rule: archText, confs: confFor(900) }, archFacts), "ours|ours|900|file", "Arch, the rule and a longer length of ours");
        assertEqual(st({ rule: archText + "\n\n", confs: {} }, archFacts), "ours|none|300|default", "blank lines after the rule: still ours");
        assertEqual(st({ rule: "", confs: {} }, archFacts), "none|none|300|default", "an empty rule file: none");
        assertEqual(st({ rule: null, confs: {} }, archFacts), "unknown|none|300|default", "the rule file unreadable: unknown");
        assertEqual(st({ rule: 3, confs: {} }, archFacts), "unknown|none|300|default", "not a text: unknown");
        assertEqual(st({ rule: archText, confs: { [etc]: null } }, archFacts), "ours|unknown|-1|unreadable", "the conf unreadable: unknown");
        assertEqual(st({ rule: rules.ruleText(Object.assign({}, arch, { program: "/usr/local/bin/timeout", timeout: "/usr/local/bin/timeout" })), confs: {} }, archFacts),
                    "outdated|none|300|default", "our rule for another timeout: outdated");
        assertEqual(st({ rule: rules.ruleText(Object.assign({}, arch, { user: "bob" })), confs: {} }, archFacts), "outdated|none|300|default",
                    "our rule for another user: outdated");
        assertEqual(st({ rule: archText.replace("auth_admin_keep", "yes"), confs: {} }, archFacts), "changed|none|300|default",
                    "a line of the rule changed: changed by hand");
        assertEqual(st({ rule: archText + "polkit.addRule(function(action, subject) { return polkit.Result.YES; });\n", confs: {} }, archFacts),
                    "changed|none|300|default", "a rule added to our file: changed");
        assertEqual(st({ rule: "// a note\n" + archText, confs: {} }, archFacts), "changed|none|300|default", "a line added above: changed");
        assertEqual(st({ rule: archBody, confs: {} }, archFacts), "changed|none|300|default", "our name, no header: not ours");
        assertEqual(st({ rule: archText.replace(/ [0-9a-f]{64}\n/, "\n"), confs: {} }, archFacts), "changed|none|300|default", "the header without a hash: changed");
        assertEqual(st({ rule: archText.replace("});\n", "})\n"), confs: {} }, archFacts), "changed|none|300|default", "the rule's end missing: changed");
        const emptyHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
        assertEqual(st({ rule: "// Written by h2s-shell " + emptyHash + "\n", confs: {} }, archFacts), "changed|none|300|default",
                    "a header alone, carrying the empty text's hash: changed");
        assertEqual(st({ rule: "// Written by h2s-shell " + PamEditRules.sha256("});\n") + "\n});\n", confs: {} }, archFacts), "outdated|none|300|default",
                    "an intact block right after the header, not today's text: outdated");
        assertEqual(st({ rule: archText + archText, confs: {} }, archFacts), "changed|none|300|default", "the rule twice: changed");
        assertEqual(st({ rule: archText, confs: {} }, { system: "arch", user: "al ex", timeout: arch.timeout, program: arch.program }),
                    "unknown|none|300|default", "facts that make no rule: cannot tell ours from outdated");
        assertEqual(st({ rule: archText, confs: { [etc]: conf(900) } }, archFacts), "ours|changed|900|file", "a conf not written by us: changed");
        assertEqual(st({ rule: archText, confs: { [etc]: rules.confText(900).replace("900", "901") } }, archFacts), "ours|changed|901|file",
                    "our conf edited by hand: changed");
        assertEqual(st({ rule: archText, confs: { [etc]: rules.confText(900) + "# more\n" } }, archFacts), "ours|changed|900|file",
                    "a line added after our conf: changed");
        assertEqual(st({ rule: archText, confs: { [etc]: "# note\n" + rules.confText(900) } }, archFacts), "ours|changed|900|file",
                    "a line added before: changed");
        const reHashed = body => "# Written by h2s-shell " + PamEditRules.sha256(body) + "\n" + body;
        assertEqual(st({ rule: archText, confs: { [etc]: reHashed("[Polkitd]\n# x\nExpirationSeconds=900\n") } }, archFacts), "ours|changed|900|file",
                    "a hash that matches a text confText does not make: changed");
        assertEqual(st({ rule: archText, confs: { [etc]: rules.confText(900).split("\n")[0] } }, archFacts), "ours|changed|300|default",
                    "the header alone: not ours");
        // NixOS: the rule is a block among the system's rules
        const nixosText = rules.ruleText(nixos);
        const nixosRules = "/* Generated by NixOS */\n\npolkit.addRule(function(action, subject) {\n  if (subject.isInGroup(\"wheel\")) return polkit.Result.YES;\n});\n\n"
            + nixosText + "\n// another rule\n";
        assertEqual(st({ rule: nixosRules, confs: {} }, nixosFacts), "ours|system|300|default", "NixOS: our block among others");
        assertEqual(st({ rule: "polkit.addRule(function(action, subject) {\n});\n", confs: {} }, nixosFacts), "none|system|300|default",
                    "NixOS: no block of ours");
        assertEqual(st({ rule: nixosRules.replace("/nix/store/0abc-", "/nix/store/0def-"), confs: { [etc]: conf(900) } }, nixosFacts),
                    "changed|system|900|file", "NixOS: a block whose text is not its hash's");
        assertEqual(st({ rule: nixosRules, confs: {} }, Object.assign({}, nixosFacts, { program: "/nix/store/0new-coreutils-full-9.12/bin/coreutils" })),
                    "outdated|system|300|default", "NixOS: coreutils moved since the switch: outdated");
        assertEqual(st({ rule: undefined, confs: {} }, nixosFacts), "none|system|300|default", "NixOS: no rules file");
        // The module's list of users: one block each
        const otherText = rules.ruleText(Object.assign({}, nixos, { user: "bob" }));
        assertEqual(st({ rule: nixosRules.replace(nixosText, otherText + nixosText), confs: {} }, nixosFacts), "ours|system|300|default",
                    "NixOS: two users' blocks, this user's second: ours");
        assertEqual(st({ rule: nixosRules.replace(nixosText, nixosText + otherText), confs: {} }, nixosFacts), "ours|system|300|default",
                    "NixOS: … this user's first: ours");
        assertEqual(st({ rule: nixosRules.replace(nixosText, otherText + otherText.replace(/bob/g, "carol")), confs: {} }, nixosFacts),
                    "outdated|system|300|default", "NixOS: other users' blocks only: outdated");
        assertEqual(st({ rule: nixosRules.replace(nixosText, otherText + nixosText.replace(/\}\);\n$/, "}); x\n")), confs: {} }, nixosFacts),
                    "outdated|system|300|default", "NixOS: this user's block not as whole lines: not ours");
        assertEqual(st({ rule: archText + archText, confs: {} }, archFacts).split("|")[0], "changed", "Arch: two blocks in the shell's file: changed");
        const fullState = rules.state({ rule: archText, confs: confFor(900) }, archFacts);
        assertEqual(fullState.secondsSource, etc, "the length's source is named");

        // ---- gdbus's answers ----
        const variant = text => json(rules.parseVariant(text));
        assertEqual(variant("(<'2'>,)"), json(["2"]), "a variant in a tuple");
        assertEqual(variant("(@a(ss(sa{sv})tt) [],)"), json([[]]), "an empty typed array");
        assertEqual(variant("([uint32 1, 2, -3],)"), json([[1, 2, -3]]), "annotated and bare numbers");
        assertEqual(variant("{'a': <true>, 'b': <false>, \"c'\": <'x'>}"), json({ a: true, b: false, "c'": "x" }), "a dictionary, both quotes");
        assertEqual(variant("('a\\'b\\\\c\\n\\u00e9\\U0001F600',)"), json(["a'b\\c\né😀"]), "escapes");
        assertEqual(rules.parseVariant("(handle 0, objectpath '/x', byte 0x1,)"), undefined, "a byte in hex: not read");
        assertEqual(variant("(handle 0, objectpath '/x', 1.5e3)"), json([0, "/x", 1500]), "handles, paths, doubles");
        assertEqual(variant("()"), json([]), "an empty tuple");
        assertEqual(variant(" ( 1 , ) \n"), json([1]), "spaces around the whole");
        assertEqual(variant("( 1 , )"), json([1]), "spaces inside");
        for (const bad of ["", "(", "(1", "(1,,)", "('a)", "('\\q',)", "('\\u12',)", "('\\U00110000',)", "<1", "{'a' 1}", "(1) x", "[1 2]",
                           "nothing", "uint32", "@as", "(<1>,", "{'a': <1>", "(<1 2>,)"])
            assertEqual(rules.parseVariant(bad), undefined, "not a GVariant: " + json(bad));
        assertEqual(rules.parseVariant(null), undefined, "no text");
        assertEqual(rules.parseVariant("[".repeat(65) + "]".repeat(65)), undefined, "nested 65 deep: too deep");
        assert(rules.parseVariant("[".repeat(64) + "]".repeat(64)) !== undefined, "nested 64 deep: read");
        assertEqual(rules.parseVariant("'" + "x".repeat(999999) + "'"), undefined, "over a million characters: too long");
        assertEqual(rules.parseVariant("'" + "x".repeat(999998) + "'")?.length, 999998, "a million characters: read");
        assertEqual(variant("('\\U0010FFFF',)"), json(["\u{10FFFF}"]), "the last code point");
        assertEqual(rules.parseVariant("(<1 ,)"), undefined, "a variant not closed before a comma");
        assertEqual(rules.parseVariant("{'a',<1>}"), undefined, "a dictionary entry without its colon");
        assertEqual(rules.parseVariant("('a\\'"), undefined, "a string whose end is escaped");
        assertEqual(variant("('',\"\")"), json(["", ""]), "empty strings");
        assertEqual(variant("('\\u20ac\\U0001f600',)"), json(["\u20ac\uD83D\uDE00"]), "escapes whose first digit is not 0");
        assertEqual(variant("(uint32\t5,)"), json([5]), "an annotation before a tab");
        assertEqual(variant("(@as\t[],)"), json([[]]), "an empty array's type before a tab");

        assertEqual(rules.sessionIdOf("(<'2'>,)\n"), "2", "the session's id");
        assertEqual(rules.sessionIdOf("(<'c1.x_y-z'>,)"), "c1.x_y-z", "letters, dot, dash, underscore");
        for (const bad of ["(<''>,)", "(<'a b'>,)", "(<'a\\'b'>,)", "(<2>,)", "(<'1'>, <'2'>)", "('2',).", "", null, "(<'" + "x".repeat(65) + "'>,)"])
            assertEqual(rules.sessionIdOf(bad), "", "no session id in " + json(bad));
        assertEqual(rules.sessionSubject("2"), "('unix-session', {'session-id': <'2'>})", "the session as polkit's subject");
        for (const bad of ["", "a'b", "a b", 2, null])
            assertEqual(rules.sessionSubject(bad), "", "no subject for " + json(bad));

        // ---- What is kept: EnumerateTemporaryAuthorizations ----
        // As gdbus prints polkit's answer (a(ss(sa{sv})tt): id, action, subject, obtained,
        // expires in seconds since the epoch; numbers after the first annotated only once)
        const shellPid = 4242;
        const nowMs = 1795000000000;
        const now = nowMs / 1000;
        const process = (pid, more) => "('unix-process', {'pid': <uint32 " + pid + ">, 'start-time': <uint64 1234567>, 'uid': <1000>" + (more ?? "") + "})";
        const item = (id, action, subject, obtained, expires, first) =>
            "('" + id + "', '" + action + "', " + subject + ", " + (first === false ? "" : "uint64 ") + obtained + ", " + (first === false ? "" : "uint64 ") + expires + ")";
        const answer = items => items.length === 0 ? "(@a(ss(sa{sv})tt) [],)" : "([" + items.join(", ") + "],)";
        const exec = "org.freedesktop.policykit.exec";
        const ours = item("tmpauthz12", exec, process(shellPid), now - 60, now + 240);
        const parse = (text, system) => rules.parseKept(text, nowMs, shellPid, system === undefined ? 300 : system);
        const kept = (text, system) => {
            const got = parse(text, system);
            return got.known === false ? "unknown:" + got.reason : got.known !== true ? "broken"
                : got.entries.map(entry => [entry.id, entry.obtainedMs - nowMs, entry.untilMs - nowMs].join(",")).join(";");
        };
        assertEqual(kept(answer([ours])), "tmpauthz12,-60000,240000", "the shell's kept authorization");
        assertEqual(kept(answer([])), "", "nothing kept");
        assertEqual(parse(answer([])).known, true, "nothing kept is known");
        assertEqual(parse(answer([])).reason, "", "… no reason");
        assertEqual(parse(answer([])).latest, null, "… no latest");
        assertEqual(parse(answer([])).earliest, null, "… no earliest");
        assertEqual(kept(answer([ours]) + "\n"), "tmpauthz12,-60000,240000", "a trailing line break");
        assertEqual(kept(answer([ours, item("tmpauthz13", exec, process(shellPid), now - 10, now + 290, false)])),
                    "tmpauthz12,-60000,240000;tmpauthz13,-10000,290000", "two of ours, the second unannotated as gdbus prints it");
        assertEqual(kept(answer([item("a", exec, process(shellPid, ", 'pidfd': <handle 0>"), now - 1, now + 299)])), "a,-1000,299000",
                    "a pidfd beside the pid");
        const others = [item("o1", "org.freedesktop.udisks2.filesystem-mount", process(shellPid), now - 120, now + 180),
                        item("o2", exec, process(777), now - 30, now + 3000),
                        item("o3", exec, "('unix-session', {'session-id': <'2'>})", now - 30, now + 270),
                        item("o4", exec, "('unix-process', {'pidfd': <handle 0>, 'uid': <1000>})", now - 30, now + 270),
                        item("o5", exec, "('system-bus-name', {'name': <':1.42'>})", now - 30, now + 270),
                        item("o6", exec, "('unix-process', {'pid': <'4242'>})", now - 30, now + 270)];
        assertEqual(kept(answer(others)), "", "other actions and subjects, another process kept long: left out");
        assertEqual(kept(answer(others.concat([ours]))), "tmpauthz12,-60000,240000", "ours among others");
        assertEqual(kept(answer([item("e", exec, process(shellPid), now - 300, now)])), "", "expiring now: not kept");
        assertEqual(kept(answer([item("e", exec, process(shellPid), now - 299, now + 1)])), "e,-299000,1000", "a second left: kept");
        const two = answer([item("late", exec, process(shellPid), now - 10, now + 290), item("early", exec, process(shellPid), now - 100, now + 200)]);
        assertEqual(parse(two).latest.id, "late", "the latest is the one kept longest");
        assertEqual(parse(two).earliest.id, "early", "the earliest is the one obtained first");
        const ties = answer([item("first", exec, process(shellPid), now - 10, now + 200), item("second", exec, process(shellPid), now - 10, now + 200)]);
        assertEqual(parse(ties).latest.id + " " + parse(ties).earliest.id, "first first", "ties: the first");
        // Kept longer than polkitd's length: its conf says less than it keeps
        const hour = answer([item("h", exec, process(shellPid), now - 60, now + 3540)]);
        assertEqual(kept(hour), "unknown:longer", "kept an hour, the conf saying 5 min: unknown, longer");
        assertEqual(parse(hour).entries.length, 1, "… its entries still given");
        assertEqual(parse(hour).earliest.id, "h", "… and the earliest");
        assertEqual(kept(answer([item("s", exec, process(shellPid), now - 1, now + 300)])), "s,-1000,300000", "the length and a second's slack: kept");
        assertEqual(kept(answer([item("s", exec, process(shellPid), now - 2, now + 300)])), "unknown:longer", "two seconds over: longer");
        assertEqual(kept(hour, -1), "h,-60000,3540000", "the system's length unknown: no such check");
        assertEqual(kept(answer([ours]), 0), "unknown:longer", "a zero length: anything kept is longer");
        assertEqual(kept(answer([item("o", exec, process(777), now - 60, now + 3540)])), "", "another process kept long: no matter");
        // Not understood: unknown, never "nothing kept"
        for (const [label, text] of [
                ["junk", "Error: GDBus.Error:org.freedesktop.PolicyKit1.Error.Failed: Can only enumerate for your own session"],
                ["not a tuple", "[]"],
                ["a tuple of two", "([], [])"],
                ["not an array inside", "('x',)"],
                ["an entry of four", "([('a', 'b', " + process(shellPid) + ", uint64 1)],)"],
                ["a subject without details", "([('a', 'b', ('unix-process',), uint64 1, uint64 2)],)"],
                ["a subject's details as a list", "([('a', 'b', ('unix-process', [1]), uint64 1, uint64 2)],)"],
                ["times as text", "([('a', 'b', " + process(shellPid) + ", '1', '2')],)"],
                ["a time not whole", "([('a', 'b', " + process(shellPid) + ", 1.5, 2)],)"],
                ["an id not text", "([(1, 'b', " + process(shellPid) + ", 1, 2)],)"],
                ["an action not text", "([('a', 2, " + process(shellPid) + ", 1, 2)],)"],
                ["a subject kind not text", "([('a', 'b', (1, {}), 1, 2)],)"],
                ["a subject of three", "([('a', 'b', ('unix-process', {}, 1), 1, 2)],)"],
                ["a null subject", "([('a', 'b', ('unix-process', nothing), 1, 2)],)"],
                ["cut short", answer([ours]).slice(0, -3)]])
            assertEqual(kept(text), "unknown:malformed", label + ": unknown");
        assertEqual(rules.parseKept(null, nowMs, shellPid, 300).reason, "unread", "no output: unread");
        assertEqual(rules.parseKept(answer([ours]), NaN, shellPid, 300).reason, "unread", "no clock: unread");
        assertEqual(rules.parseKept(answer([ours]), nowMs, 0, 300).reason, "unread", "no pid: unread");
        assertEqual(rules.parseKept(answer([ours]), nowMs, "4242", 300).reason, "unread", "a pid as text: unread");
        assertEqual(rules.parseKept(answer([item("p", exec, process(1), now - 1, now + 1)]), nowMs, 1, 300).entries.length, 1, "pid 1 is a pid");
        assertEqual(rules.parseKept("x", nowMs, shellPid, 300).entries.length, 0, "unknown: no entries");

        // ---- What to do after a reading ----
        const step = (list, minutes, at) => json(rules.revokeStep(list, minutes, at ?? nowMs));
        const listOf = (entries, known, reason) => ({ known: known ?? true, reason: reason ?? "", entries });
        const fresh = { obtainedMs: nowMs - 60000, untilMs: nowMs + 240000 };
        assertEqual(step(listOf([fresh]), 3), json({ now: false, atMs: nowMs + 120000 }), "shorter: armed for obtained plus the setting");
        assertEqual(step(listOf([fresh]), 5), json({ now: false, atMs: 0 }), "as long as polkit's: nothing");
        assertEqual(step(listOf([fresh]), 1), json({ now: true, atMs: 0 }), "the time passed (a suspend): at once");
        assertEqual(step(listOf([{ obtainedMs: nowMs - 120000, untilMs: nowMs + 180000 }]), 2), json({ now: true, atMs: 0 }), "the time just reached: at once");
        assertEqual(step(listOf([{ obtainedMs: nowMs - 119999, untilMs: nowMs + 180000 }]), 2), json({ now: false, atMs: nowMs + 1 }), "a millisecond before: armed");
        assertEqual(step(listOf([]), 3), json({ now: false, atMs: 0 }), "nothing kept: nothing");
        assertEqual(step(listOf([fresh], false, "longer"), 15), json({ now: true, atMs: 0 }), "longer: at once, whatever the setting");
        assertEqual(step(listOf([], false, "longer"), 15), json({ now: false, atMs: 0 }), "longer with nothing in it: nothing");
        assertEqual(step({ known: false, reason: "longer" }, 15), json({ now: false, atMs: 0 }), "longer without entries: nothing");
        assertEqual(step(listOf([fresh], false, "malformed"), 1), json({ now: false, atMs: 0 }), "not understood: nothing (the next reading decides)");
        assertEqual(step(null, 3), json({ now: false, atMs: 0 }), "no list: nothing");

        // ---- The shell's own revoke ----
        // Judged by the entries alone: polkitd's length in force may differ from its conf file
        const one = { obtainedMs: nowMs - 60000, untilMs: nowMs + 240000 };
        assertEqual(rules.revokeAtMs([one], 3), nowMs + 120000, "outliving the setting: obtained plus the setting");
        assertEqual(rules.revokeAtMs([one], 5), 0, "kept as long as the setting: polkitd's expiry");
        assertEqual(rules.revokeAtMs([one], 15), 0, "the setting longer: polkitd's expiry comes first");
        assertEqual(rules.revokeAtMs([{ obtainedMs: nowMs - 60000, untilMs: nowMs + 241000 }], 5), 0, "a second over: within the tolerance");
        assertEqual(rules.revokeAtMs([{ obtainedMs: nowMs - 60000, untilMs: nowMs + 241001 }], 5), nowMs + 240000, "past the tolerance: the shell's");
        assertEqual(rules.revokeAtMs([{ obtainedMs: nowMs - 60000, untilMs: nowMs + 3540000 }], 5), nowMs + 240000,
                    "an entry outliving a conf that says less (edited, polkitd not told): the shell forgets at the setting");
        assertEqual(rules.revokeAtMs([one], 1), nowMs, "one minute: a minute after it was obtained");
        const pair = [{ obtainedMs: nowMs - 10000, untilMs: nowMs + 290000 }, one];
        assertEqual(rules.revokeAtMs(pair, 3), nowMs + 120000, "several: from the earliest obtained");
        assertEqual(rules.revokeAtMs([{ obtainedMs: nowMs - 200000, untilMs: nowMs + 100000 }, { obtainedMs: nowMs - 10000, untilMs: nowMs + 290000 }], 4),
                    nowMs + 40000, "the earliest's own end is within the setting, a later one outlives it: revoked");
        assertEqual(rules.revokeAtMs([], 3), 0, "nothing kept: nothing to revoke");
        assertEqual(rules.revokeAtMs(null, 3), 0, "no entries: nothing");
        assertEqual(rules.revokeAtMs([one], 0), 0, "no setting: nothing");
        assertEqual(rules.revokeAtMs([one], 2.5), 0, "not whole minutes: nothing");
        assertEqual(rules.keptUntilMs([one], 3), nowMs + 120000, "kept until the shell's revoke");
        assertEqual(rules.keptUntilMs([one], 15), nowMs + 240000, "kept until polkitd's expiry");
        assertEqual(rules.keptUntilMs(pair, 15), nowMs + 290000, "several: the latest expiry");
        assertEqual(rules.keptUntilMs(pair, 4), nowMs + 180000, "several: the revoke when sooner");
        assertEqual(rules.keptUntilMs([], 3), 0, "nothing kept: 0");
        assertEqual(rules.keptUntilMs(null, 3), 0, "no entries: 0");

        // ---- The NixOS line ----
        assertEqual(rules.nixLine("alex", 5), "programs.h2s-shell.polkit.rememberAdmin = {\n  enable = true;\n  users = [ \"alex\" ];\n  minutes = 5;\n};",
                    "the module's option");
        assertEqual(rules.nixLine("alex", 15).includes("minutes = 15;"), true, "longer: the line's minutes");
        assertEqual(rules.nixLine("alex", 6).includes("minutes = 6;"), true, "six minutes: longer");
        assertEqual(rules.nixLine("alex", 3).includes("minutes = 5;"), true, "shorter: the shell's revoke, the default length");
        assertEqual(rules.nixLine("alex", 1).includes("minutes = 5;"), true, "one minute: the default length");
        for (const [user, minutes] of [["al\"ex", 5], ["${x}", 5], ["", 5], ["alex", 0], ["alex", 2.5], ["alex", "5"]])
            assertEqual(rules.nixLine(user, minutes), "", "no line for " + json([user, minutes]));

        // ---- The prompt's line ----
        assertEqual(rules.promptLine("ours", 5, 300), "Remembered for 5 min", "the setting and the system agree");
        assertEqual(rules.promptLine("ours", 3, 300), "Remembered for 3 min", "the setting shorter");
        assertEqual(rules.promptLine("ours", 15, 300), "Remembered for 5 min", "the system shorter");
        assertEqual(rules.promptLine("ours", 15, 330), "Remembered for 5 min", "never rounded up");
        assertEqual(rules.promptLine("ours", 60, 7200), "Remembered for 60 min", "an hour, the setting shorter");
        assertEqual(rules.promptLine("ours", 15, 60), "Remembered for 1 min", "one minute");
        assertEqual(rules.promptLine("ours", 15, 59), "Remembered for 59 s", "under a minute: seconds");
        assertEqual(rules.promptLine("ours", 1, 1), "Remembered for 1 s", "one second");
        assertEqual(rules.promptLine("ours", 5, 0), "", "a zero length: no promise");
        assertEqual(rules.promptLine("ours", 5, -1), "", "the system's length unknown: no promise");
        assertEqual(rules.promptLine("ours", 0, 300), "", "no setting: no line");
        assertEqual(rules.promptLine("ours", 2.5, 300), "", "not whole minutes: no line");
        for (const other of ["none", "outdated", "changed", "unknown"])
            assertEqual(rules.promptLine(other, 5, 300), "", "the rule " + other + ": no line");
    }
}
