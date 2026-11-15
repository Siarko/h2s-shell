pragma Singleton

import Quickshell
import QtQuick

// The small decisions of the lock screen's I/O side that are not lock rules but still
// deserve tests (tests/LockIoRulesTest.qml): the driver's queue and how it carries out a
// step, the password fallback, how a Qt key is named for the rules, how a forwarded key
// edits the prompt's field, how a methods-script run is reported, and how long a helper
// process waits before it is started again. Pure: no clock, no process, no
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
    // nixos } — what the driver found out (fallbackFacts).
    function passwordFallback(facts) {
        const system = typeof facts?.systemDirectory === "string" && facts.systemDirectory !== ""
            ? facts.systemDirectory : "/etc/pam.d";
        if (facts?.systemConfigReadable === true)
            return { directory: system, config: "h2s-shell-password" };
        if (facts?.nixos === true)
            return { directory: system, config: "login" };
        return { directory: String(facts?.shellDirectory ?? "") + "/pam", config: "password" };
    }

    // The driver's probe (a `test -r` and a `test -e /etc/NIXOS`, one word per line that
    // holds) → the facts passwordFallback takes. `lines` may be array-like: an array passed
    // through a QML signal's `var` argument arrives as a list wrapper Array.isArray rejects
    function fallbackFacts(lines) {
        const list = lines !== null && typeof lines === "object" && typeof lines.length === "number"
            ? Array.prototype.slice.call(lines) : [];
        const words = list.map(line => String(line).trim());
        return { systemConfigReadable: words.includes("readable"), nixos: words.includes("nixos") };
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

    // ---- The prompt's field ----

    // What a forwardKey effect does to the field (plan, section 7): `text` (printable,
    // never a control character — the rules filter those) is inserted at the cursor; Enter
    // submits; Backspace / Delete delete before / after the cursor; Left / Right / Home /
    // End move it; any other key changes nothing.
    // `field`: { text, cursor } → { text, cursor, submit }
    function editField(field, key, text) {
        const current = typeof field?.text === "string" ? field.text : "";
        const cursor = Math.max(0, Math.min(current.length,
            typeof field?.cursor === "number" && isFinite(field.cursor) ? Math.round(field.cursor) : current.length));
        const result = { text: current, cursor: cursor, submit: false };
        switch (key) {
        case "Enter":
            result.submit = true;
            return result;
        case "Backspace":
            if (cursor > 0) {
                result.text = current.slice(0, cursor - 1) + current.slice(cursor);
                result.cursor = cursor - 1;
            }
            return result;
        case "Delete":
            if (cursor < current.length)
                result.text = current.slice(0, cursor) + current.slice(cursor + 1);
            return result;
        case "Left":
            result.cursor = Math.max(0, cursor - 1);
            return result;
        case "Right":
            result.cursor = Math.min(current.length, cursor + 1);
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
}
