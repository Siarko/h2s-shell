import QtQuick
import qs.singletons
import qs.components
import qs.mockups.kit

// ToggleSwitch in its states, each state the settings' small switch and the popups' larger
// one (width 44, height 24, off in Theme.textDisabled) side by side:
//   off, on                     `checked` false, true
//   hover                       off, drawn as under the pointer: its pointer area's
//                               `shownLit` (the switch has no property of its own for it)
//   disabled-off, disabled-on   not `enabled`: dimmed
// The switch takes no keyboard focus. Under the pointer it draws no look of its own yet: the
// hover cell shows what it draws there, the same as off until it has one.
// Every state has a cell of its own (the kit's StateGrid lays them out), the shot cropped
// to the state's cell.
MockupWindow {
    id: root

    pointerStates: ["hover"]

    // Lights the switch's pointer area, as the pointer over it would (PointerArea.shownLit)
    function _light(toggle) {
        for (const child of toggle.children)
            if (child.shownLit !== undefined)
                child.shownLit = true;
    }

    StateGrid {
        cellWidth: 124
        cellHeight: 48
        cellsPerRow: 5

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
                        id: _small
                        anchors.verticalCenter: parent.verticalCenter
                        checked: cell.on
                        enabled: !cell.disabled
                        Component.onCompleted: if (cell.stateName === "hover") root._light(_small)
                    }
                    ToggleSwitch {
                        id: _large
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44
                        height: 24
                        offColor: Theme.textDisabled
                        checked: cell.on
                        enabled: !cell.disabled
                        Component.onCompleted: if (cell.stateName === "hover") root._light(_large)
                    }
                }
            }
        }
    }
}
