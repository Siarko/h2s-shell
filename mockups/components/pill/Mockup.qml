import QtQuick
import QtTest
import Quickshell
import qs.singletons
import qs.components
import qs.mockups.kit

// Pill in its states, each scene a row of the three sizes (s, m, l):
//   idle             not picked, no pointer
//   picked           picked (filled with the accent)
//   hover-<size>     the pointer over that size's pill, not picked (a simulated pointer move)
//   long-label       a label longer than the pill is wide: cut at the right, idle and picked
// The pointer is simulated with QtTest's events: each scene puts it where the scene needs
// it before its frames are waited for, so the look depends on the scene, never on time.
// Every scene has a cell of its own, all shown side by side while shooting, the shot cropped
// to the scene's cell; the pointer, when no pill is to be under it, is parked on a strip
// below the cells. Nothing is shown or hidden as the scenes go by, so no pill is ever under
// a pointer left where an earlier scene put it. On screen only the scene's cell is shown.
// No pill has a tooltip: its tip is a window of its own, outside the shot.
MockupWindow {
    id: root

    readonly property var sizes: ["s", "m", "l"]
    scenes: ["idle", "picked"].concat(sizes.map(size => "hover-" + size)).concat(["long-label"])

    function _stateOf(name) {
        return name.replace(/-.*$/, "");
    }

    readonly property int cellWidth: 320
    readonly property int cellHeight: 96
    readonly property int cellsPerRow: 3
    readonly property int gridHeight: Math.ceil(scenes.length / cellsPerRow) * cellHeight
    contentWidth: shooting ? cellsPerRow * cellWidth : cellWidth
    contentHeight: shooting ? gridHeight + parking.height : cellHeight
    subject: _cells.itemAt(Array.prototype.indexOf.call(scenes, scene)) ?? content_

    function _pill(name, size) {
        const cell = _cells.itemAt(Array.prototype.indexOf.call(scenes, name));
        return cell ? cell.row.children[sizes.indexOf(size)] : null;
    }

    // The pointer for the scene, before its frames are waited for
    onSceneChanged: {
        const pill = _stateOf(scene) === "hover" ? _pill(scene, scene.replace(/^hover-/, "")) : null;
        if (pill)
            pointer.mouseMove(pill, pill.width / 2, pill.height / 2);
        else
            pointer.mouseMove(parking, parking.width / 2, parking.height / 2);
    }

    TestCase {
        id: pointer
        when: false
    }

    Item {
        id: content_
        anchors.fill: parent

        // Where the pointer rests off every cell
        Item {
            id: parking
            y: root.gridHeight
            width: parent.width
            height: 8
        }

        Repeater {
            id: _cells
            model: root.scenes.length
            Item {
                id: cell
                required property int index
                readonly property bool cut: root._stateOf(root.scenes[index]) === "long"
                readonly property bool picked: root.scenes[index] === "picked"
                property alias row: _row
                x: root.shooting ? (index % root.cellsPerRow) * root.cellWidth : 0
                y: root.shooting ? Math.floor(index / root.cellsPerRow) * root.cellHeight : 0
                width: root.cellWidth
                height: root.cellHeight
                visible: root.shooting || root.scenes[index] === root.scene

                Row {
                    id: _row
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
                        }
                    }
                }
            }
        }
    }
}
