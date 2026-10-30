import QtQuick
import qs.singletons

// The one way the shell deletes something from a click: the first click asks — the button
// turns red, reading `confirmLabel`, with a "×" attached that cancels — and only a second
// click deletes (`confirmed`). Nothing times out: the question stays until it is answered.
// The owner sets `asking = false` when what the button deletes changes (another item
// selected), so a question never carries over to it.
//
//   DeleteButton {
//       confirmLabel: "Delete everywhere?"
//       cancelTip: "Cancel — keep the preset"
//       onConfirmed: WidgetPresets.remove(type, name)
//   }
Row {
    id: root

    property string label: "Delete"
    property string confirmLabel: "Delete?"
    property string cancelTip: "Cancel"
    property bool available: true
    property int fontSize: Theme.fontSizeSmall
    // Whether the first click has been made and the button waits for the second
    property bool asking: false

    signal confirmed
    // The first click, for owners that track which item is being asked about
    signal askingStarted

    spacing: 0

    Rectangle {
        id: _button
        implicitWidth: _label.implicitWidth + 2 * Theme.button.horizontalPadding
        // As tall as the label needs, never less than the theme's button height
        implicitHeight: Math.max(Theme.button.minHeight, _label.implicitHeight + 2 * Theme.button.verticalPadding)
        width: implicitWidth
        height: implicitHeight
        radius: Theme.deleteButton.radius
        // Square on the side the cancel button attaches to, so the two read as one control
        topRightRadius: root.asking ? 0 : radius
        bottomRightRadius: root.asking ? 0 : radius
        opacity: root.available ? 1 : 0.35
        color: _area.containsMouse && root.available ? Theme.surfaceHover : Theme.surface
        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

        Text {
            id: _label
            anchors.centerIn: parent
            text: root.asking ? root.confirmLabel : root.label
            font.family: Theme.fontFamily
            font.pixelSize: root.fontSize
            color: root.asking ? Theme.error : Theme.textSecondary
        }

        MouseArea {
            id: _area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (!root.available)
                    return;
                if (root.asking) {
                    root.asking = false;
                    root.confirmed();
                } else {
                    root.asking = true;
                    root.askingStarted();
                }
            }
        }
    }

    // Cancels the question, attached to the asking button
    Rectangle {
        visible: root.asking
        width: _button.height
        height: _button.height
        radius: Theme.deleteButton.radius
        topLeftRadius: 0
        bottomLeftRadius: 0
        color: _cancelArea.containsMouse ? Theme.surfaceHover : Theme.surface
        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

        Text {
            anchors.centerIn: parent
            text: "×"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.textSecondary
        }

        MouseArea {
            id: _cancelArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.asking = false
        }

        HoverTip {
            target: parent
            shown: _cancelArea.containsMouse
            text: root.cancelTip
        }
    }
}
