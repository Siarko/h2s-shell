import QtQuick
import Quickshell
import qs.singletons
import qs.components
import qs.mockups.kit

// SmallButton in every kind ThemeRules.buttonLook names, in each look it draws. Each state
// shows one column of every kind, one row each, every button of the column in the state's
// look:
//   rest             no pointer, no keyboard
//   disabled         `available: false`
//   checked          `checked: true` (a toggle that is on: the plain kinds take the accent)
//   hover            drawn as under the pointer (the button's `shownLit`)
//   focus            with the keyboard's ring (the button's `shownFocused`)
//   pressed          the same as hover: a press lights the button as the pointer does, it
//                    has no look of its own
//   checked-hover    checked, under the pointer (the plain kinds: accentHover)
//   disabled-hover   not available, under the pointer: no light
// The labels say what the kinds mean where they differ from their names: the save kind
// confirms something new ("Create"), saveChange a change to something that exists
// ("Update"). No pointer or keyboard is moved: the looks are the button's own, every button
// of a state at once, drawn the same on screen as in the shot.
// "asking" is DeleteButton's state (the first click of a button that asks), not
// SmallButton's: it is not drawn here.
MockupWindow {
    id: root

    readonly property var kinds: ["normal", "save", "saveChange", "action", "cancel", "delete", "warning", "success"]
    readonly property var labels: ({ save: "Create", saveChange: "Update" })

    pointerStates: ["hover", "pressed", "checked-hover", "disabled-hover"]
    keyboardStates: ["focus"]

    // A cell: room for the widest label and the column of eight, each 24 px tall, 8 px
    // apart, with 12 px round them; while shooting, the cells in rows of four
    StateGrid {
        cellWidth: 140
        cellHeight: 8 * 24 + 7 * 8 + 2 * 12
        cellsPerRow: 4

        Repeater {
            model: root.names.length
            StateCell {
                id: cell
                required property int index
                name: root.names[index]

                Column {
                    x: 12
                    y: 12
                    spacing: 8

                    Repeater {
                        model: ScriptModel { values: root.kinds }
                        SmallButton {
                            required property string modelData
                            label: root.labels[modelData] ?? modelData
                            kind: modelData
                            available: !cell.name.startsWith("disabled")
                            checked: cell.name.startsWith("checked")
                            shownLit: Array.prototype.includes.call(root.pointerStates, cell.name)
                            shownFocused: cell.name === "focus"
                        }
                    }
                }
            }
        }
    }
}
