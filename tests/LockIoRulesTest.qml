import QtQuick
import qs.singletons

// The lock screen's I/O-side helpers (singletons/LockIoRules.qml): the driver's queue, key
// names, the field's editing by forwarded keys, the methods script's report, and the
// helper processes' restart pause.
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
        assertEqual(JSON.stringify(rules.fallbackFacts(["readable", "nixos"])), JSON.stringify({ systemConfigReadable: true, nixos: true }),
                    "fallback facts: both");
        assertEqual(JSON.stringify(rules.fallbackFacts(["nixos\n"])), JSON.stringify({ systemConfigReadable: false, nixos: true }),
                    "fallback facts: NixOS only");
        assertEqual(JSON.stringify(rules.fallbackFacts(null)), JSON.stringify({ systemConfigReadable: false, nixos: false }),
                    "fallback facts: nothing");
        assertEqual(JSON.stringify(rules.fallbackFacts({ length: 2, 0: "readable", 1: "nixos" })),
                    JSON.stringify({ systemConfigReadable: true, nixos: true }),
                    "fallback facts: an array-like (what a QML signal's var argument delivers) is read too");

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
    }
}
