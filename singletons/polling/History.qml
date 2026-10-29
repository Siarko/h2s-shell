pragma Singleton

import Quickshell
import QtQuick

// The sample history the graphs draw: [{ t, v, dt }], `dt` being the interval the
// sample was taken at, so HistoryChart can tell a pause (a gap much longer than dt)
// from slow sampling. Kept for one hour, the longest graph window, by age rather than
// by count, since the sampling rate changes with the active profile.
Singleton {
    readonly property int maxAgeMs: 3600000

    function append(history, value, interval, now = Date.now()) {
        const kept = history.length > 0 && history[0].t < now - maxAgeMs
            ? history.filter(point => point.t >= now - maxAgeMs)
            : history.slice();
        kept.push({ t: now, v: value, dt: interval });
        return kept;
    }
}
