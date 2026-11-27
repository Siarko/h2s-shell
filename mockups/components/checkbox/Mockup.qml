import QtQuick
import qs.components
import qs.mockups.kit

// Checkbox in its states, in a settings column (200 px); each cell shows the box off above
// and on below where the state has both:
//   off, on     `checked` false, true, with a short label
//   hover       the checkbox has no look under the pointer (its MouseArea changes nothing):
//               drawn as at rest, off and on
//   focus       drawn as with the keyboard (the checkbox's `shownFocused`): the keyboard's
//               ring around the box, off and on
//   disabled    `enabled: false`: no look of its own either, off and on
//   wrapped     a long label at the column's width: it wraps, the box level with its first
//               line
//   no-label    no label: the box alone, off and on
MockupWindow {
    id: root

    pointerStates: ["hover"]
    keyboardStates: ["focus"]

    readonly property var _both: ["hover", "focus", "disabled", "no-label"]

    StateGrid {
        id: grid
        cellWidth: 232
        // Room for the wrapped label's three lines, or two boxes
        cellHeight: 96
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
                        model: root._both.includes(cell.name) ? 2 : 1
                        Checkbox {
                            required property int index
                            width: cell.name === "wrapped" ? 200 : implicitWidth
                            label: cell.name === "no-label" ? ""
                                : cell.name === "wrapped" ? "Show events from calendars shared with me by other people"
                                : "Work calendar"
                            checked: cell.name === "on" || index === 1
                            enabled: cell.name !== "disabled"
                            shownFocused: cell.name === "focus"
                        }
                    }
                }
            }
        }
    }
}
