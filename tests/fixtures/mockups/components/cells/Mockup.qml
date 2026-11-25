import QtQuick
import QtTest
import qs.components
import qs.mockups.kit

// The runners' fixture mockup with state cells (the kit's StateGrid), one of them a pointer
// state: two cells in a row while shooting, the pointer parked under them
MockupWindow {
    id: root

    pointerStates: ["hover"]

    onCurrentChanged: {
        const cell = _cells.itemAt(Array.prototype.indexOf.call(names, current));
        if (current === "hover" && cell)
            pointer.mouseMove(cell.button, cell.button.width / 2, cell.button.height / 2);
        else
            pointer.mouseMove(grid.parking, grid.parking.width / 2, grid.parking.height / 2);
    }

    TestCase {
        id: pointer
        when: false
    }

    StateGrid {
        id: grid
        cellWidth: 120
        cellHeight: 60
        cellsPerRow: 2
        parkingHeight: 8

        Repeater {
            id: _cells
            model: root.names.length
            StateCell {
                id: cell
                required property int index
                name: root.names[index]
                property alias button: _button

                SmallButton {
                    id: _button
                    x: 20
                    y: 20
                    label: "Fixture"
                    checked: cell.name === "checked"
                }
            }
        }
    }
}
