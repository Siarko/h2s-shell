import QtQuick
import qs.api

// A button of the fixture's in a card's buttons: tells its module's main when it is made, goes
// and is clicked
SmallButton {
    id: button

    property var module: null
    property var context: null
    property var _main: null
    property var _context: null

    objectName: "anchors-buttons:Warning"
    label: "Risk"
    kind: "warning"

    onClicked: _main?.clicked("Warning", context)
    Component.onCompleted: {
        _main = module?.main ?? null;
        _context = context;
        _main?.made("Warning", _context);
    }
    Component.onDestruction: {
        try {
            _main?.gone("Warning", _context);
        } catch (error) {
            // Its main went first (the module turned off)
        }
    }
}
