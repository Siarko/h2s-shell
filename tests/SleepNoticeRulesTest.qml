import QtQuick
import qs.singletons

// The sleep notice's cycle (singletons/SleepNoticeRules.qml): every row of its table of
// steps, then whole cycles.
TestCase {
    suiteName: "SleepNoticeRules"

    function _actions(result) {
        return result.actions.map(action => action.type + (action.at !== undefined ? "@" + action.at : "")).join(",");
    }

    function run() {
        const rules = SleepNoticeRules;
        const quiet = rules.initial();
        const shown = { phase: "shown", at: 1000 };
        const waiting = { phase: "waiting", at: 1000 };
        const slept = (outcome, at) => ({ type: "slept", outcome: outcome, at: at ?? 2000 });

        // --- the table ---
        let result = rules.step(quiet, slept("unlocked", 1000));
        assertEqual(result.state.phase, "shown", "quiet, slept unlocked: shown");
        assertEqual(_actions(result), "notify@1000", "… the notification, with the sleep's time");

        // The shell's own sleep after idle, which the settings leave unlocked: not counted
        const chosen = Object.assign(slept("unlocked", 1500), { leftUnlocked: true });
        result = rules.step(quiet, chosen);
        assert(result.state.phase === "quiet" && _actions(result) === "", "quiet, the idle sleep the settings leave unlocked: no notice");
        result = rules.step(waiting, chosen);
        assert(result.state.phase === "waiting" && result.state.at === 1000, "… waiting: the line keeps its sleep");
        result = rules.step(shown, chosen);
        assert(result.state.phase === "shown" && result.state.at === 1000 && _actions(result) === "", "… shown: left as it is");
        assertEqual(rules.step(shown, Object.assign(slept("locked"), { leftUnlocked: true })).state.phase, "quiet",
                    "… a sleep that locked all the same counts as locked");

        result = rules.step(shown, { type: "closed", at: 1000 });
        assertEqual(result.state.phase, "waiting", "shown, closed: waiting (acknowledged)");
        assertEqual(result.state.at, 1000, "… the time kept for the page's line");
        assertEqual(_actions(result), "", "… nothing to do");

        result = rules.step(shown, slept("unlocked", 3000));
        assertEqual(result.state.phase, "shown", "shown, slept unlocked again: still shown");
        assertEqual(_actions(result), "notify@3000", "… the notification replaced, its time updated");

        const replaced = rules.step(shown, slept("unlocked", 3000)).state;
        result = rules.step(replaced, { type: "closed", at: 1000 });
        assertEqual(result.state.phase, "shown", "a close of the notification since replaced: ignored, the new one still shown");
        assertEqual(rules.step(replaced, { type: "closed", at: 3000 }).state.phase, "waiting", "… its own close acknowledges it");
        assertEqual(rules.step(shown, { type: "closed" }).state.phase, "shown", "a close naming no notification: ignored");

        result = rules.step(shown, slept("locked"));
        assertEqual(result.state.phase, "quiet", "shown, slept locked: quiet (fixed before it was read)");
        assertEqual(_actions(result), "withdraw", "… the notification withdrawn");

        result = rules.step(waiting, slept("unlocked", 5000));
        assertEqual(result.state.phase, "waiting", "waiting, slept unlocked: still waiting");
        assertEqual(result.state.at, 5000, "… the page's line takes the new time");
        assertEqual(_actions(result), "", "… no new notification");

        result = rules.step(waiting, slept("locked"));
        assertEqual(result.state.phase, "quiet", "waiting, slept locked: quiet (fixed)");
        assertEqual(rules.waitingSince(result.state), -1, "… the page's line goes");
        assertEqual(_actions(result), "", "… nothing to withdraw");

        for (const state of [quiet, shown, waiting]) {
            result = rules.step(state, slept("unknown"));
            assertEqual(result.state.phase, state.phase, state.phase + ", slept unknown: unchanged");
            assertEqual(_actions(result), "", state.phase + ", slept unknown: never an alarm");
        }

        result = rules.step(quiet, slept("locked"));
        assertEqual(result.state.phase, "quiet", "quiet, slept locked: quiet");
        assertEqual(_actions(result), "", "… nothing");

        result = rules.step(shown, { type: "restarted" });
        assertEqual(result.state.phase, "shown", "shown, the shell restarts: still shown");
        assertEqual(_actions(result), "notify@1000", "… the notification shown again (never closed)");
        assertEqual(_actions(rules.step(waiting, { type: "restarted" })), "", "waiting, a restart: not told again");
        assertEqual(_actions(rules.step(quiet, { type: "restarted" })), "", "quiet, a restart: nothing");

        // --- what does not belong to a phase ---
        assertEqual(rules.step(quiet, { type: "closed" }).state.phase, "quiet", "closed while quiet: ignored");
        assertEqual(rules.step(waiting, { type: "closed" }).state.phase, "waiting", "closed while waiting: ignored");
        assertEqual(rules.step(shown, { type: "nonsense" }).state.phase, "shown", "an unknown event: unchanged");
        assertEqual(rules.step(shown, slept("maybe")).state.phase, "shown", "an outcome not understood: as unknown");

        // --- the page's line ---
        assertEqual(rules.waitingSince(waiting), 1000, "waiting: the line, with the unlocked sleep's time");
        assertEqual(rules.waitingSince(shown), -1, "shown: the notification, no line yet");
        assertEqual(rules.waitingSince(quiet), -1, "quiet: no line");

        // --- the remembered state ---
        assertEqual(rules.restore(undefined).phase, "quiet", "nothing remembered: quiet");
        assertEqual(rules.restore({ phase: "asleep" }).phase, "quiet", "a phase not understood: quiet");
        assertEqual(rules.restore({ phase: "waiting", at: "junk" }).at, 0, "a time not understood: 0");
        assertEqual(rules.restore({ phase: "shown", at: 7 }).at, 7, "a shown state kept with its time");
        assertEqual(rules.step({ phase: "bogus" }, slept("unlocked", 9)).state.phase, "shown",
                    "a broken remembered state starts the cycle as quiet");

        // --- whole cycles: fixed, then failing again, is told again ---
        let state = quiet;
        const told = [];
        const send = event => {
            const next = rules.step(state, event);
            state = next.state;
            told.push(_actions(next));
        };
        send(slept("unlocked", 10));
        send({ type: "closed", at: 10 });
        send(slept("unlocked", 20));
        send(slept("locked", 30));
        send(slept("unlocked", 40));
        assertEqual(told.join("|"), "notify@10||||notify@40",
                    "told, acknowledged, still unfixed (silent), fixed (silent), failing again: told again");
        assertEqual(state.phase, "shown", "… and shown");

        // --- the look at sleep ---
        const look = facts => JSON.stringify(rules.look(facts));
        const answer = (outcome, done, lookAgain) => JSON.stringify({ outcome: outcome, done: done, lookAgain: lookAgain });
        assertEqual(look({ read: "locked", elapsed: 10 }), answer("locked", true, false), "read locked: done at once");
        assertEqual(look({ read: "unlocked", ownConfirmed: true, elapsed: 10 }), answer("locked", true, false),
                    "the shell's own lock confirmed: locked, whatever was read");
        assertEqual(look({ read: "unlocked", elapsed: 500 }), answer("unlocked", false, true),
                    "unlocked before the deadline: looked at again (another locker may still come up)");
        assertEqual(look({ read: "unlocked", elapsed: 1000 }), answer("unlocked", true, false), "unlocked at the deadline: unlocked");
        assertEqual(look({ read: null, elapsed: 1200 }), answer("unknown", true, false), "no answer by the deadline (a hung read): unknown");
        assertEqual(look({ read: "unknown", elapsed: 1000 }), answer("unknown", true, false), "unknown at the deadline: unknown");
        assertEqual(look({ read: "unlocked", ownLocked: true, elapsed: 1500 }), answer("unknown", false, true),
                    "the shell's own lock still coming up past the deadline: looked at on (its inhibitor holds the machine)");
        assertEqual(look({ read: "unlocked", ownLocked: true, elapsed: 4000 }), answer("unknown", true, false),
                    "… past its own deadline: unknown, never unlocked");
        assertEqual(look({ read: "unlocked", ownLocked: true, ownConfirmed: true, elapsed: 2000 }), answer("locked", true, false),
                    "… confirmed: locked");
        assertEqual(look({ read: "maybe", elapsed: "x" }), answer("unknown", false, true), "facts not understood: unknown, looked at again");
        assertEqual(look(undefined), answer("unknown", false, true), "no facts: unknown, looked at again");
    }
}
