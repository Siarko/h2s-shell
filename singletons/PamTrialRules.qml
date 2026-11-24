pragma Singleton

import Quickshell
import QtQuick

// The trial before a PAM file is written (tests/PamTrialRulesTest.qml): the candidate text
// of a service (PamEditRules.build) is put, with a copy of every file its auth lines
// include by name, in a private staging directory, and one PAM conversation runs against
// it as the user — the user authenticates as the new rules ask. Only a trial that lets the
// user in may lead to the write; nothing is loaded as root from the staging directory,
// and running a user-writable config as the user grants nothing.
//
// Here: which files are staged (`stagingStep`, reading in rounds as PamStacks does), the
// staging script's reply, and the trial's lifetime as a state machine (`step`), whose
// effects singletons/io/PamTrial.qml carries out. Pure: texts and answers are handed in.
//
// The staged copy is the candidate's view of the system: a name it includes is looked up
// as libpam would look it up once the file is installed (the directories in order), and
// copied under that name, since libpam resolves every name in the one configuration
// directory it is given. An absolute include is read where it is, as it would be. A stack
// that cannot be followed completely (a file missing, unreadable or not parsable) is not
// tried: what PAM would run is not known. Nor is a text holding a control character other
// than a line break or a tab: the texts reach the staging script on its command line, where
// a NUL would cut a file short, and PAM reads no such character in a line.
//
// What the trial does not show:
// - It runs as the user, for the current user, `auth` lines only: the account and session
//   lines sudo or polkit run after it are not tried.
// - A module that keeps its state as root behaves as for any user: pam_faillock reads and
//   writes no tally, so a lockout or a count is not tried (only that the lines run).
// - An absolute include of the service's own installed path (`include /etc/pam.d/sudo`)
//   reads the file in force, not the candidate.
// - libpam's `@include` is not every libpam's: two stacks that use it are never taken as
//   one trial (`sameAuthLines`), so each is run by the libpam that will run it.
Singleton {
    id: root

    // The staging directory's name in its parent: the prefix and eight characters
    readonly property string stagingPrefix: "h2s-pam-trial."
    // The most a staged file may hold (pam-files.sh reads no more of a file)
    readonly property int maxFileBytes: 65536
    // PAM's messages kept for the view: the last ones, each cut to a length
    readonly property int maxMessages: 20
    readonly property int maxMessageLength: 300
    // A conversation that says nothing at all (no message, no result) this long after it
    // started is started again, at most `maxStarts` times in all, then the trial fails as a
    // start that failed. Why: Quickshell forks its PAM child from the shell's running
    // threads, and the child loads the modules (dlopen in pam_start); glibc does not reset
    // the dynamic loader's write lock in a forked child, so a fork while another thread
    // held it (dl_iterate_phdr, a dlopen or dlclose of its own) leaves the child blocked in
    // pam_start for good, before any module ran. A new fork does not inherit that. Every
    // module the shell writes speaks or ends at once (pam_unix asks, pam_fprintd and
    // pam_u2f with `cue` say what to do, pam_faillock ends), so the silence is never a
    // module waiting (a raw line of a module that waits in silence may fail the trial).
    readonly property int firstWordMs: 8000
    readonly property int maxStarts: 3

    // Why a trial did not pass, by its reason code
    readonly property var texts: ({
        failed: "The new rules did not let you in.",
        maxTries: "Too many tries.",
        error: "PAM could not run the new rules.",
        startFailed: "PAM could not start the new rules.",
        unread: "A file the new rules include could not be read.",
        unparsable: "A line PAM cannot read.",
        control: "A character PAM cannot read.",
        tooLarge: "The new rules are too long.",
        staging: "The new rules could not be put in place for the trial.",
        service: "Unknown service."
    })

    // Files are staged under these names only: what libpam takes as a name (no "/"), and
    // nothing a shell or a dot-file reading could misread
    function validName(name) {
        const value = String(name ?? "");
        return /^[A-Za-z0-9_][A-Za-z0-9._@+-]*$/.test(value) && value.length <= 255;
    }

    // A control character other than a line break or a tab (NUL included)
    function hasControl(text) {
        return /[\u0000-\u0008\u000b-\u001f\u007f]/.test(String(text ?? ""));
    }

    // A staging directory's name: the prefix and eight letters or digits (`token`)
    function stagingDirectory(parent, token) {
        const base = String(parent ?? "");
        if (!/^(\/[^/]+)+$/.test(base) || base.split("/").some(part => part === "." || part === "..")
                || !/^[A-Za-z0-9]{8}$/.test(String(token ?? "")))
            return "";
        return base + "/" + stagingPrefix + token;
    }

    // UTF-8 length of a text, as the file will hold it
    function byteLength(text) {
        let count = 0;
        for (const character of String(text)) {
            const code = character.codePointAt(0);
            count += code < 0x80 ? 1 : code < 0x800 ? 2 : code < 0x10000 ? 3 : 4;
        }
        return count;
    }

    function _refusal(code) {
        return { pending: [], files: null, stack: null, refusal: { code, text: texts[code] ?? texts.error } };
    }

    // ── Staging ──

    // What to stage for a candidate. `service` the service's name, `candidate` the file's
    // new text, `directories` where libpam looks, in order (pam-files.sh's places),
    // `answers` the files read so far (PamStackRules.filesAnswer's, merged), `final` every
    // path not answered yet is taken as unreadable (the rounds ran out).
    // → { pending (paths still to read), files ([{ name, text }], the service first; null
    // until complete or when refused), stack (PamStackRules.stack of the candidate as it
    // would be in force), refusal ({ code, text } or null) }.
    function stagingStep(service, candidate, answers, directories, final) {
        const name = String(service ?? "");
        if (!validName(name))
            return _refusal("service");
        if (typeof candidate !== "string")
            return _refusal("unread");
        if (byteLength(candidate) > maxFileBytes)
            return _refusal("tooLarge");
        if (hasControl(candidate))
            return _refusal("control");
        const dirs = (Array.isArray(directories) ? directories : []).map(String).filter(dir => dir.startsWith("/"));
        if (dirs.length === 0)
            return _refusal("unread");
        const known = answers ?? {};
        const pending = [];
        // Where the candidate will be: the first directory, which shadows the others
        const own = dirs[0].replace(/\/+$/, "") + "/" + name;
        const reader = path => {
            if (path === own)
                return candidate;
            const answer = Object.prototype.hasOwnProperty.call(known, path) ? known[path] : null;
            if (answer === null || typeof answer !== "object") {
                if (final !== true && pending.indexOf(path) < 0)
                    pending.push(path);
                return null;
            }
            if (typeof answer.text === "string")
                return answer.text;
            return answer.absent === true ? undefined : null;
        };
        const stack = PamStackRules.stack(name, reader, dirs);
        if (pending.length > 0)
            return { pending, files: null, stack: null, refusal: null };
        if (!stack.known) {
            const unparsable = stack.problems.some(problem => problem.reason === "unparsable");
            return _refusal(unparsable ? "unparsable" : "unread");
        }
        // The names the stack's auth lines include, in every file it reached
        const names = [];
        let atInclude = false;
        for (const path of stack.files) {
            for (const logical of PamStackRules.logicalLines(reader(path))) {
                const parsed = PamStackRules.parseLine(logical.text);
                const including = parsed.directive === "@include"
                    || (parsed.type === "auth" && (parsed.controlKind === "include" || parsed.controlKind === "substack"));
                if (parsed.directive === "@include")
                    atInclude = true;
                if (including && !String(parsed.target).startsWith("/") && names.indexOf(parsed.target) < 0)
                    names.push(parsed.target);
            }
        }
        const files = [{ name, text: candidate }];
        for (const included of names) {
            // The candidate's own name is the staged candidate, as it will be the installed one
            if (included === name)
                continue;
            if (!validName(included))
                return _refusal("unread");
            const path = PamStackRules.candidates(included, dirs).find(candidatePath => typeof reader(candidatePath) === "string");
            if (path === undefined)
                return _refusal("unread");
            const includedText = reader(path);
            if (hasControl(includedText))
                return _refusal("control");
            files.push({ name: included, text: includedText });
        }
        stack.atInclude = atInclude;
        return { pending: [], files, stack, refusal: null };
    }

    // The staging script's reply (CommandRunner's result and its stdout lines) → the
    // directory made, or "" when it failed. Only a directory directly in `parent` with the
    // staging prefix counts: anything else is not one asked for.
    function stageReply(lines, result, parent) {
        if (result === null || typeof result !== "object" || result.ok !== true || result.truncated === true)
            return "";
        const base = String(parent ?? "").replace(/\/+$/, "");
        if (!base.startsWith("/"))
            return "";
        const found = (Array.isArray(lines) ? lines : []).map(line => String(line).replace(/\r$/, ""))
            .filter(line => line.startsWith("staged\t"));
        if (found.length !== 1)
            return "";
        const directory = found[0].slice("staged\t".length);
        const name = directory.slice(base.length + 1);
        return directory.startsWith(base + "/") && new RegExp("^" + stagingPrefix.replace(".", "\\.") + "[A-Za-z0-9]{8}$").test(name)
            ? directory : "";
    }

    // Whether two candidates' trials would be the same trial: both stacks stagingStep's,
    // known, without `@include`, the same auth lines in the same order (each line's control,
    // module, arguments, and where it stands: its depth and whether in a substack). A shared
    // list whose two files come out so is tried once.
    function sameAuthLines(first, second) {
        if (first?.known !== true || second?.known !== true || first.atInclude !== false || second.atInclude !== false)
            return false;
        const shape = stack => JSON.stringify(stack.lines.map(line => [line.optional, line.control, line.module, line.args, line.depth, line.substack]));
        return shape(first) === shape(second);
    }

    // ── The trial's lifetime ──

    // Phases: idle (none yet), reading (the included files), staging (the directory being
    // made), running (the PAM conversation), passed, failed, cancelled. The last three end a
    // trial; a new start() may follow any of them.
    readonly property var activePhases: ["reading", "staging", "running"]

    function initialState() {
        return {
            phase: "idle", trial: 0, service: "", candidate: "", parent: "",
            directories: [], answers: {}, rounds: 0, stack: null,
            // The staging directory this trial makes (stagingDirectory), and the one to
            // remove when it ends: set from the moment it is asked for until it is removed
            target: "", staging: "",
            // PAM's messages that asked nothing [{ text, error }], the last maxMessages
            messages: [],
            // The question PAM asks now { text, visible } (visible: the answer may be
            // shown as typed), or null
            prompt: null,
            // Why it did not pass: a code of `texts` ("" while it may still pass), its
            // text, and PAM's own last error message ("" when it said none)
            reason: "", reasonText: "", pamReason: "",
            // The conversation's starts so far (each a new PAM child), whether PAM has said
            // anything in the current one, and how long it may stay silent (the start
            // event's firstWordMs, else firstWordMs)
            starts: 0, heard: false, firstWordMs: firstWordMs
        };
    }

    function _copy(state) {
        const base = state && typeof state === "object" ? state : initialState();
        return Object.assign(initialState(), base, {
            directories: Array.from(base.directories ?? []),
            answers: Object.assign({}, base.answers ?? {}),
            messages: Array.from(base.messages ?? [])
        });
    }

    function _cut(text) {
        const value = String(text ?? "");
        return value.length > maxMessageLength ? value.slice(0, maxMessageLength - 1) + "…" : value;
    }

    function _fail(next, effects, code) {
        next.phase = "failed";
        next.prompt = null;
        next.reason = code;
        next.reasonText = texts[code] ?? texts.error;
        if (next.staging !== "") {
            effects.push({ type: "removeStaging", trial: next.trial, parent: next.parent, directory: next.staging });
            next.staging = "";
        }
    }

    // A new PAM child for the staged directory, watched until it first says something
    function _startConversation(next, effects) {
        next.starts += 1;
        next.heard = false;
        effects.push({ type: "startPam", trial: next.trial, configDirectory: next.staging, config: next.service });
        effects.push({ type: "watchPam", trial: next.trial, start: next.starts, ms: next.firstWordMs });
    }

    function _readNext(next, effects, answer) {
        const step = stagingStep(next.service, next.candidate, next.answers, next.directories,
                                 answer.final === true);
        if (step.refusal !== null) {
            _fail(next, effects, step.refusal.code);
            return;
        }
        if (step.pending.length > 0) {
            effects.push({ type: "readFiles", trial: next.trial, paths: step.pending });
            return;
        }
        next.stack = step.stack;
        next.phase = "staging";
        next.staging = next.target;
        effects.push({ type: "stage", trial: next.trial, parent: next.parent, directory: next.target, files: step.files });
    }

    // One event → { state (a new object), effects [...] }. Events:
    //   { type: "start", service, text, parent, token }   a new trial of `text` as
    //                                              `service`, staged under `parent` in the
    //                                              directory `token` names (eight letters or
    //                                              digits; ignored while one runs)
    //   { type: "filesRead", trial, lines, result, paths }   a pam-files.sh run
    //   { type: "staged", trial, lines, result }    the staging script's reply
    //   { type: "pamStartFailed", trial }           PamContext.start() refused
    //   { type: "pamMessage", trial, message, messageIsError, responseRequired, responseVisible }
    //   { type: "respond", trial, text }            the user's answer to the prompt
    //   { type: "pamCompleted", trial, result }     "success" / "failed" / "maxTries" / "error"
    //   { type: "cancel", trial }                   the user cancelled
    //   { type: "pamSilent", trial, start }         the watch of that start ran out
    // Effects, each with the trial it belongs to:
    //   { type: "readFiles", paths }                run pam-files.sh (no paths: the places)
    //   { type: "stage", parent, directory, files } make the staging directory
    //   { type: "startPam", configDirectory, config }
    //   { type: "watchPam", start, ms }             answer with pamSilent after `ms`
    //                                              (replaces an earlier watch)
    //   { type: "respondPam", text }                the answer, passed on; never kept here
    //   { type: "abortPam" }
    //   { type: "removeStaging", parent, directory }
    // An event of another trial than the current one, or of a phase it no longer is in, acts
    // on nothing — except that a staging directory made for it is removed.
    function step(state, event) {
        const next = _copy(state);
        const effects = [];
        const kind = String(event?.type ?? "");
        const current = event?.trial === next.trial;
        switch (kind) {
        case "start": {
            if (activePhases.includes(next.phase))
                break;
            const trial = next.trial + 1;
            Object.assign(next, initialState(), {
                trial, phase: "reading", service: String(event.service ?? ""),
                candidate: typeof event.text === "string" ? event.text : null,
                parent: String(event.parent ?? "")
            });
            const silence = Number(event.firstWordMs);
            if (isFinite(silence) && silence > 0)
                next.firstWordMs = silence;
            next.target = stagingDirectory(next.parent, event.token);
            if (!validName(next.service)) {
                _fail(next, effects, "service");
                break;
            }
            if (next.target === "") {
                _fail(next, effects, "staging");
                break;
            }
            effects.push({ type: "readFiles", trial, paths: [] });
            break;
        }
        case "filesRead": {
            if (!current || next.phase !== "reading")
                break;
            const paths = Array.isArray(event.paths) ? event.paths : [];
            const answer = PamStackRules.filesAnswer(event.lines, event.result, paths);
            next.rounds += 1;
            if (next.directories.length === 0) {
                // The first run: the places
                if (answer.places === null || answer.places.directories.length === 0) {
                    _fail(next, effects, "unread");
                    break;
                }
                next.directories = answer.places.directories;
            }
            Object.assign(next.answers, answer.answers);
            _readNext(next, effects, { final: next.rounds >= PamStackRules.maxRounds });
            break;
        }
        case "staged": {
            const directory = stageReply(event.lines, event.result, next.parent);
            if (!current || next.phase !== "staging") {
                // Never the current trial's own directory, whoever answers for it
                if (directory !== "" && directory !== next.staging)
                    effects.push({ type: "removeStaging", trial: event.trial, parent: next.parent, directory });
                break;
            }
            if (directory === "" || directory !== next.target) {
                _fail(next, effects, "staging");
                break;
            }
            next.phase = "running";
            _startConversation(next, effects);
            break;
        }
        case "pamStartFailed":
            if (current && next.phase === "running")
                _fail(next, effects, "startFailed");
            break;
        case "pamMessage": {
            if (!current || next.phase !== "running")
                break;
            next.heard = true;
            const text = _cut(event.message);
            if (event.responseRequired === true) {
                next.prompt = { text, visible: event.responseVisible === true };
                break;
            }
            next.messages.push({ text, error: event.messageIsError === true });
            if (next.messages.length > maxMessages)
                next.messages.splice(0, next.messages.length - maxMessages);
            if (event.messageIsError === true && text.trim() !== "")
                next.pamReason = text;
            break;
        }
        case "respond":
            // One answer per question: a second, or one with no question, is dropped
            if (!current || next.phase !== "running" || next.prompt === null)
                break;
            next.prompt = null;
            effects.push({ type: "respondPam", trial: next.trial, text: String(event.text ?? "") });
            break;
        case "pamCompleted": {
            if (!current || next.phase !== "running")
                break;
            const result = String(event.result ?? "");
            if (result === "success") {
                next.phase = "passed";
                next.prompt = null;
                effects.push({ type: "removeStaging", trial: next.trial, parent: next.parent, directory: next.staging });
                next.staging = "";
                break;
            }
            _fail(next, effects, result === "failed" || result === "maxTries" ? result : "error");
            break;
        }
        case "pamSilent":
            if (!current || next.phase !== "running" || next.heard || event.start !== next.starts)
                break;
            effects.push({ type: "abortPam", trial: next.trial });
            if (next.starts >= maxStarts) {
                _fail(next, effects, "startFailed");
                break;
            }
            _startConversation(next, effects);
            break;
        case "cancel":
            if (!current || !activePhases.includes(next.phase))
                break;
            if (next.phase === "running")
                effects.push({ type: "abortPam", trial: next.trial });
            if (next.staging !== "")
                effects.push({ type: "removeStaging", trial: next.trial, parent: next.parent, directory: next.staging });
            next.staging = "";
            next.prompt = null;
            next.phase = "cancelled";
            break;
        }
        return { state: next, effects };
    }
}
