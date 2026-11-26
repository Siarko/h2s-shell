import QtQuick
import QtQuick.Layouts
import qs.panels.settings
import qs.mockups.kit

// SwitchRow in its states, in a settings column (308 px):
//   off, on       `checked` false, true; a label alone
//   hint          with a `hint` long enough to wrap
//   privileged    `need: "auth"` (polkit asks for a password): the lock before the switch
//   not-allowed   `need: "no"`: the crossed mark, the switch off and dimmed
//   kept          `need: "auth"` with `remembered` kept for ten minutes past the kit's
//                 `now`: the open lock, dimmed
//   disabled      `enabled: false`, as a page sets it where the setting does not apply: the
//                 switch dims itself, the texts stay as they are
// Every state has a cell of its own (the kit's StateGrid lays them out), the shot cropped
// to the state's cell.
MockupWindow {
    id: root

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

                ColumnLayout {
                    x: 16
                    y: 16
                    width: grid.cellWidth - 32

                    SwitchRow {
                        label: cell.name === "off" || cell.name === "on" ? "Wi-Fi" : "Wake on LAN"
                        hint: cell.name === "off" || cell.name === "on" ? ""
                            : "Lets another computer on the network wake this one from sleep."
                        checked: cell.name !== "off" && cell.name !== "not-allowed"
                        need: cell.name === "privileged" || cell.name === "kept" ? "auth"
                            : cell.name === "not-allowed" ? "no" : ""
                        remembered: cell.name === "kept" ? { kept: true, untilMs: root.now.getTime() + 600000 } : null
                        enabled: cell.name !== "disabled"
                    }
                }
            }
        }
    }
}
