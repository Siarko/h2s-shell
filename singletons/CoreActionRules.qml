pragma Singleton

import Quickshell
import QtQuick

// The core widgets' own actions (WidgetRegistry.coreEntries' `actions`): whether an
// action's effect holds, so alternate and cycle start from the state, and what an action
// that reads the state does. Pure functions, so tests/CoreActionRulesTest.qml checks them;
// the widgets read the state and act (their runAction).
Singleton {
    id: root

    // The Dictation widget: whether `id`'s effect holds for the daemon's `server` ("off",
    // "loading", "ready", "error") and `dictation` ("idle", "listening", "speaking") state.
    // Starting the server holds while it runs or loads, stopping it while it is off or
    // failed; dictation the same. undefined for an action that reports no state.
    function sttHolds(id, server, dictation) {
        const serverUp = server === "ready" || server === "loading";
        const dictating = typeof dictation === "string" && dictation !== "idle";
        switch (id) {
        case "start":
            return dictating;
        case "stop":
            return !dictating;
        case "serverStart":
            return serverUp;
        case "serverStop":
            return !serverUp;
        }
        return undefined;
    }

    // "Start or stop the server": which of the two it is now — stop while it runs or loads,
    // else start (off, or failed: a start tries again)
    function sttServerAction(server): string {
        return server === "ready" || server === "loading" ? "serverStop" : "serverStart";
    }

    // The Music widget: playing holds while the player plays, pausing while it does not
    function musicHolds(id, playing) {
        if (id === "play")
            return playing === true;
        if (id === "pause")
            return playing !== true;
        return undefined;
    }

    // The Sound widget's volume after an adjustment of `amount` (notches of a scroll, ±1 a
    // step): one percent a notch, kept between none and 150 %
    function volumeAfter(volume, amount): real {
        if (!isFinite(volume))
            return volume;
        const moved = isFinite(amount) ? volume + amount * 0.01 : volume;
        return Math.max(0, Math.min(1.5, moved));
    }
}
