import QtQuick
import qs.singletons

TestCase {
    suiteName: "PolkitRules"

    function run() {
        const rules = PolkitRules;

        // --- who asks and what for: the announcement ---
        assertEqual(rules.cleanValue("  Send\n a\tfile  "), "Send a file", "white space folded to one line, trimmed");
        assertEqual(rules.cleanValue("Re‮port​\u0007"), "Report", "control and format characters dropped (U+202E, U+200B, BEL)");
        assertEqual(rules.cleanValue("Line two"), "Line two", "a line separator is white space: folded");
        assertEqual(rules.cleanValue(42), "", "not a string: empty");
        const forty = "a".repeat(40);
        assertEqual(rules.cleanValue(forty), forty, "40 characters: kept whole");
        const cut = rules.cleanValue("b".repeat(41));
        assertEqual(cut, "b".repeat(39) + "…", "41: cut with … at 40");
        assertEqual(Array.from(rules.cleanValue("😀".repeat(50))).length, 40, "characters, not UTF-16 units, are counted");
        assertEqual(rules.moduleLabel("Tailscale", "tailscale"), "Tailscale", "a name that reads as the id: alone");
        assertEqual(rules.moduleLabel("Net Tools 2", "nettools2"), "Net Tools 2", "… letters and digits compared, lower-cased");
        assertEqual(rules.moduleLabel("System update", "xmod"), "System update (xmod)", "a name that does not: the id in brackets");
        assertEqual(rules.moduleLabel("x".repeat(60), "xmod"), "x".repeat(39) + "… (xmod)", "the name is cut, never the id");
        assertEqual(rules.moduleLabel(" ‮", "xmod"), "xmod", "no name left after cleaning: the id");
        const shown = rules.announcement({ moduleName: "Tailscale", moduleId: "tailscale", what: "Send a file",
                                           pkexecArgv: ["/usr/bin/timeout", "-k", "3", "30", "/usr/bin/tailscale", "file", "cp", "--", "my report.pdf", "laptop:", "it's", ""] });
        assertEqual(shown.module + " | " + shown.authorization, "Tailscale | Send a file", "Module and Authorization");
        assertEqual(shown.command, "/usr/bin/timeout -k 3 30 /usr/bin/tailscale file cp -- 'my report.pdf' laptop: 'it'\\''s' ''",
                    "the command: every word, shell-quoted, the timeout in front included");
        assertEqual(shown.summary + " | " + shown.body, "Module: Tailscale | Authorization: Send a file", "the notification's texts");
        assert(Object.isFrozen(shown), "frozen");
        const longWords = ["/usr/bin/timeout", "-k", "3", "30", "/usr/bin/sh", "-c", "x".repeat(500)];
        assertEqual(rules.announcement({ moduleName: "M", moduleId: "m", what: "W", pkexecArgv: longWords }).command,
                    longWords.join(" "), "a long command whole: nothing cut");
        // A hostile name and what: one line each, plain, the id still there
        const hostile = rules.announcement({ moduleName: "Shell\nAuthorization   Update the system", moduleId: "evil",
                                             what: "<b>Update</b>‮elif\nModule  System", pkexecArgv: ["/bin/true"] });
        assertEqual(hostile.module, "Shell Authorization Update the system (evil)", "a newline in the name cannot fake a second line; the id shows");
        assertEqual(hostile.authorization, "<b>Update</b>elif Module System", "markup kept as written (shown as plain text), U+202E dropped, folded");
        assert(hostile.module.indexOf("\n") < 0 && hostile.authorization.indexOf("\n") < 0 && hostile.body.indexOf("\n") < 0, "no line break anywhere");
        // The old PrivilegedAction: no module named, no Authorization line
        const legacy = rules.announcement({ legacy: true, moduleId: "tailscale", what: "Connect", pkexecArgv: ["/usr/bin/tailscale", "up"] });
        assertEqual(legacy.module + " | " + legacy.authorization + " | " + legacy.command, "Not named |  | /usr/bin/tailscale up", "legacy: Not named, no Authorization");
        assertEqual(legacy.summary + " | " + legacy.body, "Module: Not named | ", "… and its notification");
        // An unprintable word (only an old run can hand one): escaped, still one line
        assertEqual(rules.shellQuote("a\nb‮'c"), "$'a\\nb\\u202e\\'c'", "a control or format character: $'…' with escapes");
        assertEqual(rules.shellQuote("plain-1.0/x:y"), "plain-1.0/x:y", "a plain word: bare");
        assertEqual(rules.shellQuote("a b"), "'a b'", "a space: single quotes");

        // --- pkexec's message (polkit 0.120+, pkexec.c): `$(cmdline_short)' ---
        const words = ["/usr/bin/timeout", "-k", "3", "30", "/usr/bin/tailscale", "up"];
        assertEqual(rules.pkexecMessage(words), "Authentication is needed to run `/usr/bin/timeout -k 3 30 /usr/bin/tailscale up' as the super user",
                    "a short command line: whole");
        const nixWords = ["/run/current-system/sw/bin/timeout", "-k", "3", "30", "/run/current-system/sw/bin/tailscale", "file", "cp", "--", "report.pdf", "laptop:"];
        const nixLine = nixWords.join(" ");
        assertEqual(rules.pkexecShortCommand(nixWords).text, nixLine.slice(0, 38) + " ... " + nixLine.slice(nixLine.length - 37),
                    "past 80 bytes: the first 38, \" ... \", the last 37");
        const storeTimeout = "/nix/store/0123456789abcdfghijklmnpqrsvwxyz-coreutils-9.5/bin/timeout";
        assertEqual(rules.pkexecShortCommand([storeTimeout, "-k", "3", "30", "/bin/true"]).head, storeTimeout.slice(0, 38),
                    "a program path longer than 38 bytes is itself cut");
        const run = { pkexecArgv: words, programReal: "", announced: false };
        const flowFor = message => ({ actionId: "org.freedesktop.policykit.exec", message: message });
        // The messages as polkit's own translations put them (pkexec.c, po/de.po, po/pl.po of polkit 126–128)
        const english = "Authentication is needed to run `/usr/bin/timeout -k 3 30 /usr/bin/tailscale up' as the super user";
        const german = "Legitimierung ist erforderlich, um »/usr/bin/timeout -k 3 30 /usr/bin/tailscale up« als Superuser auszuführen";
        const polish = "Wymagane jest uwierzytelnienie, aby uruchomić program „/usr/bin/timeout -k 3 30 /usr/bin/tailscale up” jako superużytkownik";
        assert(rules.announces(flowFor(english), run), "matched: pkexec's action, the message names the run's command");
        assert(rules.announces(flowFor(german), run) && rules.announces(flowFor(polish), run), "… in other languages too: the command is filled in, never translated");
        assert(rules.announces(flowFor(rules.pkexecMessage(nixWords)), { pkexecArgv: nixWords, programReal: "", announced: false }),
               "a shortened command line matches");
        const storeWords = [storeTimeout, "-k", "3", "30", "/run/current-system/sw/bin/tailscale", "file", "cp", "--", "report.pdf", "laptop:"];
        assert(rules.announces(flowFor(rules.pkexecMessage(storeWords)), { pkexecArgv: storeWords, programReal: "", announced: false }),
               "… also when the program's own path is cut");
        const shortUnicode = ["/usr/bin/timeout", "-k", "3", "30", "/usr/bin/tailscale", "file", "cp", "--", "żółć-ąęś-raport-ünïcödé.pdf", "laptops:"];
        assertEqual(rules.pkexecShortCommand(shortUnicode).text, "", "(this command's 37-byte end does cut a character)");
        assert(rules.announces(flowFor(rules.pkexecMessage(shortUnicode)), { pkexecArgv: shortUnicode, programReal: "", announced: false }),
               "… and when the 37-byte end cuts a character in two");
        // By the path given or its real path (a polkit before 0.120 names only $(program), resolved)
        const linked = { pkexecArgv: ["/run/current-system/sw/bin/timeout", "-k", "3", "30", "/bin/true"],
                         programReal: "/nix/store/abc-coreutils-9.5/bin/timeout", announced: false };
        assert(rules.announces(flowFor("Authentication is needed to run `/nix/store/abc-coreutils-9.5/bin/timeout' as the super user"), linked),
               "the program by its real path");
        assert(rules.announces(flowFor("Authentication is needed to run `/run/current-system/sw/bin/timeout' as the super user"), linked),
               "the program by the path given");
        assert(!rules.announces(flowFor("Authentication is needed to run `/run/current-system/sw/bin/timeoutx' as the super user"), linked),
               "a longer path that starts with it is another program");
        // Not the run's
        assert(!rules.announces({ actionId: "org.freedesktop.systemd1.manage-units", message: english }, run), "another action: not announced");
        assert(!rules.announces(flowFor("Authentication is needed to run `/usr/bin/true' as the super user"), run),
               "a foreign pkexec request (another program): not announced");
        assert(!rules.announces(flowFor(english), Object.assign({}, run, { announced: true })),
               "a run is announced once: a request after its first is shown as polkit sent it");
        assert(!rules.announces(null, run) && !rules.announces(flowFor(english), null), "no request, or no run: no");
        assert(!rules.announces(flowFor(english), { pkexecArgv: [], programReal: "", announced: false }), "a run with no words: no");

        // --- the lock closes the prompt ---
        assert(rules.closesForLock(true, true), "locked with a request open: closed");
        assert(!rules.closesForLock(true, false) && !rules.closesForLock(false, true), "otherwise left");

        // --- finding agents in a process list ---
        assertEqual(JSON.stringify(rules.agentsIn(["/usr/lib/hyprpolkitagent/hyprpolkitagent", "kitty", "bash -l"])),
                    "[\"hyprpolkitagent\"]", "by the program's name, path dropped");
        assertEqual(JSON.stringify(rules.agentsIn(["/nix/store/x-polkit-gnome/libexec/polkit-gnome-authentication-agent-1 --flag"])),
                    "[\"polkit-gnome-authentication-agent-1\"]", "arguments ignored");
        assertEqual(rules.agentsIn(["vim hyprpolkitagent.conf", "grep hyprpolkitagent"]).length, 0,
                    "a name in the arguments is not the agent");
        assertEqual(rules.agentsIn(["/usr/lib/polkit-1/polkit-agent-helper-1"]).length, 0,
                    "polkit's helper (run by any agent, the shell's too) is no agent");
        assertEqual(rules.agentsIn(["soteria", "soteria"]).length, 1, "each once");
        assertEqual(rules.agentsIn([]).length, 0, "none");

        // --- the first start ---
        assertEqual(rules.firstStart(["hyprpolkitagent"], null), "off", "another agent running: stays off");
        assertEqual(rules.firstStart([], null), "try", "none running: tried");
        assertEqual(rules.firstStart([], true), "on", "tried and registered: on");
        assertEqual(rules.firstStart([], false), "off", "tried, not registered (an unknown agent holds it): off");

        // --- what is told ---
        assertEqual(rules.state("", false, []), "deciding", "undecided");
        assertEqual(rules.state("on", true, []), "active", "the shell's prompts");
        assertEqual(rules.state("on", false, []), "blocked", "on but not registered");
        assertEqual(rules.state("on", true, ["hyprpolkitagent"]), "conflict", "another one running beside the shell's");
        assertEqual(rules.state("off", false, ["hyprpolkitagent"]), "other", "another agent answers");
        assertEqual(rules.state("off", false, []), "none", "no agent at all");
        assertEqual(rules.state("off", false, [], true), "other", "an agent the shell does not know: refused its registration");

        // --- a refused request of the shell's own ---
        assertEqual(JSON.stringify(rules.deniedNotice("active", "Connect")),
                    JSON.stringify({ summary: "Connect — not allowed", body: "The password was not given or not accepted.", noAgent: false }),
                    "refused with an agent: not allowed");
        assert(rules.deniedNotice("none", "Connect").noAgent && rules.deniedNotice("none", "Connect").summary === "Connect — no authentication prompt answered",
               "refused with no agent at all: said so, the shell's prompt offered");

        // --- the polkit-1 stack ---
        const fingerprintFirst = "# Account management.\n"
            + "account required /nix/store/x-linux-pam/lib/security/pam_unix.so # unix (order 11000)\n"
            + "auth sufficient /nix/store/y-fprintd/lib/security/pam_fprintd.so # fprintd (order 11400)\n"
            + "auth sufficient /nix/store/x-linux-pam/lib/security/pam_unix.so likeauth try_first_pass # unix (order 11700)\n"
            + "auth required /nix/store/x-linux-pam/lib/security/pam_deny.so # deny (order 12500)\n"
            + "password sufficient /nix/store/x-linux-pam/lib/security/pam_unix.so nullok yescrypt\n";
        assertEqual(rules.pamStackOrder(fingerprintFirst), "fingerprint-first", "NixOS with fprintd: the reader first (account/password lines ignored)");
        const passwordFirst = "auth sufficient /nix/store/x-linux-pam/lib/security/pam_unix.so likeauth try_first_pass # unix (order 11700)\n"
            + "auth sufficient /nix/store/y-fprintd/lib/security/pam_fprintd.so # fprintd (order 11710)\n"
            + "auth required /nix/store/x-linux-pam/lib/security/pam_deny.so\n";
        assertEqual(rules.pamStackOrder(passwordFirst), "password-first", "pam_unix before pam_fprintd");
        assertEqual(rules.pamStackOrder("auth sufficient pam_unix.so\nauth required pam_deny.so\n"), "password", "no reader");
        assertEqual(rules.pamStackOrder("auth [success=done default=ignore] pam_fprintd.so\nauth sufficient pam_unix.so\n"),
                    "fingerprint-first", "a bracketed control");
        assertEqual(rules.pamStackOrder("#%PAM-1.0\nauth include system-auth\naccount include system-auth\n"), "", "an include (Arch): not known");
        assertEqual(rules.pamStackOrder(""), "", "no file: not known");
        assertEqual(rules.pamStackOrder("# auth sufficient pam_fprintd.so\nauth sufficient pam_unix.so\n"), "password", "a commented-out line ignored");

        // --- the prompt's conversation ---
        function replay(stack, events) {
            let conversation = rules.conversationStart();
            for (const event of events)
                conversation = rules.conversationStep(conversation, event);
            return conversation;
        }
        const message = { kind: "message" };
        const ask = { kind: "request", echo: false };

        assertEqual(rules.conversationPhase(rules.conversationStart()), "starting", "nothing arrived yet");

        // Fingerprint first: "Place your finger…" (info), nothing to answer for up to 30 s
        let conversation = replay("fingerprint-first", [message]);
        assertEqual(rules.conversationPhase(conversation), "waiting", "fingerprint first: the reader's message, no question");
        assert(rules.conversationHint(conversation, "fingerprint-first", false).text.indexOf("type the password now") >= 0,
               "fingerprint first, waiting: says the password can be typed, and when it is sent");
        assert(rules.conversationHint(conversation, "fingerprint-first", true).text.indexOf("sent as soon as it is asked") >= 0,
               "fingerprint first, a password held: says it waits to be sent");
        assert(!rules.sendHeldNow(conversation, true), "fingerprint first: a held password is not sent before it is asked for");
        assert(!rules.emptyAnswerAllowed(conversation, "fingerprint-first"), "no answer while nothing is asked");
        // [30 s] "Verification timed out" (info), then "Password: " (echo off)
        conversation = replay("fingerprint-first", [message, message, ask]);
        assertEqual(rules.conversationPhase(conversation), "asked", "after the timeout: the password asked");
        assert(rules.sendHeldNow(conversation, true), "the held password goes the moment it is asked for");
        assert(!rules.sendHeldNow(conversation, false), "nothing held, nothing sent");
        assert(!rules.emptyAnswerAllowed(conversation, "fingerprint-first"), "fingerprint first: an empty password is not sent (one more failure)");
        assertEqual(rules.conversationHint(conversation, "fingerprint-first", false).text, "", "asked: no hint needed");
        // Wrong finger ×3: "Failed to match fingerprint" (errors) between the reader's messages
        conversation = replay("fingerprint-first", [message, message, message, message, message, message, ask]);
        assertEqual(rules.conversationPhase(conversation), "asked", "three wrong fingers, then the password");
        // A wrong password: the attempt fails and a new one starts — the reader first again
        conversation = replay("fingerprint-first", [message, ask, { kind: "answered", empty: false }]);
        assertEqual(rules.conversationPhase(conversation), "checking", "answered, nothing since: checking");
        conversation = rules.conversationStep(conversation, { kind: "failed" });
        assertEqual(conversation.failures, 1, "a failure counted");
        assertEqual(rules.conversationPhase(conversation), "starting", "the new attempt starts afresh");
        conversation = rules.conversationStep(conversation, message);
        assertEqual(rules.conversationPhase(conversation), "waiting", "the retry: the reader's message again");
        assert(!rules.conversationHint(conversation, "fingerprint-first", false).error, "fingerprint first: the reader's turn is no error in itself");

        // Password first: "Password: " at once
        conversation = replay("password-first", [ask]);
        assertEqual(rules.conversationPhase(conversation), "asked", "password first: asked at once");
        assert(rules.emptyAnswerAllowed(conversation, "password-first"), "password first: an empty answer goes on to the reader");
        assert(rules.conversationHint(conversation, "password-first", false).text.indexOf("leave it empty") >= 0,
               "password first: says that Enter on an empty field uses the reader");
        assert(!rules.emptyAnswerAllowed(replay("password-first", [{ kind: "request", echo: true }]), "password-first"),
               "a shown question is not the password: no empty answer offered");
        // (empty) → "Place your finger…" → success (the prompt closes) or failure
        conversation = replay("password-first", [ask, { kind: "answered", empty: true }, message]);
        assertEqual(rules.conversationPhase(conversation), "waiting", "password first, empty: the reader's turn");
        let hint = rules.conversationHint(conversation, "password-first", false);
        assert(!hint.error && hint.text.indexOf("asked again") >= 0, "password first, empty: the password comes back if the reader gives up");
        // A wrong password: pam_unix fails and the stack goes on to the reader
        conversation = replay("password-first", [ask, { kind: "answered", empty: false }, message]);
        hint = rules.conversationHint(conversation, "password-first", false);
        assert(hint.error && hint.text.indexOf("not accepted") >= 0, "password first, a message after a typed password: it was not accepted");
        conversation = replay("password-first", [ask, { kind: "answered", empty: false }, message, { kind: "failed" }, ask]);
        assertEqual(rules.conversationPhase(conversation), "asked", "after the reader gave up: asked again");
        assertEqual(conversation.answered, "", "the new attempt forgets the old answer");
        // The helper's own error (e.g. a PAM_ERROR_MSG before the end) is a message like any other
        conversation = replay("password-first", [ask, { kind: "answered", empty: false }]);
        assertEqual(rules.conversationPhase(conversation), "checking", "a typed password, nothing since: checking");
        assertEqual(rules.conversationHint(conversation, "password-first", false).text, "", "checking: no hint");

        // Not known (e.g. an include): generic words, a held password still waits for its question
        conversation = replay("", [message]);
        assert(rules.conversationHint(conversation, "", false).text.indexOf("as soon as it is asked") >= 0, "unknown stack: generic hint");
        assert(!rules.sendHeldNow(replay("", [message, { kind: "request", echo: true }]), true),
               "a held password never goes into a shown question");
        // Another account picked: a new attempt, no failure
        conversation = rules.conversationStep(replay("", [message, ask]), { kind: "restarted" });
        assertEqual(conversation.failures, 0, "a restart is no failure");
        assertEqual(rules.conversationPhase(conversation), "starting", "a restart starts afresh");
    }
}
