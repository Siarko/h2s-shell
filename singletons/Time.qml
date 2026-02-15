pragma Singleton

import Quickshell
import QtQuick

// Shared time provider — exposes a formatted clock string updated every second
Singleton {
    id: time
    readonly property string time: {
        Qt.formatDateTime(clock.date, "hh:mm:ss dd-MM-yyyy");
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }
}
