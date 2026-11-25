import QtQuick

// One state's cell in a StateGrid (its direct child, as a Repeater's delegate places it):
// the state's items as its children, at their places inside the cell. The grid places and
// shows it by the kit's layout; it is the grid's cellWidth x cellHeight unless the mockup
// sizes it otherwise (a shot is cropped to the cell). On screen, a pointer or keyboard
// state's cell (the kit's pointerStates, keyboardStates) lies under a catcher that takes the
// real pointer — hover, presses — before the state's items do: their look, drawn by the
// mockup, stays as it is. The items stay enabled (`enabled: false` would dim some of them);
// the wheel passes through to the window's scroller.
Item {
    id: cell

    readonly property bool isStateCell: true
    // The state the cell shows, one of the kit's names
    required property string name

    readonly property Item grid: parent && parent.isStateGrid ? parent : null
    readonly property point _place: grid ? grid.cellPlace(name) : Qt.point(0, 0)

    x: _place.x
    y: _place.y
    width: grid ? grid.cellWidth : 0
    height: grid ? grid.cellHeight : 0
    visible: grid ? grid.cellShown(name) : false

    MouseArea {
        z: 1
        anchors.fill: parent
        visible: cell.grid ? cell.grid.cellFrozen(cell.name) : false
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
    }
}
