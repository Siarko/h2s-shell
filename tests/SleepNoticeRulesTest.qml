import QtQuick
import qs.singletons

// The sleep notice's cycle (singletons/SleepNoticeRules.qml): every row of the plan's
// table (notes/plans/idle-lock-flow.md §14), then whole cycles.
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

        result = rules.step(shown, { type: "closed" });
        assertEqual(result.state.phase, "waiting", "shown, closed: waiting (acknowledged)");
        assertEqual(result.state.at, 1000, "… the time kept for the page's line");
        assertEqual(_actions(result), "", "… nothing to do");

        result = rules.step(shown, slept("unlocked", 3000));
        assertEqual(result.state.phase, "shown", "shown, slept unlocked again: still shown");
        assertEqual(_actions(result), "notify@3000", "… the notification replaced, its time updated");

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
        send({ type: "closed" });
        send(slept("unlocked", 20));
        send(slept("locked", 30));
        send(slept("unlocked", 40));
        assertEqual(told.join("|"), "notify@10||||notify@40",
                    "told, acknowledged, still unfixed (silent), fixed (silent), failing again: told again");
        assertEqual(state.phase, "shown", "… and shown");
    }
}
