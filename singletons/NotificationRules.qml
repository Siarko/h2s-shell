pragma Singleton

import Quickshell
import QtQuick

// What a notification's card makes of what its sender sent, apart from the text — pure, so
// tests/NotificationRulesTest.qml checks every case without a notification server.
Singleton {
    id: root

    // The states a sender's job can be in, by the hint "x-qs-progress-state"; anything else
    // (or none) is "running"
    readonly property var progressStates: ["running", "done", "failed", "cancelled"]

    // A notification's progress, from its hints (the notification spec's "value", an int
    // 0–100; "x-qs-progress-state", the shell's own):
    //   shown  whether the card shows a bar: a number in "value", and not cancelled
    //   value  for the bar, 0..1; -1 for a run of unknown length (a value below 0); 1 when
    //          the job is done or failed
    //   state  "running" | "done" | "failed" | "cancelled"
    //   tone   the bar's colour in Theme: the accent running, success done, error failed
    // A value that is not a number (absent, a string, NaN) shows no bar.
    function progress(hints) {
        const raw = hints?.value;
        const stateHint = hints?.["x-qs-progress-state"];
        const state = progressStates.includes(stateHint) ? stateHint : "running";
        const tone = state === "done" ? "success" : state === "failed" ? "error" : "accent";
        if (typeof raw !== "number" || isNaN(raw) || state === "cancelled")
            return { shown: false, value: 0, state: state, tone: tone };
        const value = state === "done" || state === "failed" ? 1
            : raw < 0 ? -1 : Math.min(raw, 100) / 100;
        return { shown: true, value: value, state: state, tone: tone };
    }

    // How long a progress bar's wave runs after its value last grew (ms)
    readonly property int progressWaveMs: 10000

    // Whether a card's progress bar waves: its job running and its value grown within
    // `windowMs` (progressWaveMs unless given) before `now` — `grewAt` the time it last grew,
    // 0 never. A sender that stalls stops moving its value, so the wave stops with it.
    function progressWave(state, grewAt, now, windowMs) {
        if (state !== "running" || typeof grewAt !== "number" || grewAt <= 0 || typeof now !== "number")
            return false;
        const window = typeof windowMs === "number" ? windowMs : progressWaveMs;
        return now >= grewAt && now - grewAt < window;
    }

    // Whether running one of a notification's actions also takes its entry away: not for
    // a resident one (the notification spec: it stays after an action)
    function dismissAfterAction(notification): bool {
        return notification?.resident !== true;
    }

    // ---- The shell's own sender: a progress notification's handle (Notifier) ----

    // How long the toast of a handle's notification asks to show, as the expire timeout it
    // sends (ms; the spec's -1: the server decides, 0: stays): "whileRunning" stays while
    // the job starts or runs and leaves the end to the user's time; "brief" (or anything
    // else) always the user's time
    function expireTime(toast, state): int {
        return toast === "whileRunning" && (state === "starting" || state === "running") ? 0 : -1;
    }

    // The states a handle's job may be put in by update(); "done", "failed" and "cancelled"
    // end it
    readonly property var endStates: ["done", "failed", "cancelled"]

    // A progress as sent in the "value" hint: a whole percent 0–100, or -1 for a run of
    // unknown length; anything else that is not a number: 0
    function progressValue(progress): int {
        if (typeof progress !== "number" || isNaN(progress))
            return 0;
        if (progress < 0)
            return -1;
        return Math.min(100, Math.floor(progress));
    }

    // What a handle wants shown differs from what it sent: "none", "progress" (only the
    // value hint, by a whole percent) or "content" (anything else: text, actions, state,
    // an announce). `sent` null: nothing was sent yet, "content"
    function contentChange(sent, wanted): string {
        if (sent === null || sent === undefined)
            return "content";
        const others = ["summary", "body", "state", "announce", "actionsKey"];
        if (others.some(key => sent[key] !== wanted[key]))
            return "content";
        return progressValue(sent.progress) !== progressValue(wanted.progress) ? "progress" : "none";
    }

    // At most one progress-only update per handle in this time (ms)
    readonly property int minUpdateMs: 1000

    // What a handle does next (pure; one call to the server at a time per handle):
    //   handle = { ended, inFlight, id, closeWanted, sent, wanted, lastSentAt, retryAt }
    //     ended        closed, dismissed or unknown: nothing more is sent
    //     inFlight     a call to the server has not answered yet
    //     id           the server's id, 0 while not known
    //     closeWanted  close() was called
    //     sent         the content of the last call answered (null: none yet)
    //     wanted       the content it wants shown now
    //     lastSentAt   when the last call started (ms)
    //     retryAt      after a failed update, not before this time (ms; 0: no wait)
    // → { action: "none" | "show" | "update" | "close" | "later", delayMs }
    //   "later": a progress-only change waits delayMs for minUpdateMs to pass; the newest
    //   wanted content is what goes then (so a burst of updates is one call)
    function nextSend(handle, now) {
        const none = { action: "none", delayMs: 0 };
        if (!handle || handle.ended || handle.inFlight)
            return none;
        if (handle.closeWanted)
            return handle.id > 0 ? { action: "close", delayMs: 0 } : none;
        if (handle.sent === null || handle.sent === undefined)
            return { action: "show", delayMs: 0 };
        if (!(handle.id > 0))
            return none;
        const change = contentChange(handle.sent, handle.wanted);
        if (change === "none")
            return none;
        if (handle.retryAt > now)
            return { action: "later", delayMs: handle.retryAt - now };
        if (change === "progress") {
            const since = now - handle.lastSentAt;
            if (since < minUpdateMs)
                return { action: "later", delayMs: minUpdateMs - since };
        }
        return { action: "update", delayMs: 0 };
    }

    // What a handle makes of the server's answer to a show or an update (pure):
    //   handle = { ended, id }; answerId the id the server answered, 0 for none (the call
    //   failed, or its output was not an id)
    // → { id, closeId, outcome }
    //   outcome "shown"    the first answer: the id is known (the caller then checks that
    //                      the shell's own server holds it, else "unknown")
    //           "updated"  the same id again
    //           "late"     the handle ended meanwhile: whatever the answer made is closed
    //                      (closeId), so a dismissed notification never comes back
    //           "foreign"  another id: the old one was closed meanwhile and the server made
    //                      a new one — closed at once (closeId), the handle ends
    //           "failed"   no id: a first show ends the handle ("unknown"); a failed
    //                      update is sent again after retryDelay (what it sent stays unsent)
    function answered(handle, answerId) {
        const known = handle?.id > 0 ? handle.id : 0;
        const answer = Number.isInteger(answerId) && answerId > 0 ? answerId : 0;
        if (handle?.ended)
            return { id: known, closeId: answer, outcome: "late" };
        if (answer === 0)
            return { id: known, closeId: 0, outcome: "failed" };
        if (known === 0)
            return { id: answer, closeId: 0, outcome: "shown" };
        if (answer !== known)
            return { id: known, closeId: answer, outcome: "foreign" };
        return { id: known, closeId: 0, outcome: "updated" };
    }

    // After `failures` failed updates in a row, how long until the next try (ms): 1 s,
    // doubling, at most 16 s; past maxRetries, -1: the handle gives up ("unknown")
    readonly property int maxRetries: 5

    function retryDelay(failures): int {
        if (!Number.isInteger(failures) || failures < 1)
            return 0;
        if (failures > maxRetries)
            return -1;
        return 1000 * Math.pow(2, failures - 1);
    }

    // The id in gdbus's answer to Notify: "(uint32 7,)" → 7; anything else 0
    function notifyAnswerId(output): int {
        const match = /^\(uint32 ([0-9]{1,10}),\)\s*$/.exec(String(output ?? "").trim());
        if (!match)
            return 0;
        const id = Number(match[1]);
        return id > 0 && id <= 4294967295 ? id : 0;
    }

    // A notification left by a sender that is gone (pure): one of the shell's own progress
    // notifications (it has a run token) from another run of the Notifier (a reload made a
    // new one), still running — its bar would stand still for ever, and a toast that stays
    // would stay for ever
    function orphaned(hints, currentRun): bool {
        const run = hints?.["x-qs-progress-run"];
        if (typeof run !== "string" || run === "" || run === currentRun)
            return false;
        return progress(hints).state === "running";
    }

    // An announce count as the handle sends it in "x-qs-announce" (a whole number from 1,
    // as text); anything else: 0, none
    function announceCount(value): int {
        if (typeof value !== "string" && typeof value !== "number")
            return 0;
        const count = Number(value);
        return Number.isInteger(count) && count > 0 && count <= 2147483647 ? count : 0;
    }

    // Whether a notification's new hints announce it again (pure): its "x-qs-announce"
    // count differs from the one seen before (`previous`, the hint's earlier value, absent
    // for none). Only the shell's own sender is believed — a notification carrying this
    // run's token (x-qs-progress-run, made per Notifier and never handed to a module or an
    // app); an outside app's replacement never brings its toast back
    function announced(previous, hints, currentRun): bool {
        const run = hints?.["x-qs-progress-run"];
        if (typeof run !== "string" || run === "" || run !== currentRun)
            return false;
        const count = announceCount(hints?.["x-qs-announce"]);
        return count > 0 && count !== announceCount(previous);
    }

    // What an announce does to a notification's toast (pure): "restart" — it is on screen,
    // its time starts again; "queue" — it is not, it waits for a slot like a new one;
    // "none" — toasts off, no toast screen, the centre open, it is gone, or it waits
    // already. `state`: { toastsOn, toastScreen, centreOpen, alive, shown, waiting }
    function announceEffect(state): string {
        if (state?.toastsOn !== true || typeof state.toastScreen !== "string" || state.toastScreen === ""
                || state.centreOpen !== false || state.alive !== true)
            return "none";
        if (state.shown === true)
            return "restart";
        return state.waiting === true ? "none" : "queue";
    }

    // ---- GVariant text for gdbus (security-relevant: read line by line) ----
    // A handle's notification is sent with `gdbus call … --method …Notify -- <arguments>`:
    // each argument one argv word in the GVariant text format, which gdbus parses. Text
    // from anywhere (a module, a file's name) goes into it, so every string is written as
    // a single-quoted literal holding printable ASCII only:
    //   - a NUL is dropped (a D-Bus string cannot hold one; GVariant refuses "\u0000")
    //   - a lone surrogate is dropped (not a character; no UTF-8 for it)
    //   - "'" and "\" are escaped with a backslash (the only two that end or start an
    //     escape inside a single-quoted literal)
    //   - printable ASCII (0x20–0x7e) is written as it is
    //   - every other character (controls, DEL, all of non-ASCII) is written as \uXXXX, or
    //     \UXXXXXXXX above the BMP
    // So the word starts with "'" and ends with the matching "'", nothing inside can end
    // it, and no byte of it is a control character or non-ASCII. The argument list starts
    // after "--" anyway, and every word starts with "'", "@" or a type name, never "-".
    // The text is cut at `cap` characters first (code points; default gvariantTextCap),
    // which keeps a word far below the kernel's 128 KiB limit for one argument.
    readonly property int gvariantTextCap: 4000

    function _hex(code, digits): string {
        return code.toString(16).padStart(digits, "0");
    }

    // The code points of a text as a GVariant string holds it: a NUL and lone surrogates
    // dropped, at most `cap` (default gvariantTextCap). A string or a number; else none.
    function _codePoints(text, cap) {
        const source = typeof text === "string" ? text : (typeof text === "number" ? String(text) : "");
        const limit = typeof cap === "number" && cap > 0 ? Math.floor(cap) : gvariantTextCap;
        const codes = [];
        for (let i = 0; i < source.length && codes.length < limit; i++) {
            let code = source.charCodeAt(i);
            if (code >= 0xd800 && code <= 0xdbff) {
                const next = i + 1 < source.length ? source.charCodeAt(i + 1) : 0;
                if (next < 0xdc00 || next > 0xdfff)
                    continue;                                // a lone high surrogate: dropped
                code = 0x10000 + ((code - 0xd800) << 10) + (next - 0xdc00);
                i++;
            } else if (code >= 0xdc00 && code <= 0xdfff) {
                continue;                                    // a lone low surrogate: dropped
            }
            if (code === 0)
                continue;                                    // NUL: dropped
            codes.push(code);
        }
        return codes;
    }

    // The text the server receives for a text sent (what gvariantString writes, read back):
    // so a check on it (a hint key's "x-qs-" prefix) sees what the server will see
    function gvariantText(text, cap): string {
        return String.fromCodePoint(..._codePoints(text, cap));
    }

    function gvariantString(text, cap): string {
        let out = "'";
        for (const code of _codePoints(text, cap)) {
            if (code === 0x27)
                out += "\\'";
            else if (code === 0x5c)
                out += "\\\\";
            else if (code >= 0x20 && code <= 0x7e)
                out += String.fromCharCode(code);
            else if (code <= 0xffff)
                out += "\\u" + _hex(code, 4);
            else
                out += "\\U" + _hex(code, 8);
        }
        return out + "'";
    }

    // A list of strings as an "as" ("@as [...]"); an entry that is not a string or a number
    // becomes ""
    function gvariantStringArray(list): string {
        const items = Array.isArray(list) ? list : [];
        return "@as [" + items.map(item => gvariantString(typeof item === "number" ? String(item) : item)).join(", ") + "]";
    }

    // One hint's value as GVariant text, by its type, or "" when the value does not fit the
    // type (the hint is then left out):
    //   "boolean" true/false only; "byte" an integer 0–255; "int32" an integer in its range;
    //   "int64" a safe integer; "double" a finite number; "string" a string (gvariantString)
    function gvariantValue(type, value): string {
        switch (type) {
        case "boolean":
            return typeof value === "boolean" ? (value ? "true" : "false") : "";
        case "byte":
            return Number.isInteger(value) && value >= 0 && value <= 255 ? "byte " + value : "";
        case "int32":
            return Number.isInteger(value) && value >= -2147483648 && value <= 2147483647 ? "int32 " + value : "";
        case "int64":
            return Number.isSafeInteger(value) ? "int64 " + value : "";
        case "double":
            // String() of a finite number is digits, ".", "-", "e" and "+": GVariant's
            // number syntax
            return typeof value === "number" && isFinite(value) ? "double " + String(value) : "";
        case "string":
            return typeof value === "string" ? gvariantString(value) : "";
        }
        return "";
    }

    // The hints as an "a{sv}": entries [{ key, type, value }] in order, each key a string
    // (written by gvariantString), each value by gvariantValue — an entry whose key is not
    // a non-empty string or whose value does not fit its type is left out; a later entry
    // with the same key, as the server receives it (gvariantText), replaces an earlier one
    function gvariantHints(entries): string {
        const byKey = new Map();
        for (const entry of Array.isArray(entries) ? entries : []) {
            if (typeof entry?.key !== "string")
                continue;
            const key = gvariantText(entry.key);
            const value = gvariantValue(entry.type, entry.value);
            if (key === "" || value === "")
                continue;
            byKey.delete(key);
            byKey.set(key, value);
        }
        const pairs = [];
        for (const [key, value] of byKey)
            pairs.push(gvariantString(key) + ": <" + value + ">");
        return "@a{sv} {" + pairs.join(", ") + "}";
    }

    // A caller's hint value's type, as notify-send's argv infers it (Notifier.command):
    // boolean, an integer (int32, else int64), another number (double), a string;
    // anything else "" (left out)
    function hintType(value): string {
        if (typeof value === "boolean")
            return "boolean";
        if (Number.isInteger(value))
            return value >= -2147483648 && value <= 2147483647 ? "int32" : "int64";
        if (typeof value === "number")
            return "double";
        if (typeof value === "string")
            return "string";
        return "";
    }
}
