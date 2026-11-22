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
    // pkexec's message, which names the command it was given — past 80 bytes only its two
    // ends, so another command with the same ends reads the same (see announces()).

    // The action pkexec asks for
    readonly property string pkexecAction: "org.freedesktop.policykit.exec"
    // A value (the module's name, the run's `what`) is cut to this many characters, "…"
    // included
    readonly property int announcementCap: 40
    // What a run of the old PrivilegedAction shows for its module: it names none
    readonly property string unnamedModule: "Not named"

    // White space, and the characters that show as blank though they are letters or symbols
    // (Braille's blank, the Hangul fillers): a name padded with them would read as a shorter
    // one, so they fold like spaces
    readonly property var _blank: /[\s   -   　⠀ㅤᅟᅠﾠ]+/g

    // A value as the prompt shows it: control and format characters dropped, white space and
    // blank-looking fillers folded to single spaces, trimmed, cut with "…" at
    // announcementCap. Not a string: ""
    function cleanValue(value) {
        if (typeof value !== "string")
            return "";
        const kept = PrivilegedRules.characters(value.replace(_blank, " "))
            .filter(character => !PrivilegedRules.unprintableCode(character.codePointAt(0))).join("");
        // By code point: an emoji counts once and is never cut in half
        const characters = PrivilegedRules.characters(kept.replace(/ +/g, " ").trim());
        if (characters.length <= announcementCap)
            return characters.join("");
        return characters.slice(0, announcementCap - 1).join("").replace(/ +$/, "") + "…";
    }

    // The "Module" line's two parts: { name (the manifest's name, cleaned; the id when there
    // is none), id (the id, shown in brackets after the name: "" when the name reads as the
    // id — lower-cased, letters and digits only, the same) }. The id is never cut: the name
    // is free text, the id is what keeps it honest.
    function moduleParts(name, id) {
        const cleanName = cleanValue(name);
        const cleanId = cleanValue(id);
        if (cleanName === "")
            return { name: cleanId !== "" ? cleanId : unnamedModule, id: "" };
        if (cleanId === "" || cleanName.toLowerCase().replace(/[^a-z0-9]/g, "") === cleanId)
            return { name: cleanName, id: "" };
        return { name: cleanName, id: cleanId };
    }

    // The "Module" line as one text: the name, " (id)" after it when moduleParts shows one
    function moduleLabel(name, id) {
        const parts = moduleParts(name, id);
        return parts.id !== "" ? parts.name + " (" + parts.id + ")" : parts.name;
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
    // module and no purpose) } → frozen { module (the line as one text), moduleName,
    // moduleId (moduleParts: the view elides the name, never the id), authorization (""
    // for an old run: no line), command (every word, shell-quoted, nothing dropped or cut:
    // the text compared and copied), commandShown (the same for the screen: each word
    // isolated left to right, so right-to-left text in a word cannot reorder the words),
    // summary, body (the notification's: "Module: …", "Authorization: …" or "") }
    function announcement(request) {
        const legacy = request?.legacy === true;
        const parts = legacy ? { name: unnamedModule, id: "" } : moduleParts(request?.moduleName, request?.moduleId);
        const module = parts.id !== "" ? parts.name + " (" + parts.id + ")" : parts.name;
        const authorization = legacy ? "" : cleanValue(request?.what);
        const quoted = (Array.isArray(request?.pkexecArgv) ? Array.from(request.pkexecArgv) : []).map(word => shellQuote(word));
        return Object.freeze({
            module: module,
            moduleName: parts.name,
            moduleId: parts.id,
            authorization: authorization,
            command: quoted.join(" "),
            commandShown: isolatedWords(quoted),
            summary: "Module: " + module,
            body: authorization !== "" ? "Authorization: " + authorization : ""
        });
    }

    // What the polkit prompt shows where. `announcement`: announcement()'s, or null for a
    // request that is not a run of the shell's queue; `identityCount`: how many accounts can
    // answer → frozen { identity ("name": the "As user" row with the one account's name,
    // "pick": the row with a choice, "none"), announced (the Module and Command rows),
    // polkitMessage ("command": polkit's message and action id under the collapsed
    // "Command", "top": as the description over the field) }. Only a module's prompt —
    // a known module and a purpose — moves polkit's message away: there it repeats the
    // command the Command section already shows. Elsewhere (no announcement, an old run
    // naming no module or purpose) it is the only description.
    function promptLayout(announcement, identityCount) {
        const count = Number(identityCount) || 0;
        const announced = announcement !== null && announcement !== undefined;
        const fromModule = announced && String(announcement.authorization ?? "") !== ""
            && String(announcement.moduleName ?? "") !== unnamedModule;
        return Object.freeze({
            identity: count > 1 ? "pick" : count === 1 ? "name" : "none",
            announced: announced,
            polkitMessage: fromModule ? "command" : "top"
        });
    }

    // Words for the screen, in their order whatever their script: a left-to-right mark first
    // (the paragraph's direction), each word between U+2066 (left-to-right isolate) and
    // U+2069 (pop directional isolate), so the bidirectional algorithm reorders inside a word
    // at most, never across words
    function isolatedWords(words) {
        return "‎" + Array.from(words ?? []).map(word => "⁦" + String(word) + "⁩").join(" ");
    }

    // pkexec's message (polkit 0.120 and later, src/programs/pkexec.c): "Authentication is
    // needed to run `$(cmdline_short)' as the super user", translated by polkitd into the
    // agent's language with other quote marks, `cmdline_short` filled in. `command_line` is
    // the words handed to pkexec joined with single spaces (the program as given: an
    // absolute path is not resolved there); `cmdline_short` is that, or, past 80 bytes, its
    // first 38 bytes, " ... " and its last 37 bytes.
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

    // UTF-8 bytes as text, a character cut at either end dropped
    function _fromUtf8(bytes) {
        let text = "";
        let i = 0;
        while (i < bytes.length) {
            const lead = bytes[i];
            const size = lead < 0x80 ? 1 : (lead & 0xe0) === 0xc0 ? 2 : (lead & 0xf0) === 0xe0 ? 3 : (lead & 0xf8) === 0xf0 ? 4 : 0;
            if (size === 0 || i + size > bytes.length) {
                i++;
                continue;
            }
            let code = size === 1 ? lead : lead & (0xff >> (size + 1));
            for (let j = 1; j < size; j++)
                code = (code << 6) | (bytes[i + j] & 0x3f);
            text += String.fromCodePoint(code);
            i += size;
        }
        return text;
    }

    // `cmdline_short` for these words → { text (the whole line: "" when shortened), head,
    // tail (the two ends either side of " ... ", whole characters only: a character the
    // 38/37-byte cut splits is dropped; "" when not shortened) }
    function pkexecShortCommand(pkexecArgv) {
        const line = Array.from(pkexecArgv ?? []).map(word => String(word)).join(" ");
        const bytes = _utf8(line);
        if (bytes.length <= _pkexecShortLimit)
            return { text: line, head: "", tail: "" };
        return { text: "", head: _fromUtf8(bytes.slice(0, _pkexecShortHead)),
                 tail: _fromUtf8(bytes.slice(bytes.length - _pkexecShortTail)) };
    }

    // A text as a regular expression matching it literally
    function _literal(text) {
        return text.replace(/[.*+?^${}()|[\]\\\/]/g, "\\$&");
    }

    // The quote marks polkit's translations put around the command: ASCII's, the typographic
    // ones, guillemets, the CJK corner brackets and their full-width forms
    readonly property string _quoteMarks: "`'\"\u2018\u2019\u201a\u201b\u201c\u201d\u201e\u201f\u00ab\u00bb\u2039\u203a\u300c\u300d\u300e\u300f\u3008\u3009\u300a\u300b\uff02\uff07\uff62\uff63"

    // Whether a character is one of those quote marks ("" — the message's start or end — is
    // not)
    function _quoteMark(character) {
        return character !== "" && _quoteMarks.indexOf(character) >= 0;
    }

    // The text between the message's first quote mark and its last, "" without two. The
    // fixed part of pkexec's message, in every translation polkit ships, holds no quote mark
    // but the pair around the command, so this is the command as pkexec put it — whatever
    // quote marks the command itself holds stay inside.
    function _quotedPart(text) {
        let first = -1, last = -1;
        for (let i = 0; i < text.length; i++) {
            if (_quoteMark(text.charAt(i))) {
                if (first < 0)
                    first = i;
                last = i;
            }
        }
        return first >= 0 && last > first ? text.slice(first + 1, last) : "";
    }

    // Whether a polkit request (`flow`: { actionId, message }) is the one of a run
    // (`run`: { pkexecArgv (as for announcement()), announced (one of its requests was
    // announced already) }): pkexec's action, and the text between the message's first and
    // last quote mark (of any language; one white space inside each, as French and Occitan
    // put it) is exactly the run's command as pkexec puts it — its `cmdline_short`. A
    // command holding quote marks of its own cannot so wrap a shorter one. A run is
    // announced at most once; anything else is shown as polkit sent it, with no module
    // lines.
    //
    // A limit of polkit, not of this match: past 80 bytes the message keeps only the
    // command's first 38 and last 37 bytes, so another command with the same two ends gives
    // the very same message, and the flow tells nothing else. Such a request is dressed as
    // the run's. The lines are not a guard against hostile code in the session (a module
    // runs in the shell's process).
    function announces(flow, run) {
        if (!flow || !run || run.announced === true)
            return false;
        if (String(flow.actionId ?? "") !== pkexecAction)
            return false;
        const message = String(flow.message ?? "");
        const words = Array.isArray(run.pkexecArgv) ? run.pkexecArgv.map(word => String(word)) : [];
        if (message === "" || words.length === 0 || words[0] === "")
            return false;
        const short = pkexecShortCommand(words);
        // A character split by the cut may reach the message as U+FFFD, or not at all
        const pattern = short.text !== "" ? _literal(short.text)
            : _literal(short.head) + "�{0,3} \\.\\.\\. �{0,3}" + _literal(short.tail);
        return new RegExp("^\\s?" + pattern + "\\s?$").test(_quotedPart(message));
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
    // goes on to the reader), "password" (no reader), "" (not known: no file, an include
    // that is not in the text). The text alone: pamStackOrderOf takes a stack read across
    // files.
    function pamStackOrder(text) {
        const path = PamStackRules.nixosDirectories[0] + "/polkit-1";
        return pamStackOrderOf(PamStackRules.stack("polkit-1", typeof text === "string" ? { [path]: text } : {},
                                                   PamStackRules.nixosDirectories));
    }

    // The same for a stack PamStackRules.stack read. Where it is not known, only the lines
    // before the first gap decide: the reader there first is "fingerprint-first", the
    // password before a reader there is "password-first"; anything else is "" (a password
    // alone may still be followed by a reader in the part not read).
    function pamStackOrderOf(stack) {
        const lines = stack && Array.isArray(stack.lines) ? stack.lines.slice(0, Math.max(0, stack.unknownAt ?? 0)) : [];
        const fingerprint = lines.findIndex(line => line.moduleName === "pam_fprintd.so");
        const password = lines.findIndex(line => line.moduleName === "pam_unix.so");
        if (!stack || stack.known !== true) {
            if (fingerprint >= 0 && (password < 0 || fingerprint < password))
                return "fingerprint-first";
            return fingerprint >= 0 && password >= 0 ? "password-first" : "";
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
