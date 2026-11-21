pragma Singleton

import Quickshell
import QtQuick

// The small decisions of the lock screen's I/O side that are not lock rules but still
// deserve tests (tests/LockIoRulesTest.qml): the driver's queue and how it carries out a
// step, the password fallback, how a Qt key is named for the rules, how a forwarded key
// edits the prompt's field, how a methods-script run is reported, how long a helper
// process waits before it is started again, and whether another program locks before sleep
// (SleepLockNotice). Pure: no clock, no process, no
// other singleton. The rules themselves are in LockRules; the driver is Lockscreen.
Singleton {
    id: root

    // ---- The driver's queue ----

    // A dispatch function that handles one item at a time, in order: an item dispatched
    // while one is being handled (by the handler itself, or by a signal it set off) is
    // queued and handled after it — never re-entered. A handler that throws is reported to
    // `onError` and the queue goes on. This is the driver's "one step at a time" guarantee
    // (plan, section 7).
    function serialQueue(handle, onError) {
        const queue = [];
        let running = false;
        return item => {
            queue.push(item);
            if (running)
                return;
            running = true;
            try {
                while (queue.length > 0) {
                    const next = queue.shift();
                    try {
                        handle(next);
                    } catch (error) {
                        if (onError)
                            onError(error, next);
                    }
                }
            } finally {
                running = false;
            }
        };
    }

    // One step's result carried out (plan, section 7: "commit before effects"): the new
    // state stored first — `commit` must not throw, it is a plain assignment — then
    // `prepare` (the per-lock adapters), `publish` (the view), each effect in order through
    // `execute`, and `finish` (the adapters' end). Each of those is guarded on its own: one
    // that throws is reported to `onError(where, error, effect?)` and the rest still run —
    // a view that failed to publish on a lockRequested step must not keep lockCompositor
    // from being executed (the screen would silently never lock).
    // `hooks`: { commit(state), prepare(), publish(), execute(effect), finish(), onError }
    function runStep(result, hooks) {
        hooks.commit(result.state);
        const guarded = (where, action, effect) => {
            try {
                action();
            } catch (error) {
                if (hooks.onError)
                    hooks.onError(where, error, effect);
            }
        };
        if (hooks.prepare)
            guarded("prepare", () => hooks.prepare());
        if (hooks.publish)
            guarded("publish", () => hooks.publish());
        for (const effect of result.effects)
            guarded("effect", () => hooks.execute(effect), effect);
        if (hooks.finish)
            guarded("finish", () => hooks.finish());
    }

    // ---- The password fallback ----

    // The password config the rules fall back to (detection failed, named none, or the
    // detected one could not be used), chosen as scripts/lock-auth-methods.sh chooses the
    // password config: the system-wide `h2s-shell-password` when readable (the NixOS module
    // writes it; elsewhere an administrator may), else on NixOS `login` (the shipped config
    // cannot work there: pam_unix cannot reach its helper), else the shipped pam/password.
    // `facts`: { shellDirectory, systemDirectory (default /etc/pam.d), systemConfigReadable,
    // nixos } — what the driver found out (fallbackFacts, when it is known).
    function passwordFallback(facts) {
        const system = typeof facts?.systemDirectory === "string" && facts.systemDirectory !== ""
            ? facts.systemDirectory : "/etc/pam.d";
        if (facts?.systemConfigReadable === true)
            return { directory: system, config: "h2s-shell-password" };
        if (facts?.nixos === true)
            return { directory: system, config: "login" };
        return { directory: String(facts?.shellDirectory ?? "") + "/pam", config: "password" };
    }

    // One run of the driver's probe → the facts passwordFallback takes, or "not known".
    // The probe is scripts/lock-auth-methods.sh --fallback-facts, or the driver's direct
    // question when the script gives no answer; both print one word per line for what
    // holds ("readable", "nixos") and "answered" last. `run`: { started (it ran at all),
    // exitCode, crashed (killed by a signal), lines }; `lines` may be array-like (an array
    // passed through a QML signal's `var` argument arrives as a list wrapper Array.isArray
    // rejects).
    // → { known: true, systemConfigReadable, nixos }, or { known: false, reason }. Only a
    // run that ended with status 0, said nothing but these words and said "answered" last
    // is an answer: an empty or cut-off one would otherwise read as "not NixOS, no
    // system-wide config", and on NixOS that fallback cannot unlock.
    function fallbackFacts(run) {
        const unknown = reason => ({ known: false, reason: reason });
        if (run?.started !== true)
            return unknown("it could not be started");
        if (run.crashed === true)
            return unknown("it was killed");
        if (run.exitCode !== 0)
            return unknown("it exited with status " + run.exitCode);
        const lines = run.lines;
        const list = lines !== null && typeof lines === "object" && typeof lines.length === "number"
            ? Array.prototype.slice.call(lines) : [];
        const words = list.map(line => String(line).trim()).filter(word => word !== "");
        if (words.length === 0)
            return unknown("it said nothing");
        if (words[words.length - 1] !== "answered")
            return unknown("its answer has no end");
        const facts = words.slice(0, -1);
        if (facts.some(word => word !== "readable" && word !== "nixos"))
            return unknown("its answer cannot be read");
        return { known: true, systemConfigReadable: facts.includes("readable"), nixos: facts.includes("nixos") };
    }

    // The test bed's seam for which system this is, as scripts/lock-auth-methods.sh reads
    // it: H2S_LOCK_SYSTEM=nixos|other, counted only together with H2S_LOCK_SYSTEM_PAM_DIR
    // (against the real /etc/pam.d the machine itself is asked). → "nixos", "other", or ""
    // (ask the machine)
    function systemSeam(pamDirectory, system) {
        if (typeof pamDirectory !== "string" || pamDirectory === "")
            return "";
        return system === "nixos" || system === "other" ? system : "";
    }

    // ---- Keys ----

    // Qt's key codes for the names in LockRules.namedKeys. Return and the keypad's Enter
    // are both "Enter"; Backtab (Shift+Tab) is a Tab
    readonly property var _keyNames: {
        const names = {};
        names[Qt.Key_Escape] = "Escape";
        names[Qt.Key_Return] = "Enter";
        names[Qt.Key_Enter] = "Enter";
        names[Qt.Key_Backspace] = "Backspace";
        names[Qt.Key_Delete] = "Delete";
        names[Qt.Key_Tab] = "Tab";
        names[Qt.Key_Backtab] = "Tab";
        names[Qt.Key_Left] = "Left";
        names[Qt.Key_Right] = "Right";
        names[Qt.Key_Up] = "Up";
        names[Qt.Key_Down] = "Down";
        names[Qt.Key_Home] = "Home";
        names[Qt.Key_End] = "End";
        return names;
    }

    // A Qt key code → its name in LockRules.namedKeys, or "" (a character: it travels in
    // the event's `text`)
    function keyName(qtKey) {
        return _keyNames[qtKey] ?? "";
    }

    // Caps Lock from the keyboards' LEDs (singletons/lock/CapsLockLed.qml): one line per
    // `*::capslock` LED, "led <brightness>" or "led ?" (unreadable) → true when any LED is
    // on (a brightness above 0), false when there is at least one and every one reads 0,
    // null (unknown: no indicator) when there is none, or one could not be read and none is
    // on. Array-likes are accepted (a QML signal's list).
    function capsLockFromLeds(lines) {
        const list = lines !== null && typeof lines === "object" && typeof lines.length === "number" ? Array.from(lines) : [];
        let seen = 0;
        let unreadable = false;
        for (const line of list) {
            const match = /^led (\S*)\s*$/.exec(String(line));
            if (match === null)
                continue;
            seen++;
            if (!/^[0-9]+$/.test(match[1]))
                unreadable = true;
            else if (Number(match[1]) > 0)
                return true;
        }
        return seen === 0 || unreadable ? null : false;
    }

    // Whether a pointer position reported on a lock surface is a real move: not the first
    // one seen (the pointer entering, or the surface appearing under it), and not the same
    // place again (Qt Quick re-sends the hover at the last position when the scene under it
    // changes, every frame of a fade). `last`: { x, y } or null.
    function pointerMoved(last, x, y) {
        return last !== null && typeof last === "object" && (last.x !== x || last.y !== y);
    }

    // ---- The prompt's field ----

    // What a forwardKey effect does to the field (plan, section 7): `text` (printable,
    // never a control character — the rules filter those) is inserted at the cursor; Enter
    // submits; Backspace / Delete delete before / after the cursor; Left / Right / Home /
    // End move it; any other key changes nothing. Positions step by code point, never into
    // a surrogate pair (an emoji, any character beyond the BMP): half a pair is no valid
    // text, and PAM would get an invalid UTF-8 sequence. A cursor handed in inside a pair
    // is taken to the pair's start.
    // `field`: { text, cursor } → { text, cursor, submit }
    function editField(field, key, text) {
        const current = typeof field?.text === "string" ? field.text : "";
        let cursor = Math.max(0, Math.min(current.length,
            typeof field?.cursor === "number" && isFinite(field.cursor) ? Math.round(field.cursor) : current.length));
        if (_splitsPair(current, cursor))
            cursor--;
        const result = { text: current, cursor: cursor, submit: false };
        const before = _pairBefore(current, cursor) ? 2 : 1;
        const after = _pairAt(current, cursor) ? 2 : 1;
        switch (key) {
        case "Enter":
            result.submit = true;
            return result;
        case "Backspace":
            if (cursor > 0) {
                result.text = current.slice(0, cursor - before) + current.slice(cursor);
                result.cursor = cursor - before;
            }
            return result;
        case "Delete":
            if (cursor < current.length)
                result.text = current.slice(0, cursor) + current.slice(cursor + after);
            return result;
        case "Left":
            result.cursor = Math.max(0, cursor - before);
            return result;
        case "Right":
            result.cursor = Math.min(current.length, cursor + after);
            return result;
        case "Home":
            result.cursor = 0;
            return result;
        case "End":
            result.cursor = current.length;
            return result;
        }
        // Defence in depth: the rules never forward a control character, and a key named
        // above never carries text the field should take
        if (typeof text === "string" && text !== "" && (key === "" || key === undefined || key === null)
                && !/[\u0000-\u001f\u007f]/.test(text)) {
            result.text = current.slice(0, cursor) + text + current.slice(cursor);
            result.cursor = cursor + text.length;
        }
        return result;
    }

    function _isHighSurrogate(code) {
        return code >= 0xD800 && code <= 0xDBFF;
    }

    function _isLowSurrogate(code) {
        return code >= 0xDC00 && code <= 0xDFFF;
    }

    // A whole surrogate pair right before / right at `index`; `index` between the two halves
    function _pairBefore(text, index) {
        return index >= 2 && _isLowSurrogate(text.charCodeAt(index - 1)) && _isHighSurrogate(text.charCodeAt(index - 2));
    }

    function _pairAt(text, index) {
        return index + 1 < text.length && _isHighSurrogate(text.charCodeAt(index)) && _isLowSurrogate(text.charCodeAt(index + 1));
    }

    function _splitsPair(text, index) {
        return index > 0 && index < text.length && _isHighSurrogate(text.charCodeAt(index - 1)) && _isLowSurrogate(text.charCodeAt(index));
    }

    // ---- The methods script ----

    // One run of scripts/lock-auth-methods.sh, as the event the rules take. `run`:
    // { started (it ran at all), exitCode, crashed (killed by a signal), lines }.
    // A clean exit is an answer, also an empty one (the rules then take the fallback);
    // anything else is a failure with its reason, which the rules log.
    function detectionEvent(generation, run) {
        const lines = Array.isArray(run?.lines) ? run.lines.filter(line => typeof line === "string") : [];
        if (run?.started !== true)
            return { type: "methodsFailed", generation: generation, reason: "the script could not be started" };
        if (run.crashed === true)
            return { type: "methodsFailed", generation: generation, reason: "the script was killed" };
        if (run.exitCode !== 0)
            return { type: "methodsFailed", generation: generation, reason: "the script exited with status " + run.exitCode };
        return { type: "methodsDetected", generation: generation, lines: lines };
    }

    // ---- Helper processes ----

    // The pause before a long-lived helper (the logind monitor, the sleep inhibitor) is
    // started again after it ended on its own: `minimum` after a run that lasted at least
    // `healthyRun` (it worked, then something went away — logind restarting), else double
    // the previous pause, up to `maximum`. A helper that cannot work at all (no system bus)
    // so costs a process every few minutes, not a busy loop.
    // `table`: { minimum, maximum, healthyRun } in milliseconds.
    function restartDelay(previousDelay, ranMilliseconds, table) {
        const minimum = table.minimum;
        if (typeof ranMilliseconds === "number" && ranMilliseconds >= table.healthyRun)
            return minimum;
        const previous = typeof previousDelay === "number" && previousDelay > 0 ? previousDelay : 0;
        return previous === 0 ? minimum : Math.min(Math.max(previous * 2, minimum), table.maximum);
    }

    // ---- The lock marker (Lockscreen, "Recovery") ----

    // The start probe's lines → { private (XDG_RUNTIME_DIR is this user's 0700 directory),
    // key (this compositor session's, "" when it could not be worked out), marker (the
    // marker's first line, "" for none) }. Array-likes are accepted (a QML signal's list).
    function markerFacts(lines) {
        const facts = { private: false, key: "", marker: "" };
        const list = lines !== null && typeof lines === "object" && typeof lines.length === "number" ? Array.from(lines) : [];
        for (const line of list) {
            if (typeof line !== "string")
                continue;
            if (line === "private yes")
                facts.private = true;
            else if (line.startsWith("key ") && facts.key === "")
                facts.key = line.slice(4).trim();
            else if (line.startsWith("marker ") && facts.marker === "")
                facts.marker = line.slice(7).trim();
        }
        return facts;
    }

    // What Hyprland says before a lock is taken back: the output of `hyprctl -j getoption
    // misc:allow_session_lock_restore` and `hyprctl -j locked`, one after the other →
    // { restoreAllowed, locked } (true / false, null when not said). A lock is refused for
    // sure exactly when the session is locked and restoring is not allowed — and Hyprland
    // 0.57 then also kills the client that asked (it destroys the refused lock at once, and
    // Quickshell's next request on it is a protocol error: plan, section 7, "Restart").
    function hyprlandLockFacts(output) {
        const text = String(output ?? "");
        const option = /"option"\s*:\s*"misc:allow_session_lock_restore"[^}]*?"(?:bool|int)"\s*:\s*(true|false|0|1)\b/.exec(text);
        const locked = /"locked"\s*:\s*(true|false)\b/.exec(text);
        return {
            restoreAllowed: option === null ? null : option[1] === "true" || option[1] === "1",
            locked: locked === null ? null : locked[1] === "true"
        };
    }

    function lockSurelyRefused(facts) {
        return facts?.restoreAllowed === false && facts?.locked === true;
    }

    // What a starting shell does about the marker it found, `key` being this compositor
    // session's ("?" while unknown): "lock" — it says locked, for this session (or one of
    // the two keys is unknown: fail closed, a lock too many rather than one too few);
    // "stale" — locked, but for another compositor session (the compositor died or was
    // stopped since: a new session is a new login, nothing to take back); "none" —
    // unlocked, nothing, or anything else.
    function markerDecision(marker, key) {
        const fields = String(marker ?? "").trim().split(/\s+/);
        if (fields[0] !== "locked")
            return "none";
        const written = fields.length > 1 ? fields.slice(1).join(" ") : "?";
        const current = typeof key === "string" && key !== "" ? key : "?";
        return written === "?" || current === "?" || written === current ? "lock" : "stale";
    }

    // The notice of a launcher that gave up (scripts/launch.sh, "Restarts while locked"):
    // `count` is H2S_SHELL_LOCK_NOTICE as the next launcher handed it on (the restarts made
    // while the session stayed locked), `runtimeDirectory` XDG_RUNTIME_DIR, where the
    // launcher's log is. → { summary, body } for one notification, or null when there is
    // nothing to say: no count, or not a number from 1 to 999 (anything else in that
    // variable is not the launcher's). The log's path is said only when it is an absolute
    // path on one line, at most 200 characters.
    function lockNotice(count, runtimeDirectory) {
        const text = typeof count === "string" ? count : "";
        if (!/^[0-9]{1,3}$/.test(text) || Number(text) < 1)
            return null;
        const restarts = Number(text);
        const directory = typeof runtimeDirectory === "string" ? runtimeDirectory : "";
        const pathUsable = directory.startsWith("/") && directory.length <= 200 && !/[\u0000-\u001f\u007f]/.test(directory);
        return {
            summary: "The shell stopped while locked",
            body: "It stopped again after " + restarts + (restarts === 1 ? " restart" : " restarts")
                + " and was left locked. "
                + (pathUsable ? "Log: " + directory.replace(/\/+$/, "") + "/h2s-shell-launcher.log" : "Log: h2s-shell-launcher.log in XDG_RUNTIME_DIR")
        };
    }

    // ---- Other lockers before sleep (SleepLockNotice) ----
    // Whether something besides this shell locks the screen before the computer sleeps, read
    // from what logind knows about every system: the sleep "delay" inhibitors, which a
    // program takes to act before sleep. A locker of the user's own session holds one —
    // GNOME Shell, KDE's screen locker, xss-lock, swayidle with a before-sleep command,
    // hypridle — beside services that hold one for other work (NetworkManager, UPower). The
    // list says who holds each and why, not what it will do: a holder counts as a locker
    // by its name or by a reason that says it locks the screen. hypridle, swayidle and
    // xss-lock run whatever they are given — often `loginctl lock-session`, logind's Lock,
    // which this shell follows (no race at all), or nothing that locks — so they are only
    // possible lockers, whatever their reason says.

    // Holders that lock the screen before sleep when they hold a sleep inhibitor at all
    readonly property var sleepLockerNames: ["light-locker", "xfce4-screensaver",
        "cinnamon-screensaver", "mate-screensaver", "gnome shell", "screen locker", "xscreensaver",
        "xsecurelock", "hyprlock", "swaylock"]
    // Holders that run a command of the user's before sleep, which may lock by itself, ask
    // logind to lock (this shell then locks, in step with sleep) or not lock at all
    readonly property var possibleSleepLockerNames: ["hypridle", "swayidle", "xss-lock"]

    // logind's ListInhibitors as `gdbus call` prints it (a GVariant:
    // `([('sleep', 'who', "why", 'delay', uint32 1000, uint32 42), …],)`, `(@a(ssssuu) [],)`
    // for none) → [{ what, who, why, mode, uid, pid }], or null for anything else.
    function parseInhibitors(output) {
        if (typeof output !== "string" || output.length > 1000000)
            return null;
        const text = output.trim();
        let at = 0;
        const space = () => { while (at < text.length && /\s/.test(text[at])) at++; };
        const take = token => {
            space();
            if (text.startsWith(token, at)) {
                at += token.length;
                return true;
            }
            return false;
        };
        const string = () => {
            space();
            const quote = text[at];
            if (quote !== "'" && quote !== "\"")
                return null;
            let value = "";
            for (at++; at < text.length; at++) {
                const character = text[at];
                if (character === quote) {
                    at++;
                    return value;
                }
                if (character !== "\\") {
                    value += character;
                    continue;
                }
                const escaped = text[++at];
                const simple = { n: "\n", t: "\t", r: "\r", a: "\u0007", b: "\b", f: "\f", v: "\v" };
                if (escaped === "u" || escaped === "U") {
                    const length = escaped === "u" ? 4 : 8;
                    const hex = text.substr(at + 1, length);
                    if (!new RegExp("^[0-9a-fA-F]{" + length + "}$").test(hex))
                        return null;
                    const code = parseInt(hex, 16);
                    if (code > 0x10ffff)
                        return null;
                    value += String.fromCodePoint(code);
                    at += length;
                } else if (escaped !== undefined) {
                    value += simple[escaped] ?? escaped;
                } else {
                    return null;
                }
            }
            return null;
        };
        const number = () => {
            take("uint32");
            space();
            const match = /^[0-9]{1,10}/.exec(text.slice(at));
            if (!match)
                return null;
            at += match[0].length;
            return Number(match[0]);
        };
        if (!take("("))
            return null;
        take("@a(ssssuu)");
        if (!take("["))
            return null;
        const inhibitors = [];
        if (!take("]")) {
            do {
                if (!take("("))
                    return null;
                const what = string();
                if (what === null || !take(","))
                    return null;
                const who = string();
                if (who === null || !take(","))
                    return null;
                const why = string();
                if (why === null || !take(","))
                    return null;
                const mode = string();
                if (mode === null || !take(","))
                    return null;
                const uid = number();
                if (uid === null || !take(","))
                    return null;
                const pid = number();
                if (pid === null || !take(")"))
                    return null;
                inhibitors.push({ what: what, who: who, why: why, mode: mode, uid: uid, pid: pid });
            } while (take(","));
            if (!take("]"))
                return null;
        }
        take(",");
        if (!take(")"))
            return null;
        space();
        return at === text.length ? inhibitors : null;
    }

    // A holder's name as it may be shown: one line, no control characters, at most 40
    // characters ("" when nothing is left)
    function lockerName(who) {
        const text = typeof who === "string" ? who.replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]+/g, " ").replace(/\s+/g, " ").trim() : "";
        return text.length > 40 ? text.slice(0, 39) + "…" : text;
    }

    // The inhibitors read (parseInhibitors) and this user's uid → { state, names }:
    // "present" (a locker of this user holds a sleep delay inhibitor; `names` says which),
    // "possible" (only holders that may lock), "none" (the list was read and holds neither),
    // "unknown" (no list, no uid: a failed read is never "none"). The shell's own inhibitor
    // (who "h2s-shell") and other users' (a greeter's, another session's) do not count.
    // `names`: shown names, sorted, at most 3.
    function sleepLockers(inhibitors, uid) {
        if (!Array.isArray(inhibitors) || typeof uid !== "number" || !Number.isInteger(uid) || uid < 0)
            return { state: "unknown", names: [] };
        const present = new Set();
        const possible = new Set();
        for (const inhibitor of inhibitors) {
            if (inhibitor?.uid !== uid || inhibitor.mode !== "delay" || typeof inhibitor.what !== "string"
                    || !inhibitor.what.split(":").includes("sleep"))
                continue;
            const who = lockerName(inhibitor.who);
            const key = who.toLowerCase();
            if (key === "h2s-shell")
                continue;
            const why = typeof inhibitor.why === "string" ? inhibitor.why : "";
            if (possibleSleepLockerNames.includes(key))
                possible.add(who);
            else if (sleepLockerNames.includes(key) || (/\block/i.test(why) && /\b(screen|session)\b/i.test(why)))
                present.add(who || "another program");
        }
        const names = set => Array.from(set).sort().slice(0, 3);
        if (present.size > 0)
            return { state: "present", names: names(present) };
        if (possible.size > 0)
            return { state: "possible", names: names(possible) };
        return { state: "none", names: [] };
    }

    // The reader's whole output — `id -u`'s line, then gdbus's answer — → sleepLockers()
    function sleepLockersFromOutput(output) {
        const text = typeof output === "string" ? output : "";
        const newline = text.indexOf("\n");
        const first = (newline < 0 ? text : text.slice(0, newline)).trim();
        const uid = /^[0-9]{1,10}$/.test(first) ? Number(first) : null;
        return sleepLockers(newline < 0 ? null : parseInhibitors(text.slice(newline + 1)), uid);
    }

    // An array, or an array-like (a list that came through a QML signal), as an array
    function _list(value) {
        return Array.isArray(value) ? value : value && typeof value === "object" && typeof value.length === "number" ? Array.from(value) : [];
    }

    // How an outcome reads in the log, e.g. "present: swayidle" (logged when it changes)
    function sleepLockersText(lockers) {
        const state = ["present", "possible", "none"].includes(lockers?.state) ? lockers.state : "unknown";
        const names = _list(lockers?.names);
        return names.length > 0 ? state + ": " + names.join(", ") : state;
    }

    // What the user is told, given the lockers read and the setting (true / false), → null or
    // { key, summary, body }: two lockers race when the setting is on and another locks; the
    // screen stays unlocked through sleep when it is off and nothing locks it. A possible
    // locker or an unknown read says nothing.
    function sleepLockNotice(lockers, lockOnSleep) {
        const names = _list(lockers?.names).map(lockerName).filter(name => name !== "");
        if (lockers?.state === "present" && lockOnSleep === true && names.length > 0) {
            return {
                key: "both:" + names.join(","),
                summary: "Two programs lock the screen before sleep",
                body: "This shell locks it, and " + names.join(", ") + (names.length === 1 ? " does" : " do")
                    + " too. One lock is enough."
            };
        }
        if (lockers?.state === "none" && lockOnSleep === false) {
            return {
                key: "none",
                summary: "The screen stays unlocked during sleep",
                body: "Nothing locks it before the computer sleeps. Turn on \"Lock before the computer sleeps\" in Settings → Lockscreen."
            };
        }
        return null;
    }

    // One decision after a read (`fromRead` true) or a change of the setting or of the lock:
    // `memory` is { key: the notice last given ("" for none; kept in the config, so a notice
    // is given once, not at every start), quiet: reads in a row with nothing to say }. →
    // { notice (null, or sleepLockNotice's to give now), memory (to keep) }. An unknown read
    // changes nothing but the count; a different notice is given at once; the key is forgotten
    // only after two reads in a row with nothing to say — so the same problem coming back
    // later is told again, but not after one read that blinked.
    function sleepNoticeStep(memory, lockers, lockOnSleep, fromRead) {
        const key = typeof memory?.key === "string" ? memory.key : "";
        const quiet = Number.isInteger(memory?.quiet) && memory.quiet > 0 ? memory.quiet : 0;
        if (!["present", "possible", "none"].includes(lockers?.state))
            return { notice: null, memory: { key: key, quiet: fromRead === true ? 0 : quiet } };
        const notice = sleepLockNotice(lockers, lockOnSleep);
        if (notice === null) {
            const count = fromRead === true ? quiet + 1 : quiet;
            return { notice: null, memory: count >= 2 ? { key: "", quiet: count } : { key: key, quiet: count } };
        }
        if (notice.key === key)
            return { notice: null, memory: { key: key, quiet: 0 } };
        return { notice: notice, memory: { key: notice.key, quiet: 0 } };
    }
}
