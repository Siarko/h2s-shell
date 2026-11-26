import QtQuick
import qs.singletons
import qs.components
import qs.mockups.kit

// HoverTip in its states. The tip lives in its window's top item; here each cell stands in
// for that window (the tip's `parent` set to the cell's area), so that it is placed and
// kept inside as in a window, the same on screen as in the shot. It opens at once
// (`delay: 0`: no wait for a pointer resting) and stays shown (`shown: true`):
//   short      above its button, centred on it
//   wrapped    a text longer than `maxWidth` (260): wrapped, at its widest
//   below      the button at the area's top: no room above, the tip under it
//   edge       the button at the area's left edge: the tip kept 4 px inside it
//   link-rect  `anchorRect` on the address in a line of text: centred over the address,
//              not over the whole line
MockupWindow {
    id: root

    readonly property string _line: "Synced with calendar.example.org"
    readonly property string _address: "calendar.example.org"

    StateGrid {
        cellWidth: 300
        cellHeight: 112
        cellsPerRow: 3

        Repeater {
            model: root.names.length
            StateCell {
                id: cell
                required property int index
                name: root.names[index]

                // The window the tip is kept inside
                Item {
                    id: area
                    anchors.fill: parent

                    SmallButton {
                        id: button
                        visible: cell.name !== "link-rect"
                        x: cell.name === "edge" ? 0 : (area.width - width) / 2
                        y: cell.name === "below" ? 4 : area.height - height - 12
                        label: cell.name === "wrapped" ? "Forget" : "Pin"
                    }

                    Text {
                        id: line
                        visible: cell.name === "link-rect"
                        x: 16
                        y: area.height - height - 16
                        text: root._line
                        textFormat: Text.PlainText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textSecondary
                    }

                    TextMetrics {
                        id: before
                        font: line.font
                        text: root._line.slice(0, root._line.indexOf(root._address))
                    }
                    TextMetrics {
                        id: address
                        font: line.font
                        text: root._address
                    }

                    HoverTip {
                        parent: area
                        target: cell.name === "link-rect" ? line : button
                        delay: 0
                        shown: true
                        anchorRect: cell.name === "link-rect" ? Qt.rect(before.advanceWidth, 0, address.advanceWidth, line.height) : null
                        text: cell.name === "wrapped"
                            ? "Forget this network: its password is removed and it is no longer joined by itself"
                            : cell.name === "link-rect" ? "https://calendar.example.org"
                            : "Keep the panel open"
                    }
                }
            }
        }
    }
}
