import QtQuick
import qs.singletons
import qs.components
import qs.mockups.kit

// SystemControlledMark in its states, each a settings row with the setting's label, the mark
// and the setting's control, disabled:
//   beside-button   the value in force (muted) with a disabled Apply
//   beside-switch   a switch, not enabled
//   tip             the button's row drawn as under the pointer: the mark's `shownLit`, its
//                   tooltip open above it (moved from the window's top item into the cell,
//                   which a shot grabs)
// Every state has a cell of its own (the kit's StateGrid lays them out), the shot cropped
// to the state's cell. No pointer is moved.
MockupWindow {
    id: root

    pointerStates: ["tip"]

    StateGrid {
        cellWidth: 320
        cellHeight: 110
        cellsPerRow: 3

        Repeater {
            id: _cells
            model: root.names.length
            StateCell {
                id: cell
                required property int index
                name: root.names[index]
                readonly property string stateName: name
                readonly property bool withSwitch: stateName === "beside-switch"

                Row {
                    x: 16
                    y: parent.height - height - 16
                    width: parent.width - 32
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - parent.spacing * 2 - _mark.width - (cell.withSwitch ? _switch.width : _apply.width)
                        textFormat: Text.PlainText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: cell.withSwitch ? Theme.textPrimary : Theme.textMuted
                        text: cell.withSwitch ? "Hibernate" : "In force: 10 min."
                    }
                    SystemControlledMark {
                        id: _mark
                        anchors.verticalCenter: parent.verticalCenter
                        // The tooltip lies in the window's top item, outside the cell a shot
                        // grabs: here it is moved into the cell, then opened by the change
                        Component.onCompleted: {
                            if (cell.stateName !== "tip")
                                return;
                            for (const child of _mark.children)
                                if (child.objectName === "systemControlledTip")
                                    child.parent = cell;
                            shownLit = true;
                        }
                    }
                    SmallButton {
                        id: _apply
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !cell.withSwitch
                        label: "Apply"
                        kind: "save"
                        available: false
                        fontSize: Theme.fontSizeSmall
                    }
                    ToggleSwitch {
                        id: _switch
                        anchors.verticalCenter: parent.verticalCenter
                        visible: cell.withSwitch
                        checked: true
                        enabled: false
                    }
                }
            }
        }
    }
}
