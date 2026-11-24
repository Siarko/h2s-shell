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
// Every scene has a cell of its own, all shown side by side while shooting, the shot cropped
// to the scene's cell; the pointer, when no pill is to be under it, is parked on a strip
// below the cells. Nothing is shown or hidden as the scenes go by, so no pill is ever under
// a pointer left where an earlier scene put it. On screen only the scene's cell is shown.
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
    // The scenes the pointer is over the pill in
    readonly property var pointed: ["hover", "not-expandable"]

    readonly property int cellWidth: 240
    readonly property int cellHeight: 5 * 28 + 4 * 8 + 2 * 16
    readonly property int cellsPerRow: 5
    readonly property int gridHeight: Math.ceil(scenes.length / cellsPerRow) * cellHeight
    contentWidth: shooting ? cellsPerRow * cellWidth : cellWidth
    contentHeight: shooting ? gridHeight + parking.height : cellHeight
    subject: _cells.itemAt(Array.prototype.indexOf.call(scenes, scene)) ?? content_

    // The pointer for the scene, before its frames are waited for
    onSceneChanged: {
        const cell = pointed.includes(scene) ? _cells.itemAt(Array.prototype.indexOf.call(scenes, scene)) : null;
        const pill = cell ? cell.pill : null;
        if (pill)
            pointer.mouseMove(pill, Theme.row.horizontalPadding + 4, pill.collapsedHeight / 2);
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
                readonly property string sceneName: root.scenes[index]
                property alias pill: _pill
                x: root.shooting ? (index % root.cellsPerRow) * root.cellWidth : 0
                y: root.shooting ? Math.floor(index / root.cellsPerRow) * root.cellHeight : 0
                width: root.cellWidth
                height: root.cellHeight
                visible: root.shooting || sceneName === root.scene

                Column {
                    x: 16
                    y: 16
                    spacing: 8
                    visible: cell.sceneName === "kinds"

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

                // The pill with parts, in every scene but "kinds"
                StatusPill {
                    id: _pill
                    x: 16
                    y: 16
                    visible: cell.sceneName !== "kinds"
                    icon: ""
                    label: "Sending 4/6"
                    parts: root.parts
                    expanded: cell.sceneName === "expanded"
                    expandable: cell.sceneName !== "not-expandable"
                }
            }
        }
    }
}
