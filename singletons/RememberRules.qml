pragma Singleton

import Quickshell
import QtQuick

// A remembered administrator authorization (tests/RememberRulesTest.qml): a polkit rule makes
// the shell's own root runs — `pkexec <timeout> …`, action org.freedesktop.policykit.exec —
// AUTH_ADMIN_KEEP, so polkitd keeps a typed password for the shell's process for its
// ExpirationSeconds. Here: the rule's text and the polkitd.conf text for a longer length, the
// length polkitd resolves from its conf files, what is installed, the kept authorizations in
// `pkcheck --list-temp`'s output, when the shell revokes itself for a shorter setting, the
// NixOS configuration line and the prompt's line. Pure: texts are handed in, nothing is read
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

    function _validPath(path) {
        return typeof path === "string" && /^\/[^\x00-\x1f\x7f"\\]*$/.test(path) && !path.endsWith("/");
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
            + "        return polkit.Result.AUTH_ADMIN_KEEP;\n"
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
            const trimmed = line.replace(/\r$/, "").replace(/^\s+/, "");
            if (trimmed === "" || trimmed.startsWith("#"))
                continue;
            const groupLine = trimmed.match(/^\[([^\[\]\x00-\x1f]+)\]\s*$/);
            if (groupLine) {
                current = groupLine[1];
                continue;
            }
            const pair = trimmed.match(/^([^=]*?)\s*=\s*(.*)$/);
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

    // A whole file written by the shell: its first line the header, the hash of the rest
    function _confOurs(text) {
        const header = text.match(/^#\s*Written by h2s-shell\s+(\S+)[ \t]*\n/);
        return header !== null && PamEditRules.sha256(text.slice(header[0].length)) === header[1];
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

    // `pkcheck --list-temp`'s relative time ("2 min 5 sec from now", "40 sec ago") in
    // seconds; NaN when it is not one
    function _relativeSeconds(text) {
        const match = text.match(/^(?:(\d+) min )?(\d+) sec (from now|ago)$/);
        if (!match || Number(match[2]) >= 60)
            return NaN;
        const seconds = Number(match[1] ?? 0) * 60 + Number(match[2]);
        return match[3] === "ago" ? -seconds : seconds;
    }

    // The shell's kept authorizations in `pkcheck --list-temp`'s output (standard output of a
    // run that exited 0; nothing at all when the session holds none), read at nowMs, for the
    // shell's process `pid`. Each entry is five lines and a blank one:
    //   authorization id: <id>
    //   action:           <action id>
    //   subject:          unix-process:<pid>:<start time> (<command line>)
    //   obtained:         <relative> (<local time>)
    //   expires:          <relative> (<local time>)
    // Entries of other actions or subjects, and those already expired, are left out. Anything
    // not in that form makes the whole list unknown, never "nothing kept".
    // → { known, entries: [{ id, obtainedMs, untilMs }], latest (the entry kept longest, or null) }
    function parseList(text, nowMs, pid) {
        const unknown = { known: false, entries: [], latest: null };
        if (typeof text !== "string" || !Number.isFinite(nowMs) || !Number.isInteger(pid) || pid <= 0)
            return unknown;
        const lines = text.split("\n");
        const entries = [];
        let i = 0;
        while (i < lines.length) {
            if (lines[i].trim() === "") {
                i++;
                continue;
            }
            if (i + 5 > lines.length)
                return unknown;
            const id = lines[i].match(/^authorization id: (\S+)$/);
            const action = lines[i + 1].match(/^action: +(\S+)$/);
            const subject = lines[i + 2].match(/^subject: +(\S+) \(.*\)$/);
            const obtained = lines[i + 3].match(/^obtained: +(.+?) \(.*\)$/);
            const expires = lines[i + 4].match(/^expires: +(.+?) \(.*\)$/);
            if (!id || !action || !subject || !obtained || !expires)
                return unknown;
            const obtainedSeconds = _relativeSeconds(obtained[1]), expiresSeconds = _relativeSeconds(expires[1]);
            if (Number.isNaN(obtainedSeconds) || Number.isNaN(expiresSeconds))
                return unknown;
            const process = subject[1].match(/^unix-process:(\d+):\d+$/);
            if (action[1] === execAction && process && Number(process[1]) === pid && expiresSeconds > 0)
                entries.push({ id: id[1], obtainedMs: nowMs + obtainedSeconds * 1000, untilMs: nowMs + expiresSeconds * 1000 });
            i += 5;
        }
        let latest = null;
        for (const entry of entries) {
            if (latest === null || entry.untilMs > latest.untilMs)
                latest = entry;
        }
        return { known: true, entries, latest };
    }

    // When the shell revokes a kept authorization itself: its obtained time plus the setting,
    // when the setting is shorter than the system's length (or that length is unknown —
    // forgetting early is harmless); 0 when polkitd's own expiry comes first or together.
    function revokeAtMs(entry, minutes, systemSeconds) {
        if (!Number.isFinite(entry?.obtainedMs) || !Number.isInteger(minutes) || minutes < 1)
            return 0;
        if (systemSeconds >= 0 && minutes * 60 >= systemSeconds)
            return 0;
        return entry.obtainedMs + minutes * 60000;
    }

    // Until when an entry stays kept: the sooner of polkitd's expiry and the shell's revoke
    function keptUntilMs(entry, minutes, systemSeconds) {
        const revoke = revokeAtMs(entry, minutes, systemSeconds);
        return revoke ? Math.min(entry.untilMs, revoke) : entry?.untilMs ?? 0;
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
