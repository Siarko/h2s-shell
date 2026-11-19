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

    objectName: "anchors-buttons:Primary"
    label: "Go"
    kind: "primary"
    // Its own size: kept in a card, whose stack gives "m" only to a button that sets none
    size: "s"
    onClicked: _main?.clicked("Primary", context)
    Component.onCompleted: {
        _main = module?.main ?? null;
        _context = context;
        _main?.made("Primary", _context);
    }
    Component.onDestruction: {
        try {
            _main?.gone("Primary", _context);
        } catch (error) {
            // Its main went first (the module turned off)
        }
    }
}
