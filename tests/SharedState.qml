pragma Singleton

import QtQuick
import Quickshell

// The check that a suite leaves what the suites of one Quickshell process share as it found
// it (TestCase): a snapshot (the reader's, SharedStateReader) taken when the suite starts and
// compared when it reports; a difference fails it, naming the keys that changed, never their
// values (a token could be among them).
//
// tests.qml turns the check on by handing over its reader; the modules' runner does not, as
// the module suites share the host by design. The reader is handed over rather than named
// here, so that a suite's closure (tests/affected.sh follows TestCase here) does not take in
// every singleton it reads.
Singleton {
    id: root

    // What reads the shared state: { snapshot() → { key: text }, startupWritten() → bool };
    // set by tests.qml before any suite runs
    property var reader: null
    readonly property bool checking: reader !== null
    // The shell's startup has written what it writes once (the config read, the profiles
    // seeded and migrated): until then an asynchronous suite would be blamed for those
    // writes, so the ones that are checked start once this is true (whenSettled)
    property bool settled: false
    // The asynchronous suites running now: a difference may also come from them
    property var running: []
    // The asynchronous suites that finished while others still ran: reported once the last
    // has finished (TestCase.finish)
    property var unreported: []
    // How many keys a failure names
    readonly property int maxListed: 6
    // How long the startup may take to settle; then the suites start all the same, and say so
    readonly property int settleLimitMs: 5000

    property var _waiting: []

    function snapshot() {
        return reader !== null ? reader.snapshot() : {};
    }

    // The keys whose text differs between two snapshots, or that only one has, sorted
    function changedKeys(before, after) {
        const keys = new Set(Object.keys(before).concat(Object.keys(after)));
        return Array.from(keys).filter(key => before[key] !== after[key]).sort();
    }

    // "A, B and 3 more": at most `cap` keys named
    function listed(keys, cap) {
        if (keys.length <= cap)
            return keys.join(", ");
        return keys.slice(0, cap).join(", ") + " and " + (keys.length - cap) + " more";
    }

    // Runs `prepare`, then `start`, once the startup has settled (later in the event loop, at
    // once when it has): of the suites waiting, every `prepare` before the first `start`
    function whenSettled(prepare, start) {
        if (settled) {
            Qt.callLater(() => { prepare(); start(); });
            return;
        }
        _waiting = _waiting.concat([{ prepare: prepare, start: start }]);
        _settle.start();
    }

    // Settled: the startup's writes made, and the snapshot the same on three ticks in a row
    property Timer _settle: Timer {
        interval: 50
        repeat: true
        property string last: ""
        property int same: 0
        property int waited: 0
        onTriggered: {
            waited += interval;
            const now = JSON.stringify(root.snapshot());
            same = now === last ? same + 1 : 0;
            last = now;
            const ready = root.reader !== null && root.reader.startupWritten() && same >= 2;
            if (!ready && waited < root.settleLimitMs)
                return;
            if (!ready)
                console.log("SHARED-STATE: the startup did not settle in " + root.settleLimitMs / 1000
                            + " s; a suite may be blamed for its writes");
            stop();
            root.settled = true;
            const waiting = root._waiting;
            root._waiting = [];
            for (const entry of waiting)
                entry.prepare();
            for (const entry of waiting)
                entry.start();
        }
    }
}
