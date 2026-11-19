import QtQuick
import qs.api

// A button of the fixture's in a card's buttons: tells its module's main when it is made, goes
// and is clicked; it asks first
SmallButton {
    id: button

    property var module: null
    property var context: null
    property var _main: null
    property var _context: null

    objectName: "anchors-buttons:Danger"
    label: "Wipe"
    kind: "danger"
    confirm: true
    onClicked: _main?.clicked("Danger", context)
    Component.onCompleted: {
        _main = module?.main ?? null;
        _context = context;
        _main?.made("Danger", _context);
    }
    Component.onDestruction: {
        try {
            _main?.gone("Danger", _context);
        } catch (error) {
            // Its main went first (the module turned off)
        }
    }
}
