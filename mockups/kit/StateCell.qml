import QtQuick

// One state's cell in a StateGrid (its direct child, as a Repeater's delegate places it):
// the state's items as its children, at their places inside the cell. The grid places and
// shows it by the kit's layout; it is the grid's cellWidth x cellHeight unless the mockup
// sizes it otherwise (a shot is cropped to the cell). With every state on a screen only the
// cell under the pointer takes input (StateGrid.qml says why).
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
    enabled: grid ? grid.cellEnabled(name) : false
}
