import QtQuick
import qs.api

// The middle of a chain: its exports answer ping() for as long as this main lives; it
// tells the test (through `report`, set by it) when it goes
QtObject {
    property var module: null
    property var report: null

    readonly property QtObject exports: QtObject {
        function ping() {
            return "pong";
        }
    }

    Component.onDestruction: {
        if (report)
            report("mid gone");
    }
}
