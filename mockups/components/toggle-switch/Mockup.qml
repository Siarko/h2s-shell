import QtQuick
import qs.singletons
import qs.components
import qs.mockups.kit

// ToggleSwitch in its states, each scene the settings' small switch and the popups' larger
// one (width 44, height 24, off in Theme.textDisabled) side by side:
//   off, on                     `checked` false, true
//   disabled-off, disabled-on   not `enabled`: dimmed
// The switch has no look of its own under the pointer or with the keyboard: it takes no
// keyboard focus, and its pointer area only gives the cursor and the click.
// Every scene has a cell of its own, all shown side by side while shooting, the shot cropped
// to the scene's cell, as in the mockups that move a pointer; on screen only the scene's
// cell is shown.
MockupWindow {
    id: root

    scenes: ["off", "on", "disabled-off", "disabled-on"]

    readonly property int cellWidth: 124
    readonly property int cellHeight: 48
    readonly property int cellsPerRow: 4
    contentWidth: shooting ? cellsPerRow * cellWidth : cellWidth
    contentHeight: shooting ? Math.ceil(scenes.length / cellsPerRow) * cellHeight : cellHeight
    subject: _cells.itemAt(Array.prototype.indexOf.call(scenes, scene)) ?? content_

    Item {
        id: content_
        anchors.fill: parent

        Repeater {
            id: _cells
            model: root.scenes.length
            Item {
                id: cell
                required property int index
                readonly property string sceneName: root.scenes[index]
                readonly property bool on: sceneName === "on" || sceneName === "disabled-on"
                readonly property bool disabled: sceneName.startsWith("disabled-")
                x: root.shooting ? (index % root.cellsPerRow) * root.cellWidth : 0
                y: root.shooting ? Math.floor(index / root.cellsPerRow) * root.cellHeight : 0
                width: root.cellWidth
                height: root.cellHeight
                visible: root.shooting || sceneName === root.scene

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
