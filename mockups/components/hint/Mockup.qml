import QtQuick
import QtQuick.Layouts
import qs.panels.settings
import qs.mockups.kit

// Hint in its states, at a settings column's width (308 px):
//   short     one line
//   wrapped   a long hint, wrapped at the column's width
// Every state has a cell of its own (the kit's StateGrid lays them out), the shot cropped
// to the state's cell.
MockupWindow {
    id: root

    readonly property var texts: ({
        short: "Shown under the clock.",
        wrapped: "How long a toast stays when the app that sent it does not say; a toast that needs an answer stays until it is answered."
    })

    StateGrid {
        id: grid
        cellWidth: 340
        cellHeight: 80
        cellsPerRow: 2

        Repeater {
            model: root.names.length
            StateCell {
                id: cell
                required property int index
                name: root.names[index]

                ColumnLayout {
                    x: 16
                    y: 16
                    width: grid.cellWidth - 32

                    Hint { text: root.texts[cell.name] }
                }
            }
        }
    }
}
