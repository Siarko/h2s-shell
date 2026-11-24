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
// No pill has a tooltip: its tip is a window of its own, outside the shot.
MockupWindow {
    id: root

    readonly property var sizes: ["s", "m", "l"]
    scenes: ["idle", "picked"].concat(sizes.map(size => "hover-" + size)).concat(["long-label"])

    function _stateOf(name) {
        return name.replace(/-.*$/, "");
    }
    readonly property string state_: _stateOf(scene)

    contentWidth: 320
    contentHeight: 96
    subject: content_

    function _pill(name, size) {
        const row = _rows.itemAt(Array.prototype.indexOf.call(scenes, name));
        return row ? row.children[sizes.indexOf(size)] : null;
    }

    // The pointer for the scene, once its bindings (its row shown) have followed: a pointer
    // moved onto a row still hidden is not seen by its pills
    onSceneChanged: Qt.callLater(_placePointer, scene)
    function _placePointer(name) {
        if (name !== scene)
            return;
        const pill = _stateOf(name) === "hover" ? _pill(name, name.replace(/^hover-/, "")) : null;
        if (pill)
            pointer.mouseMove(pill, pill.width / 2, pill.height / 2);
        else
            pointer.mouseMove(away, 1, 1);
    }

    TestCase {
        id: pointer
        when: false
    }

    Item {
        id: content_
        anchors.fill: parent

        Item {
            id: away
            width: 4
            height: 4
        }

        Repeater {
            id: _rows
            model: root.scenes.length
            Row {
                required property int index
                readonly property string sceneName: root.scenes[index]
                readonly property bool cut: root._stateOf(sceneName) === "long"
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 16
                visible: sceneName === root.scene

                Repeater {
                    model: ScriptModel { values: root.sizes }
                    Pill {
                        required property string modelData
                        required property int index
                        anchors.verticalCenter: parent.verticalCenter
                        size: modelData
                        label: parent.cut ? "Wireless network, 5 GHz" : "Size " + modelData
                        // The middle one picked: a cut label on both looks
                        picked: root.state_ === "picked" || (parent.cut && index === 1)
                        width: parent.cut ? 80 : implicitWidth
                    }
                }
            }
        }
    }
}
