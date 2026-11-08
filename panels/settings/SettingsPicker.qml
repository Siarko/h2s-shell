import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons

// What a settings tab edits — the profile or the theme — picked from a list that opens
// over whatever is below it
ColumnLayout {
    id: _picker
    property string label
    property string current
    property var options: []
    // Options shown with a • after them: the active profiles, the theme in use; and with
    // a ✎: themes with unsaved changes
    property var marked: []
    property var edited: []
    function display(name) {
        return name + (marked.includes(name) ? " •" : "") + (edited.includes(name) ? " ✎" : "");
    }
    // Shown, but not changed, e.g. while the theme picked is previewed
    property bool locked: false
    // Whether its list is open: the window's to say, keeping one list open at a time and
    // closing it on a click elsewhere. Clicking the button asks with `toggleRequested`.
    property bool open: false
    // The open list, for the window to tell a click on it from one elsewhere
    readonly property Item optionList: _optionList
    signal toggleRequested
    // Picking closes the list too: the window closes it when told
    signal picked(string name)

    Layout.fillWidth: true
    spacing: 2
    // Above the page list, which the open list covers
    z: 10

    Text {
        text: _picker.label
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.textDisabled
    }

    Rectangle {
        id: _pickerButton
        Layout.fillWidth: true
        height: 28
        radius: Theme.dropdown.radius
        color: _pickerArea.lit && !_picker.locked ? Theme.surfaceHover : Theme.surface
        opacity: _picker.locked ? 0.5 : 1
        border.width: Theme.border.width
        border.color: _picker.open ? Theme.accent : Theme.surfaceHoverClear
        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

        Text {
            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 10; right: _arrow.left; rightMargin: 4 }
            text: _picker.display(_picker.current)
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            font.bold: true
            color: Theme.textPrimary
        }
        Text {
            font.family: Theme.fontFamily
            id: _arrow
            anchors { verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: 8 }
            visible: !_picker.locked
            text: _picker.open ? "▴" : "▾"
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textSecondary
        }

        PointerArea {
            id: _pickerArea
            enabled: !_picker.locked
            cursorShape: Qt.PointingHandCursor
            onClicked: _picker.toggleRequested()
        }

        // The options, over whatever is below; outside the layout, so opening it moves
        // nothing
        Rectangle {
            id: _optionList
            visible: _picker.open
            y: parent.height + 2
            width: parent.width
            height: _optionColumn.height + 6
            radius: Theme.dropdown.radius
            color: Theme.popupBackground
            border.width: Theme.border.width
            border.color: Theme.outline

            Column {
                id: _optionColumn
                x: 3
                y: 3
                width: parent.width - 6

                Repeater {
                    // ScriptModel, never the bare array — see "The Repeater crash"
                    model: ScriptModel { values: _picker.options }

                    Rectangle {
                        required property string modelData
                        readonly property bool picked: modelData === _picker.current
                        width: _optionColumn.width
                        height: 24
                        radius: Theme.listItem.radius
                        color: picked ? Theme.accentTint : (_optionArea.lit ? Theme.surfaceHover : Theme.surfaceHoverClear)
                        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

                        Text {
                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 8; right: parent.right; rightMargin: 6 }
                            text: _picker.display(parent.modelData)
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: parent.picked ? Theme.textPrimary : Theme.textSecondary
                        }

                        PointerArea {
                            id: _optionArea
                            centred: false
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: _picker.picked(parent.modelData)
                        }
                    }
                }
            }
        }
    }
}
