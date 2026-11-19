import QtQuick
import qs.api

// The top of a chain, by a soft use: as it goes it still calls the middle module's API, and tells the
// test (through `report`, set by it) what it got
QtObject {
    property var module: null
    property var report: null

    Component.onDestruction: {
        let answer;
        try {
            answer = module.uses.zmid ? module.uses.zmid.ping() : "none";
        } catch (error) {
            answer = "ERR " + error.name;
        }
        if (report)
            report("soft top gone, mid ping=" + answer);
    }
}
