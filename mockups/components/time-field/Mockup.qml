import QtQuick
import qs.panels.calendar
import qs.mockups.kit

// TimeField in its states, 80 px wide and 28 px tall (the event form gives it the rest of
// its row); the value is set through its `setValue`, as the form does:
//   empty           no time: the placeholders HH:MM
//   filled          10:30 (the kit's `now`)
//   focus           drawn as with the keyboard in the hours (the field's `shownFocused`): the
//                   accent border and the keyboard's ring, the colon lighter, the hours
//                   selected; no cursor is drawn
//   one-digit-hour  "7:05": the hour shown as given, one digit (its `text` reads 07:05)
MockupWindow {
    id: root

    keyboardStates: ["focus"]

    StateGrid {
        cellWidth: 112
        cellHeight: 16 + 28 + 16
        cellsPerRow: 4

        Repeater {
            model: root.names.length
            StateCell {
                id: cell
                required property int index
                name: root.names[index]

                TimeField {
                    x: 16
                    y: 16
                    width: 80
                    height: 28
                    shownFocused: cell.name === "focus"
                    Component.onCompleted: setValue(cell.name === "empty" ? ""
                        : cell.name === "one-digit-hour" ? "7:05"
                        : "10:30")
                }
            }
        }
    }
}
