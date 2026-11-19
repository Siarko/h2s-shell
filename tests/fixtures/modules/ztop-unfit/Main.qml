import QtQuick
import qs.api

// A soft dependent that is never given the middle module (it asks for a major that module
// does not have): it must not restart when that module does. Tells the test (through
// `report`, set by it) when it goes
QtObject {
    property var module: null
    property var report: null

    Component.onDestruction: {
        if (report)
            report("unfit top gone");
    }
}
