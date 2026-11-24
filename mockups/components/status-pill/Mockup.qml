import QtQuick
import QtTest
import Quickshell
import qs.singletons
import qs.components
import qs.mockups.kit

// StatusPill in its states:
//   kinds            one pill of each kind ApiElementRules.statusKinds names, no parts
//   parts            an icon, a label and three parts of different kinds, folded
//   hover            the same under the pointer (over its label, not a part: a part's tip is
//                    a window of its own, outside the shot), with a simulated pointer move
//   expanded         the same unfolded: one part per line under a rule
//   not-expandable   with parts but `expandable: false`, under the pointer: no hover look
// The pointer is simulated with QtTest's events: each scene puts it where the scene needs
// it before its frames are waited for, so the look depends on the scene, never on time.
MockupWindow {
    id: root

    readonly property var kinds: ["normal", "muted", "success", "warning", "danger"]
    readonly property var kindIcons: ({ normal: "", muted: "", success: "", warning: "", danger: "" })
    readonly property var parts: [
        { icon: "", text: "4", kind: "success", tip: "4 sent", line: "4 sent" },
        { icon: "", text: "1", kind: "muted", tip: "1 queued", line: "1 queued" },
        { icon: "", text: "1", kind: "danger", tip: "1 failed", line: "1 failed: no connection" }
    ]
    scenes: ["kinds", "parts", "hover", "expanded", "not-expandable"]

    contentWidth: 240
    contentHeight: 5 * 28 + 4 * 8 + 2 * 16
    subject: content_

    // The pointer for the scene, once its bindings (its pill shown) have followed: a pointer
    // moved onto a pill still hidden is not seen by it
    onSceneChanged: Qt.callLater(_placePointer, scene)
    function _placePointer(name) {
        if (name !== scene)
            return;
        const pill = name === "hover" ? hovered : name === "not-expandable" ? fixed : null;
        if (pill)
            pointer.mouseMove(pill, Theme.row.horizontalPadding + 4, pill.collapsedHeight / 2);
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

        Column {
            x: 16
            y: 16
            spacing: 8
            visible: root.scene === "kinds"

            Repeater {
                model: ScriptModel { values: root.kinds }
                StatusPill {
                    required property string modelData
                    icon: root.kindIcons[modelData]
                    label: modelData
                    kind: modelData
                }
            }
        }

        StatusPill {
            x: 16
            y: 16
            visible: root.scene === "parts"
            icon: ""
            label: "Sending 4/6"
            parts: root.parts
        }
        StatusPill {
            id: hovered
            x: 16
            y: 16
            visible: root.scene === "hover"
            icon: ""
            label: "Sending 4/6"
            parts: root.parts
        }
        StatusPill {
            x: 16
            y: 16
            visible: root.scene === "expanded"
            icon: ""
            label: "Sending 4/6"
            parts: root.parts
            expanded: true
        }
        StatusPill {
            id: fixed
            x: 16
            y: 16
            visible: root.scene === "not-expandable"
            icon: ""
            label: "Sending 4/6"
            parts: root.parts
            expandable: false
        }
    }
}
