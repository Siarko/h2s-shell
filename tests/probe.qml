//@ pragma UseQApplication
import QtQuick

// One-off engine probe for docs/TODO.md item 1.5: can the hand-rolled Promises library
// be replaced with the engine's own? Native `Promise` and `async`/`await` are two
// separate questions — V4 has had Promise for a long time but historically not async
// functions. Delete this file once 1.5 is decided.
//
// Run from the repo root:  quickshell -p tests/probe.qml
QtObject {
    Component.onCompleted: {
        const hasPromise = typeof Promise !== "undefined";
        console.log("[PROBE] native Promise:", hasPromise ? "yes" : "NO");

        if (hasPromise) {
            // allSettled is the one the shell actually uses; any/finally are nice to know
            console.log("[PROBE]   Promise.allSettled:", typeof Promise.allSettled);
            console.log("[PROBE]   Promise.any:", typeof Promise.any);
            console.log("[PROBE]   Promise.prototype.finally:", typeof Promise.prototype.finally);
        }

        // eval keeps a parse failure local — an `async function` written straight into
        // this file would take the whole file down, which answers the question too but
        // tells you nothing else.
        var asyncSupported = false;
        try {
            eval("(async () => 1)");
            asyncSupported = true;
        } catch (parseError) {
            console.log("[PROBE]   async parse error:", parseError);
        }
        console.log("[PROBE] async/await:", asyncSupported ? "yes" : "NO");

        // The migration hinges on this: the hand-rolled then() runs its handler inline
        // when the promise is already settled, native defers to a microtask. If this
        // line never prints, microtasks are not being drained and the library stays.
        if (hasPromise)
            Promise.resolve("ok").then(value => console.log("[PROBE] microtask drained:", value));
    }

    // Long enough for the microtask above to land before the process exits
    property var _quit: Timer {
        interval: 1000
        running: true
        onTriggered: Qt.quit()
    }
}
