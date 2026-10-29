pragma Singleton

import Quickshell
import QtQuick

// Shared time provider — the current date and time, updated every second
Singleton {
    id: time
    readonly property var date: clock.date

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }
}
