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

    objectName: "anchors-buttons:Success"
    label: "Keep"
    kind: "success"

    onClicked: _main?.clicked("Success", context)
    Component.onCompleted: {
        _main = module?.main ?? null;
        _context = context;
        _main?.made("Success", _context);
    }
    Component.onDestruction: {
        try {
            _main?.gone("Success", _context);
        } catch (error) {
            // Its main went first (the module turned off)
        }
    }
}
