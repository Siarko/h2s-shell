import QtQuick
import QtQuick.Layouts
import qs.components
import qs.panels.settings
import qs.mockups.kit

// SectionTitle in its states, in a settings column (308 px) as a page lays it out, a hint
// under it as the section's first line:
//   plain      `divider` on (after the page's own rows): the line across the column
//   first      `divider: false` (the first section under a page's heading): no line
//   controls   with children: a switch and a small button at the right end of its line,
//              the title filling the width
// Every state has a cell of its own (the kit's StateGrid lays them out), the shot cropped
// to the state's cell.
MockupWindow {
    id: root

    StateGrid {
        id: grid
        cellWidth: 340
        cellHeight: 112
        cellsPerRow: 3

        Repeater {
            model: root.names.length
            StateCell {
                id: cell
                required property int index
                name: root.names[index]

                ColumnLayout {
                    x: 16
                    y: 0
                    width: grid.cellWidth - 32
                    spacing: 0

                    SectionTitle {
                        visible: cell.name !== "controls"
                        text: "Taildrop"
                        divider: cell.name !== "first"
                    }
                    SectionTitle {
                        visible: cell.name === "controls"
                        text: "Taildrop"
                        ToggleSwitch { checked: true }
                        SmallButton { label: "Open folder" }
                    }
                    Hint { text: "Files sent from your other devices land in Downloads." }
                }
            }
        }
    }
}
