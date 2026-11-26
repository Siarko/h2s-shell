import QtQuick
import QtQuick.Layouts
import qs.components
import qs.mockups.kit

// SettingsRow (the internal row the module API's wraps) in its states, in a settings column
// (308 px):
//   label                a `label` alone
//   label-hint           with a `hint` long enough to wrap
//   value                a `value` on the right
//   controls             two children (a small button, a switch) on the right
//   value-and-controls   a value and a small button after it
//   long-value           a value too long for the room beside a button: the value is cut
//                        at its end, the label keeps its width
//   long-label           a long label beside a value, a long hint wrapped under it
// Every state has a cell of its own (the kit's StateGrid lays them out), the shot cropped
// to the state's cell.
MockupWindow {
    id: root

    readonly property var rows: ({
        label: { label: "Exit node" },
        "label-hint": { label: "Exit node", hint: "Sends all your traffic through another device of your network." },
        value: { label: "Address", value: "100.101.102.103" },
        controls: { label: "Taildrop" },
        "value-and-controls": { label: "Address", value: "100.101.102.103" },
        "long-value": { label: "Save to", value: "/home/user/Downloads/Taildrop/From other devices" },
        "long-label": { label: "Accept files from devices", value: "Never", hint: "Files sent by your other devices; others' devices cannot send any." }
    })

    StateGrid {
        id: grid
        cellWidth: 340
        cellHeight: 84
        cellsPerRow: 4

        Repeater {
            model: root.names.length
            StateCell {
                id: cell
                required property int index
                name: root.names[index]
                readonly property var row: root.rows[cell.name]

                ColumnLayout {
                    x: 16
                    y: 16
                    width: grid.cellWidth - 32

                    SettingsRow {
                        label: cell.row.label
                        hint: cell.row.hint ?? ""
                        value: cell.row.value ?? ""

                        SmallButton {
                            visible: cell.name === "controls" || cell.name === "value-and-controls" || cell.name === "long-value"
                            label: cell.name === "controls" ? "Open folder" : "Copy"
                        }
                        ToggleSwitch {
                            visible: cell.name === "controls"
                            checked: true
                        }
                    }
                }
            }
        }
    }
}
