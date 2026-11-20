import QtQuick
import qs.singletons

TestCase {
    suiteName: "NotificationRules"

    function run() {
        const progress = hints => NotificationRules.progress(hints);
        const bar = hints => {
            const result = progress(hints);
            return [result.shown, result.value, result.state, result.tone].join(" ");
        };

        // --- the value ---
        assertEqual(bar({}), "false 0 running accent", "no value: no bar");
        assertEqual(bar(undefined), "false 0 running accent", "no hints: no bar");
        assertEqual(bar({ value: 0 }), "true 0 running accent", "0: an empty bar");
        assertEqual(bar({ value: 40 }), "true 0.4 running accent", "40: four tenths");
        assertEqual(bar({ value: 100 }), "true 1 running accent", "100: full");
        assertEqual(bar({ value: 150 }), "true 1 running accent", "150: full, no more");
        assertEqual(bar({ value: -5 }), "true -1 running accent", "below 0: a run of unknown length");
        assertEqual(bar({ value: "40" }), "false 0 running accent", "a string: not a number, no bar");
        assertEqual(bar({ value: NaN }), "false 0 running accent", "NaN: no bar");
        assertEqual(bar({ value: null }), "false 0 running accent", "null: no bar");

        // --- the state ---
        assertEqual(bar({ value: 40, "x-qs-progress-state": "running" }), "true 0.4 running accent", "running: its value");
        assertEqual(bar({ value: 40, "x-qs-progress-state": "done" }), "true 1 done success", "done: full, success");
        assertEqual(bar({ value: 40, "x-qs-progress-state": "failed" }), "true 1 failed error", "failed: full, error");
        assertEqual(bar({ value: 40, "x-qs-progress-state": "cancelled" }), "false 0 cancelled accent", "cancelled: no bar");
        assertEqual(bar({ value: 40, "x-qs-progress-state": "paused" }), "true 0.4 running accent", "a state not known: running");
        assertEqual(bar({ value: 40, "x-qs-progress-state": 3 }), "true 0.4 running accent", "a state not a string: running");
        assertEqual(bar({ "x-qs-progress-state": "done" }), "false 0 done success", "done without a value: no bar");

        // --- the bar's wave: running, and its value grown lately ---
        const now = 100000;
        const wave = (state, grewAt) => NotificationRules.progressWave(state, grewAt, now);
        assertEqual(NotificationRules.progressWaveMs, 10000, "the wave lasts 10 s after the value last grew");
        assert(wave("running", now - 2000), "running, grown 2 s ago: waves");
        assert(!wave("running", now - 11000), "running, grown 11 s ago: stands still, no wave");
        assert(!wave("running", now - 10000), "… exactly 10 s ago: no wave");
        assert(!wave("done", now - 2000) && !wave("failed", now - 2000) && !wave("cancelled", now - 2000), "done, failed, cancelled: no wave, however recent");
        assert(!wave("running", 0), "never grown: no wave");
        assert(!wave("running", now + 5000), "grown after now (a clock gone back): no wave");
        assert(!wave("running", undefined) && !NotificationRules.progressWave("running", now - 2000, undefined), "a time that is not a number: no wave");
        assert(NotificationRules.progressWave("running", now - 200, now, 300) && !NotificationRules.progressWave("running", now - 400, now, 300), "another window when given");

        // --- after an action ---
        assert(NotificationRules.dismissAfterAction({ resident: false }), "not resident: the entry goes");
        assert(NotificationRules.dismissAfterAction({}), "resident not said: the entry goes");
        assert(NotificationRules.dismissAfterAction(null), "no notification: as not resident");
        assert(!NotificationRules.dismissAfterAction({ resident: true }), "resident: the entry stays");

        _sender();
        _gvariant();
    }

    // The shell's own sender's decisions: the expire time, coalescing, answers, orphans
    function _sender() {
        const rules = NotificationRules;
        // --- the expire time for a toast mode and a state ---
        assertEqual([rules.expireTime("whileRunning", "starting"), rules.expireTime("whileRunning", "running"),
                     rules.expireTime("whileRunning", "done"), rules.expireTime("whileRunning", "failed"),
                     rules.expireTime("whileRunning", "cancelled")].join(" "), "0 0 -1 -1 -1",
                    "whileRunning: stays while starting or running, the user's time at the end");
        assertEqual([rules.expireTime("brief", "running"), rules.expireTime("brief", "done"), rules.expireTime(undefined, "running"),
                     rules.expireTime("forever", "running")].join(" "), "-1 -1 -1 -1", "brief (and anything else): always the user's time");

        // --- the value hint ---
        assertEqual([0, 40, 40.9, 100, 150, -1, -0.5, NaN, "40", undefined].map(v => rules.progressValue(v)).join(" "),
                    "0 40 40 100 100 -1 -1 0 0 0", "progressValue: whole percents, capped, -1 for unknown length, not a number 0");

        // --- nextSend ---
        const content = (changes) => Object.assign({ summary: "Sending", body: "", state: "running", announce: 0, actionsKey: "[]", progress: 0 }, changes);
        const base = { ended: false, inFlight: false, id: 7, closeWanted: false, sent: content({}), wanted: content({}), lastSentAt: 10000 };
        const next = (changes, now) => rules.nextSend(Object.assign({}, base, changes), now ?? 20000);
        const act = (changes, now) => next(changes, now).action;
        assertEqual(act({ id: 0, sent: null }), "show", "nothing sent yet: the show");
        assertEqual(act({}), "none", "nothing changed: nothing");
        assertEqual(act({ wanted: content({ progress: 40 }) }), "update", "progress moved a whole percent, past the minimum time: sent");
        assertEqual(act({ wanted: content({ progress: 0.7 }) }), "none", "progress moved less than a whole percent: nothing");
        const soon = next({ wanted: content({ progress: 40 }) }, 10300);
        assertEqual(soon.action + " " + soon.delayMs, "later 700", "progress within the minimum time: later, when it has passed (coalesced)");
        assertEqual(act({ wanted: content({ summary: "Sent" }) }, 10300), "update", "a text change: at once");
        assertEqual(act({ wanted: content({ actionsKey: "[{\"id\":\"x\"}]" }) }, 10300), "update", "an action change: at once");
        assertEqual(act({ wanted: content({ state: "done", progress: 40 }) }, 10001), "update", "an end state: always, at once");
        assertEqual(act({ wanted: content({ announce: 2 }), sent: content({ announce: 0 }) }, 10300), "update",
                    "two announces since the last call: one update (the count is whatever it is now)");
        assertEqual(act({ inFlight: true, wanted: content({ summary: "Sent" }) }), "none", "a call answers first: one at a time");
        assertEqual(act({ id: 0, inFlight: true, wanted: content({ summary: "Sent" }) }), "none", "an update before the id: waits for the show's answer");
        assertEqual(act({ ended: true, wanted: content({ summary: "Sent" }) }), "none", "ended (closed, dismissed, unknown): nothing sent");
        assertEqual(act({ closeWanted: true, wanted: content({ summary: "Sent" }) }), "close", "close() wanted: the close, not the update");
        assertEqual(act({ closeWanted: true, inFlight: true }), "none", "close() while a call runs: after its answer");
        assertEqual(act({ closeWanted: true, id: 0, inFlight: true }), "none", "close() before the id: when the id comes");
        assertEqual(act({ closeWanted: true, ended: true }), "none", "after the close went: nothing more");
        assertEqual(rules.nextSend(null, 0).action, "none", "no handle: nothing");
        const retrying = next({ retryAt: 22000, wanted: content({ state: "done" }) }, 20000);
        assertEqual(retrying.action + " " + retrying.delayMs, "later 2000", "after a failed update: the retry waits its pause, even for an end state");
        assertEqual(act({ retryAt: 22000, wanted: content({ state: "done" }) }, 22000), "update", "… and goes when it has passed");
        assertEqual(act({ retryAt: 22000, closeWanted: true }, 20000), "close", "close() does not wait for a retry's pause");
        assertEqual([0, 1, 2, 3, 5, 6, 1.5].map(n => rules.retryDelay(n)).join(" "), "0 1000 2000 4000 16000 -1 0",
                    "retryDelay: 1 s doubling to 16 s, past five tries -1 (given up)");

        // --- answered ---
        const answer = (handle, id) => {
            const result = rules.answered(handle, id);
            return [result.outcome, result.id, result.closeId].join(" ");
        };
        assertEqual(answer({ ended: false, id: 0 }, 7), "shown 7 0", "the first answer: the id is known");
        assertEqual(answer({ ended: false, id: 7 }, 7), "updated 7 0", "the same id again: updated");
        assertEqual(answer({ ended: false, id: 7 }, 9), "foreign 7 9", "another id: the old was closed meanwhile, the new one is closed");
        assertEqual(answer({ ended: true, id: 7 }, 9), "late 7 9", "ended meanwhile: whatever the answer made is closed");
        assertEqual(answer({ ended: true, id: 0 }, 7), "late 0 7", "closed before the id came: closed when it comes");
        assertEqual(answer({ ended: false, id: 0 }, 0), "failed 0 0", "no id: failed");
        assertEqual(answer({ ended: false, id: 7 }, 0), "failed 7 0", "an update without an id: failed, the id kept");
        assertEqual(answer({ ended: false, id: 0 }, -3) + "|" + answer({ ended: false, id: 0 }, 1.5), "failed 0 0|failed 0 0", "an id that is no id: failed");

        // --- gdbus's answer ---
        assertEqual(["(uint32 7,)", "(uint32 7,)\n", "(uint32 0,)", "(uint32 4294967296,)", "(int32 7,)", "uint32 7", "", null,
                     "(uint32 7,)\n(uint32 8,)"].map(text => rules.notifyAnswerId(text)).join(" "),
                    "7 7 0 0 0 0 0 0 0", "notifyAnswerId: only \"(uint32 N,)\" with N a uint32 above 0");

        // --- orphans ---
        const running = run => ({ value: 40, "x-qs-progress-state": "running", "x-qs-progress-run": run });
        assert(rules.orphaned(running("old"), "new"), "another run's running notification: an orphan");
        assert(!rules.orphaned(running("new"), "new"), "this run's: not an orphan");
        assert(!rules.orphaned({ value: 40, "x-qs-progress-state": "done", "x-qs-progress-run": "old" }, "new"), "another run's, ended: kept (it stands as it ended)");
        assert(rules.orphaned({ value: 40, "x-qs-progress-run": "old" }, "new"), "another run's without a state: running, an orphan");
        assert(!rules.orphaned({ value: 40 }, "new") && !rules.orphaned({ value: 40, "x-qs-progress-run": "" }, "new")
               && !rules.orphaned({ "x-qs-progress-run": 3 }, "new") && !rules.orphaned(undefined, "new"),
               "no run token (an outside app's, or not a string): never an orphan");

        // --- announced: a raised x-qs-announce on this run's own notification ---
        const own = count => count === undefined ? { value: 40, "x-qs-progress-run": "now" }
            : { value: 40, "x-qs-progress-run": "now", "x-qs-announce": count };
        assert(rules.announced(undefined, own("1"), "now"), "announced: the first value (none before) announces");
        assert(!rules.announced("1", own("1"), "now"), "announced: the same value again (a plain update) does not");
        assert(rules.announced("1", own("2"), "now") && rules.announced("2", own(3), "now"), "announced: raised, as text or a number");
        assert(!rules.announced(undefined, own(), "now") && !rules.announced("2", own(), "now"), "announced: absent does not");
        assert(!rules.announced(undefined, own("0"), "now") && !rules.announced(undefined, own("x"), "now")
               && !rules.announced(undefined, own("1.5"), "now") && !rules.announced(undefined, own(true), "now"),
               "announced: not a whole number from 1: none");
        assert(!rules.announced(undefined, { "x-qs-announce": "1" }, "now")
               && !rules.announced(undefined, { "x-qs-announce": "1", "x-qs-progress-run": "old" }, "now")
               && !rules.announced(undefined, { "x-qs-announce": "1", "x-qs-progress-run": "" }, "")
               && !rules.announced(undefined, undefined, "now"),
               "announced: without this run's token (an outside app, another run) never believed");
    }

    // GVariant text for gdbus: every string a single-quoted literal of printable ASCII
    function _gvariant() {
        const rules = NotificationRules;
        const word = text => rules.gvariantString(text);
        assertEqual(word("Sending photo.jpg"), "'Sending photo.jpg'", "plain ASCII as it is, in single quotes");
        assertEqual(word(""), "''", "empty");
        assertEqual(word("it's"), "'it\\'s'", "a single quote escaped");
        assertEqual(word("a\\b"), "'a\\\\b'", "a backslash escaped");
        assertEqual(word("\\'"), "'\\\\\\''", "a backslash then a quote: both escaped, the quote cannot end the literal");
        assertEqual(word("say \"hi\""), "'say \"hi\"'", "a double quote needs nothing inside single quotes");
        assertEqual(word("a\nb\tc\rd"), "'a\\u000ab\\u0009c\\u000dd'", "line breaks, tabs, CR as \\u escapes");
        assertEqual(word("\u0001\u001f\u007f\u0085"), "'\\u0001\\u001f\\u007f\\u0085'", "C0, DEL, C1 as \\u escapes");
        assertEqual(word("é€"), "'\\u00e9\\u20ac'", "non-ASCII in the BMP as \\u");
        assertEqual(word("😀"), "'\\U0001f600'", "above the BMP as \\U, the pair as one character");
        assertEqual(word("‮evil"), "'\\u202eevil'", "a right-to-left override escaped, not dropped (format characters are the caller's)");
        assertEqual(word("a\u0000b"), "'ab'", "a NUL dropped");
        assertEqual(word("x\ud800y\udc00z"), "'xyz'", "lone surrogates dropped");
        assertEqual(word("\ud83d"), "''", "a high surrogate at the end dropped");
        assertEqual(word("' , 'evil': <true>} --help"), "'\\' , \\'evil\\': <true>} --help'", "an attempt to end the literal and add a hint stays inside it");
        assertEqual(word("-x"), "'-x'", "a leading \"-\" is inside the quotes: never an option");
        assertEqual(word("%s %d"), "'%s %d'", "per cent signs as they are (g_variant_parse has no format directives)");
        assertEqual(word(42), "'42'", "a number as its text");
        assertEqual(word(null) + word(undefined) + word({ toString: () => "x" }), "''''''", "anything else: empty (a pair of quotes each)");
        assertEqual(rules.gvariantString("abcdef", 3), "'abc'", "cut at the cap, in characters");
        assertEqual(rules.gvariantString("😀😀😀", 2), "'\\U0001f600\\U0001f600'", "the cap counts a pair once");
        assertEqual(rules.gvariantString("a\u0000\u0000bc", 2), "'ab'", "dropped characters do not count toward the cap");
        const long = rules.gvariantString("😀".repeat(100000));
        assert(long.length === 2 + rules.gvariantTextCap * 10 && long.length < 131072, "a very long text: cut at the default cap, the word below the kernel's 128 KiB (" + long.length + ")");
        // Every character from U+0000 to U+FFFF and some beyond: the word is printable ASCII,
        // starts and ends with its one pair of quotes, and every quote inside is escaped
        let all = "";
        for (let code = 0; code <= 0xffff; code++)
            all += String.fromCharCode(code);
        all += "😀􏿿";
        const everything = rules.gvariantString(all, 1000000);
        const inner = everything.slice(1, -1);
        const printable = everything.split("").every(character => character.charCodeAt(0) >= 0x20 && character.charCodeAt(0) <= 0x7e);
        assert(printable && everything.startsWith("'") && everything.endsWith("'"), "every character: the word is printable ASCII in quotes");
        // Read as g_variant_parse reads it: a backslash takes the next character with it
        let unescapedQuote = false;
        for (let i = 0; i < inner.length; i++) {
            if (inner[i] === "\\")
                i++;
            else if (inner[i] === "'")
                unescapedQuote = true;
        }
        assert(!unescapedQuote, "every character: no quote inside without its backslash (none ends the literal)");
        assert(inner.endsWith("\\U0001f600\\U0010ffff"), "every character: the pairs at the end as \\U");

        assertEqual(rules.gvariantStringArray(["cancel", "Cancel", "it's", 3, null]), "@as ['cancel', 'Cancel', 'it\\'s', '3', '']", "a string array: each a literal");
        assertEqual(rules.gvariantStringArray([]) + "|" + rules.gvariantStringArray("x"), "@as []|@as []", "an empty or no array: typed empty");

        const value = (type, v) => rules.gvariantValue(type, v);
        assertEqual([value("boolean", true), value("boolean", false), value("boolean", 1)].join("|"), "true|false|", "boolean: true/false only");
        assertEqual([value("byte", 2), value("byte", 256), value("byte", -1), value("byte", 1.5)].join("|"), "byte 2|||", "byte: 0–255");
        assertEqual([value("int32", -1), value("int32", 2147483647), value("int32", 2147483648), value("int32", "4")].join("|"),
                    "int32 -1|int32 2147483647||", "int32: its range, numbers only");
        assertEqual([value("int64", 2147483648), value("int64", 2 ** 60)].join("|"), "int64 2147483648|", "int64: safe integers");
        assertEqual([value("double", 0.5), value("double", 1e-7), value("double", NaN), value("double", Infinity)].join("|"),
                    "double 0.5|double 1e-7||", "double: finite numbers");
        assertEqual([value("string", "a'b"), value("string", 3), value("variant", "x")].join("|"), "'a\\'b'||", "string: strings only; an unknown type: left out");

        assertEqual(rules.gvariantHints([{ key: "value", type: "int32", value: 40 }, { key: "x-qs-progress-state", type: "string", value: "running" },
                                         { key: "resident", type: "boolean", value: true }, { key: "urgency", type: "byte", value: 1 }]),
                    "@a{sv} {'value': <int32 40>, 'x-qs-progress-state': <'running'>, 'resident': <true>, 'urgency': <byte 1>}", "hints: typed values in order");
        assertEqual(rules.gvariantHints([{ key: "value", type: "int32", value: 1 }, { key: "a", type: "string", value: "x" }, { key: "value", type: "int32", value: 2 }]),
                    "@a{sv} {'a': <'x'>, 'value': <int32 2>}", "hints: a later entry with the same key wins");
        assertEqual(rules.gvariantHints([{ key: "it's': <true>, 'x", type: "boolean", value: true }]),
                    "@a{sv} {'it\\'s\\': <true>, \\'x': <true>}", "hints: a crafted key stays one key");
        assertEqual(rules.gvariantHints([{ key: "", type: "boolean", value: true }, { key: 3, type: "boolean", value: true },
                                         { key: "n", type: "int32", value: "40" }, null]), "@a{sv} {}", "hints: a bad key or value left out");
        assertEqual(rules.gvariantHints(undefined), "@a{sv} {}", "no hints: typed empty");
        assertEqual(rules.gvariantHints([{ key: "\u0000value", type: "int32", value: 99 }, { key: "value", type: "int32", value: 40 }]),
                    "@a{sv} {'value': <int32 40>}", "hints: keys the same once a NUL is dropped are one key, the later wins");
        assertEqual(rules.gvariantHints([{ key: "\ud800", type: "boolean", value: true }]), "@a{sv} {}", "hints: a key of a lone surrogate is empty: left out");
        assertEqual(rules.gvariantText("\ud800x-qs-a\u0000b😀", 100) + "|" + rules.gvariantText("abcdef", 3) + "|" + rules.gvariantText(null),
                    "x-qs-ab😀|abc|", "gvariantText: the text as the server receives it");
        assertEqual([true, 4, 2 ** 40, 0.5, "s", null, {}].map(v => rules.hintType(v)).join(" "), "boolean int32 int64 double string  ",
                    "hintType: as notify-send's inference, else left out");
    }
}
