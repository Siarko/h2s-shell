pragma Singleton

import Quickshell
import QtQuick

// Reading PAM stacks (tests/PamStackRulesTest.qml): a service file's text parsed as libpam
// parses it, its `include`/`substack`/`@include` followed across an ordered list of
// directories, down to the `auth` lines in the order PAM runs them; the shell's own block
// in a file, pam_faillock's place, and faillock.conf. Pure: the files come from a reader
// function or a map of path → text handed in, never read here. Distribution-neutral: Arch
// (`/usr/lib/pam.d` behind `/etc/pam.d`), NixOS (generated, absolute store paths), Debian
// (`@include common-auth`), Fedora (authselect) all parse the same way. A file that cannot
// be read leaves the stack unknown, never "without such lines".
Singleton {
    id: root

    // Where libpam looks for a service, in order: the administrator's directory, then the
    // vendor directory (a file in the first shadows one of the same name in the second).
    // NixOS generates everything into the first and has no vendor directory.
    readonly property var directories: ["/etc/pam.d", "/usr/lib/pam.d"]
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

    // The file's logical lines: a line ending in a backslash (white space after it allowed)
    // goes on in the next, joined with a space; blank and comment-only lines between are
    // skipped while it goes on. A `#` starts a comment to the end of the line. Each item
    // `{ number, text }`, `number` the first physical line (from 1), `text` trimmed and
    // without the comment; empty lines are left out.
    function logicalLines(text) {
        const physical = String(text ?? "").split("\n");
        const result = [];
        let pending = "", start = 0, continuing = false;
        for (let i = 0; i < physical.length; i++) {
            let line = physical[i].replace(/\r$/, "");
            const comment = line.indexOf("#");
            if (comment >= 0)
                line = line.slice(0, comment);
            if (continuing && line.trim() === "")
                continue;
            if (!continuing)
                start = i + 1;
            continuing = /\\[ \t]*$/.test(line);
            if (continuing)
                line = line.replace(/\\[ \t]*$/, "");
            pending += (pending === "" ? "" : " ") + line;
            if (continuing && i < physical.length - 1)
                continue;
            continuing = false;
            const trimmed = pending.trim();
            if (trimmed !== "")
                result.push({ number: start, text: trimmed });
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
    // reset or a jump count. Compared with case (`Default`, `sucess` are refused).
    function controlActions(control) {
        const inner = String(control ?? "").replace(/^\[/, "").replace(/\]$/, "").trim();
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
        return (directoryList ?? directories).map(directory => directory.replace(/\/+$/, "") + "/" + value);
    }

    // The service's auth stack. `read` is a function path → answer or a map { path: answer }:
    // a string is the file's text, undefined (or a path not in the map) is "no such file" —
    // libpam goes on to the next directory — and null (or a throw) is "there but not
    // readable": the lookup stops there, the stack not known. `directoryList` the
    // directories in order (default `directories`). Result:
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
        const dirs = Array.isArray(directoryList) && directoryList.length > 0 ? directoryList : directories;
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
                const parsed = parseLine(logical.text);
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
