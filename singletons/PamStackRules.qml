pragma Singleton

import Quickshell
import QtQuick

// Reading PAM stacks (tests/PamStackRulesTest.qml): a service file's text parsed as libpam
// parses it, its `include`/`substack`/`@include` followed across an ordered list of
// directories, down to the `auth` lines in the order PAM runs them; the shell's own block
// in a file, pam_faillock's place, and faillock.conf. Pure: the files come from a reader
// function or a map of path → text handed in, never read here. Distribution-neutral: Arch
// (a vendor directory behind `/etc/pam.d`), NixOS (generated, absolute store paths), Debian
// (`@include common-auth`), Fedora (authselect) all parse the same way. A file that cannot
// be read leaves the stack unknown, never "without such lines".
Singleton {
    id: root

    // Where libpam looks for a service is the distribution's (its facts' pamDirectories, in
    // order: the administrator's directory, then a vendor directory where there is one — a
    // file in the first shadows one of the same name in the second), always handed in: with
    // none, nothing is found. NixOS generates everything into the first and has no vendor
    // directory; polkit's text alone is read as in that one directory
    readonly property var nixosDirectories: ["/etc/pam.d"]
    // How deep includes nest (libpam refuses a file at PAM_SUBSTACK_MAX_LEVEL, 16: fifteen
    // includes below the service) and how many lines a whole stack may hold before it is
    // given up on as not a real one
    readonly property int maxDepth: 15
    readonly property int maxLines: 2000

    readonly property var _types: ["auth", "account", "password", "session"]
    readonly property var _simpleControls: ["required", "requisite", "sufficient", "optional"]
    // The words libpam takes in a bracketed control (libpam/pam_handlers.c, _pam_token_returns
    // and the actions), compared with case
    readonly property var _returnNames: ["success", "open_err", "symbol_err", "service_err", "system_err",
        "buf_err", "perm_denied", "auth_err", "cred_insufficient", "authinfo_unavail", "user_unknown",
        "maxtries", "new_authtok_reqd", "acct_expired", "session_err", "cred_unavail", "cred_expired",
        "cred_err", "no_module_data", "conv_err", "authtok_err", "authtok_recover_err", "authtok_lock_busy",
        "authtok_disable_aging", "try_again", "ignore", "abort", "authtok_expired", "module_unknown",
        "bad_item", "conv_again", "incomplete", "default"]
    readonly property var _actionWords: ["ignore", "ok", "done", "bad", "die", "reset"]

    // ── One file ──

    // The file's logical lines, assembled as libpam does (_pam_str_prepare): a line ending
    // in a backslash (white space after it allowed) goes on in the next, joined with a
    // space; a `#` starts a comment to the end of the line, and a line with a comment, or a
    // blank line, ends the line being assembled — a backslash before a `#` is not a
    // continuation. Each item `{ number, text }`, `number` the first physical line (from 1),
    // `text` trimmed and without the comment; empty lines are left out. A continuation
    // still open at the end of the file (libpam gives up on the file) is a last item with
    // `unfinished: true`.
    function logicalLines(text) {
        const value = String(text ?? "");
        const physical = value.split("\n");
        // The "" after a final newline is the end of the file, not a blank line
        if (value.endsWith("\n"))
            physical.pop();
        const result = [];
        let pending = "", start = 0, continuing = false;
        const flush = () => {
            const trimmed = pending.trim();
            if (trimmed !== "")
                result.push({ number: start, text: trimmed });
            pending = "";
            continuing = false;
        };
        for (let i = 0; i < physical.length; i++) {
            let line = physical[i].replace(/\r$/, "");
            const comment = line.indexOf("#");
            if (comment >= 0)
                line = line.slice(0, comment);
            const continues = comment < 0 && /\\[ \t]*$/.test(line);
            if (continues)
                line = line.replace(/\\[ \t]*$/, "");
            if (!continues && line.trim() === "") {
                flush();
                continue;
            }
            if (!continuing)
                start = i + 1;
            pending += (continuing ? " " : "") + line;
            continuing = continues;
            if (!continuing)
                flush();
        }
        if (continuing) {
            result.push({ number: start, text: pending.trim(), unfinished: true });
            pending = "";
        }
        return result;
    }

    // A line's words, a bracketed word (`[success=1 default=ignore]`, an argument such as
    // `[query=select …]`) kept as one with its spaces; `\]` inside brackets is not the end.
    // null when a bracket is never closed.
    function words(text) {
        const parts = String(text ?? "").trim().split(/\s+/).filter(part => part !== "");
        const result = [];
        for (let i = 0; i < parts.length; i++) {
            let word = parts[i];
            if (word.startsWith("[")) {
                while (!_closesBracket(word)) {
                    i++;
                    if (i >= parts.length)
                        return null;
                    word += " " + parts[i];
                }
            }
            result.push(word);
        }
        return result;
    }

    function _closesBracket(word) {
        return word.length > 1 && word.endsWith("]") && !word.endsWith("\\]");
    }

    // A bracketed control's `value=action` pairs as a map (`[success=1 default=ignore]` →
    // { success: "1", default: "ignore" }); null when a pair is not one libpam takes: a
    // value not among its return codes or `default`, an action not ignore/ok/done/bad/die/
    // reset or a jump count. Compared with case (`Default`, `sucess` are refused). As libpam
    // reads them (pam_misc.c): a value named twice takes its last action, but `default` only
    // fills the values still unset, so its first action is the one that counts.
    function controlActions(control) {
        // libpam takes white space around `=` (`[success = ok]`)
        const inner = String(control ?? "").replace(/^\[/, "").replace(/\]$/, "").replace(/\s*=\s*/g, "=").trim();
        const actions = {};
        for (const pair of inner.split(/\s+/).filter(part => part !== "")) {
            const equals = pair.indexOf("=");
            if (equals <= 0 || equals === pair.length - 1)
                return null;
            const key = pair.slice(0, equals), action = pair.slice(equals + 1);
            if (!_returnNames.includes(key))
                return null;
            if (!_actionWords.includes(action) && !/^[1-9]\d*$/.test(action))
                return null;
            if (key === "default" && Object.prototype.hasOwnProperty.call(actions, "default"))
                continue;
            actions[key] = action;
        }
        return Object.keys(actions).length > 0 ? actions : null;
    }

    // One logical line (comment already gone, as logicalLines gives it) → what it says:
    //   `@include name`           { directive: "@include", target }
    //   `[-]type include name`    { type, optional, control: "include"|"substack", controlKind: same, target }
    //   `[-]type control module …` { type, optional, control, controlKind: "simple"|"bracketed",
    //                                actions (bracketed: the map, else null), module, moduleName, args }
    // or { error } when libpam would not take it. Type and simple control words are
    // compared without case, as libpam does.
    function parseLine(text) {
        const list = words(text);
        if (list === null)
            return { error: "A bracket is not closed" };
        if (list.length === 0)
            return { error: "Empty line" };
        if (list[0] === "@include") {
            if (list.length < 2)
                return { error: "@include names no file" };
            return { directive: "@include", target: list[1] };
        }
        const optional = list[0].startsWith("-");
        const type = list[0].replace(/^-/, "").toLowerCase();
        if (!_types.includes(type))
            return { error: "Unknown type: " + list[0] };
        if (list.length < 2)
            return { error: "No control word" };
        const control = list[1];
        if (control.startsWith("[")) {
            const actions = controlActions(control);
            if (actions === null)
                return { error: "A bracketed control is not value=action pairs" };
            if (list.length < 3)
                return { error: "No module" };
            return _moduleLine(type, optional, control, "bracketed", actions, list);
        }
        const word = control.toLowerCase();
        if (word === "include" || word === "substack") {
            if (list.length < 3)
                return { error: word + " names no file" };
            return { type, optional, control: word, controlKind: word, target: list[2] };
        }
        if (!_simpleControls.includes(word))
            return { error: "Unknown control word: " + control };
        if (list.length < 3)
            return { error: "No module" };
        return _moduleLine(type, optional, word, "simple", null, list);
    }

    function _moduleLine(type, optional, control, controlKind, actions, list) {
        const module = list[2];
        return {
            type, optional, control, controlKind, actions, module,
            moduleName: module.slice(module.lastIndexOf("/") + 1),
            // libpam hands a bracketed argument to the module without its brackets, `\]` as `]`
            args: list.slice(3).map(word => word.startsWith("[") && _closesBracket(word)
                                    ? word.slice(1, -1).replace(/\\\]/g, "]") : word)
        };
    }

    // The shell's own block in a file's text: between `# BEGIN h2s-shell <sha256>` and
    // `# END h2s-shell`. null when there is none; else { hash ("" when the marker has
    // none), beginLine, endLine (-1 when no end), complete (one begin, one end after it),
    // body (the physical lines between, joined with "\n": what the hash is of) }.
    function ownBlock(text) {
        const physical = String(text ?? "").split("\n").map(line => line.replace(/\r$/, ""));
        let begin = -1, end = -1, hash = "", begins = 0, ends = 0;
        for (let i = 0; i < physical.length; i++) {
            const opening = physical[i].match(/^\s*#\s*BEGIN h2s-shell(?:\s+(\S+))?\s*$/);
            if (opening) {
                begins++;
                if (begin < 0) {
                    begin = i;
                    hash = opening[1] ?? "";
                }
            } else if (/^\s*#\s*END h2s-shell\s*$/.test(physical[i])) {
                ends++;
                if (begin >= 0 && end < 0)
                    end = i;
            }
        }
        if (begins === 0 && ends === 0)
            return null;
        return {
            hash,
            beginLine: begin >= 0 ? begin + 1 : -1,
            endLine: end >= 0 ? end + 1 : -1,
            complete: begins === 1 && ends === 1 && begin >= 0 && end > begin,
            body: begin >= 0 && end > begin ? physical.slice(begin + 1, end).join("\n") : ""
        };
    }

    // The hash in a whole file written by the shell (polkit-1 shadowing the vendor file):
    // its first non-empty line `# Written by h2s-shell <sha256>`. null when not such a file.
    function writtenBy(text) {
        for (const line of String(text ?? "").split("\n")) {
            if (line.trim() === "")
                continue;
            const match = line.match(/^\s*#\s*Written by h2s-shell(?:\s+(\S+))?\s*$/);
            return match ? { hash: match[1] ?? "" } : null;
        }
        return null;
    }

    // ── A whole stack ──

    // The paths libpam tries for a service or an included name, in order: an absolute
    // name as it is, else the name in each directory
    function candidates(name, directoryList) {
        const value = String(name ?? "");
        if (value.startsWith("/"))
            return [value];
        if (value === "" || value.includes("/"))
            return [];
        return (Array.isArray(directoryList) ? directoryList : []).map(directory => directory.replace(/\/+$/, "") + "/" + value);
    }

    // The service's auth stack. `read` is a function path → answer or a map { path: answer }:
    // a string is the file's text, undefined (or a path not in the map) is "no such file"
    // and the next directory is tried, null (or a throw) is "there but not readable by us":
    // the lookup stops there and the stack is not known. libpam itself goes on past any file
    // it cannot open, but it runs as root and reads what the shell cannot, so what it would
    // run is not known. A reader doing real I/O answers undefined only for ENOENT and
    // ENOTDIR, null for every other failure (EACCES, EIO, …). `directoryList` the
    // directories in order (none: no file is found). Result:
    //   service, file (the service's path, "" when not found), known (every file read,
    //   every line parsed, within the limits), problems [{ reason, file, line, target }]
    //   (reason "missing" / "unreadable" / "cycle" / "depth" / "unparsable" / "too long"),
    //   unknownAt (how many of `lines` come before the first gap: all of them when known),
    //   lines [{ file, line, type, optional, control, controlKind, actions, module,
    //   moduleName, args, depth, substack (inside a substack), via [{ file, line }] (the
    //   include lines that led here) }], files (every file read, in order),
    //   block (ownBlock of the service's file, with authIndices: its lines' places in
    //   `lines`), writtenBy (of the service's file),
    //   faillock { present (true / false / null when not known), at [{ index, phase, args }] }.
    function stack(service, read, directoryList) {
        const reader = typeof read === "function" ? read
            : (path => (read && Object.prototype.hasOwnProperty.call(read, path)) ? read[path] : undefined);
        const dirs = Array.isArray(directoryList) ? directoryList : [];
        const result = {
            service: String(service ?? ""), file: "", known: true, problems: [], unknownAt: -1,
            lines: [], files: [], block: null, writtenBy: null,
            faillock: { present: null, at: [] }
        };
        let counted = 0;
        const problem = (reason, file, line, target) => {
            if (result.known)
                result.unknownAt = result.lines.length;
            result.known = false;
            result.problems.push({ reason, file, line, target });
        };
        // The first candidate that is there: { path, text }, { path, unreadable: true }, or
        // null when none is
        const open = name => {
            for (const path of candidates(name, dirs)) {
                let text = null;
                try {
                    text = reader(path);
                } catch (error) {
                    text = null;
                }
                if (typeof text === "string")
                    return { path, text };
                if (text !== undefined)
                    return { path, unreadable: true };
            }
            return null;
        };
        const walk = (path, text, chain, via, depth, substack) => {
            if (result.files.indexOf(path) < 0)
                result.files.push(path);
            for (const logical of logicalLines(text)) {
                if (++counted > root.maxLines) {
                    if (!result.problems.some(item => item.reason === "too long"))
                        problem("too long", path, logical.number, "");
                    return;
                }
                const parsed = logical.unfinished ? { error: "The file ends inside a continued line" } : parseLine(logical.text);
                if (parsed.error !== undefined) {
                    problem("unparsable", path, logical.number, parsed.error);
                    continue;
                }
                const including = parsed.directive === "@include"
                    || (parsed.type === "auth" && (parsed.controlKind === "include" || parsed.controlKind === "substack"));
                if (including) {
                    const target = parsed.target;
                    if (depth + 1 > root.maxDepth) {
                        problem("depth", path, logical.number, target);
                        continue;
                    }
                    const found = open(target);
                    if (found === null) {
                        problem("missing", path, logical.number, target);
                        continue;
                    }
                    if (found.unreadable) {
                        problem("unreadable", path, logical.number, found.path);
                        continue;
                    }
                    if (chain.indexOf(found.path) >= 0) {
                        problem("cycle", path, logical.number, found.path);
                        continue;
                    }
                    walk(found.path, found.text, chain.concat([found.path]),
                         via.concat([{ file: path, line: logical.number }]), depth + 1,
                         substack || parsed.controlKind === "substack");
                    continue;
                }
                if (parsed.type !== "auth")
                    continue;
                result.lines.push({
                    file: path, line: logical.number, type: parsed.type, optional: parsed.optional,
                    control: parsed.control, controlKind: parsed.controlKind, actions: parsed.actions,
                    module: parsed.module, moduleName: parsed.moduleName, args: parsed.args,
                    depth, substack, via
                });
            }
        };
        const top = open(result.service);
        if (top === null) {
            problem("missing", "", 0, result.service);
        } else if (top.unreadable) {
            problem("unreadable", "", 0, top.path);
        } else {
            result.file = top.path;
            walk(top.path, top.text, [top.path], [], 0, false);
            result.writtenBy = writtenBy(top.text);
            const block = ownBlock(top.text);
            if (block !== null) {
                const last = block.endLine >= 0 ? block.endLine : Infinity;
                block.authIndices = [];
                result.lines.forEach((line, index) => {
                    if (line.file === top.path && line.via.length === 0 && line.line > block.beginLine && line.line < last)
                        block.authIndices.push(index);
                });
            }
            result.block = block;
        }
        if (result.known)
            result.unknownAt = result.lines.length;
        result.lines.forEach((line, index) => {
            if (line.moduleName === "pam_faillock.so") {
                const phase = ["preauth", "authfail", "authsucc"].find(word => line.args.includes(word)) ?? "";
                result.faillock.at.push({ index, phase, args: line.args });
            }
        });
        result.faillock.present = result.faillock.at.length > 0 ? true : (result.known ? false : null);
        return result;
    }

    // ── Reading through scripts/pam-files.sh ──
    // PamStacks reads the files with that script (it tells a file not there from one it
    // cannot read) in rounds: the places first, then the paths the stacks ask for, until no
    // stack asks for one it does not have. These are its decisions; the I/O is
    // singletons/io/PamStackReader.qml's.

    // How many rounds of reading one refresh takes at most (an include chain is at most
    // maxDepth deep; faillock.conf one more)
    readonly property int maxRounds: maxDepth + 3

    // One run of the script → { places: { directories, faillockPath } or null (not in this
    // run's answer), answers: { path: { text } | { absent: true } | { unreadable: true } } }.
    // `asked`: the paths the run was asked for; each gets an answer, `unreadable` when the
    // run has no complete record of it (a run that failed, was cut short or timed out has
    // none: every path is unknown, never "not there"). `result` is CommandRunner's.
    function filesAnswer(lines, result, asked) {
        const answers = {};
        const wanted = Array.isArray(asked) ? asked.map(path => String(path)) : [];
        const usable = result !== null && typeof result === "object" && result.ok === true && result.truncated !== true;
        const list = usable && Array.isArray(lines) ? lines : [];
        const directories = [];
        let faillockPath = "", placed = false, open = null, body = [];
        for (const raw of list) {
            const line = String(raw).replace(/\r$/, "");
            if (open !== null) {
                if (line.startsWith("|")) {
                    body.push(line.slice(1));
                    continue;
                }
                if (line === "end\t" + open && wanted.includes(open) && !(open in answers))
                    answers[open] = { text: body.join("\n") + (body.length > 0 ? "\n" : "") };
                open = null;
                body = [];
                if (line.startsWith("end\t"))
                    continue;
            }
            const fields = line.split("\t");
            if (fields[0] === "directory" && fields.length === 2 && fields[1].startsWith("/")) {
                directories.push(fields[1]);
                placed = true;
            } else if (fields[0] === "faillock" && fields.length === 2 && fields[1].startsWith("/")) {
                faillockPath = fields[1];
                placed = true;
            } else if (fields[0] === "file" && fields.length === 3 && wanted.includes(fields[1])) {
                if (fields[2] === "text")
                    open = fields[1];
                else if ((fields[2] === "absent" || fields[2] === "unreadable") && !(fields[1] in answers))
                    answers[fields[1]] = fields[2] === "absent" ? { absent: true } : { unreadable: true };
            }
        }
        for (const path of wanted) {
            if (!(path in answers))
                answers[path] = { unreadable: true };
        }
        return { places: usable && placed ? { directories, faillockPath } : null, answers };
    }

    // What the files read so far give: the stacks of `request.services` (names) and of the
    // lock's configs (`request.lock`: { method: absolute path }), each service's pam_faillock
    // settings, and the paths still to be read. `request.directories` the directories in
    // order, `request.faillockPath` where faillock.conf is (pam-files.sh's places; "" none).
    // `answers` as filesAnswer gives them, merged. A path not answered yet is `pending`
    // (and counts as unreadable meanwhile). `final`: every pending path is taken as
    // unreadable instead (the rounds ran out). → { services: { name: stack },
    // lock: { method: stack }, faillock: { name: faillockConfig or null }, pending: [paths] }
    function readingStep(request, answers, final) {
        const known = answers ?? {};
        const pending = [];
        const reader = path => {
            const answer = Object.prototype.hasOwnProperty.call(known, path) ? known[path] : null;
            if (answer === null) {
                if (final !== true && pending.indexOf(path) < 0)
                    pending.push(path);
                return null;
            }
            if (typeof answer.text === "string")
                return answer.text;
            return answer.absent === true ? undefined : null;
        };
        const directoryList = Array.isArray(request?.directories) ? request.directories : [];
        const result = { services: {}, lock: {}, faillock: {}, pending };
        for (const name of (Array.isArray(request?.services) ? request.services : [])) {
            const read = stack(name, reader, directoryList);
            result.services[name] = read;
            result.faillock[name] = _faillockOf(read, reader, String(request?.faillockPath ?? ""));
        }
        const lock = request?.lock ?? {};
        for (const method of Object.keys(lock)) {
            if (typeof lock[method] === "string" && lock[method].startsWith("/"))
                result.lock[method] = stack(lock[method], reader, directoryList);
        }
        return result;
    }

    // The settings of a stack's pam_faillock (its preauth line's, else its first): null when
    // it has none, it is not known, or its settings file cannot be read
    function _faillockOf(read, reader, faillockPath) {
        if (read.faillock.present !== true)
            return null;
        const line = read.faillock.at.find(item => item.phase === "preauth") ?? read.faillock.at[0];
        const confPath = faillockConfPath(line.args);
        // The default file is read where pam-files.sh says it is (a test's own in a test tree)
        const file = confPath === faillockConfDefault ? faillockPath : confPath;
        if (file === "")
            return null;
        const text = reader(file);
        return faillockConfig(text === undefined ? "" : text, line.args, confPath);
    }

    // The methods script's answer (scripts/lock-auth-methods.sh, a run as LatestQuery hands
    // it: its lines and CommandRunner's result) → { known, fingerprint, securityKey ("ready" /
    // "absent" / "unknown"), lock: { method: absolute path of the config it uses } }. A run
    // that failed knows nothing: both "unknown", no configs.
    function methodsAnswer(lines, result) {
        const event = LockIoRules.detectionEvent(0, LockIoRules.probeRun(lines, result));
        if (event.type !== "methodsDetected")
            return { known: false, fingerprint: "unknown", securityKey: "unknown", lock: {} };
        const found = LockParseRules.parseMethods(event.lines);
        const lock = {};
        for (const method of Object.keys(found))
            lock[method] = found[method].directory.replace(/\/+$/, "") + "/" + found[method].config;
        return {
            known: true,
            fingerprint: "fingerprint" in found ? "ready" : "absent",
            securityKey: "u2f" in found ? "ready" : "absent",
            lock
        };
    }

    // ── faillock.conf ──

    readonly property string faillockConfDefault: "/etc/security/faillock.conf"

    // Which file pam_faillock reads for a line's arguments: `conf=<path>`, else the default
    function faillockConfPath(args) {
        const conf = (Array.isArray(args) ? args : []).map(word => String(word)).filter(word => word.startsWith("conf="));
        return conf.length > 0 ? conf[conf.length - 1].slice(5) : faillockConfDefault;
    }

    // pam_faillock's settings for one stack line: `text` is the text of the file it reads
    // (`path`, default faillock.conf; faillockConfPath(args) says which), `args` the line's
    // arguments, which override the file (the preauth line's decide the lock, the authfail
    // line's the counting). { deny, failInterval, unlockTime, rootUnlockTime (seconds;
    // 0 = never unlocked by time), evenDenyRoot, silent }, libpam's defaults (3, 900, 600,
    // root as unlock_time) for what is not set or set to something it would refuse. A file
    // known not to exist is "" (defaults); text not read (not a string), or a `conf=` naming
    // another file than `path`, is null: not known.
    function faillockConfig(text, args, path) {
        if (typeof text !== "string")
            return null;
        const words = Array.isArray(args) ? args.map(word => String(word)) : [];
        if (faillockConfPath(words) !== String(path ?? faillockConfDefault))
            return null;
        const config = { deny: 3, failInterval: 900, unlockTime: 600, rootUnlockTime: -1, evenDenyRoot: false, silent: false };
        const apply = (key, value) => {
            if (key === "even_deny_root" && value === "")
                config.evenDenyRoot = true;
            else if (key === "silent" && value === "")
                config.silent = true;
            else if ((key === "unlock_time" || key === "root_unlock_time") && value === "never")
                config[key === "unlock_time" ? "unlockTime" : "rootUnlockTime"] = 0;
            else if (/^\d+$/.test(value)) {
                const number = parseInt(value, 10);
                if (key === "deny")
                    config.deny = number;
                else if (key === "fail_interval" && number > 0)
                    config.failInterval = number;
                else if (key === "unlock_time")
                    config.unlockTime = number;
                else if (key === "root_unlock_time")
                    config.rootUnlockTime = number;
            }
        };
        // The file: one setting a line, `key = value` or `key value` or a bare flag, `#`
        // comments; no continuation lines
        for (const raw of text.split("\n")) {
            const line = raw.replace(/#.*$/, "").trim();
            if (line === "")
                continue;
            const match = line.match(/^(\S+?)[\s=]+(.*)$/);
            if (match)
                apply(match[1], match[2].trim());
            else
                apply(line, "");
        }
        for (const word of words) {
            const equals = word.indexOf("=");
            if (equals > 0)
                apply(word.slice(0, equals), word.slice(equals + 1));
            else
                apply(word, "");
        }
        if (config.rootUnlockTime < 0)
            config.rootUnlockTime = config.unlockTime;
        return config;
    }
}
