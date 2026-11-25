import QtQuick
import qs.components
import qs.mockups.kit

// The runners' fixture mockup with state cells (the kit's StateGrid), one of them a pointer
// state drawn in its look (the button's `shownLit`, no pointer moved): two cells in a row
// while shooting
MockupWindow {
    id: root

    pointerStates: ["hover"]

    StateGrid {
        cellWidth: 120
        cellHeight: 60
        cellsPerRow: 2

        Repeater {
            model: root.names.length
            StateCell {
                id: cell
                required property int index
                name: root.names[index]

                SmallButton {
                    x: 20
                    y: 20
                    label: "Fixture"
                    checked: cell.name === "checked"
                    shownLit: cell.name === "hover"
                }
            }
        }
    }
}
