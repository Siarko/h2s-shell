import QtQuick
import QtTest
import Quickshell
import qs.singletons
import qs.components
import qs.mockups.kit

// SmallButton in every kind ThemeRules.buttonLook names, in each state it draws. Each scene
// shows one column of every kind, one row each:
//   rest            no pointer, no keyboard
//   disabled        `available: false`
//   checked         `checked: true` (a toggle that is on: the plain kinds take the accent)
//   hover-<kind>    the pointer over that kind's button (a simulated pointer move)
//   pressed-<kind>  the pointer pressed on it, not released (a simulated press)
//   focus-<kind>    that kind's button has the keyboard (the ring inside it)
// The pointer is simulated with QtTest's events: each scene puts it where the scene needs
// it before its frames are waited for, so the look depends on the scene, never on time.
// A pressed button is never released: a release would make the look linger for a moment
// (PointerArea.linger), so the pressed scenes come last, each with its own column.
// "asking" is DeleteButton's state (the first click of a button that asks), not
// SmallButton's: it is not drawn here.
MockupWindow {
    id: root

    readonly property var kinds: ["normal", "save", "saveChange", "action", "cancel", "delete", "warning", "success"]
    readonly property var pressedKinds: ["normal", "save", "delete"]
    scenes: ["rest", "disabled", "checked"]
        .concat(kinds.map(kind => "hover-" + kind))
        .concat(kinds.map(kind => "focus-" + kind))
        .concat(pressedKinds.map(kind => "pressed-" + kind))

    // The scene's state and the kind it is about ("" for all)
    function _stateOf(name) {
        return name.replace(/-.*$/, "");
    }
    function _targetOf(name) {
        return name.indexOf("-") >= 0 ? name.replace(/^[a-z]+-/, "") : "";
    }
    readonly property string state_: _stateOf(scene)

    // The widest button (saveChange) and the column of eight, each 24 px tall, 8 px apart,
    // with 12 px round them
    contentWidth: 140
    contentHeight: 8 * 24 + 7 * 8 + 2 * 12
    subject: content_

    function _button(name, kind) {
        const column = _columns.itemAt(Array.prototype.indexOf.call(scenes, name));
        return column ? column.children[kinds.indexOf(kind)] : null;
    }

    // The pointer and the keyboard for the scene, before its frames are waited for. Taken
    // from `scene` itself, and once the scene's bindings (its column shown) have followed:
    // a pointer moved onto a column still hidden is not seen by its buttons
    onSceneChanged: Qt.callLater(_placePointer, scene)
    function _placePointer(name) {
        if (name !== scene)
            return;
        const state = _stateOf(name);
        const target = _targetOf(name);
        const button = target !== "" ? _button(name, target) : null;
        if (state === "hover" && button)
            pointer.mouseMove(button, button.width / 2, button.height / 2);
        else if (state === "pressed" && button) {
            pointer.mouseMove(button, button.width / 2, button.height / 2);
            pointer.mousePress(button, button.width / 2, button.height / 2);
        }
        else
            pointer.mouseMove(away, 1, 1);
        if (state === "focus" && button)
            button.forceActiveFocus();
        else
            away.forceActiveFocus();
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
            x: 0
            y: 0
            width: 4
            height: 4
        }

        Repeater {
            id: _columns
            model: root.scenes.length
            Column {
                required property int index
                readonly property string sceneName: root.scenes[index]
                x: 12
                y: 12
                spacing: 8
                visible: sceneName === root.scene

                Repeater {
                    model: ScriptModel { values: root.kinds }
                    SmallButton {
                        required property string modelData
                        label: modelData
                        kind: modelData
                        available: root.state_ !== "disabled"
                        checked: root.state_ === "checked"
                    }
                }
            }
        }
    }
}
