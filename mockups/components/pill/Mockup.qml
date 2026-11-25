import QtQuick
import Quickshell
import qs.singletons
import qs.components
import qs.mockups.kit

// Pill in its states, each state a row of the three sizes (s, m, l):
//   idle             not picked, no pointer
//   picked           picked (filled with the accent)
//   hover            every size drawn as under the pointer (the pill's `shownLit`): the
//                    look only recolours the background, the same at every size, so one
//                    state shows them all
//   long-label       a label longer than the pill is wide: cut at the right, idle and picked
// Every state has a cell of its own (the kit's StateGrid lays them out), the shot cropped
// to the state's cell. No pointer is moved: the hover look is the pill's own, drawn the same
// on screen as in the shot.
// No pill has a tooltip: its tip is a window of its own, outside the shot.
MockupWindow {
    id: root

    readonly property var sizes: ["s", "m", "l"]

    function _stateOf(name) {
        return name.replace(/-.*$/, "");
    }

    pointerStates: ["hover"]

    StateGrid {
        id: grid
        cellWidth: 320
        cellHeight: 96
        cellsPerRow: 3

        Repeater {
            id: _cells
            model: root.names.length
            StateCell {
                id: cell
                required property int index
                name: root.names[index]
                readonly property bool cut: root._stateOf(root.names[index]) === "long"
                readonly property bool picked: root.names[index] === "picked"
                readonly property bool lit: root.names[index] === "hover"

                Row {
                    x: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 16

                    Repeater {
                        model: ScriptModel { values: root.sizes }
                        Pill {
                            required property string modelData
                            required property int index
                            anchors.verticalCenter: parent.verticalCenter
                            size: modelData
                            label: cell.cut ? "Wireless network, 5 GHz" : "Size " + modelData
                            // The middle one picked: a cut label on both looks
                            picked: cell.picked || (cell.cut && index === 1)
                            width: cell.cut ? 80 : implicitWidth
                            shownLit: cell.lit
                        }
                    }
                }
            }
        }
    }
}
