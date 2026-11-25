import QtQuick
import Quickshell
import qs.singletons
import qs.components
import qs.mockups.kit

// StatusPill in its states:
//   kinds            one pill of each kind ApiElementRules.statusKinds names, no parts
//   parts            an icon, a label and three parts of different kinds, folded
//   hover            the same drawn as under the pointer (the pill's `shownLit`)
//   expanded         the same unfolded: one part per line under a rule
//   not-expandable   with parts but `expandable: false`, drawn as under the pointer: no
//                    hover look
// Every state has a cell of its own (the kit's StateGrid lays them out), the shot cropped
// to the state's cell. No pointer is moved: the hover look is the pill's own, drawn the same
// on screen as in the shot (a part's tip, a window of its own, is outside it).
MockupWindow {
    id: root

    readonly property var kinds: ["normal", "muted", "success", "warning", "danger"]
    readonly property var kindIcons: ({ normal: "", muted: "", success: "", warning: "", danger: "" })
    readonly property var parts: [
        { icon: "", text: "4", kind: "success", tip: "4 sent", line: "4 sent" },
        { icon: "", text: "1", kind: "muted", tip: "1 queued", line: "1 queued" },
        { icon: "", text: "1", kind: "danger", tip: "1 failed", line: "1 failed: no connection" }
    ]
    pointerStates: ["hover", "not-expandable"]

    StateGrid {
        id: grid
        cellWidth: 240
        cellHeight: 5 * 28 + 4 * 8 + 2 * 16
        cellsPerRow: 5

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
                    shownLit: Array.prototype.includes.call(root.pointerStates, cell.stateName)
                }
            }
        }
    }
}
