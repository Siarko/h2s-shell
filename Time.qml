pragma Singleton

import Quickshell
import QtQuick

Singleton {
    id: time
    readonly property string time: {
        Qt.formatDateTime(clock.date, "hh:mm:ss");
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }
}
