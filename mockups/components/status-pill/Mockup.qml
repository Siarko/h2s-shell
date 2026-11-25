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
// The pointer is simulated with QtTest's events: each state puts it where the state needs
// it before its frames are waited for, so the look depends on the state, never on time.
// Every state has a cell of its own (the kit's StateGrid lays them out), the shot cropped
// to the state's cell; the pointer, when no pill is to be under it, is parked on the grid's
// strip below the cells. Nothing is shown or hidden as the states go by, so no pill is ever
// under a pointer left where an earlier state put it.
MockupWindow {
    id: root

    readonly property var kinds: ["normal", "muted", "success", "warning", "danger"]
    readonly property var kindIcons: ({ normal: "", muted: "", success: "", warning: "", danger: "" })
    readonly property var parts: [
        { icon: "", text: "4", kind: "success", tip: "4 sent", line: "4 sent" },
        { icon: "", text: "1", kind: "muted", tip: "1 queued", line: "1 queued" },
        { icon: "", text: "1", kind: "danger", tip: "1 failed", line: "1 failed: no connection" }
    ]
    // The states the pointer is over the pill in
    readonly property var pointed: ["hover", "not-expandable"]
    pointerStates: pointed

    // The pointer for the state, before its frames are waited for
    onCurrentChanged: {
        const cell = pointed.includes(current) ? _cells.itemAt(Array.prototype.indexOf.call(names, current)) : null;
        const pill = cell ? cell.pill : null;
        if (pill)
            pointer.mouseMove(pill, Theme.row.horizontalPadding + 4, pill.collapsedHeight / 2);
        else
            pointer.mouseMove(grid.parking, grid.parking.width / 2, grid.parking.height / 2);
    }

    TestCase {
        id: pointer
        when: false
    }

    StateGrid {
        id: grid
        cellWidth: 240
        cellHeight: 5 * 28 + 4 * 8 + 2 * 16
        cellsPerRow: 5
        parkingHeight: 8

        Repeater {
            id: _cells
            model: root.names.length
            StateCell {
                id: cell
                required property int index
                name: root.names[index]
                readonly property string stateName: name
                property alias pill: _pill

                Column {
                    x: 16
                    y: 16
                    spacing: 8
                    visible: cell.stateName === "kinds"

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

                // The pill with parts, in every state but "kinds"
                StatusPill {
                    id: _pill
                    x: 16
                    y: 16
                    visible: cell.stateName !== "kinds"
                    icon: ""
                    label: "Sending 4/6"
                    parts: root.parts
                    expanded: cell.stateName === "expanded"
                    expandable: cell.stateName !== "not-expandable"
                }
            }
        }
    }
}
