import QtQuick
import qs.singletons

// PamTrialRules: which files a trial stages (the candidate verbatim, each name its auth
// lines include as libpam would find it once installed, absolute includes left where they
// are; a stack that cannot be followed is not tried), the staging script's reply, when two
// candidates are one trial, and the trial's lifetime: every event, late answers, cancels in
// each phase, the answer passed on and never kept
TestCase {
    suiteName: "PamTrialRules"

    function run() {
        const trial = PamTrialRules;
        const dirs = ["/etc/pam.d", "/usr/lib/pam.d"];
        const sudo = "#%PAM-1.0\n# BEGIN h2s-shell x\n-auth sufficient pam_fprintd.so\n# END h2s-shell\n"
            + "auth include system-auth\naccount include system-account\nsession include system-auth\n";
        const systemAuth = "auth required pam_faillock.so preauth\nauth [success=1 default=bad] pam_unix.so try_first_pass\n"
            + "auth [default=die] pam_faillock.so authfail\nauth optional pam_permit.so\n";
        const text = value => ({ text: value });
        const absent = { absent: true };
        const names = step => (step.files ?? []).map(file => file.name).join(" ");

        // ── stagingStep ──
        let step = trial.stagingStep("sudo", sudo, {}, dirs, false);
        assertEqual(step.pending.join(" "), "/etc/pam.d/system-auth", "first: the included name, in the first directory");
        assertEqual(step.files, null, "… nothing to stage yet");
        step = trial.stagingStep("sudo", sudo, { "/etc/pam.d/system-auth": absent }, dirs, false);
        assertEqual(step.pending.join(" "), "/usr/lib/pam.d/system-auth", "not there: the vendor directory next");
        step = trial.stagingStep("sudo", sudo, { "/etc/pam.d/system-auth": absent, "/usr/lib/pam.d/system-auth": text(systemAuth) }, dirs, false);
        assertEqual(step.refusal, null, "complete: not refused");
        assertEqual(names(step), "sudo system-auth", "the service first, then the included name (account's include not followed)");
        assertEqual(step.files[0].text, sudo, "the candidate verbatim");
        assertEqual(step.files[1].text, systemAuth, "… the vendor system-auth under its name");
        assertEqual(step.stack.lines.map(line => line.moduleName).join(" "), "pam_fprintd.so pam_faillock.so pam_unix.so pam_faillock.so pam_permit.so",
                    "the stack as the candidate would run it");
        step = trial.stagingStep("sudo", sudo, { "/etc/pam.d/system-auth": text("auth required pam_unix.so\n"), "/usr/lib/pam.d/system-auth": text(systemAuth) }, dirs, false);
        assertEqual(step.files[1].text, "auth required pam_unix.so\n", "/etc/pam.d shadows the vendor file");
        // The candidate is read in place of the file in the first directory, never asked for
        step = trial.stagingStep("sudo", sudo, {}, dirs, false);
        assert(!step.pending.includes("/etc/pam.d/sudo"), "the service's own file is not read: the candidate stands for it");

        // Nested, @include, substack and absolute includes
        const nested = "auth substack system-login\nauth include /etc/pam.d/absolute\n@include common-auth\n";
        step = trial.stagingStep("polkit-1", nested, {
            "/etc/pam.d/system-login": text("auth include system-auth\n"),
            "/etc/pam.d/system-auth": text(systemAuth),
            "/etc/pam.d/absolute": text("auth include from-absolute\n"),
            "/etc/pam.d/from-absolute": text("auth required pam_permit.so\n"),
            "/etc/pam.d/common-auth": text("auth required pam_unix.so\n")
        }, dirs, false);
        assertEqual(names(step), "polkit-1 system-login common-auth system-auth from-absolute",
                    "substack, @include and includes inside included files staged by name; an absolute include read in place, the names it includes staged");

        // Not tried
        const code = result => result.refusal?.code ?? "";
        assertEqual(code(trial.stagingStep("sudo", sudo, { "/etc/pam.d/system-auth": { unreadable: true } }, dirs, false)), "unread",
                    "an included file that cannot be read: not tried");
        assertEqual(code(trial.stagingStep("sudo", sudo, { "/etc/pam.d/system-auth": absent, "/usr/lib/pam.d/system-auth": absent }, dirs, false)), "unread",
                    "an included file that is nowhere: not tried");
        assertEqual(code(trial.stagingStep("sudo", sudo, {}, dirs, true)), "unread", "the rounds ran out: what is not read is unreadable");
        assertEqual(code(trial.stagingStep("sudo", "auth bogus pam_unix.so\n", {}, dirs, false)), "unparsable", "a line PAM cannot read");
        assertEqual(code(trial.stagingStep("sudo", "auth include sudo\n", {}, dirs, false)), "unread", "a candidate that includes itself: a cycle, not tried");
        assertEqual(code(trial.stagingStep("../sudo", sudo, {}, dirs, false)), "service", "a service that is no name");
        assertEqual(code(trial.stagingStep(".sudo", sudo, {}, dirs, false)), "service", "… nor a dot-file");
        assertEqual(code(trial.stagingStep("sudo", null, {}, dirs, false)), "unread", "no candidate text");
        assertEqual(code(trial.stagingStep("sudo", sudo, {}, [], false)), "unread", "no directories");
        assertEqual(code(trial.stagingStep("sudo", "#" + "é".repeat(32768) + "\n", {}, dirs, false)), "tooLarge", "over 64 KiB as UTF-8");
        assertEqual(code(trial.stagingStep("sudo", "#" + "e".repeat(65534) + "\n", {}, dirs, false)), "", "… 64 KiB is taken");
        assertEqual(["\u007f", "\u0080", "\u07ff", "\u0800", "\uffff", "\u{10000}"].map(character => trial.byteLength(character)).join(" "), "1 2 2 3 3 4",
                    "a file's length counted in UTF-8 bytes, at each boundary");
        assertEqual(trial.validName("a".repeat(255)) + " " + trial.validName("a".repeat(256)), "true false", "a name of at most 255 characters");
        step = trial.stagingStep("sudo", "auth include x\nauth include x\n", {}, dirs, false);
        assertEqual(step.pending.join(" "), "/etc/pam.d/x", "a name included twice: read once");
        step = trial.stagingStep("sudo", "auth include x\nauth include x\n", { "/etc/pam.d/x": text("auth required pam_permit.so\n") }, dirs, false);
        assertEqual(names(step), "sudo x", "… staged once");
        assertEqual(trial.validName("system-auth") && trial.validName("polkit-1") && !trial.validName("a/b") && !trial.validName("")
                    && !trial.validName("-x"), true, "names: what libpam takes, nothing a shell could misread");

        // ── stageReply ──
        const ok = { ok: true, truncated: false };
        const parent = "/run/user/1000";
        assertEqual(trial.stageReply(["staged\t/run/user/1000/h2s-pam-trial.AbC12345"], ok, parent), "/run/user/1000/h2s-pam-trial.AbC12345", "the directory made");
        assertEqual(trial.stageReply(["staged\t/run/user/1000/h2s-pam-trial.AbC12345"], ok, parent + "/"), "/run/user/1000/h2s-pam-trial.AbC12345", "… a parent with a slash");
        assertEqual(trial.stageReply(["staged\t/run/user/1000/h2s-pam-trial.AbC12345"], { ok: false }, parent), "", "the script failed");
        assertEqual(trial.stageReply(["staged\t/tmp/h2s-pam-trial.AbC12345"], ok, parent), "", "a directory elsewhere");
        assertEqual(trial.stageReply(["staged\t/run/user/1000/x/h2s-pam-trial.AbC12345"], ok, parent), "", "not directly in the parent");
        assertEqual(trial.stageReply(["staged\t/run/user/1000/h2s-pam-trialXAbC12345"], ok, parent), "", "the prefix's dot is a dot");
        assertEqual(trial.stageReply(["staged\t/run/user/1000/h2s-pam-trial.AbC1234"], ok, parent), "", "eight characters");
        assertEqual(trial.stageReply(["staged\t/run/user/1000/h2s-pam-trial.AbC12345", "staged\t/run/user/1000/h2s-pam-trial.AbC12346"], ok, parent), "", "two directories");
        assertEqual(trial.stageReply(["staged\t/run/user/1000/h2s-pam-trial.AbC12345"], { ok: true, truncated: true }, parent), "", "a cut reply");
        assertEqual(trial.stageReply(["staged\th2s-pam-trial.AbC12345"], ok, "relative"), "", "a relative parent");
        assertEqual(trial.stageReply(["staged\t/run/user/1000/h2s-pam-trial.AbC12345"], null, parent), "", "no result");
        assertEqual(trial.stageReply(["staged\t/run/user/1000/h2s-pam-trial.AbC12345"], "ok", parent), "", "a result that is no object");

        // ── sameAuthLines ──
        const vendor = "#%PAM-1.0\n# BEGIN h2s-shell x\n-auth sufficient pam_fprintd.so\n# END h2s-shell\nauth include system-auth\naccount include system-auth\n";
        const files = { "/etc/pam.d/system-auth": text(systemAuth) };
        const sudoStack = trial.stagingStep("sudo", sudo, files, dirs, false).stack;
        const polkitStack = trial.stagingStep("polkit-1", vendor, files, dirs, false).stack;
        assertEqual(trial.sameAuthLines(sudoStack, polkitStack), true, "sudo and polkit with the same auth lines: one trial");
        const other = trial.stagingStep("polkit-1", vendor.replace("sufficient", "required"), files, dirs, false).stack;
        assertEqual(trial.sameAuthLines(sudoStack, other), false, "another control: two trials");
        const inline = trial.stagingStep("polkit-1", "-auth sufficient pam_fprintd.so\nauth substack system-auth\n", files, dirs, false).stack;
        assertEqual(trial.sameAuthLines(sudoStack, inline), false, "the same lines in a substack: two trials");
        assertEqual(trial.sameAuthLines(sudoStack, { known: false, lines: sudoStack.lines }), false, "a stack not known: two trials");

        // ── step ──
        let state = trial.initialState();
        let out = null;
        const go = event => {
            const result = trial.step(state, event);
            state = result.state;
            return result.effects;
        };
        const types = effects => effects.map(effect => effect.type).join(" ");
        const places = ["directory\t/etc/pam.d", "directory\t/usr/lib/pam.d", "faillock\t/etc/security/faillock.conf"];
        const fileLines = (path, body) => ["file\t" + path + "\ttext"].concat(body.split("\n").filter(line => line !== "").map(line => "|" + line), ["end\t" + path]);
        const dir = parent + "/h2s-pam-trial.AbC12345";

        let effects = go({ type: "start", service: "sudo", text: sudo, parent });
        assertEqual(state.phase + " " + state.trial + " " + types(effects), "reading 1 readFiles", "start: the places read first");
        assertEqual(effects[0].paths.length + " " + effects[0].trial, "0 1", "… no paths, keyed to trial 1");
        assertEqual(types(go({ type: "start", service: "sudo", text: sudo, parent })) + " " + state.trial, " 1", "a start while one runs: ignored");
        effects = go({ type: "filesRead", trial: 1, lines: places, result: ok, paths: [] });
        assertEqual(types(effects) + " " + effects[0].paths.join(" "), "readFiles /etc/pam.d/system-auth", "the places: then the included file");
        assertEqual(state.directories.join(" "), dirs.join(" "), "… the directories pam-files.sh named");
        effects = go({ type: "filesRead", trial: 1, lines: fileLines("/etc/pam.d/system-auth", systemAuth), result: ok, paths: ["/etc/pam.d/system-auth"] });
        assertEqual(state.phase + " " + types(effects), "staging stage", "all read: staged");
        assertEqual(effects[0].parent + " " + effects[0].files.map(file => file.name).join(","), parent + " sudo,system-auth", "… under the parent, both files");
        assertEqual(effects[0].files[1].text, systemAuth, "… system-auth's text as read");
        assertEqual(types(go({ type: "staged", trial: 1, lines: ["staged\t" + dir], result: ok })), "startPam", "staged: the conversation starts");
        assertEqual(state.phase + " " + state.staging, "running " + dir, "… running, the directory kept");
        assertEqual(types(go({ type: "pamMessage", trial: 0, message: "late", messageIsError: false, responseRequired: false })) + state.messages.length, "0",
                    "a message of another trial: dropped");
        go({ type: "pamMessage", trial: 1, message: "Place your finger", messageIsError: false, responseRequired: false });
        go({ type: "pamMessage", trial: 1, message: "Password: ", messageIsError: false, responseRequired: true, responseVisible: false });
        assertEqual(JSON.stringify(state.messages) + " " + JSON.stringify(state.prompt), '[{"text":"Place your finger","error":false}] {"text":"Password: ","visible":false}',
                    "PAM's messages kept; its question is the prompt");
        effects = go({ type: "respond", trial: 1, text: "secret-123" });
        assertEqual(types(effects) + " " + effects[0].text + " " + state.prompt, "respondPam secret-123 null", "the answer passed on, the prompt gone");
        assert(!JSON.stringify(state).includes("secret-123"), "… the answer is not kept in the state");
        assertEqual(types(go({ type: "respond", trial: 1, text: "again" })), "", "a second answer to one question: dropped");
        effects = go({ type: "pamCompleted", trial: 1, result: "success" });
        assertEqual(state.phase + " " + types(effects) + " " + effects[0].directory + " " + state.staging, "passed removeStaging " + dir + " ",
                    "success: passed, the staging directory removed");
        assertEqual(types(go({ type: "pamCompleted", trial: 1, result: "failed" })) + state.phase, "passed", "a completion after the end: nothing");

        // A failure, PAM's reason, and try again
        effects = go({ type: "start", service: "sudo", text: sudo, parent });
        assertEqual(state.trial + " " + state.phase + " " + state.messages.length + " " + state.reason, "2 reading 0 ", "start again: a new trial, a clean state");
        go({ type: "filesRead", trial: 2, lines: places, result: ok, paths: [] });
        go({ type: "filesRead", trial: 2, lines: fileLines("/etc/pam.d/system-auth", systemAuth), result: ok, paths: ["/etc/pam.d/system-auth"] });
        go({ type: "staged", trial: 2, lines: ["staged\t" + dir], result: ok });
        for (let i = 0; i < 25; i++)
            go({ type: "pamMessage", trial: 2, message: "info " + i, messageIsError: false, responseRequired: false });
        assertEqual(state.messages.length + " " + state.messages[0].text, "20 info 5", "the last 20 messages kept");
        go({ type: "pamMessage", trial: 2, message: "Authentication failed " + "x".repeat(400), messageIsError: true, responseRequired: false });
        assertEqual(state.pamReason.length + " " + state.pamReason.startsWith("Authentication failed") + " " + state.pamReason.endsWith("…"), "300 true true",
                    "PAM's error message is its reason, cut to 300");
        go({ type: "pamMessage", trial: 2, message: "y".repeat(300), messageIsError: false, responseRequired: false });
        assertEqual(state.messages[state.messages.length - 1].text, "y".repeat(300), "a message of 300 characters kept whole");
        assert(state.pamReason.startsWith("Authentication failed"), "… a message that is no error is not PAM's reason");
        effects = go({ type: "pamCompleted", trial: 2, result: "failed" });
        assertEqual(state.phase + " " + state.reason + " " + types(effects), "failed failed removeStaging", "failed: the reason, the directory removed");
        assertEqual(state.reasonText, trial.texts.failed, "… its text");
        const resultOf = result => {
            state = trial.initialState();
            go({ type: "start", service: "sudo", text: "auth required pam_unix.so\n", parent });
            go({ type: "filesRead", trial: 1, lines: places, result: ok, paths: [] });
            go({ type: "staged", trial: 1, lines: ["staged\t" + dir], result: ok });
            go({ type: "pamCompleted", trial: 1, result });
            return state.phase + " " + state.reason;
        };
        assertEqual(resultOf("maxTries"), "failed maxTries", "maxTries");
        assertEqual(resultOf("error"), "failed error", "error");
        assertEqual(resultOf("anything"), "failed error", "an unknown result: an error, never a pass");

        // Refusals before PAM
        state = trial.initialState();
        go({ type: "start", service: "sudo", text: sudo, parent });
        effects = go({ type: "filesRead", trial: 1, lines: places, result: { ok: false }, paths: [] });
        assertEqual(state.phase + " " + state.reason + " " + types(effects), "failed unread ", "pam-files.sh failed: not tried, nothing staged");
        state = trial.initialState();
        go({ type: "start", service: "sudo", text: sudo, parent });
        go({ type: "filesRead", trial: 1, lines: places, result: ok, paths: [] });
        go({ type: "filesRead", trial: 1, lines: ["file\t/etc/pam.d/system-auth\tunreadable"], result: ok, paths: ["/etc/pam.d/system-auth"] });
        assertEqual(state.phase + " " + state.reason, "failed unread", "an included file unreadable: not tried");
        state = trial.initialState();
        go({ type: "start", service: "sudo", text: sudo, parent });
        go({ type: "filesRead", trial: 1, lines: places, result: ok, paths: [] });
        go({ type: "filesRead", trial: 1, lines: [], result: { ok: false }, paths: ["/etc/pam.d/system-auth"] });
        assertEqual(state.phase + " " + state.reason, "failed unread", "a read of the included file that failed: unreadable, not tried");
        state = trial.initialState();
        go({ type: "start", service: "sudo", text: sudo, parent: "" });
        assertEqual(state.phase + " " + state.reason, "failed staging", "no private place to stage in: not tried");
        state = trial.initialState();
        go({ type: "start", service: "../etc", text: sudo, parent });
        assertEqual(state.phase + " " + state.reason, "failed service", "a service that is no name");
        state = trial.initialState();
        go({ type: "start", service: "sudo", text: "auth required pam_unix.so\n", parent });
        go({ type: "filesRead", trial: 1, lines: places, result: ok, paths: [] });
        effects = go({ type: "staged", trial: 1, lines: ["staged\t/elsewhere/h2s-pam-trial.AbC12345"], result: ok });
        assertEqual(state.phase + " " + state.reason + " " + types(effects), "failed staging ", "staged somewhere else: failed, that directory not touched");
        state = trial.initialState();
        go({ type: "start", service: "sudo", text: "auth required pam_unix.so\n", parent });
        go({ type: "filesRead", trial: 1, lines: places, result: ok, paths: [] });
        go({ type: "staged", trial: 1, lines: ["staged\t" + dir], result: ok });
        effects = go({ type: "pamStartFailed", trial: 1 });
        assertEqual(state.phase + " " + state.reason + " " + types(effects), "failed startFailed removeStaging", "PAM refused to start: failed, removed");
        state = trial.initialState();
        go({ type: "start", service: "sudo", text: "auth required pam_unix.so\n", parent });
        go({ type: "filesRead", trial: 1, lines: places, result: ok, paths: [] });
        go({ type: "staged", trial: 1, lines: ["staged\t" + dir], result: ok });
        assertEqual(types(go({ type: "pamStartFailed", trial: 0 })) + " " + state.phase, " running", "a start failure of another trial: nothing");
        state = trial.initialState();
        go({ type: "start", service: "sudo", text: "auth required pam_unix.so\n", parent });
        go({ type: "filesRead", trial: 1, lines: ["faillock\t/etc/security/faillock.conf"], result: ok, paths: [] });
        assertEqual(state.phase + " " + state.reason, "failed unread", "no PAM directory named: not tried");
        state = trial.initialState();
        go({ type: "start", service: "sudo", text: "auth required pam_unix.so\n", parent });
        effects = go({ type: "filesRead", trial: 1, lines: ["directory\t/etc/pam.d"], result: ok, paths: [] });
        assertEqual(state.phase + " " + types(effects), "staging stage", "one directory (NixOS' shape) is enough");
        out = trial.step(null, { type: "start", service: "sudo", text: "x", parent });
        assertEqual(out.state.phase + " " + out.state.trial, "reading 1", "no state yet: the initial one");

        // Cancels
        const toPhase = phase => {
            state = trial.initialState();
            go({ type: "start", service: "sudo", text: "auth required pam_unix.so\n", parent });
            if (phase === "reading")
                return;
            go({ type: "filesRead", trial: 1, lines: places, result: ok, paths: [] });
            if (phase === "staging")
                return;
            go({ type: "staged", trial: 1, lines: ["staged\t" + dir], result: ok });
            go({ type: "pamMessage", trial: 1, message: "Password: ", messageIsError: false, responseRequired: true });
        };
        toPhase("reading");
        assertEqual(types(go({ type: "cancel", trial: 1 })) + " " + state.phase, " cancelled", "cancel while reading: nothing to undo");
        assertEqual(types(go({ type: "filesRead", trial: 1, lines: places, result: ok, paths: [] })) + " " + state.phase, " cancelled", "… the read's answer after it: nothing");
        toPhase("staging");
        assertEqual(types(go({ type: "cancel", trial: 1 })) + " " + state.phase, " cancelled", "cancel while staging");
        effects = go({ type: "staged", trial: 1, lines: ["staged\t" + dir], result: ok });
        assertEqual(types(effects) + " " + effects[0].directory + " " + state.phase, "removeStaging " + dir + " cancelled",
                    "… the directory made after it: removed, no conversation");
        toPhase("running");
        effects = go({ type: "cancel", trial: 1 });
        assertEqual(types(effects) + " " + state.phase + " " + state.prompt + " " + state.staging, "abortPam removeStaging cancelled null ",
                    "cancel while running: aborted, removed");
        assertEqual(types(go({ type: "pamCompleted", trial: 1, result: "success" })) + " " + state.phase, " cancelled", "… a success after the cancel: still cancelled");
        assertEqual(types(go({ type: "respond", trial: 1, text: "x" })), "", "… an answer after it: dropped");
        toPhase("running");
        assertEqual(types(go({ type: "cancel", trial: 7 })) + " " + state.phase, " running", "a cancel of another trial: nothing");
        // A staging reply of an earlier trial, after a new one started
        toPhase("staging");
        go({ type: "cancel", trial: 1 });
        go({ type: "start", service: "sudo", text: "auth required pam_unix.so\n", parent });
        go({ type: "filesRead", trial: 2, lines: places, result: ok, paths: [] });
        effects = go({ type: "staged", trial: 1, lines: ["staged\t" + dir], result: ok });
        assertEqual(types(effects) + " " + effects[0].trial + " " + state.phase + " " + state.staging, "removeStaging 1 staging ",
                    "trial 1's directory arriving during trial 2: removed, trial 2 still waits for its own");
    }
}
