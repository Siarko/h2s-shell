pragma Singleton

import Quickshell
import QtQuick

// The rule editor's text (tests/PamEditRulesTest.qml): a service's rows (PamRuleRules) to
// the Arch file and back. sudo: the shell's lines between `# BEGIN h2s-shell <sha256>` and
// `# END h2s-shell` at the top of the file's auth lines, the hash of the lines between.
// polkit-1: a whole /etc/pam.d/polkit-1 of the shell's own that shadows the vendor file —
// its first line `# Written by h2s-shell <sha256>` (the hash of the rest), then the vendor
// file with the same block at the top of its auth lines; removing the rules removes the file.
// Here: how each row is written (`-auth` for a sufficient reader or key, the counted
// pattern, the closing lines), reading the block back into rows, taking in a hand-made file
// (`adopt`: lines the editor writes become rows, everything else a raw row in its place,
// non-auth lines kept), noticing a file changed by hand, and the NixOS module options for
// the same rows. Pure: texts are handed in, nothing is read or written. No text is made for
// rows PamRuleRules.check refuses.
Singleton {
    id: root

    readonly property string beginMarker: "# BEGIN h2s-shell"
    readonly property string endMarker: "# END h2s-shell"
    readonly property string writtenMarker: "# Written by h2s-shell"
    // The line under it in a polkit-1 made by Replace: its other phases' lines are the
    // hand-made file's, so only its auth lines are compared with the vendor file's
    readonly property string replacedMarker: "# h2s-shell: replaced a hand-made file"
    // The closing lines, by PamRuleRules.closingOf's answer. The permit closing keeps the
    // result the rows set: libpam's `done` ends the stack only on a pass so far, so a stack
    // that already failed goes on to the pam_deny line, whose `requisite` ends it with that
    // failure — the service's own lines below the block are never reached either way.
    readonly property var closingLines: ({
        permit: ["auth [default=done] pam_permit.so", "auth requisite pam_deny.so"],
        deny: ["auth requisite pam_deny.so"]
    })
    // What is read back as a closing, by kind, longest first: the lines above, and the permit
    // line alone (a block that ends so still reads as the permit closing; built again it
    // gets both lines)
    readonly property var closingForms: ({
        permit: [closingLines.permit, closingLines.permit.slice(0, 1)],
        deny: [closingLines.deny]
    })
    // sudo's own auth lines on Arch: what "Password (as the system)" stands for in a file
    // taken in, unless the caller names others (`facts.systemLines`)
    readonly property var sudoSystemLines: ["auth include system-auth"]

    readonly property var reasonTexts: ({
        unread: "The file could not be read.",
        unparsable: "A line PAM cannot read.",
        block: "The shell's block is broken.",
        hash: "Lines in the shell's block were changed.",
        fingerprint: "A fingerprint line outside the shell's block.",
        securityKey: "A security key line outside the shell's block.",
        notOurs: "Not written by the shell.",
        fileHash: "The file was changed."
    })

    // ── sha256 ──

    readonly property var _k: [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    function _utf8(text) {
        const bytes = [];
        for (let i = 0; i < text.length; i++) {
            let code = text.charCodeAt(i);
            if (code >= 0xd800 && code < 0xdc00 && i + 1 < text.length) {
                const next = text.charCodeAt(i + 1);
                if (next >= 0xdc00 && next < 0xe000) {
                    code = 0x10000 + ((code - 0xd800) << 10) + (next - 0xdc00);
                    i++;
                }
            }
            if (code < 0x80)
                bytes.push(code);
            else if (code < 0x800)
                bytes.push(0xc0 | (code >> 6), 0x80 | (code & 63));
            else if (code < 0x10000)
                bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 63), 0x80 | (code & 63));
            else
                bytes.push(0xf0 | (code >> 18), 0x80 | ((code >> 12) & 63), 0x80 | ((code >> 6) & 63), 0x80 | (code & 63));
        }
        return bytes;
    }

    // The sha256 of a text's UTF-8 bytes, in hex: the same as `sha256sum` of the file
    function sha256(text) {
        const bytes = _utf8(String(text ?? ""));
        const length = bytes.length;
        bytes.push(0x80);
        while (bytes.length % 64 !== 56)
            bytes.push(0);
        const high = Math.floor(length / 0x20000000), low = (length * 8) >>> 0;
        bytes.push((high >>> 24) & 255, (high >>> 16) & 255, (high >>> 8) & 255, high & 255,
                   (low >>> 24) & 255, (low >>> 16) & 255, (low >>> 8) & 255, low & 255);
        const rotate = (value, count) => (value >>> count) | (value << (32 - count));
        const hash = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
        const words = new Array(64);
        for (let offset = 0; offset < bytes.length; offset += 64) {
            for (let i = 0; i < 16; i++) {
                const at = offset + 4 * i;
                words[i] = (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3];
            }
            for (let i = 16; i < 64; i++) {
                const s0 = rotate(words[i - 15], 7) ^ rotate(words[i - 15], 18) ^ (words[i - 15] >>> 3);
                const s1 = rotate(words[i - 2], 17) ^ rotate(words[i - 2], 19) ^ (words[i - 2] >>> 10);
                words[i] = (words[i - 16] + s0 + words[i - 7] + s1) | 0;
            }
            let [a, b, c, d, e, f, g, h] = hash;
            for (let i = 0; i < 64; i++) {
                const t1 = (h + (rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)) + ((e & f) ^ (~e & g)) + _k[i] + words[i]) | 0;
                const t2 = ((rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)) + ((a & b) ^ (a & c) ^ (b & c))) | 0;
                h = g; g = f; f = e; e = (d + t1) | 0;
                d = c; c = b; b = a; a = (t1 + t2) | 0;
            }
            [a, b, c, d, e, f, g, h].forEach((value, i) => { hash[i] = (hash[i] + value) | 0; });
        }
        return hash.map(value => (value >>> 0).toString(16).padStart(8, "0")).join("");
    }

    // ── Rows to lines ──

    // A sufficient reader or key line may be skipped when its module is gone (`-auth`): the
    // row falls away instead of breaking the stack. A required or requisite one is plain
    // `auth`: a second factor never silently disappears.
    function _prefix(control) {
        return control === "sufficient" ? "-auth" : "auth";
    }

    // A counted Password row: pam_faillock's preauth (a lockout closes the service),
    // pam_unix, and authfail reached only on a wrong password — the jump on success skips it
    // where a pass must not end the stack. No pattern for `optional`: an own row never is.
    function countedLines(control) {
        const middle = {
            sufficient: ["[success=done default=ignore]", "optional"],
            required: ["[success=1 default=bad]", "[default=bad]"],
            requisite: ["[success=1 default=bad]", "[default=die]"]
        }[control];
        if (!middle)
            return [];
        return ["auth required pam_faillock.so preauth",
                "auth " + middle[0] + " pam_unix.so try_first_pass",
                "auth " + middle[1] + " pam_faillock.so authfail"];
    }

    // How a row's word is written. `required` and `requisite` must pass: libpam's plain words
    // treat a module's PAM_IGNORE as no answer, and with nothing else deciding the closing
    // `[default=done] pam_permit.so` would then let the user in; so they are written as the
    // plain word's actions (libpam's pam_handlers.c) with only `ignore` a failure. (pam_fprintd
    // returns PAM_AUTHINFO_UNAVAIL without a reader or an enrolled finger, a failure either
    // way; pam_u2f with `nouserok` returns PAM_IGNORE for a user without a key.)
    readonly property var writtenControls: ({
        required: "[success=ok new_authtok_reqd=ok ignore=bad default=bad]",
        requisite: "[success=ok new_authtok_reqd=ok ignore=die default=die]"
    })

    function writtenControl(control) {
        return Object.prototype.hasOwnProperty.call(writtenControls, control) ? writtenControls[control] : String(control ?? "");
    }

    // The editor's word for a line's control: the word itself, or the word whose written
    // form the bracketed control is (the same actions in any order); "" for another control
    function controlWord(line) {
        if (line?.controlKind === "simple")
            return line.control;
        if (line?.controlKind !== "bracketed" || !line.actions)
            return "";
        const same = (first, second) => {
            const keys = Object.keys(first);
            return keys.length === Object.keys(second).length && keys.every(key => second[key] === first[key]);
        };
        for (const word of Object.keys(writtenControls)) {
            if (same(line.actions, PamStackRules.controlActions(writtenControls[word])))
                return word;
        }
        return "";
    }

    // The lines one row is written as: a raw row exactly as typed; the fixed row none (the
    // system's lines stay where they are). A detail left unset is not written.
    function rowLines(row) {
        const method = row?.method, word = String(row?.control ?? ""), control = writtenControl(word);
        const details = row?.details ?? {};
        if (method === "raw")
            return [String(details.text ?? "")];
        if (method === "fingerprint") {
            const words = [_prefix(word), control, "pam_fprintd.so"];
            if (details.timeout !== undefined)
                words.push("timeout=" + details.timeout);
            if (details.tries !== undefined)
                words.push("max-tries=" + details.tries);
            return [words.join(" ")];
        }
        if (method === "securityKey")
            return [[_prefix(word), control, "pam_u2f.so", "cue"].concat(details.pin === true ? ["pinverification=1"] : []).join(" ")];
        if (method === "password")
            return details.counted === true ? countedLines(word) : ["auth " + control + " pam_unix.so try_first_pass"];
        return [];
    }

    // The lines that end the shell's lines when the fixed row is gone ([] with it)
    function closingLinesOf(rows, facts) {
        return closingLines[PamRuleRules.closingOf(rows, facts)] ?? [];
    }

    // The shell's lines for the rows, in order, the closing lines last where there are any
    function blockLines(rows, facts) {
        const list = Array.isArray(rows) ? rows : [];
        const lines = [];
        for (const row of list) {
            if (!PamRuleRules.isFixed(row))
                lines.push(...rowLines(row));
        }
        lines.push(...closingLinesOf(list, facts));
        return lines;
    }

    // The block as physical lines, markers included; [] for no lines
    function blockText(lines) {
        if (!Array.isArray(lines) || lines.length === 0)
            return [];
        return [beginMarker + " " + sha256(lines.join("\n"))].concat(lines, [endMarker]);
    }

    // ── Text helpers ──

    function _words(text) {
        return PamStackRules.words(String(text ?? "").replace(/#.*$/, "")) ?? [];
    }

    function _sameWords(first, second) {
        return JSON.stringify(_words(first)) === JSON.stringify(_words(second));
    }

    // The same line but for how its word is spelled (plain or the written bracket form)
    function _sameRowWords(first, second) {
        const spelled = text => {
            const words = _words(text);
            const line = PamStackRules.parseLine(words.join(" "));
            const word = controlWord(line);
            if (words.length > 1 && word !== "")
                words[1] = word;
            return JSON.stringify(words);
        };
        return spelled(first) === spelled(second);
    }

    function _isMarker(line) {
        return /^\s*#\s*(BEGIN|END) h2s-shell(\s.*)?$/.test(line) || /^\s*#\s*Written by h2s-shell(\s.*)?$/.test(line)
            || line.trim() === replacedMarker;
    }

    // Where a line goes after the physical lines: before a final newline's ""
    function _endIndex(text, physical) {
        return text === "" || text.endsWith("\n") ? physical.length - 1 : physical.length;
    }

    // The physical index of the first line that runs auth lines (an auth line or @include);
    // -1 when none
    function _firstAuthIndex(text) {
        for (const logical of PamStackRules.logicalLines(text)) {
            const parsed = PamStackRules.parseLine(logical.text);
            if (parsed.directive === "@include" || parsed.type === "auth")
                return logical.number - 1;
        }
        return -1;
    }

    // Each logical line with its last physical line (0-based start and end): a backslash
    // at the end goes on into the next line unless that one is blank or only a comment
    function _spans(text) {
        const physical = String(text ?? "").split("\n").map(line => line.replace(/\r$/, ""));
        return PamStackRules.logicalLines(text).map(logical => {
            let end = logical.number - 1;
            while (end + 1 < physical.length && !physical[end].includes("#") && /\\[ \t]*$/.test(physical[end])
                   && physical[end + 1].replace(/#.*$/, "").trim() !== "")
                end++;
            return { start: logical.number - 1, end, text: logical.text, unfinished: logical.unfinished === true,
                     raw: end === logical.number - 1 ? physical[end].trim() : logical.text };
        });
    }

    // ── Lines to rows ──

    // The row that writes exactly this line (its words), or null: a reader, key or
    // uncounted password line in the editor's own form with details in range and a word
    // the editor offers for it (an `optional` one stays a raw line, kept as it is)
    function _ownRow(words) {
        const line = PamStackRules.parseLine(words.join(" "));
        // A hand-made file's plain required/requisite is read as the word too
        const word = controlWord(line);
        if (line.error !== undefined || line.module === undefined || !PamRuleRules.isControl(word))
            return null;
        const method = { "pam_fprintd.so": "fingerprint", "pam_u2f.so": "securityKey", "pam_unix.so": "password" }[line.module];
        if (method === undefined || !PamRuleRules.controlAllowed(method, word))
            return null;
        let candidate = null;
        if (line.module === "pam_fprintd.so") {
            const details = {};
            const spec = PamRuleRules.methods.fingerprint.details;
            for (const argument of line.args) {
                const match = argument.match(/^(timeout|max-tries)=(-1|\d+)$/);
                if (!match)
                    return null;
                const name = match[1] === "timeout" ? "timeout" : "tries";
                const value = parseInt(match[2], 10);
                const inRange = value === spec[name].noLimit || (value >= spec[name].min && value <= spec[name].max);
                if (name in details || !inRange)
                    return null;
                details[name] = value;
            }
            candidate = { method: "fingerprint", control: word, details };
        } else if (line.module === "pam_u2f.so") {
            candidate = { method: "securityKey", control: word, details: { pin: line.args.includes("pinverification=1"), cue: true } };
        } else if (line.module === "pam_unix.so") {
            candidate = { method: "password", control: word, details: { counted: false } };
        }
        if (candidate === null)
            return null;
        const written = rowLines(candidate);
        return written.length === 1 && _sameRowWords(written[0], words.join(" ")) ? candidate : null;
    }

    // The control of a counted pattern starting at items[index], or ""
    function _countedAt(items, index) {
        for (const control of PamRuleRules.controlsFor("password")) {
            const lines = countedLines(control);
            if (index + lines.length <= items.length
                    && lines.every((line, i) => JSON.stringify(_words(line)) === JSON.stringify(items[index + i].words)))
                return control;
        }
        return "";
    }

    // Items ({ text: what a raw row keeps, words }) → { rows (ids r1…, no fixed row),
    // closing ("permit" / "deny" when the last items are a closing form the rows before
    // them would get, else "") }
    function _readItems(items, facts) {
        const rows = [];
        const kinds = [];
        for (let i = 0; i < items.length; i++) {
            const counted = _countedAt(items, i);
            if (counted !== "") {
                rows.push({ method: "password", control: counted, details: { counted: true } });
                i += 2;
                continue;
            }
            rows.push(_ownRow(items[i].words) ?? { method: "raw", control: "", details: { text: items[i].text } });
        }
        let closing = "";
        for (const kind of Object.keys(closingForms)) {
            for (const form of closingForms[kind]) {
                const tail = rows.slice(rows.length - form.length);
                if (closing !== "" || rows.length < form.length
                        || !tail.every((row, i) => row.method === "raw" && _sameWords(form[i], row.details.text))
                        || PamRuleRules.closingOf(rows.slice(0, rows.length - form.length), facts) !== kind)
                    continue;
                rows.splice(rows.length - form.length, form.length);
                closing = kind;
            }
        }
        rows.forEach((row, i) => { row.id = "r" + (i + 1); });
        return { rows, closing };
    }

    function _blockItems(body) {
        return String(body ?? "").split("\n").filter(line => _words(line).length > 0)
            .map(line => ({ text: line, words: _words(line) }));
    }

    // The rows of a file the shell wrote, from its block: sudo's text, or polkit's (null /
    // undefined = no /etc/pam.d/polkit-1: the vendor file in force). The fixed row closes
    // the list unless the block ends with closing lines. null when the text was not read
    // or the block is broken; whether it was changed by hand is changes()'s.
    function rows(text, service, facts) {
        if (service === "polkit-1" && (text === null || text === undefined))
            return [PamRuleRules.fixedRow()];
        if (typeof text !== "string")
            return null;
        const block = PamStackRules.ownBlock(text);
        if (block === null)
            return [PamRuleRules.fixedRow()];
        if (!block.complete)
            return null;
        const read = _readItems(_blockItems(block.body), facts);
        return read.closing !== "" ? read.rows : read.rows.concat([PamRuleRules.fixedRow()]);
    }

    // The service's own auth lines, the run that stands for the fixed row: `facts.systemLines`
    // for this service ({ "sudo": […], "polkit-1": […] }), else sudo's `auth include
    // system-auth` (Arch) and polkit's the vendor file's lines that run auth lines (auth
    // lines and @include)
    function _systemLines(service, facts) {
        const given = facts?.systemLines?.[service];
        if (Array.isArray(given))
            return given.map(line => String(line));
        if (service === "sudo")
            return sudoSystemLines;
        return _authSpans(String(facts?.vendorText ?? "")).map(span => span.text);
    }

    // Where the service's own lines stand among `spans` (lines that run auth lines): the
    // index of their last run with nothing but @include lines after it (another phase's
    // lines are brought in that way: Debian's `@include common-account`); -1 when none
    function _systemRun(spans, system) {
        if (system.length === 0)
            return -1;
        for (let i = spans.length - system.length; i >= 0; i--) {
            if (!system.every((line, j) => _sameWords(spans[i + j].text, line)))
                continue;
            const after = spans.slice(i + system.length);
            return after.every(span => PamStackRules.parseLine(span.text).directive !== undefined) ? i : -1;
        }
        return -1;
    }

    // How a file is taken in: { rows, own, raw (how many rows of each), fixed, remove (the
    // physical indices that go: the shell's markers and block, the auth lines that became
    // rows), insertAt (the physical index the shell's block goes before) }
    function _adoptPlan(text, service, facts) {
        const value = String(text ?? "");
        const physical = value.split("\n");
        const block = PamStackRules.ownBlock(value);
        const inBlock = index => block !== null && block.complete && index >= block.beginLine - 1 && index <= block.endLine - 1;
        const remove = new Set();
        physical.forEach((line, i) => {
            if (_isMarker(line.replace(/\r$/, "")) || inBlock(i))
                remove.add(i);
        });
        // Every line outside the block that runs auth lines — an auth line, an @include (it
        // brings auth lines too: the system's run when it is one, else a raw row the checks
        // refuse, never dropped), one that does not parse but is not another phase's; the
        // other phases' lines stay where they are
        const entries = [];
        for (const span of _spans(value)) {
            if (inBlock(span.start))
                continue;
            const parsed = span.unfinished ? { error: "unfinished" } : PamStackRules.parseLine(span.text);
            if (parsed.error !== undefined) {
                const type = (_words(span.text)[0] ?? "").replace(/^-/, "").toLowerCase();
                if (["account", "password", "session"].includes(type))
                    continue;
            } else if (parsed.directive === undefined && parsed.type !== "auth") {
                continue;
            }
            entries.push(span);
        }
        // The service's own lines, and the @include lines after them, stay where they are
        const run = _systemRun(entries, _systemLines(service, facts));
        const fixed = run >= 0;
        const taken = fixed ? entries.slice(0, run) : entries;
        // The block's lines and the taken lines, top to bottom
        const items = [];
        if (block !== null && block.complete)
            items.push(..._blockItems(block.body).map(item => Object.assign({ at: block.beginLine }, item)));
        for (const span of taken) {
            items.push({ at: span.start, text: span.raw, words: _words(span.text) });
            for (let i = span.start; i <= span.end; i++)
                remove.add(i);
        }
        items.sort((first, second) => first.at - second.at);
        const read = _readItems(items, facts);
        const rowsTaken = read.rows.concat(fixed && read.closing === "" ? [PamRuleRules.fixedRow()] : []);
        const starts = entries.map(span => span.start).concat(block !== null && block.complete ? [block.beginLine - 1] : []);
        return {
            rows: rowsTaken,
            own: read.rows.filter(row => row.method !== "raw").length,
            raw: read.rows.filter(row => row.method === "raw").length,
            fixed: fixed && read.closing === "",
            remove,
            insertAt: starts.length > 0 ? Math.min(...starts) : _endIndex(value, physical)
        };
    }

    // A hand-made file taken in: its auth lines top to bottom as rows — the editor's
    // own forms (the block's lines, a reader or key line as the editor writes it, the
    // counted pattern) as rows, everything else as a raw row in its place; the trailing run
    // of the service's own lines as the fixed row. → { rows, own, raw, fixed, hash (the
    // text's sha256: build's `facts.replace`, so a Replace acts only on the text taken in) }.
    // A raw row typed in the editor's own form is read back as that row the same way.
    function adopt(text, service, facts) {
        const plan = _adoptPlan(text, service, facts);
        return { rows: plan.rows, own: plan.own, raw: plan.raw, fixed: plan.fixed, hash: sha256(String(text ?? "")) };
    }

    // ── Changed by hand ──

    // Whether a service's file is still as the shell left it (R6). `text`: the
    // file's text (polkit: /etc/pam.d/polkit-1, null / undefined when there is none).
    // → { known, changed, reasons: [{ reason, line (1-based, 0 for the file), text }] }
    function changes(text, service) {
        const result = { known: true, changed: false, reasons: [] };
        const reason = (name, line) => {
            result.changed = true;
            result.reasons.push({ reason: name, line, text: reasonTexts[name] });
        };
        if (service === "polkit-1" && (text === null || text === undefined))
            return result;
        if (typeof text !== "string")
            return { known: false, changed: false, reasons: [{ reason: "unread", line: 0, text: reasonTexts.unread }] };
        if (service === "polkit-1") {
            const newline = text.indexOf("\n");
            const first = newline < 0 ? text : text.slice(0, newline);
            const written = /^\s*#\s*Written by h2s-shell(?:\s+(\S+))?\s*$/.exec(first.replace(/\r$/, ""));
            if (!written) {
                reason("notOurs", 0);
                return result;
            }
            if ((written[1] ?? "") !== sha256(newline < 0 ? "" : text.slice(newline + 1)))
                reason("fileHash", 1);
        }
        const block = PamStackRules.ownBlock(text);
        if (block !== null && !block.complete)
            reason("block", Math.max(block.beginLine, block.endLine, 0));
        else if (block !== null && block.hash !== sha256(block.body))
            reason("hash", block.beginLine);
        for (const span of _spans(text)) {
            const parsed = span.unfinished ? { error: "unfinished" } : PamStackRules.parseLine(span.text);
            if (parsed.error !== undefined) {
                reason("unparsable", span.start + 1);
                continue;
            }
            const outside = block === null || !block.complete || span.start + 1 < block.beginLine || span.start + 1 > block.endLine;
            if (outside && parsed.type === "auth" && parsed.moduleName === "pam_fprintd.so")
                reason("fingerprint", span.start + 1);
            else if (outside && parsed.type === "auth" && parsed.moduleName === "pam_u2f.so")
                reason("securityKey", span.start + 1);
        }
        return result;
    }

    // The lines that run auth lines (auth lines and @include), as spans
    function _authSpans(text) {
        return _spans(text).filter(span => {
            const parsed = PamStackRules.parseLine(span.text);
            return parsed.directive !== undefined || parsed.type === "auth";
        });
    }

    // Our polkit-1 without its first line (null when it is not ours)
    function _ownRest(text) {
        if (typeof text !== "string" || PamStackRules.writtenBy(text) === null)
            return null;
        const newline = text.indexOf("\n");
        return newline < 0 ? "" : text.slice(newline + 1);
    }

    // Whether polkit's own file changed since ours was written ("Apply again to take it
    // over"): our polkit-1 without its block against the vendor file — every line when ours
    // was built from it, only the auth lines after a Replace (replacedMarker)
    function vendorChanged(text, vendorText) {
        const rest = _ownRest(text);
        if (rest === null || typeof vendorText !== "string")
            return false;
        const block = PamStackRules.ownBlock(rest);
        if (rest.split("\n")[0].trim() !== replacedMarker) {
            const physical = rest.split("\n");
            if (block !== null && block.complete)
                physical.splice(block.beginLine - 1, block.endLine - block.beginLine + 1);
            return physical.join("\n") !== vendorText;
        }
        const outside = _authSpans(rest).filter(span => block === null || !block.complete
                                                || span.start + 1 < block.beginLine || span.start + 1 > block.endLine);
        const vendor = _authSpans(vendorText);
        return outside.length !== vendor.length || outside.some((span, i) => !_sameWords(span.text, vendor[i].text));
    }

    // Whether the system's own lines (adopt's run) stand below the shell's block in `text`
    // and are reached: "" when they are, else why not. The file's own lines between stay
    // as they are, unless one can let the user in alone (sufficient, done on success) or
    // cannot be judged (an include)
    function _systemProblem(text, service, facts) {
        const spans = _authSpans(text);
        const run = _systemRun(spans, _systemLines(service, facts));
        if (run < 0)
            return "The system's own lines are not below the shell's: nothing would ask the system's password.";
        for (const span of spans.slice(0, run)) {
            const parsed = PamStackRules.parseLine(span.text);
            const lets = parsed.module === undefined || parsed.control === "sufficient"
                || (parsed.actions && (parsed.actions.success ?? parsed.actions.default) === "done");
            if (lets)
                return "A line of the file between the shell's lines and the system's can let you in on its own.";
        }
        return "";
    }

    // What the page shows for a service's file: { known, changed, reasons, rows (the rows
    // in force: from the block, or adopt's when changed by hand), adopted (adopt's, when
    // changed), vendorChanged }. `facts.vendorText` for polkit.
    function state(text, service, facts) {
        const found = changes(text, service);
        const adopted = found.changed ? adopt(text, service, facts) : null;
        return {
            known: found.known, changed: found.changed, reasons: found.reasons,
            rows: adopted ? adopted.rows : (found.known ? rows(text, service, facts) : null),
            adopted,
            vendorChanged: service === "polkit-1" && !found.changed && vendorChanged(text, facts?.vendorText)
        };
    }

    // ── Building the file ──

    function _refused(code, text, warnings) {
        return { ok: false, text: null, remove: false, refusals: [{ code, row: -1, id: "", text }], warnings: warnings ?? [] };
    }

    // The new text of a service's file for the rows. `currentText`: the file as it
    // is (sudo: /etc/pam.d/sudo; polkit: /etc/pam.d/polkit-1, null / undefined when there is
    // none). `facts`: PamRuleRules.check's, with `service`, `vendorText` (polkit: the vendor
    // file), `replace` (the user took a hand-made file in: adopt's `hash` of the text taken
    // in; its auth lines go into the block), `takeOver` (polkit: our file rebuilt from the
    // vendor file, dropping what a Replace kept) and optionally `systemLines`. Our polkit-1
    // is otherwise rebuilt from itself, the block swapped in place. → { ok, text, remove
    // (polkit: delete our file, the vendor file is in force again — only when it would be
    // the vendor file), refusals, warnings }. Refused (no text) for rows the checks refuse —
    // a file changed by hand is R6 unless replaced —, a Replace of a text that changed since
    // ("changed"), a fixed row with the service's own lines not below the block
    // ("noSystem", unless the shell writes no lines), a file not read ("unread").
    function build(currentText, rows, facts) {
        const known = facts ?? {};
        const service = String(known.service ?? "");
        if (!PamRuleRules.services.includes(service))
            return _refused("service", "Unknown service.");
        if (service === "sudo" && typeof currentText !== "string")
            return _refused("unread", reasonTexts.unread);
        if (service === "polkit-1" && typeof known.vendorText !== "string")
            return _refused("unread", "polkit's own file could not be read.");
        if (service === "polkit-1" && currentText !== null && currentText !== undefined && typeof currentText !== "string")
            return _refused("unread", reasonTexts.unread);
        const ownFile = service === "sudo" || typeof currentText === "string";
        const replace = ownFile && typeof known.replace === "string" && known.replace !== "";
        if (replace && sha256(String(currentText)) !== known.replace)
            return _refused("changed", "The file changed since it was taken in: read it again.");
        const found = replace ? { changed: false } : changes(currentText, service);
        const checked = PamRuleRules.check(rows, Object.assign({}, known, { changedByHand: known.changedByHand === true || found.changed }));
        if (checked.refusals.length > 0)
            return { ok: false, text: null, remove: false, refusals: checked.refusals, warnings: checked.warnings };
        const lines = blockLines(rows, known);
        let physical, at;
        if (replace) {
            const plan = _adoptPlan(currentText, service, known);
            const all = String(currentText).split("\n");
            physical = all.filter((line, i) => !plan.remove.has(i));
            at = all.filter((line, i) => i < plan.insertAt && !plan.remove.has(i)).length;
        } else {
            const own = service === "polkit-1" && known.takeOver !== true ? _ownRest(currentText) : null;
            const base = service === "sudo" ? currentText : (own ?? known.vendorText);
            physical = base.split("\n");
            const block = PamStackRules.ownBlock(base);
            if (block !== null) {
                at = block.beginLine - 1;
                physical.splice(at, block.endLine - block.beginLine + 1);
            } else {
                const first = _firstAuthIndex(base);
                at = first >= 0 ? first : _endIndex(base, physical);
            }
        }
        // No lines of ours (the fixed row alone) leaves the file's auth lines as they are
        const problem = lines.length > 0 && PamRuleRules.hasFixedRow(rows) ? _systemProblem(physical.slice(at).join("\n"), service, known) : "";
        if (problem !== "")
            return _refused("noSystem", problem, checked.warnings);
        const without = physical.join("\n");
        physical.splice(at, 0, ...blockText(lines));
        let text = physical.join("\n");
        if (service === "polkit-1") {
            if (lines.length === 0 && !replace && without === known.vendorText)
                return { ok: true, text: null, remove: true, refusals: [], warnings: checked.warnings };
            if (replace)
                text = replacedMarker + "\n" + text;
            text = writtenMarker + " " + sha256(text) + "\n" + text;
        }
        return { ok: true, text, remove: false, refusals: [], warnings: checked.warnings };
    }

    // ── NixOS ──

    function _nixString(value) {
        return "\"" + String(value).replace(/\\/g, "\\\\").replace(/"/g, "\\\"").replace(/\$\{/g, "\\${") + "\"";
    }

    readonly property string nixosRawText: "The module's options take a plain auth line with one of the four words."

    // One row as the module's attribute set: { text } or { refusal }
    function _nixRow(row) {
        const details = row?.details ?? {};
        const control = "control = " + _nixString(row?.control) + ";";
        const fields = [];
        if (row?.method === "system")
            return { text: "{ method = \"system\"; }" };
        if (row?.method === "fingerprint") {
            fields.push("method = \"fingerprint\";", control);
            if (details.timeout !== undefined)
                fields.push("timeout = " + details.timeout + ";");
            if (details.tries !== undefined)
                fields.push("tries = " + details.tries + ";");
        } else if (row?.method === "securityKey") {
            fields.push("method = \"securityKey\";", control, "pin = " + (details.pin === true) + ";");
        } else if (row?.method === "password") {
            fields.push("method = \"password\";", control, "counted = " + (details.counted === true) + ";");
        } else if (row?.method === "raw") {
            const text = String(details.text ?? "").replace(/#.*$/, "");
            const line = PamStackRules.parseLine(text);
            const original = _words(text);
            if (line.error !== undefined || line.module === undefined || line.optional || line.controlKind !== "simple"
                    || original.slice(3).some(word => word.startsWith("[")))
                return { refusal: nixosRawText };
            fields.push("method = \"raw\";", "control = " + _nixString(line.control) + ";", "module = " + _nixString(line.module) + ";",
                        "args = [" + line.args.map(argument => " " + _nixString(argument)).join("") + " ];");
        } else {
            return { refusal: PamRuleRules.texts.R4method };
        }
        return { text: "{ " + fields.join(" ") + " }" };
    }

    // The shell's module options for the rows: `rows` one list (sudo and polkit), or
    // with `split` { sudo, polkit } (or "polkit-1") one per service. `facts` as for check
    // (system "nixos" assumed), the other service's rows filled in. → { ok, text,
    // refusals, warnings }, each item with its `service`; no text while one is refused.
    function nixosSnippet(rows, split, facts) {
        const lists = split === true
            ? { "sudo": rows?.sudo, "polkit-1": rows?.["polkit-1"] ?? rows?.polkit }
            : { "sudo": rows, "polkit-1": rows };
        const services = split === true ? ["sudo", "polkit-1"] : ["sudo"];
        const refusals = [], warnings = [];
        const blocks = [];
        for (const service of services) {
            const list = Array.isArray(lists[service]) ? lists[service] : [];
            const known = Object.assign({ system: "nixos" }, facts ?? {}, { service, otherService: lists[PamRuleRules.otherService(service)] });
            const checked = PamRuleRules.check(list, known);
            refusals.push(...checked.refusals.map(item => Object.assign({ service }, item)));
            warnings.push(...checked.warnings.map(item => Object.assign({ service }, item)));
            const entries = [];
            list.forEach((row, i) => {
                const made = _nixRow(row);
                if (made.refusal !== undefined)
                    refusals.push({ service, code: "R8", row: i, id: String(row?.id ?? ""), text: made.refusal });
                else
                    entries.push("    " + made.text);
            });
            const name = split !== true ? "rules" : (service === "sudo" ? "sudo.rules" : "polkit.rules");
            blocks.push(["  " + name + " = ["].concat(entries, ["  ];"]).join("\n"));
        }
        if (refusals.length > 0)
            return { ok: false, text: null, refusals, warnings };
        return { ok: true, text: "programs.h2s-shell.pam = {\n" + blocks.join("\n") + "\n};\n", refusals, warnings };
    }
}
