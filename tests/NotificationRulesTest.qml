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

        // --- after an action ---
        assert(NotificationRules.dismissAfterAction({ resident: false }), "not resident: the entry goes");
        assert(NotificationRules.dismissAfterAction({}), "resident not said: the entry goes");
        assert(NotificationRules.dismissAfterAction(null), "no notification: as not resident");
        assert(!NotificationRules.dismissAfterAction({ resident: true }), "resident: the entry stays");
    }
}
