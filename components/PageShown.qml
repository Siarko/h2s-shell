import QtQuick

// Whether the view it sits in is on screen, for a core page or section that reads the
// system: `shown` is the reading ModuleContribution hands a module's page (module API 1.2) —
// its parent visible and its window open — and `becameShown` comes once each time that turns
// true, the first time included when it is built on screen. The settings window hides instead
// of closing and keeps the open page, and a page switch builds the new page: a read done only
// in Component.onCompleted shows facts from the first opening on every later one.
//
//   PageShown { onBecameShown: Something.refresh() }
//
// It draws nothing and takes no place in a layout (an item not visible is left out).
Item {
    id: root

    visible: false
    width: 0
    height: 0

    readonly property bool shown: (parent?.visible ?? false) && (Window.window?.visible ?? false)
    signal becameShown()

    // Once per showing: the value at creation and its first change may both say true
    property bool _announced: false
    onShownChanged: _follow()
    Component.onCompleted: _follow()
    function _follow() {
        if (!shown) {
            _announced = false;
            return;
        }
        if (_announced)
            return;
        _announced = true;
        becameShown();
    }
}
