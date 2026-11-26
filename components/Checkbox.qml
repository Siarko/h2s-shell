import QtQuick
import qs.singletons

// A checkbox with an optional label beside it. Clicking either, or Space while it has the
// focus, emits `toggled`; the owner flips `checked`, so the box can follow state kept
// elsewhere (a calendar enabled in GoogleCalendar, say). Takes the focus on Tab; an owner
// that wants Tab to go somewhere particular sets `Keys.onTabPressed`. Given a width, a long
// label wraps to more lines inside it, the box level with the first; without one it is as
// wide as its label on one line.
Item {
    id: root

    property bool checked: false
    property string label: ""
    // Drawn as with the keyboard, without it: a preview of the look (the mockups' keyboard
    // states). Only the look: no key is taken
    property bool shownFocused: false

    signal toggled

    // The first line's height: the box is centred on it
    readonly property real _lineHeight: 22

    implicitWidth: _box.width + (root.label !== "" ? 6 + _label.implicitWidth : 0)
    implicitHeight: Math.max(_lineHeight, _label.visible ? _label.y + _label.implicitHeight : 0)
    activeFocusOnTab: true

    Keys.onSpacePressed: root.toggled()

    Rectangle {
        id: _box
        y: Math.round((root._lineHeight - height) / 2)
        width: 14
        height: 14
        radius: Theme.checkbox.radius
        color: root.checked ? Theme.accent : "transparent"
        border.color: root.activeFocus || root.shownFocused ? Theme.textSecondary : (root.checked ? Theme.accent : Theme.textDisabled)
        border.width: Theme.border.width

        Text {
            anchors.centerIn: parent
            visible: root.checked
            text: "✓"
            color: Theme.textPrimary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeTiny
        }
    }

    Text {
        id: _label
        objectName: "checkboxLabel"
        visible: root.label !== ""
        x: _box.width + 6
        y: Math.max(0, Math.round((root._lineHeight - _metrics.height) / 2))
        width: Math.max(0, root.width - x)
        text: root.label
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Theme.textSecondary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
    }

    FontMetrics {
        id: _metrics
        font: _label.font
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
