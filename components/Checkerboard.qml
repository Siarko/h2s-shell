import QtQuick
import qs.singletons

// Squares behind a colour with transparency, so the transparency shows
Item {
    id: root

    property int cellSize: 8

    clip: true

    Grid {
        columns: Math.ceil(root.width / root.cellSize)

        Repeater {
            model: Math.ceil(root.width / root.cellSize) * Math.ceil(root.height / root.cellSize)

            Rectangle {
                required property int index
                readonly property int _columns: Math.ceil(root.width / root.cellSize)
                width: root.cellSize
                height: root.cellSize
                color: (index % _columns + Math.floor(index / _columns)) % 2 === 0 ? Theme.checkerLight : Theme.checkerDark
            }
        }
    }
}
