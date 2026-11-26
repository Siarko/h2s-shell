import QtQuick
import Quickshell
import qs.singletons
import qs.components
import qs.mockups.kit

// FloatingList in its states. Each cell is an overlay host (objectName "overlayHost"), as a
// popup's panel is: the list floats inside the cell, under (or over) the button that is its
// anchor. Its entries are the mockup's stand-ins, drawn as a dropdown's options (an entry's
// look is its owner's; the list gives the frame, the place and the keys):
//   below           the button at the top: the list under it
//   above           the button at the cell's bottom: no room below, the list over it
//   scrolling       ten entries, `maximumHeight: 120`: cut at the bottom (it scrolls)
//   groups          FloatingListHeader over each group's first entry
//   current         `highlight` on the second entry as the list shows: the keys' ring and
//                   light
//   disabled-entry  an entry with `floatingEntryEnabled: false`: dimmed
// The list is held open by its `open` binding: on screen a click outside it changes nothing.
MockupWindow {
    id: root

    keyboardStates: ["current"]

    readonly property var _sources: ["Battery", "Processor", "Memory", "Network", "Disk"]
    readonly property var _many: ["Battery", "Processor", "Memory", "Network", "Disk", "Fans",
        "Graphics", "Temperature", "Swap", "Uptime"]

    // A stand-in entry, drawn as a dropdown's option
    component Entry: Rectangle {
        id: entry
        required property Item owner
        property string text: ""
        property bool available: true
        readonly property bool floatingEntry: true
        readonly property string floatingEntryText: text
        readonly property bool floatingEntryEnabled: available
        readonly property bool current: owner.currentItem === entry
        function floatingActivate() {}

        width: parent ? parent.width : 0
        height: 24
        radius: Theme.listItem.radius
        color: current && available ? Theme.surfaceHover : Theme.surfaceHoverClear
        border.width: current ? Theme.border.width : 0
        border.color: Theme.textSecondary

        Text {
            anchors { left: parent.left; right: parent.right; leftMargin: 6; rightMargin: 6; verticalCenter: parent.verticalCenter }
            text: entry.text
            textFormat: Text.PlainText
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: entry.available ? Theme.textSecondary : Theme.textDisabled
            opacity: entry.available ? 1 : 0.5
        }
    }

    // The rows of a cell's list: a group's title ("#" before it) or an entry
    function _rows(name) {
        if (name === "scrolling")
            return _many;
        if (name === "groups")
            return ["#Hardware", "Battery", "Processor", "Memory", "#System", "Network", "Uptime"];
        return _sources;
    }

    StateGrid {
        cellWidth: 212
        // Room for the button and the list of the groups, five entries and two titles
        cellHeight: 16 + 24 + 2 + 5 * 24 + 2 * 24 + 6 + 16
        cellsPerRow: 3

        Repeater {
            model: root.names.length
            StateCell {
                id: cell
                required property int index
                name: root.names[index]

                Item {
                    objectName: "overlayHost"
                    anchors.fill: parent

                    SmallButton {
                        id: anchorButton
                        x: 16
                        y: cell.name === "above" ? parent.height - height - 16 : 16
                        label: "+ Add"
                    }

                    FloatingList {
                        id: floating
                        anchorItem: anchorButton
                        listWidth: 180
                        open: true
                        maximumHeight: cell.name === "scrolling" ? 120 : 240
                        // The keys on the second entry, put there as the list shows (an
                        // opening puts them nowhere)
                        onVisibleChanged: if (visible && cell.name === "current") highlight(rows.itemAt(1).entry)

                        Repeater {
                            id: rows
                            model: ScriptModel { values: root._rows(cell.name) }
                            Column {
                                id: row
                                required property string modelData
                                required property int index
                                readonly property bool title: modelData.startsWith("#")
                                readonly property alias entry: _entry
                                width: parent ? parent.width : 0

                                FloatingListHeader {
                                    visible: row.title
                                    text: row.modelData.slice(1)
                                }
                                Entry {
                                    id: _entry
                                    visible: !row.title
                                    owner: floating
                                    text: row.modelData
                                    available: !(cell.name === "disabled-entry" && row.index === 2)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
