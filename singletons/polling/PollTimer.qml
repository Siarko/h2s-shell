import QtQuick

// The timer behind every polled source. Its interval comes from a profile setting and
// can change at any time:
//   - an interval of 0 means paused, as does `active` being false
//   - a new interval takes a sample at once, rather than after a full new period —
//     coming back from a slow rate, the graph should not wait 30 s
//   - `paused()` fires when it stops, so a source that measures deltas (CPU, link speed)
//     can drop its baseline instead of averaging over the whole pause
Timer {
    id: root

    // The source's own gate (sensor found, link up, …)
    property bool active: true

    signal paused

    running: interval > 0 && active
    repeat: true
    triggeredOnStart: true

    onIntervalChanged: if (running) restart()
    onRunningChanged: if (!running) paused()
}
