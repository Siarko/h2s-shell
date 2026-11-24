import QtQuick
import qs.singletons

// NixosApplyRules: the root step's words for each op (create, apply on a root-owned
// configuration, switch on one of the user's, restore) from the reading and the candidate,
// what it refuses before a run, the places a run may write, the prompt's purpose, and its
// reply: every last line with its exit code, a line that does not agree with the op, the code
// or the values, and output that is no answer — a failure, never "applied". Pure.
TestCase {
    suiteName: "NixosApplyRules"

    function run() {
        const rules = NixosApplyRules;
        const sha = PamEditRules.sha256;
        const show = value => JSON.stringify(value);
        const live = rules.livePaths;
        const base = "/scratch";
        const paths = { bin: base + live.bin, profile: base + live.profile, store: base + live.store, backups: base + live.backups };
        const scripts = ["lib\n", "file\n", "step\n"];
        const folder = base + "/etc/nixos";
        const old = "{\"version\":1}\n";
        const text = "{\"version\":1,\"idle\":{\"hibernateDelay\":\"3h\"}}";
        const drv = base + "/nix/store/zyxwvsrqpnmlkjihgfdcba9876543210-nixos-system-test.drv";
        const out = base + "/nix/store/0123456789abcdfghijklmnpqrsvwxyz-nixos-system-test";
        const backup = "h2s-shell.json.20261124T101500Z";
        const reading = more => Object.assign({
            configuration: { found: true, folder, entry: "flake.nix", type: "flake" },
            rootWrites: true, host: "laptop",
            file: { path: folder + "/h2s-shell.json", state: "present", sha256: sha(old) }
        }, more ?? {});
        const candidate = more => Object.assign({ text, drvPath: drv, outPath: out }, more ?? {});
        const plan = (request, more) => rules.plan(request, more?.paths ?? paths, more?.live ?? false, more?.scripts ?? scripts, more?.shell ?? "/bin/sh");
        const code = planned => planned.refusal?.code ?? "";
        const head = ["/bin/sh", "-c", "lib\nfile\nstep\n", "sh", base];

        // ── apply: a root-owned flake ──
        const applied = plan({ op: "apply", reading: reading(), candidate: candidate() });
        assertEqual(applied.refusal, null, "apply: planned");
        assertEqual(show(applied.argv), show(head.concat(["apply", folder, "flake.nix", "laptop", sha(old), sha(text), drv, out, text])),
                    "apply: the three files' text, the base, the folder, entry, host, the file read, the candidate's hash, what was built, the candidate");
        assertEqual(show(applied.expected), show({ op: "apply", folder, current: sha(old), sha256: sha(text) }), "apply: what the reply must say");
        assertEqual(applied.what, "Write h2s-shell.json in " + folder + " and switch NixOS to the system built for laptop",
                    "apply: the prompt names the folder and the host");
        const absent = plan({ op: "apply", reading: reading({ file: { state: "absent", sha256: "" } }), candidate: candidate() });
        assertEqual(absent.argv[9], "absent", "apply: no file yet — absent");
        assertEqual(absent.expected.current, "absent", "… expected so");
        assertEqual(plan({ op: "apply", reading: reading(), candidate: candidate({ sha256: sha(text) }) }).refusal, null, "apply: the build's own hash, the same: planned");
        // ── switch: the user's configuration, nothing written ──
        const switched = plan({ op: "apply", reading: reading({ rootWrites: false }), candidate: candidate() });
        assertEqual(show(switched.argv), show(head.concat(["switch", folder, "flake.nix", "laptop", sha(text), drv, out, text])),
                    "switch: the folder not root's — no current file in the words");
        assertEqual(show(switched.expected), show({ op: "switch", folder, current: "", sha256: sha(text) }), "switch: expected");
        assertEqual(switched.what, "Switch NixOS to the system built for laptop from " + folder, "switch: the prompt");
        assertEqual(rules.what("switch", folder, "-"), "Switch NixOS to the system built from " + folder, "switch, classic: the prompt");
        assertEqual(rules.applyOp(reading({ rootWrites: "true" })) + " " + rules.applyOp(null) + " " + rules.applyOp(reading()), "switch switch apply",
                    "the op: apply only where root may write");
        // ── classic ──
        const classic = plan({ op: "apply", reading: reading({ configuration: { found: true, folder, entry: "configuration.nix", type: "classic" }, host: "" }),
                               candidate: candidate() });
        assertEqual(show(classic.argv.slice(5, 9)), show(["apply", folder, "configuration.nix", "-"]), "classic: the entry file, no host");
        assertEqual(classic.what, "Write h2s-shell.json in " + folder + " and switch NixOS to the system built from it", "classic: the prompt names the folder");
        // ── create, restore ──
        const created = plan({ op: "create", reading: reading({ file: { state: "absent", sha256: "" } }) });
        assertEqual(show(created.argv), show(head.concat(["create", folder])), "create: the folder only");
        assertEqual(show(created.expected), show({ op: "create", folder, current: "absent", sha256: sha("{\"version\":1}\n") }), "create: the file it writes");
        assertEqual(created.what, "Create h2s-shell.json in " + folder, "create: the prompt");
        const from = { folder, backup, sha256: sha(text) };
        const restored = plan({ op: "restore", reading: reading(), from });
        assertEqual(show(restored.argv), show(head.concat(["restore", folder, backup, sha(text)])), "restore: the backup and what the file holds");
        assertEqual(show(restored.expected), show({ op: "restore", folder, current: sha(text), sha256: "" }), "restore: expected");
        assertEqual(restored.what, "Put back the previous h2s-shell.json in " + folder, "restore: the prompt");
        assertEqual(plan({ op: "restore", reading: reading(), from: { folder, backup: backup + "-2.absent", sha256: "absent" } }).argv[8], "absent",
                    "restore: a file absent now, a numbered backup of none");

        // ── refused before a run ──
        const refusals = [
            ["a shell not absolute", plan({ op: "apply", reading: reading(), candidate: candidate() }, { shell: "sh" }), "arguments"],
            ["a shell not text", plan({ op: "apply", reading: reading(), candidate: candidate() }, { shell: 5 }), "arguments"],
            ["the system's places for a stand-in", plan({ op: "apply", reading: reading(), candidate: candidate() }, { paths: live }), "paths"],
            ["scratch places for the system's pkexec", plan({ op: "apply", reading: reading(), candidate: candidate() }, { live: true }), "paths"],
            ["places under /var", plan({ op: "create", reading: reading() }, { paths: { bin: "/var/x" + live.bin, profile: "/var/x" + live.profile,
                                                                                         store: "/var/x" + live.store, backups: "/var/x" + live.backups } }), "paths"],
            ["places not under one folder", plan({ op: "create", reading: reading() }, { paths: Object.assign({}, paths, { store: "/other/nix/store" }) }), "paths"],
            ["a script not read", plan({ op: "apply", reading: reading(), candidate: candidate() }, { scripts: ["lib\n", "", "step\n"] }), "script"],
            ["no configuration", plan({ op: "apply", reading: reading({ configuration: { found: false, folder: "" } }), candidate: candidate() }), "notFound"],
            ["no reading", plan({ op: "apply", candidate: candidate() }), "notFound"],
            ["a folder not plain", plan({ op: "apply", reading: reading({ configuration: { found: true, folder: base + "/etc/../nixos", entry: "flake.nix", type: "flake" } }),
                                          candidate: candidate() }), "paths"],
            ["a folder outside the base", plan({ op: "apply", reading: reading({ configuration: { found: true, folder: "/etc/nixos", entry: "flake.nix", type: "flake" } }),
                                                 candidate: candidate() }), "paths"],
            ["a folder that only starts like the base", plan({ op: "create", reading: reading({ configuration: { found: true, folder: base + "x/etc", entry: "flake.nix", type: "flake" },
                                                                                            file: { state: "absent" } }) }), "paths"],
            ["an op it does not know", plan({ op: "rebuild", reading: reading() }), "arguments"],
            ["create: the user's folder", plan({ op: "create", reading: reading({ rootWrites: false, file: { state: "absent" } }) }), "notRoot"],
            ["create: a file there", plan({ op: "create", reading: reading() }), "exists"],
            ["create: a file not read", plan({ op: "create", reading: reading({ file: { state: "unreadable" } }) }), "unread"],
            ["restore: the user's folder", plan({ op: "restore", reading: reading({ rootWrites: false }), from }), "notRoot"],
            ["restore: another folder now", plan({ op: "restore", reading: reading(), from: Object.assign({}, from, { folder: base + "/other" }) }), "otherFolder"],
            ["restore: no outcome", plan({ op: "restore", reading: reading() }), "otherFolder"],
            ["restore: not a backup", plan({ op: "restore", reading: reading(), from: Object.assign({}, from, { backup: "../x" }) }), "backupName"],
            ["restore: a backup of another file", plan({ op: "restore", reading: reading(), from: Object.assign({}, from, { backup: "flake.nix.20261124T101500Z" }) }), "backupName"],
            ["restore: what the file holds not known", plan({ op: "restore", reading: reading(), from: Object.assign({}, from, { sha256: "" }) }), "unread"],
            ["apply: a file not read", plan({ op: "apply", reading: reading({ file: { state: "unreadable", sha256: "" } }), candidate: candidate() }), "unread"],
            ["apply: a file not read, a hash given", plan({ op: "apply", reading: reading({ file: { state: "unreadable", sha256: sha(old) } }), candidate: candidate() }), "unread"],
            ["apply: no drvPath", plan({ op: "apply", reading: reading(), candidate: candidate({ drvPath: undefined }) }), "built"],
            ["apply: a drvPath in another store of the same length", plan({ op: "apply", reading: reading(),
                                                                            candidate: candidate({ drvPath: drv.replace("/scratch/", "/scrxtch/") }) }), "built"],
            ["apply: a file read, its hash not", plan({ op: "apply", reading: reading({ file: { state: "present", sha256: "" } }), candidate: candidate() }), "unread"],
            ["apply: a flake's host not plain", plan({ op: "apply", reading: reading({ host: "lap top" }), candidate: candidate() }), "host"],
            ["apply: no host", plan({ op: "apply", reading: reading({ host: "" }), candidate: candidate() }), "host"],
            ["apply: an entry with a folder", plan({ op: "apply", reading: reading({ configuration: { found: true, folder, entry: "../c.nix", type: "classic" } }),
                                                    candidate: candidate() }), "arguments"],
            ["apply: a flake not named flake.nix", plan({ op: "apply", reading: reading({ configuration: { found: true, folder, entry: "configuration.nix", type: "flake" } }),
                                                         candidate: candidate() }), "arguments"],
            ["apply: flake.nix as classic", plan({ op: "apply", reading: reading({ configuration: { found: true, folder, entry: "flake.nix", type: "classic" } }),
                                                   candidate: candidate() }), "arguments"],
            ["apply: no candidate", plan({ op: "apply", reading: reading() }), "candidate"],
            ["apply: a candidate not an object", plan({ op: "apply", reading: reading(), candidate: candidate({ text: "[1]" }) }), "candidate"],
            ["apply: a candidate with a NUL", plan({ op: "apply", reading: reading(), candidate: candidate({ text: "{\u0000}" }) }), "candidate"],
            ["apply: a candidate over 64 KiB", plan({ op: "apply", reading: reading(), candidate: candidate({ text: "{" + "x".repeat(rules.maxBytes) }) }), "candidate"],
            ["apply: a candidate over 64 KiB in bytes", plan({ op: "apply", reading: reading(), candidate: candidate({ text: "{" + "é".repeat(rules.maxBytes / 2) }) }), "candidate"],
            ["apply: a candidate not valid Unicode", plan({ op: "apply", reading: reading(), candidate: candidate({ text: "{\uD800}" }) }), "candidate"],
            ["apply: the build's hash not the text's", plan({ op: "apply", reading: reading(), candidate: candidate({ sha256: sha(old) }) }), "candidate"],
            ["apply: a drvPath outside the store", plan({ op: "apply", reading: reading(), candidate: candidate({ drvPath: "/tmp/zyxwvsrqpnmlkjihgfdcba9876543210-x.drv" }) }), "built"],
            ["apply: a drvPath not a .drv", plan({ op: "apply", reading: reading(), candidate: candidate({ drvPath: out }) }), "built"],
            ["apply: an out path that is a .drv", plan({ op: "apply", reading: reading(), candidate: candidate({ outPath: drv }) }), "built"],
            ["apply: an out path below one", plan({ op: "apply", reading: reading(), candidate: candidate({ outPath: out + "/bin" }) }), "built"],
            ["apply: a store hash too short", plan({ op: "apply", reading: reading(), candidate: candidate({ outPath: base + "/nix/store/0123-x" }) }), "built"],
            ["apply: a store hash with letters base-32 has not", plan({ op: "apply", reading: reading(),
                                                                         candidate: candidate({ outPath: base + "/nix/store/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee-x" }) }), "built"]
        ];
        for (const [name, planned, expected] of refusals) {
            assertEqual(code(planned), expected, "refused, " + name);
            assert(planned.argv === null && planned.expected === null, "… " + name + ": no words");
        }
        assertEqual(plan({ op: "apply", reading: reading(), candidate: candidate({ text: "{" + "x".repeat(rules.maxBytes - 1) }) }).refusal, null,
                    "apply: a candidate of exactly 64 KiB");
        assertEqual(plan({ op: "apply", reading: reading({ host: "a".repeat(253) }), candidate: candidate() }).refusal, null, "apply: the longest host");
        assertEqual(code(plan({ op: "apply", reading: reading({ host: "a".repeat(254) }), candidate: candidate() })), "host", "… one longer refused");
        assert(rules.validEntry("e".repeat(251) + ".nix") && !rules.validEntry("e".repeat(252) + ".nix"), "entries: at most 255 characters");
        assert(rules.validEntry("_a-b.c.nix") && !rules.validEntry(".hidden.nix") && !rules.validEntry("-a.nix") && !rules.validEntry("a.nixx") && !rules.validEntry(null),
               "entries: plain .nix names");
        assertEqual(show(rules.refusal("nope")), show({ code: "nope", text: rules.texts.arguments }), "a code without a text: the request's");
        assertEqual(rules.refusal("changed").text, "Your configuration changed since the build. Nothing changed. Build again.", "the changed text");
        assertEqual(rules.pathsRefusal(live, true), "", "the system's places for the system's pkexec");
        assertEqual(rules.timeoutMs, 1800000, "a run may take 30 minutes");

        // ── the reply ──
        const result = (code, stderr, more) => Object.assign({ ok: code === 0, code, stdout: "", stderr, dismissed: false, refused: false, cancelled: false,
                                                               blocked: "", timedOut: false, error: "" }, more ?? {});
        const said = (code, line, more) => result(code, "pkexec:x\nactivating the configuration...\n" + line + "\n", Object.assign({ stdout: line + "\n" }, more ?? {}));
        const pick = (outcome, keys) => show(keys.reduce((picked, key) => Object.assign(picked, { [key]: outcome[key] }), {}));
        const keys = ["ok", "quiet", "kind", "op", "folder", "generation", "backup", "sha256", "nothingChanged", "refused", "error"];
        const reply = (planned, code, line, more) => rules.reply(said(code, line, more), planned.expected);

        assertEqual(pick(reply(applied, 0, "applied 49 " + backup), keys),
                    show({ ok: true, quiet: false, kind: "applied", op: "apply", folder, generation: 49, backup, sha256: sha(text), nothingChanged: false, refused: "", error: "" }),
                    "applied: the generation, the backup, the file holds the candidate");
        assertEqual(pick(reply(applied, 0, "applied unknown " + backup, { stdout: "" }), ["ok", "generation"]), show({ ok: true, generation: 0 }),
                    "applied: a generation not known; on stderr alone");
        assertEqual(pick(rules.reply(result(0, "", { stdout: "applied 49 " + backup + "\n" }), applied.expected), ["ok", "kind"]), show({ ok: true, kind: "applied" }),
                    "applied: on stdout alone (stderr gone)");
        assertEqual(pick(reply(switched, 0, "applied 49 -"), ["ok", "kind", "backup", "sha256"]), show({ ok: true, kind: "applied", backup: "", sha256: sha(text) }),
                    "switch applied: no backup");
        assertEqual(pick(reply(applied, 4, "applied-with-errors 50 " + backup), keys),
                    show({ ok: true, quiet: false, kind: "appliedWithErrors", op: "apply", folder, generation: 50, backup, sha256: sha(text), nothingChanged: false,
                           refused: "", error: rules.texts.appliedWithErrors }), "exit 4: applied with errors, said so");
        assertEqual(pick(reply(switched, 4, "applied-with-errors 50 -"), ["ok", "kind"]), show({ ok: true, kind: "appliedWithErrors" }), "switch: applied with errors");
        assertEqual(pick(reply(applied, 1, "failed 51 " + backup), keys),
                    show({ ok: false, quiet: false, kind: "failed", op: "apply", folder, generation: 51, backup, sha256: sha(text), nothingChanged: false,
                           refused: "", error: rules.texts.failed }), "a failed activation: the file kept, maybe partly changed");
        assertEqual(pick(reply(switched, 1, "failed 51 -"), ["kind", "backup", "nothingChanged"]), show({ kind: "failed", backup: "", nothingChanged: false }), "switch failed");
        assertEqual(pick(reply(applied, 1, "restored " + sha(old) + " " + backup + "-1"), keys),
                    show({ ok: false, quiet: false, kind: "failed", op: "apply", folder, generation: 0, backup: backup + "-1", sha256: sha(old), nothingChanged: true,
                           refused: "", error: rules.texts.profile }), "the profile not set: the old file back, nothing changed");
        assertEqual(pick(reply(absent, 1, "restored absent " + backup + "-1"), ["kind", "sha256", "nothingChanged"]), show({ kind: "failed", sha256: "absent", nothingChanged: true }),
                    "… no file before: none again");
        assertEqual(pick(reply(applied, 5, "not-activated 48 " + sha(old) + " " + backup), keys),
                    show({ ok: false, quiet: false, kind: "failed", op: "apply", folder, generation: 48, backup, sha256: sha(old), nothingChanged: true,
                           refused: "", error: rules.texts.notActivated }), "not activated: the generation before, the old file back");
        assertEqual(pick(reply(switched, 5, "not-activated 48 - -"), ["kind", "backup", "sha256", "nothingChanged", "error"]),
                    show({ kind: "failed", backup: "", sha256: "", nothingChanged: true, error: rules.texts.notActivated }), "switch not activated: nothing written");
        assertEqual(pick(reply(applied, 6, "not-restored " + sha(text) + " " + backup), keys),
                    show({ ok: false, quiet: false, kind: "failed", op: "apply", folder, generation: 0, backup, sha256: sha(text), nothingChanged: false,
                           refused: "", error: rules.texts.notRestored }), "not restored: the candidate still written, the old one in its backup");
        assertEqual(pick(reply(created, 0, "created " + sha(old) + " " + backup + ".absent"), keys),
                    show({ ok: true, quiet: false, kind: "created", op: "create", folder, generation: 0, backup: backup + ".absent", sha256: sha(old), nothingChanged: false,
                           refused: "", error: "" }), "created");
        assertEqual(pick(reply(restored, 0, "restored " + sha(old) + " " + backup + "-1"), keys),
                    show({ ok: true, quiet: false, kind: "restored", op: "restore", folder, generation: 0, backup: backup + "-1", sha256: sha(old), nothingChanged: false,
                           refused: "", error: "" }), "restored");
        assertEqual(pick(reply(restored, 0, "restored absent " + backup + "-1"), ["ok", "sha256"]), show({ ok: true, sha256: "absent" }), "restored: no file now");
        // Refusals: on stderr, exit 3
        const refusedReply = (planned, reason) => rules.reply(result(3, "error: x\nrefused " + reason + "\n"), planned.expected);
        assertEqual(pick(refusedReply(applied, "changed"), keys),
                    show({ ok: false, quiet: false, kind: "changed", op: "apply", folder, generation: 0, backup: "", sha256: sha(old), nothingChanged: true,
                           refused: "changed", error: rules.texts.changed }), "refused changed: the configuration changed since the build, nothing changed");
        assertEqual(pick(refusedReply(switched, "evaluation"), ["kind", "refused", "nothingChanged", "error"]),
                    show({ kind: "refused", refused: "evaluation", nothingChanged: true, error: rules.texts.evaluation }), "refused, its text");
        assertEqual(refusedReply(created, "zzz").error, rules.texts.arguments, "a refusal without a text: the request's");
        assertEqual(pick(rules.reply(result(3, "refused changed\n", { stdout: "x\n" }), applied.expected), ["kind"]), show({ kind: "changed" }),
                    "a refusal: whatever stdout says");
        // What never counts
        const failures = [
            ["no output", rules.reply(result(0, ""), applied.expected)],
            ["no result", rules.reply(null, applied.expected)],
            ["applied, exit 1", reply(applied, 1, "applied 49 " + backup)],
            ["applied, exit 4", reply(applied, 4, "applied 49 " + backup)],
            ["applied, no exit code", reply(applied, undefined, "applied 49 " + backup)],
            ["applied, exit as text", reply(applied, "0", "applied 49 " + backup)],
            ["applied with errors, exit 0", reply(applied, 0, "applied-with-errors 49 " + backup)],
            ["applied, not the last line", rules.reply(result(0, "applied 49 " + backup + "\nsomething else\n", { stdout: "applied 49 " + backup + "\nmore\n" }), applied.expected)],
            ["applied, a generation not a number", reply(applied, 0, "applied x9 " + backup)],
            ["applied, a negative generation", reply(applied, 0, "applied -1 " + backup)],
            ["applied, no backup after apply", reply(applied, 0, "applied 49 -")],
            ["applied, a backup after switch", reply(switched, 0, "applied 49 " + backup)],
            ["applied, a backup that is no backup", reply(applied, 0, "applied 49 ../x")],
            ["applied, a word more", reply(applied, 0, "applied 49 " + backup + " x")],
            ["applied, a word less", reply(applied, 0, "applied 49")],
            ["applied for create", reply(created, 0, "applied 49 " + backup)],
            ["applied for restore", reply(restored, 0, "applied 49 " + backup)],
            ["created for apply", reply(applied, 0, "created " + sha(old) + " " + backup + ".absent")],
            ["created, another hash", reply(created, 0, "created " + sha(text) + " " + backup + ".absent")],
            ["created, a backup of a file", reply(created, 0, "created " + sha(old) + " " + backup)],
            ["created, exit 1", reply(created, 1, "created " + sha(old) + " " + backup + ".absent")],
            ["restored for restore, exit 1", reply(restored, 1, "restored " + sha(old) + " " + backup)],
            ["restored for restore, not a hash", reply(restored, 0, "restored xyz " + backup)],
            ["restored for restore, not a backup", reply(restored, 0, "restored absent x")],
            ["restored after apply, exit 0", reply(applied, 0, "restored " + sha(old) + " " + backup)],
            ["restored after apply, another file", reply(applied, 1, "restored " + sha(text) + " " + backup)],
            ["restored after apply, unknown", reply(applied, 1, "restored unknown unknown")],
            ["restored after switch", reply(switched, 1, "restored " + sha(old) + " " + backup)],
            ["not activated, exit 1", reply(applied, 1, "not-activated 48 " + sha(old) + " " + backup)],
            ["not activated, another file", reply(applied, 5, "not-activated 48 " + sha(text) + " " + backup)],
            ["not activated, no backup after apply", reply(applied, 5, "not-activated 48 " + sha(old) + " -")],
            ["not activated, a file after switch", reply(switched, 5, "not-activated 48 " + sha(old) + " -")],
            ["not activated, a backup after switch", reply(switched, 5, "not-activated 48 - " + backup)],
            ["not activated, a word less", reply(switched, 5, "not-activated 48 -")],
            ["not activated, a bad generation", reply(switched, 5, "not-activated x - -")],
            ["not restored, exit 1", reply(applied, 1, "not-restored " + sha(text) + " " + backup)],
            ["not restored, another file", reply(applied, 6, "not-restored " + sha(old) + " " + backup)],
            ["not restored, not a backup", reply(applied, 6, "not-restored " + sha(text) + " x")],
            ["not restored, a word more", reply(applied, 6, "not-restored " + sha(text) + " " + backup + " x")],
            ["not restored after switch", reply(switched, 6, "not-restored " + sha(text) + " " + backup)],
            ["failed, exit 0", reply(applied, 0, "failed 51 " + backup)],
            ["refused, exit 1", rules.reply(result(1, "refused changed\n"), applied.expected)],
            ["refused, exit 0", rules.reply(result(0, "refused changed\n"), applied.expected)],
            ["refused, on stdout only", rules.reply(result(3, "x\n", { stdout: "refused changed\n" }), applied.expected)],
            ["refused, a code not a word", rules.reply(result(3, "refused Changed!\n"), applied.expected)],
            ["refused, two words", rules.reply(result(3, "refused changed now\n"), applied.expected)],
            ["refused, no code", rules.reply(result(3, "refused\n"), applied.expected)],
            ["a timed-out run", rules.reply(result(-1, "activating\n", { timedOut: true }), applied.expected)],
            ["an expected op not known", reply({ expected: { op: "rebuild", folder } }, 0, "applied 49 -")],
            ["nothing expected", reply({ expected: null }, 0, "applied 49 -")]
        ];
        for (const [name, outcome] of failures) {
            const reason = name === "a timed-out run" ? rules.texts.timedOut : rules.texts.unclear;
            assert(!outcome.ok && !outcome.quiet && outcome.kind === "failed" && !outcome.nothingChanged && outcome.error === reason,
                   "never applied: " + name + " — " + show(outcome));
        }
        assertEqual(rules.reply(result(-1, "", { timedOut: true }), applied.expected).error, rules.texts.timedOut, "timed out: said so");
        assertEqual(rules.reply(result(2, "boom\n"), applied.expected).error, rules.texts.unclear, "no answer it can read: the system may have changed");
        // Quiet: a prompt dismissed, refused by polkit, the session locked; a cancel
        const quiet = more => rules.reply(result(126, "", more), applied.expected);
        assertEqual(pick(quiet({ dismissed: true }), keys),
                    show({ ok: false, quiet: true, kind: "", op: "apply", folder, generation: 0, backup: "", sha256: sha(old), nothingChanged: true, refused: "", error: "" }),
                    "dismissed: quiet, nothing changed");
        assertEqual(pick(quiet({ refused: true }), ["quiet", "nothingChanged"]), show({ quiet: true, nothingChanged: true }), "not authorized: quiet, nothing changed");
        assertEqual(pick(quiet({ blocked: "locked" }), ["quiet", "nothingChanged", "kind"]), show({ quiet: true, nothingChanged: true, kind: "" }), "locked: quiet, nothing ran");
        assertEqual(pick(quiet({ cancelled: true }), ["quiet", "nothingChanged", "sha256"]), show({ quiet: true, nothingChanged: false, sha256: "" }),
                    "cancelled: quiet, but it may have changed something");
        assertEqual(pick(rules.reply(said(0, "applied 49 " + backup, { dismissed: true }), applied.expected), ["ok"]), show({ ok: true }),
                    "a line it can read wins over the flags");
        assertEqual(rules.reply(result(126, "", { dismissed: true }), null).sha256, "", "dismissed, nothing expected: the file not known");
    }
}
