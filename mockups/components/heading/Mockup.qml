import QtQuick
import QtQuick.Layouts
import qs.components
import qs.panels.settings
import qs.mockups.kit

// Heading in its states, in a settings column (308 px), a hint under it as a page has:
//   plain      the heading alone
//   controls   with a child: a switch at the right end of its line (a page's own switch),
//              the heading filling the width
// Every state has a cell of its own (the kit's StateGrid lays them out), the shot cropped
// to the state's cell.
MockupWindow {
    id: root

    StateGrid {
        id: grid
        cellWidth: 340
        cellHeight: 96
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
                    spacing: 6

                    Heading {
                        visible: cell.name === "plain"
                        text: "Wi-Fi"
                    }
                    Heading {
                        visible: cell.name === "controls"
                        text: "Wi-Fi"
                        ToggleSwitch { checked: true }
                    }
                    Hint { text: "The wireless networks this computer joins." }
                }
            }
        }
    }
}
