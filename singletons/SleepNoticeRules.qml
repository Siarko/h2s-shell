pragma Singleton

import Quickshell
import QtQuick

// The sleep notice, by the outcome of each sleep — pure, so tests/SleepNoticeRulesTest.qml
// checks the cycle without logind or a notification server. A sleep's outcome is "locked",
// "unlocked" or "unknown" (no lock state could be read), observed at PrepareForSleep; no
// program names, no prediction.
//
//   quiet ── slept unlocked ──▶ shown ── closed ──▶ waiting ── slept locked ──▶ quiet
//                                 └──── slept locked (fixed before it was read) ──▶ quiet
//
// "shown" is the critical notification, one at a time; closing it acknowledges it, and the
// Lock screen page keeps a line while it waits for a sleep that locks. A system that was
// fixed and fails again is told again; there is no "Don't tell me again". An unknown
// outcome never raises an alarm. The state is remembered data (Config), so a restart
// neither repeats nor loses it.
Singleton {
    id: root

    readonly property var phases: ["quiet", "shown", "waiting"]

    // `at`: the time (wall clock ms) of the unlocked sleep the notice is about, 0 in quiet
    function initial() {
        return { phase: "quiet", at: 0 };
    }

    // A remembered state, as Config read it back: anything not understood is quiet
    function restore(saved) {
        if (saved === null || typeof saved !== "object" || !phases.includes(saved.phase))
            return initial();
        if (saved.phase === "quiet")
            return initial();
        const at = Number(saved.at);
        return { phase: saved.phase, at: isFinite(at) && at > 0 ? at : 0 };
    }

    // The page's line, while the notice waits for a fix: → its time, or −1 for no line
    function waitingSince(state) {
        return state?.phase === "waiting" ? state.at : -1;
    }

    // `event`: { type: "slept", outcome: "locked" | "unlocked" | "unknown", at } (after the
    // resume), { type: "closed", at } (the notification about the sleep at `at` closed: ×,
    // or its action; a close of one since replaced is ignored), or
    // { type: "restarted" } (the shell started with this remembered state). → { state,
    // actions }: notify { at } (show the notification, replacing one shown), withdraw (take
    // it back). A changed state is for the caller to remember.
    function step(state, event) {
        const current = restore(state);
        const stay = { state: current, actions: [] };
        switch (event?.type) {
        case "slept":
            if (event.outcome === "unlocked") {
                const at = Number(event.at) || 0;
                if (current.phase === "quiet" || current.phase === "shown")
                    return { state: { phase: "shown", at: at }, actions: [{ type: "notify", at: at }] };
                // Waiting: still not fixed; the page's line takes the new time
                return { state: { phase: "waiting", at: at }, actions: [] };
            }
            if (event.outcome === "locked") {
                if (current.phase === "shown")
                    return { state: initial(), actions: [{ type: "withdraw" }] };
                return { state: initial(), actions: [] };
            }
            // Unknown, or anything else: no lock state could be read, never an alarm
            return stay;
        case "closed":
            if (current.phase === "shown" && Number(event.at) === current.at)
                return { state: { phase: "waiting", at: current.at }, actions: [] };
            return stay;
        case "restarted":
            if (current.phase === "shown")
                return { state: current, actions: [{ type: "notify", at: current.at }] };
            return stay;
        default:
            return stay;
        }
    }
}
