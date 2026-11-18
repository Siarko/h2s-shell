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

    // What to tell when a privileged request of the shell's own was refused (pkexec exited
    // 127), with the agents in `agentState` (state()): → { summary, body, noAgent }. With no
    // agent at all the refusal may be that, and the shell offers its own prompt (noAgent)
    function deniedNotice(agentState, what) {
        if (agentState === "none")
            return { summary: String(what) + " — no authentication prompt answered", noAgent: true,
                     body: "No polkit agent is running, so programs asking for an administrator's password are refused. The shell can be the agent." };
        return { summary: String(what) + " — not allowed", body: "The password was not given or not accepted.", noAgent: false };
    }

    // ── Who asks, and what for (a run of PrivilegedRuns, the shell's queue) ──
    // The prompt (polkit/AuthPrompt.qml) shows "Module", "Authorization" and the command
    // for the run at the head of the queue, when the request is that run's (announces());
    // the notification sent when the shell's prompt does not answer says the same. The
    // agent's flow names no caller and no command line: what ties a request to a run is
    // pkexec's message, which names the command it was given.

    // The action pkexec asks for
    readonly property string pkexecAction: "org.freedesktop.policykit.exec"
    // A value (the module's name, the run's `what`) is cut to this many characters, "…"
    // included
    readonly property int announcementCap: 40
    // What a run of the old PrivilegedAction shows for its module: it names none
    readonly property string unnamedModule: "Not named"

    // A value as the prompt shows it: control and format characters dropped, white space
    // folded to single spaces, trimmed, cut with "…" at announcementCap. Not a string: ""
    function cleanValue(value) {
        if (typeof value !== "string")
            return "";
        let kept = "";
        for (const character of value.replace(/\s+/g, " ")) {
            if (!PrivilegedRules.unprintableCode(character.codePointAt(0)))
                kept += character;
        }
        const characters = Array.from(kept.replace(/ +/g, " ").trim());
        if (characters.length <= announcementCap)
            return characters.join("");
        return characters.slice(0, announcementCap - 1).join("").replace(/ +$/, "") + "…";
    }

    // The "Module" line: the manifest's name, with the id in brackets when the name does not
    // read as the id (lower-cased, letters and digits only, it differs from it). The id is
    // never cut: the name is free text, the id is what keeps it honest. No name: the id.
    function moduleLabel(name, id) {
        const cleanName = cleanValue(name);
        const cleanId = cleanValue(id);
        if (cleanName === "")
            return cleanId !== "" ? cleanId : unnamedModule;
        if (cleanId === "" || cleanName.toLowerCase().replace(/[^a-z0-9]/g, "") === cleanId)
            return cleanName;
        return cleanName + " (" + cleanId + ")";
    }

    // One word as a shell reads it back: bare when it holds only characters a shell takes
    // as they are; else in single quotes; a word holding a control or format character in
    // $'…' with that character escaped, so the command stays on one line and shows every
    // character it holds
    function shellQuote(word) {
        const text = String(word);
        if (/^[A-Za-z0-9_@%+=:,.\/-]+$/.test(text))
            return text;
        if (!PrivilegedRules.unprintable(text))
            return "'" + text.replace(/'/g, "'\\''") + "'";
        let quoted = "$'";
        for (const character of text) {
            const code = character.codePointAt(0);
            if (character === "\\" || character === "'")
                quoted += "\\" + character;
            else if (code === 0x0a)
                quoted += "\\n";
            else if (code === 0x09)
                quoted += "\\t";
            else if (code === 0x0d)
                quoted += "\\r";
            else if (!PrivilegedRules.unprintableCode(code))
                quoted += character;
            else if (code < 0x80)
                quoted += "\\x" + code.toString(16).padStart(2, "0");
            else if (code <= 0xffff)
                quoted += "\\u" + code.toString(16).padStart(4, "0");
            else
                quoted += "\\U" + code.toString(16).padStart(8, "0");
        }
        return quoted + "'";
    }

    // Every text of a run's announcement. `request`: { moduleName, moduleId, what,
    // pkexecArgv (the words handed to pkexec, after pkexec itself: the shell's `timeout`
    // first for a module's run), legacy (a run of the old PrivilegedAction: it names no
    // module and no purpose) } → frozen { module, authorization ("" for an old run: no
    // line), command (every word, shell-quoted, nothing dropped or cut), summary, body (the
    // notification's: "Module: …", "Authorization: …" or "") }
    function announcement(request) {
        const legacy = request?.legacy === true;
        const module = legacy ? unnamedModule : moduleLabel(request?.moduleName, request?.moduleId);
        const authorization = legacy ? "" : cleanValue(request?.what);
        const words = Array.isArray(request?.pkexecArgv) ? Array.from(request.pkexecArgv) : [];
        return Object.freeze({
            module: module,
            authorization: authorization,
            command: words.map(word => shellQuote(word)).join(" "),
            summary: "Module: " + module,
            body: authorization !== "" ? "Authorization: " + authorization : ""
        });
    }

    // pkexec's message (polkit 0.120 and later, src/programs/pkexec.c): "Authentication is
    // needed to run `$(cmdline_short)' as the super user", translated by polkitd into the
    // agent's language, `cmdline_short` filled in. `command_line` is the words handed to
    // pkexec joined with single spaces (the program as given: an absolute path is not
    // resolved there); `cmdline_short` is that, or, past 80 bytes, its first 38 bytes, " ... "
    // and its last 37 bytes.
    readonly property int _pkexecShortLimit: 80
    readonly property int _pkexecShortHead: 38
    readonly property int _pkexecShortTail: 37

    // A text's UTF-8 bytes
    function _utf8(text) {
        const bytes = [];
        for (const character of String(text)) {
            const code = character.codePointAt(0);
            if (code < 0x80)
                bytes.push(code);
            else if (code < 0x800)
                bytes.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
            else if (code < 0x10000)
                bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
            else
                bytes.push(0xf0 | (code >> 18), 0x80 | ((code >> 12) & 0x3f), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
        }
        return bytes;
    }

    // UTF-8 bytes as text, a character cut at either end dropped → { text, cut }
    function _fromUtf8(bytes) {
        let text = "";
        let cut = false;
        let i = 0;
        while (i < bytes.length) {
            const lead = bytes[i];
            const size = lead < 0x80 ? 1 : (lead & 0xe0) === 0xc0 ? 2 : (lead & 0xf0) === 0xe0 ? 3 : (lead & 0xf8) === 0xf0 ? 4 : 0;
            if (size === 0 || i + size > bytes.length) {
                cut = true;
                i++;
                continue;
            }
            let code = size === 1 ? lead : lead & (0xff >> (size + 1));
            for (let j = 1; j < size; j++)
                code = (code << 6) | (bytes[i + j] & 0x3f);
            text += String.fromCodePoint(code);
            i += size;
        }
        return { text: text, cut: cut };
    }

    // `cmdline_short` for these words → { text (whole, when nothing was cut inside a
    // character), head, tail (the two ends either side of " ... ", whole characters only;
    // "" when not shortened) }
    function pkexecShortCommand(pkexecArgv) {
        const line = Array.from(pkexecArgv ?? []).map(word => String(word)).join(" ");
        const bytes = _utf8(line);
        if (bytes.length <= _pkexecShortLimit)
            return { text: line, head: "", tail: "" };
        const head = _fromUtf8(bytes.slice(0, _pkexecShortHead));
        const tail = _fromUtf8(bytes.slice(bytes.length - _pkexecShortTail));
        return { text: head.cut || tail.cut ? "" : head.text + " ... " + tail.text, head: head.text, tail: tail.text };
    }

    // pkexec's message in English for these words, as polkit 0.120 and later sends it
    function pkexecMessage(pkexecArgv) {
        const short = pkexecShortCommand(pkexecArgv);
        return "Authentication is needed to run `" + (short.text !== "" ? short.text : short.head + " ... " + short.tail) + "' as the super user";
    }

    // Whether `message` holds `path` as a whole word (no path character either side): the
    // message of a polkit before 0.120 names only the program ($(program): its real path)
    function _namesPath(message, path) {
        if (path === "")
            return false;
        const pathCharacter = /[A-Za-z0-9._\/-]/;
        for (let at = message.indexOf(path); at >= 0; at = message.indexOf(path, at + 1)) {
            const before = at === 0 ? "" : message.charAt(at - 1);
            const after = message.charAt(at + path.length);
            if (!pathCharacter.test(before) && (after === "" || !pathCharacter.test(after)))
                return true;
        }
        return false;
    }

    // Whether `message` holds the short command line of these words (in any language: the
    // command is the part polkitd fills in, never translated)
    function _namesCommand(message, words) {
        const short = pkexecShortCommand(words);
        if (short.text !== "")
            return message.indexOf(short.text) >= 0;
        // A character cut by the 38/37-byte ends: both whole parts, in order
        const at = message.indexOf(short.head);
        return short.head !== "" && at >= 0 && message.indexOf(short.tail, at + short.head.length) >= 0;
    }

    // Whether a polkit request (`flow`: { actionId, message }) is the one of a run
    // (`run`: { pkexecArgv (as for announcement()), programReal (the real path of the
    // program pkexec is given, "" when not known), announced (one of its requests was
    // announced already) }): pkexec's action, and the message names the command the run
    // handed to pkexec — its program by the path given or its real path. A run is announced
    // at most once; anything else is shown as polkit sent it, with no module lines.
    function announces(flow, run) {
        if (!flow || !run || run.announced === true)
            return false;
        if (String(flow.actionId ?? "") !== pkexecAction)
            return false;
        const message = String(flow.message ?? "");
        const words = Array.isArray(run.pkexecArgv) ? run.pkexecArgv.map(word => String(word)) : [];
        if (message === "" || words.length === 0 || words[0] === "")
            return false;
        const real = typeof run.programReal === "string" ? run.programReal : "";
        const programs = real !== "" && real !== words[0] ? [words[0], real] : [words[0]];
        return programs.some(program => {
            const named = [program].concat(words.slice(1));
            return _namesCommand(message, named) || _namesPath(message, program);
        });
    }

    // Whether the open request is closed because the session locked: a password is never
    // asked behind or over the lock screen. Every request, the shell's or another
    // program's; one that opens while locked too.
    function closesForLock(locked, requestOpen) {
        return locked === true && requestOpen === true;
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
