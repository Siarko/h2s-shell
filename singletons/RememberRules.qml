pragma Singleton

import Quickshell
import QtQuick

// A remembered administrator authorization (tests/RememberRulesTest.qml): a polkit rule makes
// the shell's own root runs — `pkexec <timeout> …`, action org.freedesktop.policykit.exec —
// AUTH_ADMIN_KEEP, so polkitd keeps a typed password for the shell's process for its
// ExpirationSeconds. Here: the rule's text and the polkitd.conf text for a longer length, the
// length polkitd resolves from its conf files, what is installed, the kept authorizations as
// polkit's authority lists them over D-Bus (`gdbus call`), when the shell revokes them for a
// shorter setting, the NixOS configuration line and the prompt's line. Pure: texts are handed in, nothing is read
// or written.
Singleton {
    id: root

    readonly property string execAction: "org.freedesktop.policykit.exec"
    // polkitd's length when no conf file sets one (its compiled default, five minutes)
    readonly property int defaultSeconds: 300
    // The files polkitd reads ExpirationSeconds from, in its order
    readonly property var confPaths: ["/etc/polkit-1/polkitd.conf", "/run/polkit-1/polkitd.conf", "/usr/share/polkit-1/polkitd.conf"]
    // Where the shell writes them on Arch (the rules file must be readable by the user, so
    // the page can read it back; /etc/polkit-1/rules.d is not)
    readonly property string rulePath: "/usr/share/polkit-1/rules.d/40-h2s-shell.rules"
    readonly property string confPath: "/etc/polkit-1/polkitd.conf"
    readonly property string ruleMarker: "// Written by h2s-shell"
    readonly property string confMarker: "# Written by h2s-shell"
    readonly property real maxUnsigned: 4294967295

    // ── Texts ──

    // A user name the texts may carry inside a quoted string (JavaScript and Nix)
    function validUser(user) {
        return typeof user === "string" && user.length <= 256 && /^[A-Za-z0-9_][A-Za-z0-9_.-]*\$?$/.test(user);
    }

    // An absolute path the texts may carry quoted; no spaces, as the command line's first
    // word is matched up to one
    function _validPath(path) {
        return typeof path === "string" && /^\/[^\x00-\x20\x7f"\\]*$/.test(path) && !path.endsWith("/");
    }

    function _baseName(path) {
        return path.slice(path.lastIndexOf("/") + 1);
    }

    // The rule's text for facts { user, timeout (the trusted timeout as on the shell's PATH),
    // program (that path resolved, as pkexec reports it) }; "" when a fact is not usable.
    // Where the resolved file is not named timeout it is a multi-call binary (NixOS's
    // coreutils) that other programs resolve to as well: the command line's first word must
    // then be the timeout too.
    function ruleText(facts) {
        const user = facts?.user, timeout = facts?.timeout, program = facts?.program;
        if (!validUser(user) || !_validPath(timeout) || !_validPath(program))
            return "";
        const multiCall = _baseName(program) !== "timeout";
        const body = "polkit.addRule(function(action, subject) {\n"
            + "    if (action.id == \"" + execAction + "\" && subject.user == \"" + user + "\" &&\n"
            + "        action.lookup(\"program\") == \"" + program + "\""
            + (multiCall ? " &&\n        action.lookup(\"command_line\").indexOf(\"" + timeout + " \") == 0" : "")
            + ")\n"
            + "        return \"auth_admin_keep\";\n"
            + "});\n";
        return ruleMarker + " " + PamEditRules.sha256(body) + "\n" + body;
    }

    // polkitd.conf setting its length to `seconds` (a whole number, 1 or more); "" otherwise
    function confText(seconds) {
        if (!Number.isInteger(seconds) || seconds < 1 || seconds > maxUnsigned)
            return "";
        const body = "[Polkitd]\nExpirationSeconds=" + seconds + "\n";
        return confMarker + " " + PamEditRules.sha256(body) + "\n" + body;
    }

    // The NixOS module's option for the user and the setting. The module's minutes set
    // polkitd's length; a setting shorter than polkit's default is the shell's own revoke, so
    // the line never goes below it. "" when the user or the minutes are not usable.
    function nixLine(user, minutes) {
        if (!validUser(user) || !Number.isInteger(minutes) || minutes < 1)
            return "";
        return "programs.h2s-shell.polkit.rememberAdmin = {\n"
            + "  enable = true;\n"
            + "  users = [ \"" + user + "\" ];\n"
            + "  minutes = " + Math.max(minutes, defaultSeconds / 60) + ";\n"
            + "};";
    }

    // ── polkitd's length ──

    // A key file's string for [group] key as GLib's g_key_file_get_string gives it; null
    // when GLib would refuse the file, the key is absent or its escapes cannot be read —
    // polkitd goes on to the next file in each case
    function _keyFileString(text, group, key) {
        let current = null, found = null;
        for (const line of String(text).split("\n")) {
            const trimmed = line.replace(/\r$/, "").replace(/^[ \t\n\v\f\r]+/, "");
            if (trimmed === "" || trimmed.startsWith("#"))
                continue;
            const groupLine = trimmed.match(/^\[([^\[\]\x00-\x1f]+)\][ \t\n\v\f\r]*$/);
            if (groupLine) {
                current = groupLine[1];
                continue;
            }
            const pair = trimmed.match(/^([^=]*?)[ \t\n\v\f\r]*=[ \t\n\v\f\r]*(.*)$/);
            if (!pair || current === null || !/^[^\[\]=]+(\[[^\[\]=]+\])?$/.test(pair[1]))
                return null;
            if (current === group && pair[1] === key)
                found = pair[2];
        }
        if (found === null)
            return null;
        let value = "";
        for (let i = 0; i < found.length; i++) {
            if (found[i] !== "\\") {
                value += found[i];
                continue;
            }
            const escaped = { s: " ", n: "\n", t: "\t", r: "\r", "\\": "\\" }[found[++i]];
            if (escaped === undefined)
                return null;
            value += escaped;
        }
        return value;
    }

    // ExpirationSeconds as polkitd parses it (g_ascii_strtoull, base 10, the whole string,
    // at most G_MAXUINT); null when it refuses the value
    function _parseSeconds(value) {
        const match = value.match(/^[ \t\n\v\f\r]*([+-]?)(\d+)$/);
        if (!match)
            return null;
        const number = Number(match[2]);
        if (match[1] === "-")
            return number === 0 ? 0 : null;
        return number <= maxUnsigned ? number : null;
    }

    // The length polkitd resolves from its conf files. `files` maps a path to its text
    // (undefined or absent: no such file; null: there but not readable by the shell).
    // polkitd takes the first file whose [Polkitd] ExpirationSeconds it can read as a string
    // and stops there; a value it then refuses leaves the length it had (its default at its
    // start) — not knowable from here. → { seconds (-1 unknown), source (the deciding path,
    // "" for the default), reason: "default" | "file" | "invalid" | "unreadable" }
    function expirationSeconds(files) {
        for (const path of confPaths) {
            const text = files?.[path];
            if (text === undefined)
                continue;
            if (typeof text !== "string")
                return { seconds: -1, source: path, reason: "unreadable" };
            const value = _keyFileString(text, "Polkitd", "ExpirationSeconds");
            if (value === null)
                continue;
            const seconds = _parseSeconds(value);
            return seconds === null ? { seconds: -1, source: path, reason: "invalid" }
                                    : { seconds, source: path, reason: "file" };
        }
        return { seconds: defaultSeconds, source: "", reason: "default" };
    }

    // ── What is installed ──

    // The shell's rule in a file's text: its header line, then the lines up to the first
    // `});`. null when there is none; else { hash, body ("" when the end is missing),
    // complete, count (headers in the file), alone (nothing but the rule in the file) }
    function _ruleBlock(text) {
        const lines = String(text).split("\n");
        const headers = lines.map(line => line.match(/^\s*\/\/\s*Written by h2s-shell(?:\s+(\S+))?\s*$/));
        const start = headers.findIndex(header => header !== null);
        if (start < 0)
            return null;
        const end = lines.indexOf("});", start + 1);
        const complete = end >= 0;
        const outside = lines.slice(0, start).concat(complete ? lines.slice(end + 1) : []);
        return {
            hash: headers[start][1] ?? "",
            body: complete ? lines.slice(start + 1, end + 1).join("\n") + "\n" : "",
            complete,
            count: headers.filter(header => header !== null).length,
            alone: outside.every(line => line.trim() === "")
        };
    }

    // The conf is the shell's when it is exactly a text confText makes
    function _confOurs(text) {
        const seconds = text.match(/\nExpirationSeconds=(\d+)\n$/);
        return seconds !== null && text === confText(Number(seconds[1]));
    }

    // What is in force, from the texts read (each: a string, undefined when there is no such
    // file, null when it could not be read). files { rule, confs: { path: text } } and facts
    // { system: "arch" | "nixos", user, timeout, program }. On Arch the rule file is the
    // shell's alone; on NixOS the rule is a block in the system's rules file, among others.
    // → { rule: "none" | "ours" | "outdated" | "changed" | "unknown", conf: "none" | "ours" |
    //     "changed" | "unknown" | "system" (NixOS: the module's), seconds, secondsSource,
    //     secondsReason } — "outdated": the shell's own rule, intact, made for other facts
    // (another timeout, another user); "unknown" also when the facts cannot make a rule.
    function state(files, facts) {
        const nixos = facts?.system === "nixos";
        const length = expirationSeconds(files?.confs);
        return {
            rule: _ruleState(files?.rule, facts, nixos),
            conf: nixos ? "system" : _confState(files?.confs?.[confPath]),
            seconds: length.seconds,
            secondsSource: length.source,
            secondsReason: length.reason
        };
    }

    function _ruleState(text, facts, nixos) {
        if (text === null || (text !== undefined && typeof text !== "string"))
            return "unknown";
        if (text === undefined)
            return "none";
        const block = _ruleBlock(text);
        if (block === null)
            return nixos || text.trim() === "" ? "none" : "changed";
        if (!block.complete || block.count !== 1 || (!nixos && !block.alone) || PamEditRules.sha256(block.body) !== block.hash)
            return "changed";
        const wanted = ruleText(facts);
        if (wanted === "")
            return "unknown";
        return wanted === ruleMarker + " " + block.hash + "\n" + block.body ? "ours" : "outdated";
    }

    function _confState(text) {
        if (text === undefined)
            return "none";
        if (typeof text !== "string")
            return "unknown";
        return _confOurs(text) ? "ours" : "changed";
    }

    // ── What is kept now ──

    // A GVariant as `gdbus call` prints it (g_variant_print with type annotations) → the
    // value: a tuple or an array as a JS array, a dictionary as an object, a variant as its
    // value, numbers as numbers, strings as strings; undefined for anything else
    function parseVariant(text) {
        if (typeof text !== "string" || text.length > 1000000)
            return undefined;
        const failed = {};
        let at = 0, depth = 0;
        const space = () => { while (/^[ \t\n\r]$/.test(text[at] ?? "")) at++; };
        const annotations = ["boolean", "byte", "int16", "uint16", "int32", "uint32", "int64", "uint64", "double",
                             "handle", "objectpath", "signature"];
        const simple = { n: "\n", t: "\t", r: "\r", a: "\u0007", b: "\b", f: "\f", v: "\v", "\\": "\\", "'": "'", "\"": "\"" };
        const string = () => {
            const body = text.slice(at).match(text[at] === "'" ? /^'([^'\\]*(?:\\[\s\S][^'\\]*)*)'/ : /^"([^"\\]*(?:\\[\s\S][^"\\]*)*)"/);
            if (!body)
                return failed;
            at += body[0].length;
            let bad = false;
            const value = body[1].replace(/\\(u[0-9a-fA-F]{4}|U[0-9a-fA-F]{8}|[\s\S])/g, (all, escaped) => {
                if (escaped.length === 1) {
                    bad = bad || !(escaped in simple);
                    return simple[escaped] ?? "";
                }
                const code = parseInt(escaped.slice(1), 16);
                bad = bad || code > 0x10ffff;
                return code > 0x10ffff ? "" : String.fromCodePoint(code);
            });
            return bad ? failed : value;
        };
        // The items up to `close`, separated by commas (a trailing one allowed)
        const items = (close, item) => {
            const list = [];
            space();
            if (text[at] === close) {
                at++;
                return list;
            }
            for (;;) {
                const value = item();
                if (value === failed)
                    return failed;
                list.push(value);
                space();
                if (text[at] === ",") {
                    at++;
                    space();
                    if (text[at] === close) {
                        at++;
                        return list;
                    }
                    continue;
                }
                if (text[at] !== close)
                    return failed;
                at++;
                return list;
            }
        };
        const value = () => {
            if (++depth > 64)
                return failed;
            try {
                space();
                if (text[at] === "@") {
                    // A type for an empty container: skipped
                    while (/^[^ \t\n\r]$/.test(text[at] ?? ""))
                        at++;
                    return value();
                }
                const word = text.slice(at).match(/^[a-z][a-z0-9]*/)?.[0] ?? "";
                if (annotations.includes(word)) {
                    at += word.length;
                    return value();
                }
                if (word === "true" || word === "false") {
                    at += word.length;
                    return word === "true";
                }
                const character = text[at];
                if (character === "'" || character === "\"")
                    return string();
                if (character === "(")
                    return (at++, items(")", value));
                if (character === "[")
                    return (at++, items("]", value));
                if (character === "<") {
                    at++;
                    const inner = value();
                    space();
                    if (inner === failed || text[at] !== ">")
                        return failed;
                    at++;
                    return inner;
                }
                if (character === "{") {
                    at++;
                    const entries = items("}", () => {
                        const key = value();
                        space();
                        if (key === failed || text[at] !== ":")
                            return failed;
                        at++;
                        const item = value();
                        return item === failed ? failed : [key, item];
                    });
                    if (entries === failed)
                        return failed;
                    const object = {};
                    for (const [key, item] of entries)
                        object[String(key)] = item;
                    return object;
                }
                const number = text.slice(at).match(/^-?\d+(\.\d+)?([eE][+-]?\d+)?/)?.[0];
                if (number !== undefined) {
                    at += number.length;
                    return Number(number);
                }
                return failed;
            } finally {
                depth--;
            }
        };
        const result = value();
        space();
        return result === failed || at !== text.length ? undefined : result;
    }

    // The logind session's id from `gdbus call … Properties.Get … Session Id` (`(<'2'>,)`):
    // "" when it is not one a subject may carry
    function sessionIdOf(text) {
        const value = parseVariant(String(text ?? "").trim());
        const id = Array.isArray(value) && value.length === 1 ? value[0] : null;
        return typeof id === "string" && /^[A-Za-z0-9_.-]{1,64}$/.test(id) ? id : "";
    }

    // The session as polkit's subject, a gdbus argument: "" for an id that is not one
    function sessionSubject(sessionId) {
        return typeof sessionId === "string" && /^[A-Za-z0-9_.-]{1,64}$/.test(sessionId)
            ? "('unix-session', {'session-id': <'" + sessionId + "'>})" : "";
    }

    // The shell's kept authorizations from the authority's EnumerateTemporaryAuthorizations
    // for the session, as `gdbus call` prints it (exit 0):
    //   ([('<id>', '<action>', ('unix-process', {'pid': <uint32 N>, 'start-time': <…>,
    //     'uid': <…>}), uint64 <obtained>, uint64 <expires>), …],)   — `(@a(ss(sa{sv})tt) [],)`
    // for none — the times in seconds since the epoch. Those of the exec action whose subject
    // is the shell's process `pid` count; others, and those expired at nowMs, are left out.
    // Anything not in that form makes the list unknown, never "nothing kept". An entry kept
    // longer than polkitd's length (systemSeconds, when known, a second's slack) makes it
    // unknown too, "longer" — polkitd keeps a length other than its conf file's, which it
    // reads only at its start and on SIGHUP — its entries still given, so that the shell can
    // forget them.
    // → { known, reason ("" | "unread" | "malformed" | "longer"),
    //     entries: [{ id, obtainedMs, untilMs }], latest (kept longest), earliest (obtained first) }
    function parseKept(text, nowMs, pid, systemSeconds) {
        const unknown = reason => ({ known: false, reason, entries: [], latest: null, earliest: null });
        if (typeof text !== "string" || !Number.isFinite(nowMs) || !Number.isInteger(pid) || pid <= 0)
            return unknown("unread");
        const value = parseVariant(text.trim());
        if (!Array.isArray(value) || value.length !== 1 || !Array.isArray(value[0]))
            return unknown("malformed");
        const entries = [];
        let longer = false;
        for (const item of value[0]) {
            const well = Array.isArray(item) && item.length === 5 && typeof item[0] === "string" && typeof item[1] === "string"
                && Array.isArray(item[2]) && item[2].length === 2 && typeof item[2][0] === "string"
                && typeof item[2][1] === "object" && !Array.isArray(item[2][1])
                && Number.isInteger(item[3]) && Number.isInteger(item[4]);
            if (!well)
                return unknown("malformed");
            const [id, action, subject, obtained, expires] = item;
            if (action !== execAction || subject[0] !== "unix-process" || subject[1].pid !== pid || expires * 1000 <= nowMs)
                continue;
            entries.push({ id, obtainedMs: obtained * 1000, untilMs: expires * 1000 });
            if (systemSeconds >= 0 && expires - obtained > systemSeconds + 1)
                longer = true;
        }
        let latest = null, earliest = null;
        for (const entry of entries) {
            if (latest === null || entry.untilMs > latest.untilMs)
                latest = entry;
            if (earliest === null || entry.obtainedMs < earliest.obtainedMs)
                earliest = entry;
        }
        return { known: !longer, reason: longer ? "longer" : "", entries, latest, earliest };
    }

    // When the shell revokes the kept authorizations itself (one revoke ends them all): the
    // earliest obtained time plus the setting, when any entry would outlive it by more than a
    // second. Judged by the entries alone: polkitd reads its length only at its start and on
    // SIGHUP, so its conf file may say less than it keeps. 0: nothing to revoke.
    function revokeAtMs(entries, minutes) {
        if (!Array.isArray(entries) || !Number.isInteger(minutes) || minutes < 1)
            return 0;
        let earliest = Infinity, until = -Infinity;
        for (const entry of entries) {
            earliest = Math.min(earliest, entry.obtainedMs);
            until = Math.max(until, entry.untilMs);
        }
        const revoke = earliest + minutes * 60000;
        return until > revoke + 1000 ? revoke : 0;
    }

    // Until when something stays kept: the latest expiry, or the shell's revoke when sooner;
    // 0 when nothing is kept
    function keptUntilMs(entries, minutes) {
        if (!Array.isArray(entries) || entries.length === 0)
            return 0;
        const until = Math.max(...entries.map(entry => entry.untilMs));
        const revoke = revokeAtMs(entries, minutes);
        return revoke ? Math.min(until, revoke) : until;
    }

    // What the shell does after reading the list (parseKept's answer) at nowMs: revoke at
    // once — the list says "longer", or the revoke time has passed (a timer that did not fire
    // in time, across a suspend) —, arm one timer for the revoke time, or nothing.
    // → { now (revoke now), atMs (the time to arm for, 0 for none) }
    function revokeStep(list, minutes, nowMs) {
        if (list?.reason === "longer" && (list.entries?.length ?? 0) > 0)
            return { now: true, atMs: 0 };
        if (list?.known !== true)
            return { now: false, atMs: 0 };
        const at = revokeAtMs(list.entries, minutes);
        if (at === 0)
            return { now: false, atMs: 0 };
        return at <= nowMs ? { now: true, atMs: 0 } : { now: false, atMs: at };
    }

    // The prompt's line for a run of the shell's queue while the rule is installed: the
    // shorter of the setting and the system's length, never rounded up. "" when the rule is
    // not ours, or a length is unknown: no promise then.
    function promptLine(ruleState, minutes, systemSeconds) {
        if (ruleState !== "ours" || !Number.isInteger(minutes) || minutes < 1 || !(systemSeconds > 0))
            return "";
        const seconds = Math.min(minutes * 60, systemSeconds);
        return "Remembered for " + (seconds >= 60 ? Math.floor(seconds / 60) + " min" : seconds + " s");
    }
}
