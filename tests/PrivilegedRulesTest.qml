import QtQuick
import qs.singletons

// Running as administrator, the decisions (singletons/PrivilegedRules.qml): text that cannot
// be shown, the options, every refusal before pkexec runs, the words handed to pkexec (the
// shell's `timeout` inside it), where pkexec is, the answer, and the queue's life.
TestCase {
    suiteName: "PrivilegedRules"

    function run() {
        const rules = PrivilegedRules;

        // --- text ---
        for (const text of ["a\nb", "tab\there", "‮evil", "zero​width", "soft­hyphen", "nul\u0000",
                            "tag󠀁", "lone \ud800 surrogate", "\u0085next line", "bom﻿",
                            "line\u2028separator", "paragraph\u2029separator",
                            "unit\u001fseparator", "c1 \u009f end", "lone \udfff low"])
            assert(rules.unprintable(text), "unprintable: " + JSON.stringify(text));
        for (const text of ["", "plain words", "café", "日本語", "emoji 😀", "--flag=value", "a b"])
            assert(!rules.unprintable(text), "printable: " + JSON.stringify(text));
        assertEqual(rules.cleanWhat("  Send\n a\tfile ‮ "), "Send a file", "what: white space folded, a format character dropped, trimmed");
        assertEqual(rules.cleanWhat("​‮ \n"), "", "what: nothing left");
        assertEqual(rules.cleanWhat(42) + rules.cleanWhat(null) + rules.cleanWhat(undefined), "", "what: not a string → \"\"");
        assertEqual(rules.cleanWhat("x".repeat(500)).length, rules.whatMaxLength, "what: capped");
        assertEqual(rules.cleanWhat("Send 😀 a file"), "Send 😀 a file", "what: an emoji survives cleaning");
        assertEqual(rules.cleanWhat("x".repeat(rules.whatMaxLength - 1) + "😀😀"), "x".repeat(rules.whatMaxLength - 1) + "😀",
                    "what: an emoji at the cap counted as one character, never cut in half");
        assertEqual(rules.cleanWhat("Send\u2028a\u2029file"), "Send a file", "what: line and paragraph separators are white space, folded");
        // Surrogate pairs at the ends of their ranges stay whole; a lone low surrogate after
        // any other character is dropped, never glued to it
        assertEqual(JSON.stringify(rules.characters(42)), "[]", "characters: not a string → none");
        assertEqual(rules.characters("a\ud800\udc00b").join("|"), "a|\ud800\udc00|b", "characters: U+10000 (D800 DC00) is one character");
        assertEqual(rules.characters("x\udbff\udfffy").join("|"), "x|\udbff\udfff|y", "characters: U+10FFFF (DBFF DFFF) is one character");
        assertEqual(rules.cleanWhat("a\ud800\udc00b") + rules.cleanWhat("x\udbff\udfffy"), "a\ud800\udc00bx\udbff\udfffy",
                    "what: pairs at the ends of the surrogate ranges kept");
        assertEqual(rules.cleanWhat("a\udc00b"), "ab", "what: a lone low surrogate after a letter dropped");
        assertEqual(rules.cleanWhat("\ue000\udc00"), "\ue000", "what: a lone low surrogate after a character above the surrogates dropped");

        // --- The notification when the shell's prompt does not answer ---
        const announced = PolkitRules.announcement({ moduleName: "Tailscale", moduleId: "tailscale", what: "Send a file", pkexecArgv: ["/usr/bin/true"] });
        for (const agentState of ["other", "blocked", "deciding", "none"])
            assertEqual(JSON.stringify(rules.launchNotice(announced, rules.shellAnswers(agentState))),
                        JSON.stringify({ summary: "Module: Tailscale", options: { body: "Authorization: Send a file", format: "plain" } }),
                        "launchNotice, agent " + agentState + ": who runs what, plain");
        for (const agentState of ["active", "conflict"])
            assertEqual(rules.launchNotice(announced, rules.shellAnswers(agentState)), null, "launchNotice, agent " + agentState + ": none, the shell's prompt says it");
        assertEqual(JSON.stringify(rules.launchNotice(PolkitRules.announcement({ legacy: true, what: "x", pkexecArgv: [] }), false)),
                    JSON.stringify({ summary: "Module: Not named", options: { body: "", format: "plain" } }), "launchNotice: an old run names no module and no purpose");
        assertEqual(rules.launchNotice(null, false), null, "launchNotice: no announcement, none");

        // --- the options ---
        const good = { what: "Connect", timeoutMs: 30000 };
        assertEqual(JSON.stringify(rules.options(good)), JSON.stringify({ problem: "", what: "Connect", timeoutMs: 30000, notifyFailures: true,
                                                                        environment: {}, callbacks: { onStdout: null, onStderr: null, onLine: null, done: null } }),
                    "options: what and timeoutMs, notifyFailures true by default");
        assertEqual(JSON.stringify(rules.options({ what: "Connect", timeoutMs: 30000, endWithShell: true })), JSON.stringify(rules.options(good)),
                    "options: the command runner's endWithShell is ignored — a privileged run never has setpriv put around its pkexec");
        for (const given of [undefined, null, "x", [1]])
            assertEqual(rules.options(given).problem, "the options are not an object (what and timeoutMs are needed)",
                        "options: not an object (" + JSON.stringify(given) + ") → a problem");
        assertEqual(rules.options({ what: "x", timeoutMs: 999 }).timeoutMs, 0, "timeoutMs out of range: none kept");
        for (const limit of [undefined, 999, 3600001, NaN, Infinity, "30000"])
            assert(rules.options({ what: "x", timeoutMs: limit }).problem.startsWith("timeoutMs"), "timeoutMs " + String(limit) + " → a problem");
        assertEqual(rules.options({ what: "x", timeoutMs: 1000 }).timeoutMs + rules.options({ what: "x", timeoutMs: 3600000 }).timeoutMs, 3601000,
                    "timeoutMs: 1 s and 1 h are the ends of the range");
        assert(rules.options({ what: "x", timeoutMs: 1000, notifyFailures: "yes" }).problem.startsWith("notifyFailures"), "notifyFailures not a bool → a problem");
        assert(rules.options({ what: "x", timeoutMs: 1000, done: "no" }).problem.startsWith("done"), "done not a function → a problem");
        assertEqual(rules.options({ what: "x", timeoutMs: 1000, notifyFailures: false }).notifyFailures, false, "notifyFailures false");
        // The environment (1.14): module test mode only, CommandRunner's shape, a plain copy
        const answersDone = () => {};
        const environmentGiven = { TS_FAKE_STATE: "running", DROPPED: null };
        const inTest = rules.options({ what: "x", timeoutMs: 1000, environment: environmentGiven }, true);
        assert(inTest.problem === "" && JSON.stringify(inTest.environment) === JSON.stringify(environmentGiven) && inTest.environment !== environmentGiven,
               "environment in test mode: taken, as a copy: " + JSON.stringify(inTest));
        const outside = rules.options({ what: "x", timeoutMs: 1000, environment: environmentGiven, done: answersDone }, false);
        assert(outside.problem === "environment is taken in module test mode only" && JSON.stringify(outside.environment) === "{}"
               && outside.callbacks.done === answersDone, "environment outside test mode: a problem, none kept, done still owed: " + JSON.stringify(outside));
        assertEqual(rules.options({ what: "x", timeoutMs: 1000, environment: environmentGiven }).problem, "environment is taken in module test mode only",
                    "environment, test mode not said: refused");
        assertEqual(rules.options({ what: "x", timeoutMs: 1000, environment: null }, false).problem, "", "environment null outside test mode: as not given");
        for (const wrong of ["A=1", [1], { "A=B": "x" }, { "": "x" }, { A: 1 }, { A: "a\u0000b" }])
            assert(rules.options({ what: "x", timeoutMs: 1000, environment: wrong }, true).problem.startsWith("the environment"),
                   "environment " + JSON.stringify(wrong) + " in test mode → a problem");
        const flipping = {};
        let valueReads = 0;
        Object.defineProperty(flipping, "A", { get() { return ++valueReads === 1 ? "first" : "switched"; }, enumerable: true });
        const flipped = rules.options({ what: "x", timeoutMs: 1000, environment: flipping }, true);
        assert(valueReads === 1 && flipped.environment.A === "first", "environment: each value read once, the copy kept: " + JSON.stringify(flipped.environment));
        const refusedEnvironment = rules.refusal({ argv: ["/usr/bin/true"], options: outside, active: true, locked: false, available: true, unavailableReason: "" });
        assert(refusedEnvironment.error.startsWith("environment") && refusedEnvironment.blocked === "", "outside test mode the run is refused with an error: " + JSON.stringify(refusedEnvironment));

        // Each option read once: a getter cannot pass the check and then hand over another value
        const reads = {};
        const counted = {};
        const answers = { what: "Connect", timeoutMs: 2000, notifyFailures: false, onStdout: () => {}, onStderr: () => {}, onLine: () => {}, done: () => {} };
        for (const name of Object.keys(answers)) {
            reads[name] = 0;
            Object.defineProperty(counted, name, { get() { return ++reads[name] === 1 ? answers[name] : "switched"; }, enumerable: true });
        }
        const once = rules.options(counted);
        assert(Object.keys(reads).every(name => reads[name] === 1), "options: every field read once: " + JSON.stringify(reads));
        assert(once.problem === "" && once.what === "Connect" && once.timeoutMs === 2000 && once.notifyFailures === false
               && once.callbacks.done === answers.done && once.callbacks.onLine === answers.onLine, "… and what was read is what is kept");
        assert(rules.options({ what: "x", done: answers.done }).callbacks.done === answers.done && rules.options({ what: "x", onLine: answers.onLine }).callbacks.onLine === null,
               "options wrong: done kept (an answer is owed), the others not");

        // --- refusals before pkexec runs ---
        const base = { argv: ["/usr/bin/tailscale", "up"], options: rules.options(good), active: true, locked: false,
                       available: true, unavailableReason: "", declaration: { problem: "", paths: ["/usr/bin/tailscale"] } };
        const asked = changes => rules.refusal(Object.assign({}, base, changes));
        assertEqual(asked({}), null, "everything right: no refusal");
        assert(asked({ options: rules.options({ what: "x" }) }).error.startsWith("timeoutMs") && asked({ options: rules.options({ what: "x" }) }).blocked === "",
               "bad options: error, not blocked");
        assert(asked({ argv: "not a list" }).error !== "" && !asked({ argv: "not a list" }).notFound, "argv not a list: error");
        assert(asked({ argv: [] }).error !== "", "argv empty: error");
        const missing = asked({ argv: ["", "up"] });
        assert(missing.notFound && missing.blocked === "" && missing.error.includes("not found"),
               "argv[0] \"\" (the path of a program not found): notFound: " + JSON.stringify(missing));
        assert(asked({ argv: [""] }).notFound, "argv [\"\"] alone: notFound");
        // Only an empty first word with the rest fine is notFound; any other wrong command is an error
        for (const [argv, what] of [[{ 0: "", 1: "up", length: 2 }, "a list that is no array"], [[5, "up"], "a first word not text"],
                                    [["", "a\u0000b"], "an empty first word and a later word with a NUL"]]) {
            const wrong = asked({ argv: argv });
            assert(!wrong.notFound && wrong.blocked === "" && wrong.error !== "", what + ": an error, not notFound: " + JSON.stringify(wrong));
        }
        assertEqual(asked({ active: false }).error, "the module is off", "module off: error");
        assertEqual(asked({ locked: true }).blocked, "locked", "locked: blocked locked");
        assertEqual(asked({ options: rules.options({ what: " ‮\n", timeoutMs: 1000 }) }).blocked, "no-purpose", "what empty after cleaning: no-purpose");
        assertEqual(asked({ options: rules.options({ timeoutMs: 1000 }) }).blocked, "no-purpose", "no what at all: no-purpose");
        assertEqual(asked({ argv: ["/usr/bin/tailscale", "file", "a\nb"] }).blocked, "unprintable", "a newline in a word: unprintable");
        const rtl = asked({ argv: ["/usr/bin/tailscale", "cp", "report‮fdp.exe"] });
        assert(rtl.blocked === "unprintable" && rtl.error.startsWith("word 3"), "U+202E in a word: unprintable, which word said: " + JSON.stringify(rtl));
        assertEqual(asked({ available: false, unavailableReason: "no pkexec found" }).error, "no pkexec found", "not available: error, the reason");
        assertEqual(asked({ available: false, unavailableReason: "x" }).blocked, "", "… not blocked");
        const relative = asked({ argv: ["tailscale", "up"] });
        assert(relative.notFound && relative.blocked === "" && relative.error.includes("absolute"),
               "argv[0] not absolute (root's PATH is never searched): notFound: " + JSON.stringify(relative));
        assert(relative.error.startsWith("\"tailscale\" is not an absolute path"), "… the word named whole: " + relative.error);
        const firstWord = asked({ argv: ["/opt/a\u202eb", "up"], declaration: { problem: "", paths: ["/opt/a\u202eb"] } });
        assert(firstWord.blocked === "unprintable" && firstWord.error.startsWith("word 1"), "a format character in argv[0]: unprintable, word 1: " + JSON.stringify(firstWord));
        // The command is not parsed: whatever argv[0] is, an absolute path the manifest declares passes
        for (const argv of [["/bin/sh", "-c", "id"], ["/usr/bin/env", "tailscale"], ["/usr/bin/python3", "-c", "x"],
                            ["/usr/bin/timeout", "5", "/bin/sh"], ["/nix/store/abc-coreutils-9.5/bin/coreutils", "--coreutils-prog=env", "/bin/sh"]])
            assertEqual(asked({ argv: argv, declaration: { problem: "", paths: [argv[0]] } }), null, "an absolute argv[0] declared passes, whatever it is: " + argv[0]);
        // … but a declared program the user could change is no declared path: refused
        const userWritable = rules.declaration({ why: "x", programs: ["tool"] }, undefined, "x",
                                               { tool: { path: "/home/u/.local/bin/tool", trusted: false, reason: "the user can write it" } });
        assertEqual(userWritable.paths.length, 0, "a declared program that is not trusted: no path");
        assertEqual(asked({ argv: ["/home/u/.local/bin/tool"], declaration: userWritable }).blocked, "undeclared",
                    "a declared program in a place the user can write: blocked undeclared");
        assertEqual(rules.declaration({ why: "x", programs: ["tool"] }, undefined, "x", { tool: { path: "/usr/bin/tool" } }).paths.length, 0,
                    "trusted not said: no path");

        // --- (1.36) the manifest's declaration ---
        const programsFound = { tailscale: { path: "/usr/bin/tailscale", trusted: true }, systemctl: { path: "/usr/bin/systemctl", trusted: true },
                                curl: { path: "/usr/bin/curl", trusted: true }, missing: { path: "", trusted: false } };
        const block = { why: "Connect", programs: ["tailscale", "systemctl", "missing"] };
        assertEqual(JSON.stringify(rules.declaration(block, undefined, "tailscale", programsFound)),
                    JSON.stringify({ problem: "", paths: ["/usr/bin/tailscale", "/usr/bin/systemctl"] }),
                    "declared, no acknowledgements recorded (the baseline): the declared programs' paths — a missing one none, an undeclared one (curl) not");
        assertEqual(rules.declaration(null, undefined, "tailscale", programsFound).problem,
                    "asks for administrator rights; module.json does not declare it (privileged)", "no block: refused, said");
        assert(rules.declaration({ why: "x" }, undefined, "x", programsFound).problem !== "" && rules.declaration("yes", undefined, "x", programsFound).problem !== "",
               "a block without a list of programs, or not an object: refused");
        assertEqual(rules.declaration(block, { tailscale: { source: "user", privileged: true } }, "tailscale", programsFound).problem, "",
                    "acknowledged with privileged: true: allowed");
        for (const [list, what] of [[{ tailscale: { source: "user", privileged: false } }, "privileged false"], [{ tailscale: { source: "user" } }, "privileged not said"],
                                    [{}, "no acknowledgement for the id"], [null, "a list that is null"], [[], "a list that is no object"],
                                    [{ tailscale: true }, "an acknowledgement that is no object"]]) {
            const answer = rules.declaration(block, list, "tailscale", programsFound);
            assert(answer.problem === "asks for administrator rights; the user has not approved its declaration" && answer.paths.length === 0,
                   what + ": not approved, nothing may run: " + JSON.stringify(answer));
        }
        assertEqual(rules.declaration(block, undefined, "tailscale", null).paths.length, 0, "programs not looked at: no path");
        assertEqual(rules.declaration(block, Object.create({ tailscale: { source: "user", privileged: true } }), "tailscale", programsFound).problem,
                    "asks for administrator rights; the user has not approved its declaration", "an inherited acknowledgement is none: not approved");
        assertEqual(rules.declaration({ why: "x", programs: ["constructor", "__proto__"] }, undefined, "x", {}).paths.length, 0, "inherited names find nothing");
        const undeclared = asked({ declaration: rules.declaration(null, undefined, "tailscale", programsFound) });
        assert(undeclared.blocked === "undeclared" && undeclared.error.includes("does not declare") && !undeclared.notFound,
               "no block: blocked undeclared: " + JSON.stringify(undeclared));
        assertEqual(asked({ declaration: undefined }).blocked, "undeclared", "no declaration given at all: blocked undeclared");
        assertEqual(asked({ declaration: { problem: "", paths: "/usr/bin/tailscale" } }).blocked, "undeclared", "a declaration of the wrong shape: blocked undeclared");
        assertEqual(asked({ declaration: rules.declaration(block, {}, "tailscale", programsFound) }).blocked, "undeclared", "not approved: blocked undeclared");
        const other = asked({ argv: ["/usr/bin/curl", "-o", "/etc/x"], declaration: rules.declaration(block, undefined, "tailscale", programsFound) });
        assert(other.blocked === "undeclared" && other.error === "runs \"/usr/bin/curl\" as administrator; module.json's privileged.programs does not name it",
               "argv[0] a program it has but did not declare: blocked undeclared, which said: " + JSON.stringify(other));
        assertEqual(asked({ argv: ["/usr/bin/systemctl", "start", "x"], declaration: rules.declaration(block, undefined, "tailscale", programsFound) }), null,
                    "a declared program by its path: passes");
        assertEqual(asked({ argv: ["/usr/bin/../bin/tailscale", "up"] }).blocked, "undeclared", "the same program by another spelling of its path: not the declared path");
        assertEqual(rules.refusedResult(undeclared).blocked + " " + rules.refusedResult(undeclared).dismissed, "undeclared false",
                    "the answer: blocked undeclared, not dismissed");
        assert(rules.blockedReasons.includes("undeclared"), "undeclared is a blocked reason");
        // Whose code asks: the stack names the module's directory alone
        assertEqual(rules.callerProblem(["/m/a"], "/m/a"), "", "the module's own code alone: fine");
        assertEqual(rules.callerProblem(["/m/b"], "/m/a"), "a run as administrator that crosses modules is refused: only a module's own code may ask",
                    "another module's code with this handle: refused");
        assert(rules.callerProblem(["/m/b", "/m/a"], "/m/a").includes("crosses modules") && rules.callerProblem(["/m/a", "/m/b"], "/m/a").includes("crosses modules"),
               "two modules on the stack, either order: refused");
        assert(rules.callerProblem([], "/m/a").includes("cannot trace") && rules.callerProblem(null, "/m/a").includes("cannot trace")
               && rules.callerProblem(["/m/a"], "").includes("cannot trace"), "no module seen, or no directory of its own: refused");
        // The old PrivilegedAction's elevating words
        assertEqual(rules.legacyElevateProblem(["pkexec"], false), "", "\"pkexec\" alone outside test mode: the trusted pkexec, fine");
        for (const [words, what] of [[["pkexec", "/bin/sh", "-c", "id", "--"], "pkexec then a shell"], [["/usr/bin/pkexec", "/home/u/evil"], "a path then a program"],
                                     [["pkexec", "--user", "x"], "pkexec with words of its own"], [[], "none"], ["pkexec", "not a list"], [[""], "an empty word"], [[7], "not a string"]])
            assert(rules.legacyElevateProblem(words, false).startsWith("elevate must be") && rules.legacyElevateProblem(words, true).startsWith("elevate must be"),
                   what + ": refused, in test mode too: " + JSON.stringify(words));
        assertEqual(rules.legacyElevateProblem(["/usr/bin/pkexec"], false), "elevate must be \"pkexec\", the shell's trusted pkexec: \"/usr/bin/pkexec\" is refused",
                    "one path outside test mode: refused, the word named (only the trusted pkexec by name)");
        assertEqual(rules.legacyElevateProblem(["/m/a/tests/programs/pkexec"], true), "", "test mode: one word, left to the test-mode gate");
        assertEqual(rules.legacyElevateProblem(["/m/a/tests/programs/pkexec", "/bin/sh"], true).startsWith("elevate must be"), true, "test mode: a stand-in with more words: refused");

        // The old PrivilegedAction: a module on the stack, declared, approved, the program declared
        const approved = rules.declaration(block, undefined, "tailscale", programsFound);
        assertEqual(rules.legacyDeclarationProblem("tailscale", approved, "/usr/bin/tailscale"), "", "PrivilegedAction: a declared program from a declaring module: goes on");
        assertEqual(rules.legacyDeclarationProblem("", approved, "/usr/bin/tailscale"),
                    "a run as administrator from code the shell cannot trace to a module is refused", "PrivilegedAction from no module seen: refused (fail closed)");
        assertEqual(rules.legacyDeclarationProblem(undefined, approved, "/usr/bin/tailscale") !== "", true, "… no id at all: refused");
        assert(rules.legacyDeclarationProblem("tailscale", approved, "/bin/sh").includes("privileged.programs does not name it"),
               "PrivilegedAction: a program not declared: refused, which said");
        assert(rules.legacyDeclarationProblem("tailscale", null, "/usr/bin/tailscale").includes("does not declare it"), "PrivilegedAction: no declaration: refused");
        assert(rules.legacyDeclarationProblem("tailscale", rules.declaration(block, {}, "tailscale", programsFound), "/usr/bin/tailscale").includes("not approved"),
               "PrivilegedAction: not approved: refused");
        // Its place in the order: after notFound and the module off, before the lock and the rest
        assert(asked({ argv: ["", "up"], declaration: undefined }).notFound, "notFound before undeclared");
        assertEqual(asked({ active: false, declaration: undefined }).error, "the module is off", "module off before undeclared");
        assertEqual(asked({ locked: true, declaration: undefined }).blocked, "undeclared", "undeclared before locked");
        assertEqual(asked({ options: rules.options({ timeoutMs: 1000 }), declaration: undefined }).blocked, "undeclared", "undeclared before no-purpose");
        assertEqual(asked({ available: false, declaration: undefined }).blocked, "undeclared", "undeclared before availability");
        // The order
        assertEqual(asked({ locked: true, options: rules.options({ timeoutMs: 1000 }) }).blocked, "locked", "locked before no-purpose");
        assertEqual(asked({ active: false, locked: true }).error, "the module is off", "module off before locked");
        assertEqual(asked({ options: rules.options({ timeoutMs: 1000 }), argv: ["/usr/bin/tailscale", "a\nb"] }).blocked, "no-purpose",
                    "no-purpose before unprintable");
        assertEqual(asked({ argv: ["/usr/bin/tailscale", "a\nb"], available: false }).blocked, "unprintable", "unprintable before availability");
        assert(asked({ argv: ["relative"], active: false }).notFound, "a relative argv[0] (notFound) before the module off");
        assertEqual(rules.refusedResult(asked({ locked: true })).dismissed, true, "a run refused for the lock is dismissed too");
        assertEqual(rules.refusedResult(asked({ options: rules.options({ timeoutMs: 1000 }) })).dismissed, false, "… other refusals are not");

        // --- the words handed to pkexec ---
        assertEqual(JSON.stringify(rules.pkexecArgv("/run/wrappers/bin/pkexec", "/usr/bin/timeout", 30000, 3000, ["/usr/bin/tailscale", "file", "cp", "--", "-x"])),
                    JSON.stringify(["/run/wrappers/bin/pkexec", "/usr/bin/timeout", "-k", "3", "30", "/usr/bin/tailscale", "file", "cp", "--", "-x"]),
                    "pkexec, then the shell's timeout with its kill-after and the limit, then the command as given");
        assertEqual(rules.pkexecArgv("/p", "/t", 2500, 0, ["/c"]).slice(2, 5).join(" "), "-k 0.001 2.5", "seconds with decimals; a kill-after of 0 is 1 ms");
        assertEqual(JSON.stringify(rules.shellArgv("/usr/bin/timeout", ["/bin/sh", "-c", "x", "sh", "a"])),
                    JSON.stringify(["pkexec", "/usr/bin/timeout", "-k", "3", "300", "/bin/sh", "-c", "x", "sh", "a"]),
                    "shellArgv: the shell's own command under the timeout, its limit, pkexec by name");
        assertEqual([rules.shellArgv("", ["/bin/sh"]), rules.shellArgv("timeout", ["/bin/sh"]), rules.shellArgv("/t", ["sh"]), rules.shellArgv("/t", [])].join(","),
                    ",,,", "… no trusted timeout or no absolute command: null");
        assertEqual([rules.shellArgv("/t", "/bin/sh"), rules.shellArgv("/t", [5]), rules.shellArgv("/t", ["sh", "/x"]), rules.shellArgv(null, ["/bin/sh"])].join(","),
                    ",,,", "… a command that is not a list of words, a first word not text, a relative first word: null");
        assertEqual([rules.shellCheckWaits(true, false), rules.shellCheckWaits(true, true), rules.shellCheckWaits(false, false)].join(" "),
                    "true false false", "shellCheckWaits: the shell's own command waits for the look-up of the timeout, others do not");
        assertEqual(JSON.stringify(rules.shellArgv("/t", ["/bin/true"])), JSON.stringify(["pkexec", "/t", "-k", "3", "300", "/bin/true"]),
                    "… a command of one word");

        // --- a command of the shell's own asking for its own limit and lines ---
        assertEqual(JSON.stringify(rules.shellArgv("/t", ["/bin/true"], 1800000)), JSON.stringify(["pkexec", "/t", "-k", "3", "1800", "/bin/true"]),
                    "shellArgv with a longer limit: the limit among the words the prompt shows");
        assertEqual(JSON.stringify(rules.shellArgv("/t", ["/bin/true"], 3600000)), JSON.stringify(["pkexec", "/t", "-k", "3", "3600", "/bin/true"]),
                    "… the longest allowed, an hour");
        assertEqual(JSON.stringify(rules.shellArgv("/t", ["/bin/true"], 1000)), JSON.stringify(["pkexec", "/t", "-k", "3", "1", "/bin/true"]),
                    "… the shortest allowed, a second");
        assertEqual(rules.shellArgv("/t", ["/bin/true"], 1000.5)[4], "1.001", "… rounded to whole ms (1000.5 ms is 1.001 s, not 1.0005 cut to 1)");
        assertEqual([rules.shellArgv("/t", ["/bin/true"], 3600001), rules.shellArgv("/t", ["/bin/true"], 999), rules.shellArgv("/t", ["/bin/true"], 0),
                     rules.shellArgv("/t", ["/bin/true"], NaN), rules.shellArgv("/t", ["/bin/true"], Infinity), rules.shellArgv("/t", ["/bin/true"], "600000"),
                     rules.shellArgv("/t", ["/bin/true"], null)].join(","),
                    ",,,,,,", "… a limit past an hour, under a second, not a number: null, never clamped");
        assertEqual(rules.shellMaxRunMs, 3600000, "the longest limit of the shell's own commands: an hour");
        const lineCallback = () => {};
        assertEqual(JSON.stringify(rules.shellOptions({ what: "x", argv: ["/bin/true"] })), JSON.stringify({ problem: "", timeoutMs: 300000, onLine: null }),
                    "shellOptions: none asked: today's limit, no line callback");
        assertEqual(JSON.stringify([rules.shellOptions(undefined), rules.shellOptions(null)]),
                    JSON.stringify([{ problem: "", timeoutMs: 300000, onLine: null }, { problem: "", timeoutMs: 300000, onLine: null }]),
                    "… no request: the same (startShell refuses it for its words)");
        assertEqual(JSON.stringify(rules.shellOptions({ timeoutMs: null, onLine: null })), JSON.stringify({ problem: "", timeoutMs: 300000, onLine: null }),
                    "… null for either: not given");
        const longer = rules.shellOptions({ timeoutMs: 1800000.4, onLine: lineCallback });
        assert(longer.problem === "" && longer.timeoutMs === 1800000 && longer.onLine === lineCallback, "… a longer limit and a callback taken: " + JSON.stringify(longer));
        assertEqual(rules.shellOptions({ timeoutMs: 1000 }).timeoutMs, 1000, "… a second, the shortest");
        assertEqual(rules.shellOptions({ timeoutMs: 3600000 }).timeoutMs, 3600000, "… an hour, the longest");
        for (const wrong of [3600001, 999, 0, -1, NaN, Infinity, "600000", true]) {
            const refused = rules.shellOptions({ timeoutMs: wrong, onLine: lineCallback });
            assert(refused.problem === "timeoutMs must be 1000 to 3600000 ms (1 s to 1 h)" && refused.timeoutMs === 300000,
                   "… a limit of " + String(wrong) + " refused, the default kept: " + JSON.stringify(refused));
        }
        const notCallback = rules.shellOptions({ timeoutMs: 1000, onLine: "line" });
        assert(notCallback.problem === "onLine is not a function" && notCallback.onLine === null, "… an onLine that is no function refused: " + JSON.stringify(notCallback));
        let limitReads = 0;
        const getter = { get timeoutMs() { limitReads++; return limitReads === 1 ? 2000 : 7200000; } };
        const readOnce = rules.shellOptions(getter);
        assert(limitReads === 1 && readOnce.timeoutMs === 2000, "… each field read once: what is checked is what is used");
        assertEqual(rules.shellOptions({ get timeoutMs() { throw new Error("x"); } }).timeoutMs, 300000, "… a read that throws: not given");
        assertEqual(rules.shellStandIn(true, "/f/tests/programs/pkexec", ["/f/tests/programs/pkexec"]), "/f/tests/programs/pkexec",
                    "shellStandIn: test mode, a module's stand-in pkexec asked: that one");
        assertEqual([rules.shellStandIn(false, "/f/tests/programs/pkexec", ["/f/tests/programs/pkexec"]),
                     rules.shellStandIn(true, "/usr/bin/pkexec", ["/f/tests/programs/pkexec"]),
                     rules.shellStandIn(true, "", [""]), rules.shellStandIn(true, "/f/pkexec", null), rules.shellStandIn(true, 5, [5])].join(","),
                    ",,,,", "… outside test mode, a path no module's stand-in, nothing asked, no list, not text: the trusted pkexec (\"\")");

        // --- the old PrivilegedAction: its default "pkexec" is the shell's trusted one ---
        assert(rules.legacySystemPkexec(["pkexec"], false), "\"pkexec\" by name outside test mode: the trusted pkexec");
        assert(rules.legacySystemPkexec(["pkexec", "--disable-internal-agent"], false), "… with words of its own too");
        assert(!rules.legacySystemPkexec(["pkexec"], true), "test mode: left to the test-mode gate");
        assert(!rules.legacySystemPkexec(["/usr/bin/pkexec"], false) && !rules.legacySystemPkexec(["/opt/x/elevate"], false),
               "an elevating program given by its path: as given");
        const legacyArgv = ["pkexec", "/usr/bin/tailscale", "up"];
        assertEqual(JSON.stringify(rules.legacyLaunch(legacyArgv, true, true, "/run/wrappers/bin/pkexec", "")),
                    JSON.stringify({ argv: ["/run/wrappers/bin/pkexec", "/usr/bin/tailscale", "up"], problem: "" }),
                    "the trusted pkexec in place of the name, the command after it");
        const unlooked = rules.legacyLaunch(legacyArgv, true, false, "", "");
        assert(unlooked.problem.includes("not available") && unlooked.argv.length === 0,
               "the look-up not answered at launch: nothing run, never a pkexec not looked for: " + JSON.stringify(unlooked));
        assert(rules.legacyCheckWaits(true, false), "the trusted pkexec not looked up yet: the run waits in its check");
        assert(!rules.legacyCheckWaits(true, true), "… looked up (found or not): it goes on");
        assert(!rules.legacyCheckWaits(false, false), "an elevating program given by its path, or test mode: no look-up waited for");
        // Waiting in the check step: the queue still holds it as "checking", so a lock ends
        // it as "locked" and no head deadline runs meanwhile
        let waiting = rules.queueStep(rules.queueStart(false), { type: "add", id: 1, owner: "a", now: 10 });
        waiting = rules.queueStep(waiting.state, { type: "add", id: 2, owner: "b", now: 11 });
        assertEqual(waiting.state.jobs[0].phase, "checking", "the first run is being checked (waiting for the look-up)");
        assertEqual(rules.nextDeadline(waiting.state), 0, "no deadline while it waits: nothing lets the next run go");
        assertEqual(rules.nextDeadline({ jobs: [{ deadline: 5 }, { deadline: 1 }, { deadline: 0 }] }), 1, "nextDeadline: the earliest, however small");
        const later = rules.queueStep(waiting.state, { type: "tick", now: 10 + rules.headStrictMs + 1 });
        assertEqual(JSON.stringify(later.effects), "[]", "a tick long after: the second run is not started");
        const lockedWait = rules.queueStep(later.state, { type: "lock", locked: true, now: 9000 });
        assertEqual(JSON.stringify(lockedWait.effects.filter(effect => effect.id === 1)), JSON.stringify([{ type: "answer", id: 1, kind: "locked" }]),
                    "the session locked while it waits: answered \"locked\"");
        const lateCheck = rules.queueStep(lockedWait.state, { type: "checked", id: 1, found: true, shellAgent: true, now: 9100 });
        assertEqual(lateCheck.effects.length, 0, "its check answering after the lock: nothing launches");
        const unavailable = rules.legacyLaunch(legacyArgv, true, true, "", "pkexec is not installed");
        assert(unavailable.problem.includes("not available") && unavailable.problem.includes("not installed") && unavailable.argv.length === 0,
               "no trusted pkexec: the run fails as not available, nothing run: " + JSON.stringify(unavailable));
        assertEqual(JSON.stringify(rules.legacyLaunch(["/opt/x/elevate", "/bin/true"], false, false, "", "").argv), JSON.stringify(["/opt/x/elevate", "/bin/true"]),
                    "an elevating program given by its path: run as given, no look-up waited for");

        // --- where pkexec is ---
        const root = path => "stat\tpkexec\t0\t755\t0\t" + path;
        const wrapper = ["user\t1000\t1000 998", "cand\tpkexec\t/run/wrappers/bin/pkexec", root("/"), root("/run"), root("/run/wrappers"),
                         root("/run/wrappers/bin"), "stat\tpkexec\t0\t4511\t0\t/run/wrappers/bin/pkexec"];
        assertEqual(JSON.stringify(rules.pkexecChoice(wrapper)), JSON.stringify({ path: "/run/wrappers/bin/pkexec", reason: "" }),
                    "NixOS: the setuid wrapper, root's");
        const storeFirst = ["user\t1000\t1000", "cand\tpkexec\t/usr/bin/pkexec", root("/"), root("/usr"), root("/usr/bin"), root("/usr/bin/pkexec"),
                            "cand\tpkexec\t/bin/pkexec", root("/"), root("/bin"), "stat\tpkexec\t0\t4755\t0\t/bin/pkexec"];
        assertEqual(rules.pkexecChoice(storeFirst).path, "/bin/pkexec", "a trusted copy that is not setuid is passed over for the setuid one after it");
        assert(rules.pkexecChoice(storeFirst.slice(0, 6)).reason.includes("not setuid"), "only a copy that is not setuid: none, and why");
        const userOwned = ["user\t1000\t1000", "cand\tpkexec\t/usr/bin/pkexec", root("/"), root("/usr"), root("/usr/bin"),
                           "stat\tpkexec\t1000\t4755\t1000\t/usr/bin/pkexec"];
        assertEqual(rules.pkexecChoice(userOwned).path, "", "setuid but the user's file: none");
        assertEqual(rules.pkexecChoice(["user\t1000\t1000", "cand\tpkexec\t"]).reason, "pkexec is not installed", "not found: not installed");
        assertEqual(rules.pkexecChoice([]).reason, "the look-up for pkexec did not answer", "no answer: said so");
        assert(rules.setuidRoot({ owner: "0", mode: "4755" }) && !rules.setuidRoot({ owner: "0", mode: "104755" }),
               "setuidRoot: a mode of more than five octal digits is not read");
        assert(!rules.setuidRoot({ owner: "0", mode: 4755 }) && !rules.setuidRoot({ owner: "0", mode: "2755" }),
               "setuidRoot: a mode that is no text is not read; setgid alone (2755, read as octal) is not setuid");

        // --- available ---
        const facts = { testMode: false, standIn: "", pkexecKnown: true, pkexec: "/usr/bin/pkexec", pkexecReason: "",
                        timeoutKnown: true, timeout: "/usr/bin/timeout" };
        const availability = changes => rules.availability(Object.assign({}, facts, changes));
        assertEqual(JSON.stringify(availability({})), JSON.stringify({ available: true, reason: "", pkexec: "/usr/bin/pkexec", timeout: "/usr/bin/timeout" }),
                    "both found: available");
        assert(!availability({ pkexecKnown: false }).available, "pkexec still looked for: not yet");
        assertEqual(availability({ pkexec: "", pkexecReason: "pkexec is not installed" }).reason, "pkexec is not installed", "no pkexec: the reason");
        assert(!availability({ timeout: "" }).available && availability({ timeout: "" }).reason.includes("timeout"), "no trusted timeout: not available");
        assert(!availability({ timeoutKnown: false }).available, "timeout still looked for: not yet");
        assertEqual(availability({ testMode: true, standIn: "/m/tests/programs/pkexec" }).pkexec, "/m/tests/programs/pkexec",
                    "test mode: the module's stand-in");
        const noStandIn = availability({ testMode: true, standIn: "" });
        assert(!noStandIn.available && noStandIn.reason.startsWith("test mode:"), "test mode without a stand-in: not available — never the system's pkexec");
        assert(rules.shellAnswers("active") && rules.shellAnswers("conflict") && !rules.shellAnswers("other") && !rules.shellAnswers("none")
               && !rules.shellAnswers("blocked") && !rules.shellAnswers("deciding"), "the shell's prompt answers in active and conflict only");

        // --- the answer ---
        const ran = (code, more) => rules.runResult(Object.assign({ ok: code === 0, code: code, stdout: "out", stderr: "", cancelled: false,
                                                                   failedToStart: false, durationMs: 100, error: "" }, more ?? {}), 30000);
        assert(ran(0).ok && Object.isFrozen(ran(0)) && ran(0).stdout === "out" && ran(0).blocked === "", "exit 0: ok, frozen, the output");
        assert(ran(126).dismissed && !ran(126).ok, "126: dismissed");
        assert(ran(127).refused && !ran(127).dismissed, "127: refused");
        assert(ran(124, { durationMs: 30000 }).timedOut && ran(137, { durationMs: 31000 }).timedOut, "124 or 137 after the limit: timedOut");
        assert(!ran(124, { durationMs: 500 }).timedOut, "124 before the limit: the command's own status");
        assert(ran(-1, { durationMs: 33000 }).timedOut && !ran(-1, { durationMs: 33000 }).ok, "no status after the limit and the kill-after (timeout ended by its KILL): timedOut");
        assert(!ran(-1, { durationMs: 32999 }).timedOut, "… no status before the limit and the kill-after: a crash (the prompt's time counts too)");
        assert(!ran(-1, { durationMs: 500 }).timedOut, "… no status well before the limit: a crash, not the limit");
        assert(!ran(-1, { durationMs: 33000, failedToStart: true }).timedOut, "… pkexec never started: not timed out");
        assert(!ran(-1, { durationMs: 33000, cancelled: true }).timedOut, "… cancelled: not timed out");
        assert(ran(124, { durationMs: 30000 }).timedOut && !ran(124, { durationMs: 29999 }).timedOut, "124 from the limit on, without the kill-after");
        assertEqual(rules.stderrTailChars, 1048576, "an answer keeps the last 1 MB of stderr");
        assert(!ran(126, { cancelled: true, code: 126 }).dismissed && ran(-1, { cancelled: true }).cancelled, "cancelled: nothing else");
        assertEqual(ran(-1, { failedToStart: true }).error, "pkexec could not be started", "pkexec not started: said so");
        assert(!ran(0).notFound && !ran(1).notFound && !rules.cancelledResult().notFound && rules.notFoundResult("/usr/bin/x").notFound,
               "notFound only in the answer for a program not there");
        assert(!rules.runResult({ code: 124 }, 1).timedOut, "124 with no duration known: not timed out");
        assertEqual(rules.runResult({}, 30000).code, -1, "no status: code -1");
        assert(!ran(0, { ok: false }).ok && !ran(0, { cancelled: true }).ok, "ok only when the runner says ok, the status is 0 and it was not cancelled");
        assert(rules.cancelledResult().cancelled && !rules.cancelledResult().ok, "cancelledResult: cancelled");
        assertEqual(rules.failureNotice(ran(127), "Connect", 30000, true), null, "refused: no failure notice (the agent tells it)");
        assertEqual(rules.failureNotice(ran(126), "Connect", 30000, true), null, "dismissed: none");
        assertEqual(rules.failureNotice(ran(0), "Connect", 30000, true), null, "ok: none");
        assertEqual(rules.failureNotice(rules.lockedResult(), "Connect", 30000, true), null, "locked: none");
        assertEqual(rules.failureNotice(rules.cancelledResult(), "Connect", 30000, true), null, "cancelled: none");
        assertEqual(JSON.stringify(rules.failureNotice(ran(1, { stderr: "first\nError: no route\n" }), "Connect", 30000, true)),
                    JSON.stringify({ summary: "Connect failed", body: "Error: no route" }), "a failure: its last stderr line");
        assertEqual(rules.failureNotice(ran(3), "Connect", 30000, true).body, "Exit code 3", "… or its exit code");
        assertEqual(rules.failureNotice(ran(124, { durationMs: 30000 }), "Connect", 30000, true).body, "It did not end within 30 s", "timed out: said so");
        assert(rules.failureNotice(rules.notFoundResult("/usr/bin/x"), "Connect", 30000, true).body.includes("/usr/bin/x"), "not found: the program named");
        assertEqual(rules.failureNotice(rules.refusedResult({ blocked: "", error: "timeoutMs is needed" }), "Connect", 30000, false), null,
                    "refused before the queue, asked wrongly: no notification (the result says it)");
        assert(rules.failureNotice(rules.refusedResult({ blocked: "", notFound: true, error: "the program was not found" }), "Connect", 30000, false) !== null,
               "… but a program not found is told");

        // --- the queue ---
        const step = (state, event) => rules.queueStep(state, event);
        const kinds = stepped => stepped.effects.map(effect => effect.type + ":" + effect.id + (effect.kind ? ":" + effect.kind : "")).join(" ");
        const phases = state => state.jobs.map(job => job.id + "=" + job.phase).join(" ");
        let queue = rules.queueStart(false);
        let stepped = step(queue, { type: "add", id: 1, owner: "m1", now: 0 });
        assertEqual(kinds(stepped), "check:1", "queue: the first run is looked at at once");
        stepped = step(stepped.state, { type: "add", id: 2, owner: "m1", now: 0 });
        assertEqual(kinds(stepped) + " | " + phases(stepped.state), " | 1=checking 2=waiting", "… a second one waits");
        stepped = step(stepped.state, { type: "checked", id: 1, found: true, shellAgent: true, now: 100 });
        assertEqual(kinds(stepped) + " | " + rules.nextDeadline(stepped.state), "launch:1 | 2100", "found: pkexec started, the head held for 2 s");
        const asking = stepped.state;
        assertEqual(kinds(step(asking, { type: "tick", now: 2099 })), "", "before 2 s: still held");
        stepped = step(asking, { type: "tick", now: 2100 });
        assertEqual(kinds(stepped) + " | " + phases(stepped.state), "check:2 | 1=running 2=checking", "2 s with no request: released, the next looked at");
        assertEqual(rules.nextDeadline(stepped.state), 0, "… released: no deadline left");
        // Its own request seen
        stepped = step(asking, { type: "request", open: true, own: true, now: 500 });
        assertEqual(rules.nextDeadline(stepped.state), 0, "its own request opens: held while it is open, no deadline");
        const ownOpen = stepped.state;
        assertEqual(kinds(step(ownOpen, { type: "tick", now: 60000 })), "", "… a minute later still held");
        stepped = step(ownOpen, { type: "request", open: false, own: false, now: 61000 });
        assertEqual(kinds(stepped) + " | " + phases(stepped.state), "check:2 | 1=running 2=checking", "its request ended: released");
        assertEqual(rules.nextDeadline(stepped.state), 0, "… no deadline left");
        assertEqual(kinds(step(asking, { type: "request", open: false, own: false, now: 500 })) + " | "
                    + rules.nextDeadline(step(asking, { type: "request", open: false, own: false, now: 500 }).state), " | 2100",
                    "no request ending that was never seen opening: nothing, the 2 s unchanged");
        // Another program's request shown after its own: held until no request is open
        stepped = step(ownOpen, { type: "request", open: true, own: false, now: 3000 });
        assertEqual(kinds(stepped) + " | " + phases(stepped.state), " | 1=asking 2=waiting",
                    "its own replaced by another program's: not released");
        assertEqual(kinds(step(stepped.state, { type: "request", open: false, own: false, now: 9000 })) + " | "
                    + phases(step(stepped.state, { type: "request", open: false, own: false, now: 9000 }).state),
                    "check:2 | 1=running 2=checking", "… released when that one ends too");
        // … but not past 2 minutes from the launch: another program's prompt left open does
        // not stall every later run
        assertEqual(rules.nextDeadline(stepped.state), 100 + rules.headStrictMs, "another program's request after its own: at most 2 minutes from the launch");
        assertEqual(kinds(step(stepped.state, { type: "tick", now: 60000 })), "", "… a minute later still held");
        const foreignAfterOwn = step(stepped.state, { type: "tick", now: 100 + rules.headStrictMs });
        assertEqual(kinds(foreignAfterOwn) + " | " + phases(foreignAfterOwn.state), "check:2 | 1=running 2=checking",
                    "… released after 2 minutes, that request still open");
        stepped = step(step(ownOpen, { type: "request", open: true, own: false, now: 3000 }).state, { type: "request", open: true, own: true, now: 4000 });
        assertEqual(kinds(step(stepped.state, { type: "tick", now: 200000 })) + " | " + rules.nextDeadline(stepped.state), " | 0",
                    "its own open again after the other: held, no limit");
        // Another program's request in front, before its own was seen: its own may wait behind it
        stepped = step(asking, { type: "request", open: true, own: false, now: 500 });
        assertEqual(rules.nextDeadline(stepped.state), 100 + rules.headStrictMs, "another program's request open: the 2 s do not run, at most 2 minutes from the launch");
        const otherInFront = stepped.state;
        assertEqual(kinds(step(otherInFront, { type: "tick", now: 30000 })), "", "… 30 s later still held");
        assertEqual(kinds(step(otherInFront, { type: "tick", now: 100 + rules.headStrictMs })), "check:2", "… released after 2 minutes");
        stepped = step(otherInFront, { type: "request", open: false, own: false, now: 30000 });
        assertEqual(kinds(stepped) + " | " + rules.nextDeadline(stepped.state), " | 32000", "that one ended: the 2 s start again");
        assertEqual(kinds(step(stepped.state, { type: "tick", now: 32000 })), "check:2", "… and release the head when they pass");
        assertEqual(rules.nextDeadline(step(stepped.state, { type: "request", open: false, own: false, now: 31000 }).state), 32000,
                    "… a second end with none open after it does not start them again");
        stepped = step(step(otherInFront, { type: "request", open: true, own: true, now: 40000 }).state, { type: "tick", now: 200000 });
        assertEqual(kinds(stepped), "", "its own after it: held while it is open, no limit");
        assertEqual(rules.nextDeadline(step(otherInFront, { type: "request", open: false, own: false, now: 119000 }).state), 100 + rules.headStrictMs,
                    "… the 2 s after another's end never pass the 2 minutes");
        // The run ends while it holds the head
        stepped = step(asking, { type: "exited", id: 1, now: 300 });
        assertEqual(kinds(stepped) + " | " + phases(stepped.state), "answer:1:result check:2 | 2=checking", "exited: answered, the next looked at");
        // Another agent: strict
        const strict = step(step(step(rules.queueStart(false), { type: "add", id: 1, owner: "m", now: 0 }).state,
                                 { type: "add", id: 2, owner: "m", now: 0 }).state,
                            { type: "checked", id: 1, found: true, shellAgent: false, now: 0 }).state;
        assertEqual(rules.nextDeadline(strict), rules.headStrictMs, "another agent: held up to 2 minutes");
        assertEqual(kinds(step(strict, { type: "request", open: true, own: true, now: 10 })) + kinds(step(strict, { type: "tick", now: 2000 })), "",
                    "… requests are not looked at, 2 s mean nothing");
        assertEqual(kinds(step(strict, { type: "tick", now: rules.headStrictMs })), "check:2", "… released after 2 minutes");
        assertEqual(kinds(step(strict, { type: "exited", id: 1, now: 5000 })), "answer:1:result check:2", "… or when it ends");
        // Not found
        const checking = step(rules.queueStart(false), { type: "add", id: 1, owner: "m", now: 0 }).state;
        assertEqual(kinds(step(step(checking, { type: "add", id: 2, owner: "m", now: 0 }).state, { type: "checked", id: 1, found: false, now: 1 })),
                    "answer:1:notFound check:2", "its program not there: notFound, pkexec never started, the next looked at");
        // Cancels
        assertEqual(kinds(step(asking, { type: "cancel", id: 2, now: 200 })), "answer:2:cancelled", "cancel while waiting: answered at once, nothing signalled");
        assertEqual(kinds(step(checking, { type: "cancel", id: 1, now: 1 })), "answer:1:cancelled", "cancel while its program is looked at: the same");
        stepped = step(asking, { type: "cancel", id: 1, killAfterMs: 3000, now: 1000 });
        assertEqual(kinds(stepped) + " | " + phases(stepped.state), "signal:1 | 1=ending 2=waiting",
                    "cancel after start: signalled, not answered yet, the next still waits");
        const cancelled = stepped.state;
        assertEqual(kinds(step(cancelled, { type: "tick", now: 2100 })), "", "… the 2 s mean nothing now: it holds the head until it is gone");
        assertEqual(kinds(step(cancelled, { type: "exited", id: 1, now: 1500 })), "answer:1:cancelled check:2", "… its exit: answered cancelled, the next starts");
        stepped = step(cancelled, { type: "tick", now: 4000 });
        assertEqual(kinds(stepped), "answer:1:cancelled check:2", "… or killAfterMs later without an exit (run as root, it cannot be signalled)");
        assertEqual(kinds(step(stepped.state, { type: "exited", id: 1, now: 9000 })), "", "… its late exit is not answered again");
        assertEqual(kinds(step(cancelled, { type: "cancel", id: 1, now: 1100 })), "", "cancel twice: once");
        assertEqual(rules.nextDeadline(step(cancelled, { type: "request", open: true, own: true, now: 1200 }).state), 4000,
                    "… a request after the cancel does not hold the ending run past killAfterMs");
        assertEqual(kinds(step(cancelled, { type: "ownerGone", owner: "m1", killAfterMs: 3000, now: 1300 })), "forget:2",
                    "… its owner gone then: not signalled again (its waiting run forgotten)");
        assertEqual(kinds(step(step(cancelled, { type: "ownerGone", owner: "m1", now: 1300 }).state, { type: "exited", id: 1, now: 1400 })),
                    "forget:1", "… and it ends with no answer");
        for (const [killAfterMs, deadline] of [[500, 1500], [0, 1000], [-5, 4000], [undefined, 4000]])
            assertEqual(rules.nextDeadline(step(asking, { type: "cancel", id: 1, killAfterMs: killAfterMs, now: 1000 }).state), deadline,
                        "cancel with killAfterMs " + killAfterMs + ": ending until " + deadline + " (not a number, or negative: the default)");
        const atOnce = step(asking, { type: "cancel", id: 1, killAfterMs: 0, now: 1 });
        assertEqual(kinds(step(atOnce.state, { type: "tick", now: 1 })), "answer:1:cancelled check:2", "killAfterMs 0: a tick at once ends it");
        const lone = step(step(step(step(rules.queueStart(false), { type: "add", id: 1, owner: "m", now: 0 }).state,
                                    { type: "checked", id: 1, found: true, shellAgent: true, now: 0 }).state, { type: "tick", now: 2000 }).state,
                          { type: "cancel", id: 1, killAfterMs: 3000, now: 2100 }).state;
        assertEqual(kinds(step(lone, { type: "add", id: 2, owner: "m", now: 2200 })), "check:2", "a run ending that had let the head go holds nothing: the next starts");
        const released = step(asking, { type: "tick", now: 2100 }).state;
        stepped = step(released, { type: "cancel", id: 1, killAfterMs: 3000, now: 2200 });
        assertEqual(kinds(stepped) + " | " + phases(stepped.state), "signal:1 | 1=ending 2=checking", "cancel of a run that let the head go: the next goes on");
        // A module turned off
        let off = step(rules.queueStart(false), { type: "add", id: 1, owner: "m1", now: 0 }).state;
        off = step(off, { type: "add", id: 2, owner: "m1", now: 0 }).state;
        off = step(off, { type: "add", id: 3, owner: "m2", now: 0 }).state;
        off = step(off, { type: "checked", id: 1, found: true, shellAgent: true, now: 0 }).state;
        stepped = step(off, { type: "ownerGone", owner: "m1", killAfterMs: 3000, now: 100 });
        assertEqual(kinds(stepped) + " | " + phases(stepped.state), "signal:1 forget:2 | 1=ending 3=waiting",
                    "module off: its waiting run forgotten, its started one cancelled; another module's waits for the cancelled one");
        assertEqual(kinds(step(stepped.state, { type: "exited", id: 1, now: 500 })), "forget:1 check:3", "… the cancelled one ends with no answer, the next starts");
        assertEqual(kinds(step(stepped.state, { type: "tick", now: 3100 })), "forget:1 check:3", "… or killAfterMs later");
        assertEqual(kinds(step(off, { type: "ownerGone", owner: "", now: 0 })), "", "an empty owner touches nothing");
        const unowned = step(step(rules.queueStart(false), { type: "add", id: 1, now: 0 }).state, { type: "add", id: 2, now: 0 }).state;
        assertEqual(kinds(step(unowned, { type: "ownerGone", owner: "", now: 0 })), "", "… not even runs added with no owner");
        // The lock
        let lockQueue = step(rules.queueStart(false), { type: "add", id: 1, owner: "m", now: 0 }).state;
        lockQueue = step(lockQueue, { type: "checked", id: 1, found: true, shellAgent: true, now: 0 }).state;
        lockQueue = step(lockQueue, { type: "tick", now: 2000 }).state;
        lockQueue = step(lockQueue, { type: "add", id: 2, owner: "m", now: 2000 }).state;
        lockQueue = step(lockQueue, { type: "add", id: 3, owner: "n", now: 2000 }).state;
        assertEqual(phases(lockQueue), "1=running 2=checking 3=waiting", "lock: a run going, one looked at, one waiting");
        stepped = step(lockQueue, { type: "lock", locked: true, now: 2100 });
        assertEqual(kinds(stepped) + " | " + phases(stepped.state), "answer:2:locked answer:3:locked | 1=running",
                    "locked: the waiting runs answered locked; the started one goes on");
        assertEqual(kinds(step(stepped.state, { type: "add", id: 4, owner: "m", now: 2200 })), "answer:4:locked", "… a run asked for while locked: answered locked");
        const askingLocked = step(asking, { type: "lock", locked: true, now: 200 });
        assertEqual(kinds(askingLocked) + " | " + phases(askingLocked.state), "answer:2:locked | 1=asking", "… a run already asking is left to its prompt");
        assertEqual(kinds(step(askingLocked.state, { type: "tick", now: 2100 })), "", "… and nothing starts while locked");
        const unlocked = step(step(askingLocked.state, { type: "add", id: 5, owner: "m", now: 300 }).state, { type: "lock", locked: false, now: 400 });
        assertEqual(kinds(unlocked), "", "unlocked: nothing was kept to start");
        assertEqual(kinds(step(rules.queueStart(true), { type: "add", id: 1, owner: "m", now: 0 })), "answer:1:locked", "a queue started locked: runs answered locked");
        assertEqual(rules.nextDeadline(step(step(rules.queueStart(false), { type: "add", id: 1, owner: "m" }).state, { type: "checked", id: 1, found: true, shellAgent: true }).state),
                    rules.headQuietMs, "an event with no time counts as 0");
        // Odd events
        assertEqual(kinds(step(asking, { type: "exited", id: 99, now: 0 })) + kinds(step(asking, { type: "checked", id: 2, found: true, now: 0 }))
                    + kinds(step(asking, { type: "add", id: 1, now: 0 })) + kinds(step(asking, { type: "nonsense", now: 0 })), "",
                    "an unknown run, a run not being looked at, an id queued twice, an unknown event: nothing");
    }
}
