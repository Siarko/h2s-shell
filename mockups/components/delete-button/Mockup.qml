import QtQuick
import qs.components
import qs.mockups.kit

// DeleteButton in its states. Each cell is a column of its two kinds — "delete", and
// "save" for a button that asks before turning something on — each with a short and a long
// label, every button of the cell in the state's look:
//   rest           at rest, not asking
//   hover          drawn as under the pointer (the button's `shownLit`)
//   focus          drawn as with the keyboard (its `shownFocused`): the ring inside
//   asking         `asking: true`: the question, the × attached
//   asking-hover   asking, drawn as under the pointer: the question and the × lit at once
//                  (one pointer would light one of them; the preview lights both)
//   disabled       `available: false`: dimmed; the short labels at rest, the long ones
//                  asking
//   cut            `maximumWidth: 96`: the long label at rest and its question, each cut
//   wraps          `maximumWidth: 140` with `wraps: true`: on more lines, the button
//                  taller
// No pointer or keyboard is moved: the looks are the button's own, drawn the same on screen
// as in the shot. The tooltips open only under a real pointer, so none shows here.
MockupWindow {
    id: root

    pointerStates: ["hover", "asking-hover"]
    keyboardStates: ["focus"]

    readonly property var _texts: ({
        delete: { short: ["Delete", "Delete?"], long: ["Delete preset", "Delete everywhere?"] },
        save: { short: ["Turn on", "Turn on?"], long: ["Start hotspot", "Start the hotspot now?"] }
    })

    // The buttons of a cell: kind, long label or short, asking
    function _buttons(name) {
        const narrow = name === "cut" || name === "wraps";
        const list = [];
        for (const kind of ["delete", "save"]) {
            if (narrow) {
                list.push({ kind: kind, long: true, asking: false });
                list.push({ kind: kind, long: true, asking: true });
            } else {
                const asking = name === "asking" || name === "asking-hover";
                list.push({ kind: kind, long: false, asking: asking });
                list.push({ kind: kind, long: true, asking: asking || name === "disabled" });
            }
        }
        return list;
    }

    // A cell: room for the longest question and its × on one line, and a column of four
    // buttons, two of them on two lines where they wrap
    StateGrid {
        cellWidth: 224
        cellHeight: 200
        cellsPerRow: 4

        Repeater {
            model: root.names.length
            StateCell {
                id: cell
                required property int index
                name: root.names[index]

                Column {
                    x: 16
                    y: 16
                    spacing: 8

                    Repeater {
                        model: root._buttons(cell.name).length
                        DeleteButton {
                            required property int index
                            readonly property var spec: root._buttons(cell.name)[index]
                            readonly property var texts: root._texts[spec.kind][spec.long ? "long" : "short"]
                            kind: spec.kind
                            label: texts[0]
                            confirmLabel: texts[1]
                            asking: spec.asking
                            available: cell.name !== "disabled"
                            maximumWidth: cell.name === "cut" ? 96 : cell.name === "wraps" ? 140 : Infinity
                            wraps: cell.name === "wraps"
                            shownLit: cell.name === "hover" || cell.name === "asking-hover"
                            shownFocused: cell.name === "focus"
                        }
                    }
                }
            }
        }
    }
}
