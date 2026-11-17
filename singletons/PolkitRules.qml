pragma Singleton

import Quickshell
import QtQuick

// The polkit agent's decisions — pure, so tests/PolkitRulesTest.qml checks them without
// polkit. Authentication holds the live state; notes/plans/polkit.md has the reasoning.
Singleton {
    id: root

    // Authentication agents by their program's name, as a process list shows it. Not
    // every agent there is, the usual ones: one not here is still found at the first start
    // by the shell failing to register.
    readonly property var knownAgents: [
        "hyprpolkitagent",
        "polkit-gnome-authentication-agent-1",
        "polkit-kde-authentication-agent-1",
        "polkit-mate-authentication-agent-1",
        "lxqt-policykit-agent",
        "lxpolkit",
        "xfce-polkit",
        "soteria",
        "polkit-dumb-agent"
    ]

    // The known agents among `commands` (each a process's command line): their names
    function agentsIn(commands) {
        const found = [];
        for (const command of commands ?? []) {
            const program = String(command).trim().split(/\s+/)[0] ?? "";
            const name = program.slice(program.lastIndexOf("/") + 1);
            if (knownAgents.includes(name) && !found.includes(name))
                found.push(name);
        }
        return found;
    }

    // At the first start: with another agent running, the shell's stays off; with none,
    // it is tried, and kept on if it registered. → "off", "try", "on"
    function firstStart(othersRunning, triedAndRegistered) {
        if ((othersRunning ?? []).length > 0)
            return "off";
        if (triedAndRegistered === undefined || triedAndRegistered === null)
            return "try";
        return triedAndRegistered ? "on" : "off";
    }

    // What to tell about the agents: "deciding", "active" (the shell's prompts), "blocked"
    // (the shell's is on but could not register: another holds the session), "conflict"
    // (the shell's holds it while another agent runs, unable to register), "other"
    // (another agent answers — a known one running, or `unknownAgent`: the shell was
    // refused registering), "none" (no agent: requests for a password are refused)
    function state(mode, registered, othersRunning, unknownAgent) {
        const others = (othersRunning ?? []).length > 0;
        if (mode !== "on" && mode !== "off")
            return "deciding";
        if (mode === "on")
            return !registered ? "blocked" : others ? "conflict" : "active";
        return others || unknownAgent === true ? "other" : "none";
    }

    // ── The prompt's conversation ──
    // polkit's helper runs one fixed PAM stack, `polkit-1`, and relays its conversation:
    // a question (PAM_PROMPT_ECHO_OFF/ON → `request`, answered with `submit`), a message
    // (PAM_TEXT_INFO / PAM_ERROR_MSG → the supplementary message), the end (success, or a
    // failure after which Quickshell starts the stack again). Where a fingerprint reader
    // comes first, pam_fprintd only sends messages for up to 30 s (or three non-matching
    // fingers) before the password is asked; nothing an agent sends ends that wait. So the
    // prompt follows what actually arrived — never a module's wording — and keeps a
    // password typed before it is asked for, to send it the moment it is.

    // What the stack in /etc/pam.d/polkit-1 (its text) does first: "fingerprint-first"
    // (pam_fprintd before pam_unix), "password-first" (pam_unix first: an empty password
    // goes on to the reader), "password" (no reader), "" (not known: no file, an include)
    function pamStackOrder(text) {
        let fingerprint = -1, password = -1, index = 0;
        for (const raw of String(text ?? "").split("\n")) {
            const line = raw.replace(/#.*$/, "").trim();
            if (line === "")
                continue;
            const tokens = line.split(/\s+/);
            if (tokens[0].replace(/^-/, "") !== "auth")
                continue;
            // The control may be a bracketed list with spaces: the module follows it
            let at = 1;
            if (tokens[at]?.startsWith("[")) {
                while (at < tokens.length && !tokens[at].endsWith("]"))
                    at++;
            }
            const control = tokens[1] ?? "";
            const module = tokens[at + 1] ?? "";
            if (control === "include" || control === "substack" || line.startsWith("@include"))
                return fingerprint < 0 && password < 0 ? "" : (fingerprint >= 0 ? "fingerprint-first" : "password-first");
            const name = module.slice(module.lastIndexOf("/") + 1);
            if (name === "pam_fprintd.so" && fingerprint < 0)
                fingerprint = index;
            else if (name === "pam_unix.so" && password < 0)
                password = index;
            index++;
        }
        if (password < 0)
            return fingerprint < 0 ? "" : "fingerprint-first";
        if (fingerprint < 0)
            return "password";
        return fingerprint < password ? "fingerprint-first" : "password-first";
    }

    // One attempt's conversation as far as it went: `asked` (a question waits for an
    // answer, `echo` whether it is shown), `answered` ("" / "empty" / "text": what the
    // last answer was), `messages` (messages since the start or the last answer),
    // `failures` (attempts that ended without success in this request)
    function conversationStart() {
        return { asked: false, echo: false, answered: "", messages: 0, failures: 0 };
    }

    // The conversation after `event`: { kind: "message" } (info or error),
    // { kind: "request", echo }, { kind: "answered", empty }, { kind: "failed" } (the
    // attempt ended; a new one starts), { kind: "restarted" } (a new attempt, e.g. another
    // account picked)
    function conversationStep(conversation, event) {
        const next = Object.assign({}, conversation ?? conversationStart());
        switch (event?.kind) {
        case "message":
            next.messages++;
            break;
        case "request":
            next.asked = true;
            next.echo = event.echo === true;
            break;
        case "answered":
            next.asked = false;
            next.echo = false;
            next.answered = event.empty ? "empty" : "text";
            next.messages = 0;
            break;
        case "failed":
        case "restarted":
            Object.assign(next, { asked: false, echo: false, answered: "", messages: 0 });
            if (event.kind === "failed")
                next.failures++;
            break;
        }
        return next;
    }

    // "asked" (a question waits), "checking" (an answer went, nothing since), "waiting"
    // (messages and no question: e.g. a fingerprint reader waiting for a finger), "starting"
    // (nothing yet)
    function conversationPhase(conversation) {
        if (conversation.asked)
            return "asked";
        if (conversation.messages > 0)
            return "waiting";
        return conversation.answered !== "" ? "checking" : "starting";
    }

    // A password typed before it was asked for (`held`) goes the moment a hidden answer is
    // asked for — never into a shown question (that asks something else)
    function sendHeldNow(conversation, held) {
        return held === true && conversation.asked && !conversation.echo;
    }

    // An empty answer is sent only where it means something: with the password first, it
    // goes on to the fingerprint reader. Elsewhere it would be one more failed password.
    function emptyAnswerAllowed(conversation, stack) {
        return conversation.asked && !conversation.echo && stack === "password-first";
    }

    // The line under PAM's message saying what the prompt waits for and what can be done:
    // { text, error }. `held`: a password typed and Entered before it was asked for.
    function conversationHint(conversation, stack, held) {
        const phase = conversationPhase(conversation);
        const readerGivesUp = "when the fingerprint reader gives up (after 30 s, or three fingers that do not match)";
        if (phase === "asked")
            return { text: emptyAnswerAllowed(conversation, stack) ? "Or leave it empty and press Enter to use the fingerprint reader." : "", error: false };
        if (held === true)
            return { text: "The password is sent as soon as it is asked for"
                + (stack === "fingerprint-first" ? " — " + readerGivesUp + "." : "."), error: false };
        if (phase === "waiting") {
            // With the password first, a message after a typed answer means pam_unix did not
            // accept it and the stack went on to the reader
            if (stack === "password-first" && conversation.answered === "text")
                return { text: "That password was not accepted. Use the fingerprint reader, or wait: the password is asked again when it gives up.", error: true };
            if (stack === "password-first" && conversation.answered === "empty")
                return { text: "The password is asked again if the fingerprint reader gives up.", error: false };
            return { text: stack === "fingerprint-first"
                    ? "Or type the password now: it is sent " + readerGivesUp + "."
                    : "You can type the password already: it is sent as soon as it is asked for.", error: false };
        }
        return { text: "", error: false };
    }
}
