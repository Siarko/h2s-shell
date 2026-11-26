import QtQuick
import qs.panels.calendar
import qs.mockups.kit

// DateField in its states, at its own width and 28 px tall, as the event form shows it:
//   empty    no `date`: the placeholders DD.MM.YYYY
//   filled   `date` 2026-01-15 (the kit's `now`)
//   focus    drawn as with the keyboard in the day (the field's `shownFocused`): the accent
//            border, the separators lighter, the day's digits selected; no cursor is drawn
//   armed    `armed: true`: the calendar's next click fills it, a thicker accent border
MockupWindow {
    id: root

    keyboardStates: ["focus"]

    StateGrid {
        cellWidth: 140
        cellHeight: 16 + 28 + 16
        cellsPerRow: 4

        Repeater {
            model: root.names.length
            StateCell {
                id: cell
                required property int index
                name: root.names[index]

                DateField {
                    x: 16
                    y: 16
                    height: 28
                    date: cell.name === "empty" ? "" : "2026-01-15"
                    armed: cell.name === "armed"
                    shownFocused: cell.name === "focus"
                }
            }
        }
    }
}
