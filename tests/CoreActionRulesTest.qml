import QtQuick
import qs.singletons

// The core widgets' own actions: whether their effect holds, and what a state-aware one does
TestCase {
    suiteName: "CoreActionRules"

    function run() {
        const R = CoreActionRules;

        // --- Dictation ---
        assertEqual(["off", "loading", "ready", "error"].map(server => R.sttHolds("serverStart", server, "idle")).join(","), "false,true,true,false",
                    "starting the server holds while it loads or runs");
        assertEqual(["off", "loading", "ready", "error"].map(server => R.sttHolds("serverStop", server, "idle")).join(","), "true,false,false,true",
                    "stopping it holds while it is off or failed");
        assertEqual(["idle", "listening", "speaking"].map(dictation => R.sttHolds("start", "ready", dictation)).join(","), "false,true,true",
                    "starting dictation holds while it listens or speaks");
        assertEqual(["idle", "listening", "speaking"].map(dictation => R.sttHolds("stop", "ready", dictation)).join(","), "true,false,false",
                    "stopping it while idle");
        assert(R.sttHolds("start", "ready", undefined) === false && R.sttHolds("stop", "ready", undefined) === true, "an unknown dictation state: not dictating");
        assert(R.sttHolds("toggle", "ready", "idle") === undefined && R.sttHolds("serverToggle", "ready", "idle") === undefined
               && R.sttHolds("bogus", "off", "idle") === undefined, "an action that reports no state: unknown");
        assertEqual(["off", "loading", "ready", "error", undefined].map(server => R.sttServerAction(server)).join(","),
                    "serverStart,serverStop,serverStop,serverStart,serverStart", "start or stop the server: stop while it loads or runs, else start");

        // --- Music ---
        assert(R.musicHolds("play", true) === true && R.musicHolds("play", false) === false, "playing holds while it plays");
        assert(R.musicHolds("pause", false) === true && R.musicHolds("pause", true) === false, "pausing while it does not");
        assert(R.musicHolds("pause", undefined) === true && R.musicHolds("play", undefined) === false, "… an unknown state: not playing");
        assert(R.musicHolds("next", true) === undefined, "skipping reports no state");

        // --- Sound ---
        const near = (value, expected) => Math.abs(value - expected) < 1e-9;
        assert(near(R.volumeAfter(0.5, 1), 0.51) && near(R.volumeAfter(0.5, -1), 0.49), "one percent a notch, either way");
        assert(near(R.volumeAfter(0.5, 0.5), 0.505), "… a fraction of a notch, a fraction of one");
        assert(near(R.volumeAfter(1.495, 1), 1.5) && near(R.volumeAfter(1.5, 3), 1.5), "never above 150 %");
        assert(near(R.volumeAfter(0.005, -1), 0) && near(R.volumeAfter(0, -2), 0), "never below none");
        assert(near(R.volumeAfter(0.5, NaN), 0.5) && near(R.volumeAfter(0.5, Infinity), 0.5), "an amount that is no number: unchanged");
        assert(isNaN(R.volumeAfter(NaN, 1)), "a volume that is no number: left as it is");
    }
}
