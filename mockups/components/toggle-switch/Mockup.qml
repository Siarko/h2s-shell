import QtQuick
import qs.singletons
import qs.components
import qs.mockups.kit

// ToggleSwitch in its states, each state a column: the settings' small switch above the
// popups' larger one (width 44, height 24), both in the same colours:
//   off, on                     `checked` false, true
//   hover, hover-on             off and on, drawn as under the pointer: its pointer area's
//                               `shownLit` (the switch has no property of its own for it)
//   disabled-off, disabled-on   not `enabled`: dimmed
// The switch takes no keyboard focus.
// Every state has a cell of its own (the kit's StateGrid lays them out), the shot cropped
// to the state's cell.
MockupWindow {
    id: root

    pointerStates: ["hover", "hover-on"]

    // Lights the switch's pointer area, as the pointer over it would (PointerArea.shownLit)
    function _light(toggle) {
        for (const child of toggle.children)
            if (child.shownLit !== undefined)
                child.shownLit = true;
    }

    StateGrid {
        cellWidth: 72
        cellHeight: 72
        cellsPerRow: 6

        Repeater {
            id: _cells
            model: root.names.length
            StateCell {
                id: cell
                required property int index
                name: root.names[index]
                readonly property string stateName: name
                readonly property bool on: stateName === "on" || stateName === "hover-on" || stateName === "disabled-on"
                readonly property bool lit: stateName.startsWith("hover")
                readonly property bool disabled: stateName.startsWith("disabled-")

                Column {
                    anchors.centerIn: parent
                    spacing: 12

                    ToggleSwitch {
                        id: _small
                        anchors.horizontalCenter: parent.horizontalCenter
                        checked: cell.on
                        enabled: !cell.disabled
                        Component.onCompleted: if (cell.lit) root._light(_small)
                    }
                    ToggleSwitch {
                        id: _large
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 44
                        height: 24
                        checked: cell.on
                        enabled: !cell.disabled
                        Component.onCompleted: if (cell.lit) root._light(_large)
                    }
                }
            }
        }
    }
}
