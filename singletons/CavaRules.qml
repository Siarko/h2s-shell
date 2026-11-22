pragma Singleton

import Quickshell
import QtQuick

// What a run of cava (the music visualiser's levels) came to, when to try it again, and
// what to log — pure, so tests/CavaRulesTest.qml checks every case. CavaReader (I/O) runs
// cava and hands its ends here.
Singleton {
    id: root

    // A run that ended → why, in a line: `exited` false is a run without an exit status
    // (the program could not be started); `stderr` is the lines it printed there, of
    // which the first that says something is kept
    function problem(exited, code, crashed, stderr) {
        if (exited !== true)
            return "cava could not be started";
        const said = _said(stderr);
        if (crashed === true)
            return "cava crashed" + said;
        return "cava exited with code " + code + said;
    }

    // The first line of what it said, on one line and capped, for a log line and a view
    function _said(lines) {
        const first = Array.from(lines ?? []).map(line => String(line).trim()).find(line => line !== "") ?? "";
        const plain = first.replace(/[\u0000-\u001f\u007f]/g, " ").slice(0, 200);
        return plain !== "" ? ": " + plain : "";
    }

    // Whether a run that ended is tried again by itself: one that exited is (a crash, a
    // library gone, a sound server not there yet), one that could not be started is not —
    // the program is not there, and each try would only say so again; it is tried again
    // when asked (the visualiser shown again, its settings changed)
    function retries(exited) {
        return exited === true;
    }

    // How long to wait before the next try after `failures` failed runs in a row (1 or
    // more): `baseMs`, doubled at each failure, at most `mostMs`
    function retryDelay(failures, baseMs, mostMs) {
        const doublings = Math.max(0, (failures ?? 1) - 1);
        return Math.min(baseMs * Math.pow(2, doublings), mostMs);
    }

    // The line to log when the outcome changes from `before` to `after` (each "" while it
    // runs, else its problem); "" when there is nothing new to say
    function logLine(before, after) {
        if (before === after)
            return "";
        if (after === "")
            return "cava runs again";
        return "no levels from cava: " + after;
    }
}
