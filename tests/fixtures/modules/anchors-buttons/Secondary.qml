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

    objectName: "anchors-buttons:Secondary"
    label: "Look"
    kind: "secondary"

    onClicked: _main?.clicked("Secondary", context)
    Component.onCompleted: {
        _main = module?.main ?? null;
        _context = context;
        _main?.made("Secondary", _context);
    }
    Component.onDestruction: {
        try {
            _main?.gone("Secondary", _context);
        } catch (error) {
            // Its main went first (the module turned off)
        }
    }
}
