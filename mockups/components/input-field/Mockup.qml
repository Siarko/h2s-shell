import QtQuick
import qs.components
import qs.mockups.kit

// InputField in its states, in a settings column (200 px); where a state has both, the
// empty field above and the filled one below:
//   empty, filled  the placeholder; a text longer than the box (the input scrolled to its
//                  end, as a text set from outside leaves it)
//   focus          drawn as with the keyboard (the field's `shownFocused`): the accent
//                  border and the keyboard's ring, no placeholder; no cursor is drawn (the
//                  window never takes the keyboard)
//   problem        `problem: true`: the red border, filled and focused alike
//   password       `password: true`: dots and the eye
//   revealed       `password` with `revealed: true`: the text and the open eye
//   outlined       `outlined: true`: a border at rest
//   disabled       `enabled: false`, as a page sets it: the field has no look of its own
//                  for it (pages that dim one set its opacity themselves)
MockupWindow {
    id: root

    keyboardStates: ["focus"]

    readonly property var _both: ["focus", "problem", "outlined", "disabled"]

    StateGrid {
        id: grid
        cellWidth: 232
        cellHeight: 16 + 26 + 8 + 26 + 16
        cellsPerRow: 4

        Repeater {
            model: root.names.length
            StateCell {
                id: cell
                required property int index
                name: root.names[index]
                readonly property bool both: root._both.includes(name)
                readonly property bool secret: name === "password" || name === "revealed"

                Column {
                    x: 16
                    y: 16
                    spacing: 8

                    Repeater {
                        model: cell.both ? 2 : 1
                        InputField {
                            required property int index
                            width: 200
                            placeholder: cell.secret ? "Password" : "Network name"
                            text: cell.secret ? "correct horse"
                                : cell.name === "empty" || (cell.both && index === 0) ? ""
                                : "Home network on the second floor"
                            password: cell.secret
                            revealed: cell.name === "revealed"
                            problem: cell.name === "problem"
                            outlined: cell.name === "outlined"
                            enabled: cell.name !== "disabled"
                            shownFocused: cell.name === "focus" || (cell.name === "problem" && index === 1)
                        }
                    }
                }
            }
        }
    }
}
