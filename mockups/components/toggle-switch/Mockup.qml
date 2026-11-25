import QtQuick
import qs.singletons
import qs.components
import qs.mockups.kit

// ToggleSwitch in its states, each state the settings' small switch and the popups' larger
// one (width 44, height 24, off in Theme.textDisabled) side by side:
//   off, on                     `checked` false, true
//   disabled-off, disabled-on   not `enabled`: dimmed
// The switch has no look of its own under the pointer or with the keyboard: it takes no
// keyboard focus, and its pointer area only gives the cursor and the click.
// Every state has a cell of its own (the kit's StateGrid lays them out), the shot cropped
// to the state's cell, as in the mockups that move a pointer.
MockupWindow {
    id: root

    StateGrid {
        cellWidth: 124
        cellHeight: 48
        cellsPerRow: 4

        Repeater {
            id: _cells
            model: root.names.length
            StateCell {
                id: cell
                required property int index
                name: root.names[index]
                readonly property string stateName: name
                readonly property bool on: stateName === "on" || stateName === "disabled-on"
                readonly property bool disabled: stateName.startsWith("disabled-")

                Row {
                    anchors.centerIn: parent
                    spacing: 20

                    ToggleSwitch {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: cell.on
                        enabled: !cell.disabled
                    }
                    ToggleSwitch {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44
                        height: 24
                        offColor: Theme.textDisabled
                        checked: cell.on
                        enabled: !cell.disabled
                    }
                }
            }
        }
    }
}
