import QtQuick
import qs.singletons

// The lock screen's I/O-side helpers (singletons/LockIoRules.qml): the driver's queue, key
// names, the field's editing by forwarded keys, the methods script's report, the helper
// processes' restart pause, and the recovery's lock marker and Hyprland probe.
TestCase {
    suiteName: "LockIoRules"

    function run() {
        const rules = LockIoRules;

        // --- the queue: one at a time, in order, never re-entered ---
        {
            const handled = [];
            let depth = 0;
            let maxDepth = 0;
            let dispatch = null;
            dispatch = rules.serialQueue(item => {
                depth++;
                maxDepth = Math.max(maxDepth, depth);
                handled.push(item);
                // An effect that raises events synchronously
                if (item === "a") {
                    dispatch("b");
                    dispatch("c");
                }
                if (item === "b")
                    dispatch("d");
                depth--;
            });
            dispatch("a");
            assertEqual(handled.join(""), "abcd", "events raised while handling are handled after, in the order raised");
            assertEqual(maxDepth, 1, "the handler is never re-entered");
            dispatch("e");
            assertEqual(handled.join(""), "abcde", "the queue works again afterwards");
        }
        {
            const handled = [];
            const errors = [];
            const dispatch = rules.serialQueue(item => {
                handled.push(item);
                if (item === "boom")
                    throw new Error("x");
            }, (error, item) => errors.push(item));
            dispatch("boom");
            dispatch("after");
            assertEqual(handled.join(","), "boom,after", "a handler that throws does not stop the queue");
            assertEqual(errors.join(","), "boom", "the error is reported with its item");
        }

        // --- carrying out a step: commit first, each part guarded ---
        {
            const order = [];
            const errors = [];
            let committed = null;
            const hooks = {
                commit: state => { committed = state; order.push("commit"); },
                prepare: () => order.push("prepare"),
                publish: () => { order.push("publish"); throw new Error("view broke"); },
                execute: effect => {
                    order.push(effect.type);
                    if (effect.type === "bad")
                        throw new Error("effect broke");
                },
                finish: () => order.push("finish"),
                onError: (where, error, effect) => errors.push(where + (effect ? ":" + effect.type : ""))
            };
            rules.runStep({ state: { phase: "locking" }, effects: [{ type: "lockCompositor" }, { type: "bad" }, { type: "announceLocked" }] }, hooks);
            assertEqual(order.join(","), "commit,prepare,publish,lockCompositor,bad,announceLocked,finish",
                        "runStep: the state committed first; publishing that throws does not keep the effects (lockCompositor) from running");
            assertEqual(committed.phase, "locking", "runStep: the new state is stored");
            assertEqual(errors.join(","), "publish,effect:bad", "runStep: each failure is reported with where it happened");
            const throwingPrepare = [];
            rules.runStep({ state: {}, effects: [{ type: "lockCompositor" }] }, {
                commit: () => {}, prepare: () => { throw new Error("x"); }, execute: effect => throwingPrepare.push(effect.type)
            });
            assertEqual(throwingPrepare.join(","), "lockCompositor", "runStep: a failing prepare (the adapters) does not stop the effects either, even without onError");
        }

        // --- the password fallback ---
        const fallbackOf = facts => JSON.stringify(rules.passwordFallback(facts));
        assertEqual(fallbackOf({ shellDirectory: "/shell", systemDirectory: "/etc/pam.d", systemConfigReadable: true, nixos: true }),
                    JSON.stringify({ directory: "/etc/pam.d", config: "h2s-shell-password" }), "fallback: the system-wide config when readable (NixOS)");
        assertEqual(fallbackOf({ shellDirectory: "/shell", systemDirectory: "/etc/pam.d", systemConfigReadable: true, nixos: false }),
                    JSON.stringify({ directory: "/etc/pam.d", config: "h2s-shell-password" }), "fallback: … also elsewhere");
        assertEqual(fallbackOf({ shellDirectory: "/shell", systemDirectory: "/etc/pam.d", systemConfigReadable: false, nixos: true }),
                    JSON.stringify({ directory: "/etc/pam.d", config: "login" }), "fallback: NixOS without it: login (the shipped one cannot work there)");
        assertEqual(fallbackOf({ shellDirectory: "/shell", systemDirectory: "/etc/pam.d", systemConfigReadable: false, nixos: false }),
                    JSON.stringify({ directory: "/shell/pam", config: "password" }), "fallback: elsewhere without it: the shipped pam/password");
        assertEqual(fallbackOf({ shellDirectory: "/shell", systemDirectory: "/tmp/test-pam", systemConfigReadable: false, nixos: true }),
                    JSON.stringify({ directory: "/tmp/test-pam", config: "login" }), "fallback: the system directory as given (the test bed's seam)");
        assertEqual(fallbackOf({ shellDirectory: "/shell" }), JSON.stringify({ directory: "/shell/pam", config: "password" }),
                    "fallback: nothing known yet: the shipped one");
        assertEqual(fallbackOf({ shellDirectory: "/shell", systemDirectory: "", systemConfigReadable: true }),
                    JSON.stringify({ directory: "/etc/pam.d", config: "h2s-shell-password" }), "fallback: no system directory given: /etc/pam.d");
        // --- the fallback probe's answer: an answer only when it is whole ---
        const factsOf = (lines, run) => JSON.stringify(rules.fallbackFacts(Object.assign({ started: true, exitCode: 0, crashed: false, lines: lines }, run ?? {})));
        const known = (readable, nixos) => JSON.stringify({ known: true, systemConfigReadable: readable, nixos: nixos });
        const unknown = reason => JSON.stringify({ known: false, reason: reason });
        assertEqual(factsOf(["readable", "nixos", "answered"]), known(true, true), "fallback facts: both");
        assertEqual(factsOf(["nixos\n", "answered"]), known(false, true), "fallback facts: NixOS only");
        assertEqual(factsOf(["readable", "answered"]), known(true, false), "fallback facts: the system-wide config only");
        assertEqual(factsOf(["answered"]), known(false, false), "fallback facts: neither holds — said, not assumed");
        assertEqual(factsOf(["readable", "", "answered", ""]), known(true, false), "fallback facts: blank lines do not count");
        assertEqual(factsOf({ length: 3, 0: "readable", 1: "nixos", 2: "answered" }), known(true, true),
                    "fallback facts: an array-like (what a QML signal's var argument delivers) is read too");
        assertEqual(factsOf([]), unknown("it said nothing"), "fallback facts: an empty answer is not known");
        assertEqual(factsOf(null), unknown("it said nothing"), "fallback facts: no lines at all is not known");
        assertEqual(factsOf(["nixos"]), unknown("its answer has no end"), "fallback facts: the final word missing (NixOS) is not known");
        assertEqual(factsOf(["readable", "nixos"]), unknown("its answer has no end"), "fallback facts: the final word missing (both) is not known");
        assertEqual(factsOf(["answered", "nixos"]), unknown("its answer has no end"), "fallback facts: the final word must be last");
        assertEqual(factsOf(["bash: line 3: syntax error", "answered"]), unknown("its answer cannot be read"), "fallback facts: garbage is not known");
        assertEqual(factsOf(["NIXOS", "answered"]), unknown("its answer cannot be read"), "fallback facts: a word it does not know is not known");
        assertEqual(factsOf(["readable", "nixos", "answered"], { exitCode: 126 }), unknown("it exited with status 126"),
                    "fallback facts: a non-zero exit is not known, whatever it said");
        assertEqual(factsOf(["readable", "answered"], { crashed: true }), unknown("it was killed"), "fallback facts: a killed run is not known");
        assertEqual(factsOf([], { started: false, exitCode: -1 }), unknown("it could not be started"), "fallback facts: a run that could not be started is not known");
        assertEqual(JSON.stringify(rules.fallbackFacts(undefined)), unknown("it could not be started"), "fallback facts: no run is not known");
        // The direct question (the driver's own, when the script gives no answer) answers
        // in the same words; what follows from its answers on each system
        const fallbackFrom = lines => {
            const facts = rules.fallbackFacts({ started: true, exitCode: 0, crashed: false, lines: lines });
            return facts.known ? fallbackOf({ shellDirectory: "/shell", systemDirectory: "/etc/pam.d", systemConfigReadable: facts.systemConfigReadable, nixos: facts.nixos }) : "unknown";
        };
        assertEqual(fallbackFrom(["nixos", "answered"]), JSON.stringify({ directory: "/etc/pam.d", config: "login" }), "the direct answer on NixOS: login");
        assertEqual(fallbackFrom(["readable", "nixos", "answered"]), JSON.stringify({ directory: "/etc/pam.d", config: "h2s-shell-password" }),
                    "the direct answer on NixOS with the system-wide config: that one");
        assertEqual(fallbackFrom(["answered"]), JSON.stringify({ directory: "/shell/pam", config: "password" }), "the direct answer elsewhere: the shipped one");
        assertEqual(fallbackFrom(["readable", "answered"]), JSON.stringify({ directory: "/etc/pam.d", config: "h2s-shell-password" }),
                    "the direct answer elsewhere with the system-wide config: that one");
        assertEqual(fallbackFrom([]), "unknown", "the direct question without an answer: nothing follows");
        // The test bed's seam for the system counts only with its own PAM directory
        assertEqual(rules.systemSeam("/tmp/test-pam", "nixos"), "nixos", "system seam: nixos");
        assertEqual(rules.systemSeam("/tmp/test-pam", "other"), "other", "system seam: other");
        assertEqual(rules.systemSeam("/tmp/test-pam", "neither"), "", "system seam: a value it does not know: the machine is asked");
        assertEqual(rules.systemSeam("/tmp/test-pam", null), "", "system seam: not set: the machine is asked");
        assertEqual(rules.systemSeam("", "nixos"), "", "system seam: without the PAM directory seam it does not count");
        assertEqual(rules.systemSeam(null, "nixos"), "", "system seam: … also when that is not set at all");

        // --- key names ---
        assertEqual(rules.keyName(Qt.Key_Return), "Enter", "Return is Enter");
        assertEqual(rules.keyName(Qt.Key_Enter), "Enter", "the keypad's Enter is Enter");
        assertEqual(rules.keyName(Qt.Key_Escape), "Escape", "Escape");
        assertEqual(rules.keyName(Qt.Key_Backspace), "Backspace", "Backspace");
        assertEqual(rules.keyName(Qt.Key_Delete), "Delete", "Delete");
        assertEqual(rules.keyName(Qt.Key_Backtab), "Tab", "Shift+Tab is a Tab");
        assertEqual(rules.keyName(Qt.Key_A), "", "a letter is no named key (it travels as text)");
        assertEqual(rules.keyName(Qt.Key_Space), "", "space is a character");
        const names = [Qt.Key_Escape, Qt.Key_Return, Qt.Key_Backspace, Qt.Key_Delete, Qt.Key_Tab, Qt.Key_Left,
                       Qt.Key_Right, Qt.Key_Up, Qt.Key_Down, Qt.Key_Home, Qt.Key_End].map(key => rules.keyName(key));
        assert(names.every(name => LockRules.namedKeys.includes(name)), "every name is one of LockRules.namedKeys");
        assertEqual(new Set(names).size, LockRules.namedKeys.length, "and every named key has a Qt key");

        // --- the field ---
        const edit = (text, cursor, key, typed) => JSON.stringify(rules.editField({ text: text, cursor: cursor }, key, typed));
        assertEqual(edit("ab", 2, "", "c"), JSON.stringify({ text: "abc", cursor: 3, submit: false }), "a character goes in at the cursor");
        assertEqual(edit("ac", 1, "", "b"), JSON.stringify({ text: "abc", cursor: 2, submit: false }), "also in the middle");
        assertEqual(edit("", 0, "", "xyz"), JSON.stringify({ text: "xyz", cursor: 3, submit: false }), "several characters at once");
        assertEqual(edit("abc", 3, "Backspace", ""), JSON.stringify({ text: "ab", cursor: 2, submit: false }), "Backspace deletes before the cursor");
        assertEqual(edit("abc", 0, "Backspace", ""), JSON.stringify({ text: "abc", cursor: 0, submit: false }), "Backspace at the start does nothing");
        assertEqual(edit("abc", 1, "Delete", ""), JSON.stringify({ text: "ac", cursor: 1, submit: false }), "Delete deletes after the cursor");
        assertEqual(edit("abc", 3, "Delete", ""), JSON.stringify({ text: "abc", cursor: 3, submit: false }), "Delete at the end does nothing");
        assertEqual(edit("abc", 2, "Left", ""), JSON.stringify({ text: "abc", cursor: 1, submit: false }), "Left");
        assertEqual(edit("abc", 0, "Left", ""), JSON.stringify({ text: "abc", cursor: 0, submit: false }), "Left stops at the start");
        assertEqual(edit("abc", 1, "Right", ""), JSON.stringify({ text: "abc", cursor: 2, submit: false }), "Right");
        assertEqual(edit("abc", 3, "Right", ""), JSON.stringify({ text: "abc", cursor: 3, submit: false }), "Right stops at the end");
        assertEqual(edit("abc", 2, "Home", ""), JSON.stringify({ text: "abc", cursor: 0, submit: false }), "Home");
        assertEqual(edit("abc", 0, "End", ""), JSON.stringify({ text: "abc", cursor: 3, submit: false }), "End");
        assertEqual(edit("abc", 3, "Enter", ""), JSON.stringify({ text: "abc", cursor: 3, submit: true }), "Enter submits, the text untouched");
        assertEqual(edit("", 0, "Enter", ""), JSON.stringify({ text: "", cursor: 0, submit: true }), "Enter on an empty field still submits (the rules refuse it)");
        assertEqual(edit("abc", 3, "Tab", "\t"), JSON.stringify({ text: "abc", cursor: 3, submit: false }), "Tab does nothing");
        assertEqual(edit("abc", 3, "Escape", ""), JSON.stringify({ text: "abc", cursor: 3, submit: false }), "Escape does nothing in the field");
        assertEqual(edit("abc", 3, "", "\u0001"), JSON.stringify({ text: "abc", cursor: 3, submit: false }), "a control character is not inserted");
        assertEqual(edit("abc", 3, "Up", "x"), JSON.stringify({ text: "abc", cursor: 3, submit: false }), "a named key's text is not inserted");
        assertEqual(edit("abc", 99, "", "d"), JSON.stringify({ text: "abcd", cursor: 4, submit: false }), "a cursor past the end is clamped");
        assertEqual(JSON.stringify(rules.editField(null, "", "a")), JSON.stringify({ text: "a", cursor: 1, submit: false }), "no field is an empty one");
        {
            // wrong character, Backspace, the password, Enter — the harness's typing test
            let field = { text: "", cursor: 0, submit: false };
            for (const [key, typed] of [["", "x"], ["Backspace", ""], ["", "p"], ["", "w"], ["Enter", ""]])
                field = rules.editField(field, key, typed);
            assertEqual(JSON.stringify(field), JSON.stringify({ text: "pw", cursor: 2, submit: true }), "a typo corrected, then Enter");
        }
        // A character beyond the BMP (an emoji) is two UTF-16 units: never split (PAM would
        // get half a pair, an invalid UTF-8 sequence)
        const emoji = "😀";
        const wellFormed = text => !/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(^|[^\uD800-\uDBFF])[\uDC00-\uDFFF]/.test(text);
        assertEqual(edit("a" + emoji, 3, "Backspace", ""), JSON.stringify({ text: "a", cursor: 1, submit: false }),
                    "Backspace after an emoji deletes all of it");
        assertEqual(edit(emoji + "a", 0, "Delete", ""), JSON.stringify({ text: "a", cursor: 0, submit: false }),
                    "Delete before an emoji deletes all of it");
        assertEqual(edit("a" + emoji + "b", 3, "Left", ""), JSON.stringify({ text: "a" + emoji + "b", cursor: 1, submit: false }),
                    "Left steps over an emoji");
        assertEqual(edit("a" + emoji + "b", 1, "Right", ""), JSON.stringify({ text: "a" + emoji + "b", cursor: 3, submit: false }),
                    "Right steps over an emoji");
        assertEqual(JSON.stringify(rules.editField(rules.editField({ text: emoji, cursor: 2 }, "Left", ""), "", "x")),
                    JSON.stringify({ text: "x" + emoji, cursor: 1, submit: false }), "Left then x: the x goes before the emoji, not inside it");
        assertEqual(edit(emoji, 1, "", "x"), JSON.stringify({ text: "x" + emoji, cursor: 1, submit: false }),
                    "a cursor handed in inside a pair is taken to its start");
        assertEqual(edit(emoji, 1, "Backspace", ""), JSON.stringify({ text: emoji, cursor: 0, submit: false }),
                    "… so Backspace there deletes nothing of it");
        assertEqual(edit("a" + emoji + emoji, 5, "Backspace", ""), JSON.stringify({ text: "a" + emoji, cursor: 3, submit: false }),
                    "two emoji: one Backspace, one emoji");
        assertEqual(edit("\uD83D", 1, "Backspace", ""), JSON.stringify({ text: "", cursor: 0, submit: false }),
                    "a lone half (never typed, but) is one unit");
        {
            // Every key from every position of a mixed text keeps the text well formed
            const text = "a" + emoji + "é" + emoji;
            let allWellFormed = true;
            for (let cursor = 0; cursor <= text.length; cursor++) {
                for (const [key, typed] of [["Backspace", ""], ["Delete", ""], ["Left", ""], ["Right", ""], ["", "x"]]) {
                    let field = rules.editField({ text: text, cursor: cursor }, key, typed);
                    field = rules.editField(field, "", "y");
                    if (!wellFormed(field.text))
                        allWellFormed = false;
                }
            }
            assert(allWellFormed, "every edit from every cursor position leaves well-formed text (no half pairs)");
        }

        // --- the methods script's report ---
        const detected = run => JSON.stringify(rules.detectionEvent(7, run));
        assertEqual(detected({ started: true, exitCode: 0, crashed: false, lines: ["password\t/etc/pam.d\tlogin"] }),
                    JSON.stringify({ type: "methodsDetected", generation: 7, lines: ["password\t/etc/pam.d\tlogin"] }), "a clean exit is an answer");
        assertEqual(detected({ started: true, exitCode: 0, crashed: false, lines: [] }),
                    JSON.stringify({ type: "methodsDetected", generation: 7, lines: [] }), "an empty answer is an answer (the rules take the fallback)");
        assertEqual(rules.detectionEvent(7, { started: true, exitCode: 1, crashed: false, lines: ["password\t/x\ty"] }).type,
                    "methodsFailed", "a non-zero exit is a failure, whatever it printed");
        assertEqual(rules.detectionEvent(7, { started: true, exitCode: 1, crashed: false, lines: [] }).reason,
                    "the script exited with status 1", "and says so");
        assertEqual(rules.detectionEvent(7, { started: true, exitCode: 0, crashed: true, lines: [] }).type,
                    "methodsFailed", "killed by a signal: a failure");
        assertEqual(rules.detectionEvent(7, { started: false, exitCode: -1, crashed: false, lines: [] }).reason,
                    "the script could not be started", "not started at all: a failure");
        assertEqual(rules.detectionEvent(3, { started: true, exitCode: 0, crashed: false, lines: ["a", 5, null] }).lines.length, 1,
                    "only strings are passed on");

        // --- Caps Lock, from the keyboards' LEDs (singletons/lock/CapsLockLed.qml) ---
        assertEqual(rules.capsLockFromLeds(["led 1"]), true, "one LED, on: Caps Lock on");
        assertEqual(rules.capsLockFromLeds(["led 0"]), false, "one LED, off: off");
        assertEqual(rules.capsLockFromLeds(["led 0", "led 1"]), true, "two keyboards, one LED on: on");
        assertEqual(rules.capsLockFromLeds(["led 0", "led 0"]), false, "two, both off: off");
        assertEqual(rules.capsLockFromLeds(["led 255"]), true, "any brightness above 0 is on");
        assertEqual(rules.capsLockFromLeds([]), null, "no LED at all: unknown (no indicator)");
        assertEqual(rules.capsLockFromLeds(["led ?"]), null, "an LED that cannot be read: unknown");
        assertEqual(rules.capsLockFromLeds(["led 0", "led ?"]), null, "one off, one unreadable: unknown, not off");
        assertEqual(rules.capsLockFromLeds(["led ?", "led 1"]), true, "one unreadable, one on: on");
        assertEqual(rules.capsLockFromLeds(["led ", "led -1", "led x"]), null, "junk values: unknown");
        assertEqual(rules.capsLockFromLeds(["junk", "", "1"]), null, "lines that are no LED's: none seen");
        assertEqual(rules.capsLockFromLeds({ length: 1, 0: "led 1" }), true, "a QML list (array-like) is read");
        assertEqual(rules.capsLockFromLeds(null), null, "nothing: unknown");

        // --- pointer motion on a lock surface ---
        assert(!rules.pointerMoved(null, 10, 10), "the first position (the pointer entering) is no move");
        assert(!rules.pointerMoved({ x: 10, y: 10 }, 10, 10), "the same position again (a re-sent hover) is no move");
        assert(rules.pointerMoved({ x: 10, y: 10 }, 11, 10), "another position is");
        assert(!rules.pointerMoved("junk", 1, 1), "junk before is no move");

        // --- the helpers' restart pause ---
        const table = { minimum: 1000, maximum: 60000, healthyRun: 60000 };
        assertEqual(rules.restartDelay(0, 10, table), 1000, "the first quick failure waits the minimum");
        assertEqual(rules.restartDelay(1000, 10, table), 2000, "each further quick failure doubles it");
        assertEqual(rules.restartDelay(40000, 10, table), 60000, "up to the maximum");
        assertEqual(rules.restartDelay(60000, 10, table), 60000, "and stays there");
        assertEqual(rules.restartDelay(60000, 120000, table), 1000, "a helper that ran for a while starts again soon");
        assertEqual(rules.restartDelay(undefined, undefined, table), 1000, "nothing known: the minimum");
        assertEqual(rules.restartDelay(500, 0, { minimum: 30000, maximum: 600000, healthyRun: Infinity }), 30000,
                    "a previous pause below the minimum is raised to it");

        // --- the lock marker (Lockscreen, "Recovery") ---
        const facts = rules.markerFacts(["private yes", "key b00t:wayland-1:66:1234:99", "marker locked b00t:wayland-1:66:1234:99"]);
        assert(facts.private && facts.key === "b00t:wayland-1:66:1234:99" && facts.marker === "locked b00t:wayland-1:66:1234:99",
               "the probe's lines: private, the session's key, the marker's line");
        assert(!rules.markerFacts(["private no"]).private, "a runtime dir that is not private is said so");
        assert(!rules.markerFacts([]).private && rules.markerFacts([]).key === "" && rules.markerFacts([]).marker === "",
               "no lines: not private, no key, no marker");
        assert(!rules.markerFacts(null).private && !rules.markerFacts("private yes").private, "junk is no answer");
        assertEqual(rules.markerFacts({ length: 1, 0: "private yes" }).private, true, "a QML list (array-like) is read");
        assertEqual(rules.markerFacts(["key a", "key b"]).key, "a", "the first key line counts");

        const key = "b00t:wayland-1:66:1234:99";
        assertEqual(rules.markerDecision("locked " + key, key), "lock", "locked, this session's key: lock again");
        assertEqual(rules.markerDecision("locked other:wayland-1:66:1:1", key), "stale", "locked for another compositor session: stale");
        assertEqual(rules.markerDecision("locked " + key.replace("b00t", "boot2"), key), "stale", "… or another boot: stale");
        assertEqual(rules.markerDecision("locked ?", key), "lock", "locked, the key not known when written: lock (fail closed)");
        assertEqual(rules.markerDecision("locked", key), "lock", "locked with no key at all: lock (fail closed)");
        assertEqual(rules.markerDecision("locked " + key, "?"), "lock", "this session's key unknown: lock (fail closed)");
        assertEqual(rules.markerDecision("locked " + key, ""), "lock", "… also when empty");
        assertEqual(rules.markerDecision("unlocked", key), "none", "unlocked: nothing to do");
        assertEqual(rules.markerDecision("", key), "none", "no marker: nothing");
        assertEqual(rules.markerDecision(undefined, key), "none", "nothing at all: nothing");
        assertEqual(rules.markerDecision("lockedx " + key, key), "none", "a word that is not exactly locked: nothing");
        assertEqual(rules.markerDecision("  locked   " + key + "  ", key), "lock", "spaces around do not matter");

        // --- the notice of a launcher that gave up (scripts/launch.sh) ---
        const notice = rules.lockNotice("3", "/run/user/1000");
        assertEqual(notice.summary, "The shell stopped while locked", "a count: a notice");
        assertEqual(notice.body, "It stopped again after 3 restarts and was left locked. Log: /run/user/1000/h2s-shell-launcher.log",
                    "… saying how many restarts, and where the launcher's log is");
        assertEqual(rules.lockNotice("1", "/run/user/1000/").body,
                    "It stopped again after 1 restart and was left locked. Log: /run/user/1000/h2s-shell-launcher.log",
                    "one restart: singular; a trailing slash dropped");
        assertEqual(rules.lockNotice(undefined, "/run/user/1000"), null, "no variable: nothing to say");
        assertEqual(rules.lockNotice("", "/run/user/1000"), null, "empty: nothing");
        assertEqual(rules.lockNotice("0", "/run/user/1000"), null, "zero restarts: nothing");
        assertEqual(rules.lockNotice("1000", "/run/user/1000"), null, "more than three digits: not the launcher's");
        assertEqual(rules.lockNotice("3 <b>x</b>", "/run/user/1000"), null, "anything but digits: not the launcher's");
        assertEqual(rules.lockNotice(3, "/run/user/1000"), null, "not a string: not the launcher's");
        assertEqual(rules.lockNotice("3", "relative/dir").body, "It stopped again after 3 restarts and was left locked. Log: h2s-shell-launcher.log in XDG_RUNTIME_DIR",
                    "a runtime dir that is not an absolute path is not shown");
        assert(rules.lockNotice("3", "/run/user/1000\nforged line").body.indexOf("forged") < 0, "… nor one with a line break");
        assert(rules.lockNotice("3", "/" + "x".repeat(250)).body.indexOf("xxx") < 0, "… nor one longer than 200 characters");
        assert(rules.lockNotice("3", undefined).body.endsWith("in XDG_RUNTIME_DIR"), "no runtime dir: named by the variable");

        // --- Hyprland's word before a lock is taken back ---
        const said = (option, locked) => '{"option":"misc:allow_session_lock_restore","bool":' + option + ',"set":true}\n{"locked": ' + locked + "}";
        let hypr = rules.hyprlandLockFacts(said("false", "true"));
        assert(hypr.restoreAllowed === false && hypr.locked === true && rules.lockSurelyRefused(hypr),
               "locked, restoring not allowed: a lock is refused for sure (do not ask: Hyprland kills the client that asks)");
        hypr = rules.hyprlandLockFacts(said("true", "true"));
        assert(hypr.restoreAllowed === true && !rules.lockSurelyRefused(hypr), "restoring allowed: ask");
        hypr = rules.hyprlandLockFacts(said("false", "false"));
        assert(hypr.locked === false && !rules.lockSurelyRefused(hypr), "not locked: ask (the marker says the owner left it locked)");
        hypr = rules.hyprlandLockFacts('{"option":"misc:allow_session_lock_restore","int":0,"set":true}{"locked":true}');
        assert(hypr.restoreAllowed === false && rules.lockSurelyRefused(hypr), "an int option reads as well");
        for (const output of ["", "hyprctl: command not found", "{\"locked\": true}", said("false", "maybe"), null, undefined,
                              '{"option":"misc:other","bool":false}{"locked":true}'])
            assert(!rules.lockSurelyRefused(rules.hyprlandLockFacts(output)),
                   "an answer that does not say both facts is no refusal (ask; the launcher bounds the cost): " + JSON.stringify(output));
        assert(!rules.lockSurelyRefused(null) && !rules.lockSurelyRefused({}), "no facts: no refusal");

        // --- other lockers before sleep (SleepLockNotice) ---
        // logind's ListInhibitors as gdbus prints it (copied from a real answer, names changed)
        const listed = "([('sleep', 'hypridle', \"Hypridle wants to delay sleep until it's before_sleep handling is done.\", 'delay', uint32 1000, uint32 2090), "
            + "('sleep', 'UPower', 'Pause device polling', 'delay', 0, 2450), "
            + "('shutdown', 'Some Browser', 'Saving browser state', 'delay', uint32 1000, uint32 3732014), "
            + "('sleep', 'NetworkManager', 'NetworkManager needs to turn off networks', 'delay', uint32 0, uint32 890)],)";
        const parsed = rules.parseInhibitors(listed);
        assertEqual(parsed?.length, 4, "every inhibitor of the list is read");
        assertEqual(JSON.stringify(parsed[0]), JSON.stringify({ what: "sleep", who: "hypridle",
            why: "Hypridle wants to delay sleep until it's before_sleep handling is done.", mode: "delay", uid: 1000, pid: 2090 }),
                    "… with its fields; a double-quoted string (it holds a quote) reads as well");
        assertEqual(parsed[1].uid, 0, "… a number without its type reads too");
        assertEqual(JSON.stringify(rules.parseInhibitors("(@a(ssssuu) [],)")), "[]", "an empty list: none");
        assertEqual(rules.parseInhibitors("([('sleep', 'it\\'s', 'a\\nb \\u00e9', 'delay', uint32 1, uint32 2)],)")?.[0]?.who, "it's",
                    "escapes are read");
        assertEqual(rules.parseInhibitors("([('sleep', 'x', 'a\\nb \\u00e9', 'delay', uint32 1, uint32 2)],)")?.[0]?.why, "a\nb \u00e9",
                    "… a line break and a \\u escape");
        for (const broken of ["", "Error: GDBus.Error:org.freedesktop.DBus.Error.ServiceUnknown: no logind", "([('sleep', 'x')],)",
                              "([('sleep', 'x', 'y', 'delay', uint32 1, uint32 2)],) trailing", "([('sleep', 'x', 'y', 'delay', uint32 1, uint32 2)",
                              "([('sleep', 'x, 'y', 'delay', 1, 2)],)", null, undefined, 42])
            assertEqual(rules.parseInhibitors(broken), null, "anything but a list is no list: " + JSON.stringify(broken));

        const holder = (who, why, extra) => Object.assign({ what: "sleep", who: who, why: why, mode: "delay", uid: 1000, pid: 7 }, extra ?? {});
        const lockersOf = (list, uid) => JSON.stringify(rules.sleepLockers(list, uid ?? 1000));
        assertEqual(lockersOf(parsed), JSON.stringify({ state: "possible", names: ["hypridle"] }),
                    "hypridle holds one whatever its before_sleep_cmd: only possibly a locker; services and shutdown inhibitors do not count");
        assertEqual(lockersOf([holder("xss-lock", "xss-lock is waiting for sleep")]), JSON.stringify({ state: "present", names: ["xss-lock"] }),
                    "a locker known by name");
        assertEqual(lockersOf([holder("GNOME Shell", "GNOME needs to lock the screen")]), JSON.stringify({ state: "present", names: ["GNOME Shell"] }),
                    "… or by a reason that says it locks the screen");
        assertEqual(lockersOf([holder("my-locker", "Setting up lock screen")]), JSON.stringify({ state: "present", names: ["my-locker"] }),
                    "… any name");
        assertEqual(lockersOf([holder("backup", "Finish the block write"), holder("clock", "Saving the clock")]), JSON.stringify({ state: "none", names: [] }),
                    "\"block\", \"clock\" are no lock; nor is a reason without the screen or session");
        assertEqual(lockersOf([holder("h2s-shell", "Lock the screen before sleep")]), JSON.stringify({ state: "none", names: [] }),
                    "the shell's own inhibitor does not count");
        assertEqual(lockersOf([holder("xss-lock", "lock", { uid: 120 })]), JSON.stringify({ state: "none", names: [] }),
                    "another user's (a greeter's) does not count");
        assertEqual(lockersOf([holder("xss-lock", "lock", { mode: "block" })]), JSON.stringify({ state: "none", names: [] }),
                    "a block inhibitor stops sleep, it does not lock before it");
        assertEqual(lockersOf([holder("swayidle", "Setup Up Lock Screen", { what: "handle-lid-switch:sleep" })]),
                    JSON.stringify({ state: "present", names: ["swayidle"] }), "sleep among other things counts");
        assertEqual(lockersOf([holder("swayidle", "Setup Up Lock Screen", { what: "shutdown:idle" })]), JSON.stringify({ state: "none", names: [] }),
                    "… not without it");
        assertEqual(lockersOf([holder("xss-lock", ""), holder("hypridle", "")]), JSON.stringify({ state: "present", names: ["xss-lock"] }),
                    "a locker outweighs a possible one");
        assertEqual(lockersOf([holder("d", "lock screen"), holder("c", "lock screen"), holder("b", "lock screen"), holder("a", "lock screen"), holder("a", "lock screen")]),
                    JSON.stringify({ state: "present", names: ["a", "b", "c"] }), "names: once each, sorted, three at most");
        const longName = rules.sleepLockers([holder("x\n<b>y</b>" + "z".repeat(60), "lock screen")], 1000).names[0];
        assert(longName.indexOf("\n") < 0 && longName.length <= 40, "a name from outside: one line, capped (" + longName + ")");
        assertEqual(lockersOf(null), JSON.stringify({ state: "unknown", names: [] }), "no list: unknown, never none");
        assertEqual(JSON.stringify(rules.sleepLockers([], null)), JSON.stringify({ state: "unknown", names: [] }), "no uid: unknown");
        assertEqual(lockersOf([], -1), JSON.stringify({ state: "unknown", names: [] }), "… a uid that is none");
        assertEqual(JSON.stringify(rules.sleepLockersFromOutput("1000\n" + listed)), JSON.stringify({ state: "possible", names: ["hypridle"] }),
                    "the reader's output: the uid, then the list");
        assertEqual(rules.sleepLockersFromOutput("1000\n").state, "unknown", "gdbus said nothing (it failed): unknown");
        assertEqual(rules.sleepLockersFromOutput("").state, "unknown", "nothing at all: unknown");
        assertEqual(rules.sleepLockersFromOutput("x\n(@a(ssssuu) [],)").state, "unknown", "no uid read: unknown");
        assertEqual(rules.sleepLockersText({ state: "present", names: ["a", "b"] }), "present: a, b", "the outcome in the log");
        assertEqual(rules.sleepLockersText(null), "unknown", "… none read");
        assertEqual(rules.sleepLockersText({ state: "possible", names: { length: 1, 0: "hypridle" } }), "possible: hypridle",
                    "… names in an array-like (a list that came through a QML signal) as well");

        const otherLocks = { state: "present", names: ["swayidle"] };
        const noneLocks = { state: "none", names: [] };
        const maybeLocks = { state: "possible", names: ["hypridle"] };
        const unknownRead = { state: "unknown", names: [] };
        const both = rules.sleepLockNotice(otherLocks, true);
        assertEqual(both?.key, "both:swayidle", "on, and another locks: two lockers race");
        assertEqual(both?.summary, "Two programs lock the screen before sleep", "… said so");
        assertEqual(both?.body, "swayidle locks it too. Keep one of them: \"Lock before the computer sleeps\" is in Settings → Lockscreen.",
                    "… naming the other and the setting");
        assertEqual(rules.sleepLockNotice({ state: "present", names: ["a", "b"] }, true)?.body.startsWith("a, b lock it too."), true, "two others: plural");
        const unlockedSleep = rules.sleepLockNotice(noneLocks, false);
        assertEqual(unlockedSleep?.key, "none", "off, and nothing else locks: the screen stays unlocked through sleep");
        assertEqual(unlockedSleep?.summary, "The screen stays unlocked during sleep", "… said so");
        assertEqual(rules.sleepLockNotice(otherLocks, false), null, "off, another locks: nothing to say");
        assertEqual(rules.sleepLockNotice(noneLocks, true), null, "on, nothing else: nothing to say");
        for (const lockOnSleep of [true, false]) {
            assertEqual(rules.sleepLockNotice(maybeLocks, lockOnSleep), null, "a maybeLocks locker says nothing (" + lockOnSleep + ")");
            assertEqual(rules.sleepLockNotice(unknownRead, lockOnSleep), null, "an unknown read says nothing (" + lockOnSleep + ")");
        }
        assertEqual(rules.sleepLockNotice(noneLocks, "yes"), null, "a setting that is not a boolean: nothing");

        let told = rules.sleepNoticeStep("", noneLocks, false);
        assertEqual(told.notice?.key, "none", "a notice not yet given: given");
        assertEqual(told.remember, "none", "… and remembered");
        told = rules.sleepNoticeStep("none", noneLocks, false);
        assert(told.notice === null && told.remember === "none", "given before: not again (also after a restart: the key is in the config)");
        told = rules.sleepNoticeStep("none", unknownRead, false);
        assert(told.notice === null && told.remember === "none", "a failed read changes nothing");
        told = rules.sleepNoticeStep("none", noneLocks, true);
        assert(told.notice === null && told.remember === "", "switched on: nothing to say, the key forgotten");
        told = rules.sleepNoticeStep("", noneLocks, false);
        assertEqual(told.notice?.key, "none", "… so switched off again, it is told again");
        told = rules.sleepNoticeStep("none", otherLocks, true);
        assertEqual(told.notice?.key, "both:swayidle", "another notice: given");
        told = rules.sleepNoticeStep("both:swayidle", { state: "present", names: ["xss-lock"] }, true);
        assertEqual(told.notice?.key, "both:xss-lock", "another locker: told again");
        told = rules.sleepNoticeStep("both:swayidle", maybeLocks, true);
        assert(told.notice === null && told.remember === "", "a maybeLocks locker: nothing, the key forgotten");
        assertEqual(rules.sleepNoticeStep(undefined, unknownRead, true).remember, "", "no key kept: \"\"");
    }
}
