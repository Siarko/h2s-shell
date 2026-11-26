import QtQuick
import QtQuick.Layouts
import qs.components
import qs.mockups.kit

// Notice (the internal line the module API's wraps) in its states, in a settings column
// (308 px):
//   warning, danger, success   one line of each `kind`
//   wrapped                    a long notice of each kind, one under another, wrapped at the
//                              column's width
// Every state has a cell of its own (the kit's StateGrid lays them out), the shot cropped
// to the state's cell.
MockupWindow {
    id: root

    readonly property var kinds: ["warning", "danger", "success"]
    readonly property var lines: ({
        warning: "The key expires in 3 days.",
        danger: "Could not send: the device is offline.",
        success: "Sent to laptop."
    })
    readonly property var long: ({
        warning: "The key expires in 3 days: log in again on this device before then, or it leaves your network.",
        danger: "Could not send holiday-photos.zip: the device went offline before the transfer was done.",
        success: "Sent holiday-photos.zip to laptop; it is in that device's Downloads folder."
    })

    StateGrid {
        id: grid
        cellWidth: 340
        cellHeight: 160
        cellsPerRow: 4

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
                    spacing: 10

                    Notice {
                        visible: cell.name !== "wrapped"
                        kind: cell.name
                        text: root.lines[cell.name] ?? ""
                    }
                    Repeater {
                        model: cell.name === "wrapped" ? root.kinds : []
                        Notice {
                            required property string modelData
                            kind: modelData
                            text: root.long[modelData]
                        }
                    }
                }
            }
        }
    }
}
