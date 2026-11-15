import QtQuick
import qs.singletons

TestCase {
    suiteName: "PolkitRules"

    function run() {
        const rules = PolkitRules;

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
