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

    // Whether running one of a notification's actions also takes its entry away: not for
    // a resident one (the notification spec: it stays after an action)
    function dismissAfterAction(notification): bool {
        return notification?.resident !== true;
    }
}
