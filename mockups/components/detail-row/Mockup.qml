import QtQuick
import QtQuick.Layouts
import qs.panels.settings
import qs.mockups.kit

// DetailRow in its states, in a settings column (308 px) of three details, the middle one
// the state's:
//   value        a short value beside its label
//   long-value   a value too long for the line (a key, an address): wrapped anywhere
//   empty        `value: ""`: the row hidden, the two around it close up
// Every state has a cell of its own (the kit's StateGrid lays them out), the shot cropped
// to the state's cell.
MockupWindow {
    id: root

    readonly property var middle: ({
        value: "192.168.1.1",
        "long-value": "fd7a:115c:a1e0:ab12:4843:cd96:6258:b240/128, 100.101.102.103/32",
        empty: ""
    })

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
                    y: 16
                    width: grid.cellWidth - 32
                    spacing: 4

                    DetailRow { label: "Address"; value: "192.168.1.20/24" }
                    DetailRow { label: "Gateway"; value: root.middle[cell.name] }
                    DetailRow { label: "DNS"; value: "192.168.1.1" }
                }
            }
        }
    }
}
