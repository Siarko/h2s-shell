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
        const fullState = rules.state({ rule: archText, confs: confFor(900) }, archFacts);
        assertEqual(fullState.secondsSource, etc, "the length's source is named");

        // ---- pkcheck --list-temp ----
        // As polkit 127/128's pkcheck prints it (src/programs/pkcheck.c: the labels padded to
        // one column, polkit_subject_to_string, the command line read from /proc, the times
        // relative to pkcheck's own clock and in %c)
        const shellPid = 4242;
        const nowMs = 1795000000000;
        const entry = (id, action, subject, obtained, expires) => "authorization id: " + id + "\n"
            + "action:           " + action + "\n"
            + "subject:          " + subject + "\n"
            + "obtained:         " + obtained + " (Mon 23 Nov 2026 10:02:11 AM CET)\n"
            + "expires:          " + expires + " (Mon 23 Nov 2026 10:07:11 AM CET)\n"
            + "\n";
        const shellSubject = "unix-process:4242:1234567 (/usr/bin/quickshell -p /home/alex/.config/quickshell/default)";
        const ours = entry("tmpauthz12", "org.freedesktop.policykit.exec", shellSubject, "1 min 0 sec ago", "4 min 0 sec from now");
        const list = text => rules.parseList(text, nowMs, shellPid, 300);
        const kept = text => { const got = list(text); return got.known === false ? "unknown" : got.known !== true ? "broken" : got.entries.map(item => [item.id, item.obtainedMs - nowMs, item.untilMs - nowMs].join(",")).join(";"); };
        assertEqual(kept(ours), "tmpauthz12,-61000,240000", "the shell's kept authorization");
        assertEqual(kept(""), "", "nothing kept: pkcheck prints nothing");
        assertEqual(kept("\n"), "", "a lone newline: nothing kept");
        assertEqual(list("").known, true, "an empty list is known");
        assertEqual(list("").latest, null, "nothing kept: no latest");
        assertEqual(kept(ours.slice(0, -1)), "tmpauthz12,-61000,240000", "without the closing blank line");
        assertEqual(kept(ours.slice(0, -2)), "tmpauthz12,-61000,240000", "without any closing newline");
        assertEqual(rules.parseList(ours.replace(/4242/g, "1"), nowMs, 1).entries.length, 1, "pid 1 is a pid");
        assertEqual(kept(entry("tmpauthz3", "org.freedesktop.policykit.exec", shellSubject, "12 sec ago", "4 min 48 sec from now")),
                    "tmpauthz3,-13000,288000", "seconds alone");
        assertEqual(kept(entry("tmpauthz4", "org.freedesktop.policykit.exec", shellSubject, "0 sec from now", "5 min 0 sec from now")),
                    "tmpauthz4,-1000,300000", "just obtained");
        const others = entry("tmpauthz1", "org.freedesktop.udisks2.filesystem-mount", shellSubject, "2 min 0 sec ago", "3 min 0 sec from now")
            + entry("tmpauthz2", "org.freedesktop.policykit.exec", "unix-process:777:99 (bash)", "30 sec ago", "4 min 30 sec from now")
            + entry("tmpauthz5", "org.freedesktop.policykit.exec", "unix-process:42420:5 (other)", "30 sec ago", "4 min 30 sec from now")
            + entry("tmpauthz6", "org.freedesktop.policykit.exec", "unix-process:unknown ((null))", "30 sec ago", "4 min 30 sec from now")
            + entry("tmpauthz7", "org.freedesktop.policykit.exec", "system-bus-name::1.42 ((null))", "30 sec ago", "4 min 30 sec from now");
        assertEqual(kept(others), "", "other actions and other subjects: left out");
        assertEqual(kept(others + ours), "tmpauthz12,-61000,240000", "ours among others");
        assertEqual(kept(entry("tmpauthz8", "org.freedesktop.policykit.exec", shellSubject, "6 min 0 sec ago", "1 min 0 sec ago")), "",
                    "already expired: not kept");
        assertEqual(kept(entry("tmpauthz8", "org.freedesktop.policykit.exec", shellSubject, "5 min 0 sec ago", "0 sec from now")), "",
                    "expiring now: not kept");
        assertEqual(kept(entry("tmpauthz9", "org.freedesktop.policykit.exec", "unix-process:4242:1 (a (b) c)", "1 sec ago", "1 sec from now")),
                    "tmpauthz9,-2000,1000", "parentheses in the command line");
        const two = ours + entry("tmpauthz13", "org.freedesktop.policykit.exec", shellSubject, "10 sec ago", "4 min 50 sec from now");
        assertEqual(kept(two), "tmpauthz12,-61000,240000;tmpauthz13,-11000,290000", "two of ours, in their order");
        assertEqual(list(two).latest.id, "tmpauthz13", "the latest is the one kept longest");
        assertEqual(list(entry("a", "org.freedesktop.policykit.exec", shellSubject, "1 sec ago", "9 min 0 sec from now") + ours).latest.id, "a",
                    "kept longest, wherever it stands");
        assertEqual(list(entry("first", "org.freedesktop.policykit.exec", shellSubject, "1 sec ago", "4 min 0 sec from now") + ours).latest.id, "first",
                    "a tie: the first");
        // Not understood: unknown, never "nothing kept"
        for (const [label, text] of [
                ["junk", "Error: something\n"],
                ["cut short", ours.split("\n").slice(0, 3).join("\n") + "\n"],
                ["a line missing", ours.replace(/^action:.*\n/m, "")],
                ["lines out of order", ours.replace(/^(action:.*)\n(subject:.*)$/m, "$2\n$1")],
                ["an unknown relative time", ours.replace("1 min 0 sec ago", "a while ago")],
                ["a subject without its command line", ours.replace(" (/usr/bin/quickshell -p /home/alex/.config/quickshell/default)", "")],
                ["an empty id", ours.replace("tmpauthz12", "")],
                ["no local time", ours.replace(/ \(Mon 23 Nov 2026 10:07:11 AM CET\)/, "")],
                ["an extra line", ours.slice(0, -1) + "note: x\n"],
                ["text after a good entry", ours + "trailing\n"]])
            assertEqual(kept(text), "unknown", label + ": unknown");
        assertEqual(kept(null), "unknown", "no output: unknown");
        // Without a length to check against, so that only the form decides
        assertEqual(rules.parseList(ours.replace("1 min 0 sec ago", "75 sec ago"), nowMs, shellPid).reason, "malformed", "75 sec, never printed so: malformed");
        assertEqual(rules.parseList(ours.replace("1 min 0 sec ago", "60 sec ago"), nowMs, shellPid).reason, "malformed", "60 sec alone: malformed");
        assertEqual(rules.parseList(ours.replace("4 min 0 sec from now", "4 min 60 sec from now"), nowMs, shellPid).reason, "malformed", "seconds past 59: malformed");
        assertEqual(rules.parseList(ours.replace("1 min 0 sec ago", "59 sec ago"), nowMs, shellPid).known, true, "59 sec: read");
        assertEqual(rules.parseList(ours, nowMs, shellPid, 0).reason, "longer", "a zero length: anything kept is longer");
        assertEqual(rules.parseList(ours, NaN, shellPid).known, false, "no clock: unknown");
        assertEqual(rules.parseList(ours, nowMs, 0).known, false, "no pid: unknown");
        assertEqual(rules.parseList(ours, nowMs, "4242").known, false, "a pid as text: unknown");
        assertEqual(rules.parseList(ours, nowMs, undefined).latest, null, "unknown: no latest");
        assertEqual(rules.parseList("x", nowMs, shellPid).entries.length, 0, "unknown: no entries");
        assertEqual(rules.parseList("x", nowMs, shellPid).reason, "malformed", "not in the form: malformed");
        assertEqual(rules.parseList(null, nowMs, shellPid).reason, "unread", "no output: unread");
        assertEqual(list(ours).reason, "", "known: no reason");
        assertEqual(list(two).earliest.id, "tmpauthz12", "the earliest is the one obtained first");
        assertEqual(list(entry("b", "org.freedesktop.policykit.exec", shellSubject, "4 min 0 sec ago", "1 min 0 sec from now") + ours).earliest.id, "b",
                    "obtained first, wherever it stands");
        assertEqual(list(ours + entry("tie", "org.freedesktop.policykit.exec", shellSubject, "1 min 0 sec ago", "2 min 0 sec from now")).earliest.id, "tmpauthz12",
                    "a tie: the first");
        assertEqual(list("").earliest, null, "nothing kept: no earliest");
        // Kept longer than polkitd's length: forged, or a length other than the conf's
        const outliving = entry("tmpauthz20", "org.freedesktop.policykit.exec", shellSubject, "1 min 0 sec ago", "59 min 0 sec from now");
        assertEqual(kept(outliving), "unknown", "an entry outliving the system's length: unknown");
        assertEqual(list(outliving).reason, "longer", "… said why");
        assertEqual(list(outliving).entries.length, 1, "… its entries still given, to be forgotten");
        assertEqual(list(outliving).earliest.id, "tmpauthz20", "… and the earliest");
        assertEqual(kept(entry("e", "org.freedesktop.policykit.exec", shellSubject, "1 sec ago", "5 min 0 sec from now")), "e,-2000,300000",
                    "the system's length and the second's truncation: kept");
        assertEqual(kept(entry("f", "org.freedesktop.policykit.exec", shellSubject, "2 sec ago", "5 min 0 sec from now")), "unknown",
                    "a second past the tolerance: unknown");
        assertEqual(kept(entry("g", "org.freedesktop.policykit.exec", "unix-process:777:1 (bash)", "1 min 0 sec ago", "59 min 0 sec from now")), "",
                    "another process's long entry: not the shell's, no matter");
        assertEqual(rules.parseList(outliving, nowMs, shellPid, -1).known, true, "the system's length unknown: no such check");
        assertEqual(rules.parseList(outliving, nowMs, shellPid).known, true, "no length handed in: no such check");
        // Another process of the user whose command line carries newlines and lines that read
        // as an entry of the shell's: either the list breaks, or the forged entry is checked
        // like any other
        const forger = text => entry("tmpauthz30", "org.freedesktop.policykit.exec", "unix-process:777:99 (sh -c " + text + ")", "30 sec ago", "4 min 30 sec from now");
        // The forger's command line closes its own entry, adds one for the shell's pid, and
        // opens a last one that the forger's real obtained and expires lines complete
        const forgedEntry = (expires) => "x)\nobtained:         1 sec ago (x)\nexpires:          4 min 0 sec from now (x)\n\n"
            + "authorization id: forged\naction:           org.freedesktop.policykit.exec\n"
            + "subject:          unix-process:4242:1234567 (q)\nobtained:         0 sec from now (x)\nexpires:          " + expires + " (x)\n\n"
            + "authorization id: tail\naction:           a.b\nsubject:          unix-session:2 (y";
        assertEqual(list(forger(forgedEntry("999 min 0 sec from now"))).reason, "longer", "a forged entry kept for ever: unknown, as longer");
        assertEqual(kept(forger("\naction: junk")), "unknown", "a command line breaking the form: unknown");
        const forgedFresh = forgedEntry("5 min 0 sec from now");
        const withForged = list(ours + forger(forgedFresh));
        assertEqual(withForged.entries.map(item => item.id).join(","), "tmpauthz12,forged", "a fresh forged entry within the length: read as the shell's");
        assertEqual(withForged.earliest.id, "tmpauthz12", "… but the revoke stays armed from the real, earlier one");
        assertEqual(rules.revokeAtMs(withForged.entries, 3), nowMs - 61000 + 180000, "… and the revoke time with it");

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
