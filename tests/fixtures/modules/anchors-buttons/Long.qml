import QtQuick
import qs.api

// A button of the fixture's in a card's buttons: tells its module's main when it is made, goes
// and is clicked; its label longer than the region gives it
SmallButton {
    id: button

    property var module: null
    property var context: null
    property var _main: null
    property var _context: null

    objectName: "anchors-buttons:Long"
    label: "A label far longer than a third of the card it stands in"
    kind: "secondary"

    onClicked: _main?.clicked("Long", context)
    Component.onCompleted: {
        _main = module?.main ?? null;
        _context = context;
        _main?.made("Long", _context);
    }
    Component.onDestruction: {
        try {
            _main?.gone("Long", _context);
        } catch (error) {
            // Its main went first (the module turned off)
        }
    }
}
