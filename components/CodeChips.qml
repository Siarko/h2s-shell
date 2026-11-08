import QtQuick
import Quickshell
import qs.singletons

// Codes found in a notification (Notifications.extractedCodes — one-time passwords and
// the like), each a chip that copies it with a click.
Flow {
    id: root

    property var codes: []

    spacing: 6

    Repeater {
        // ScriptModel, never the bare array — see "The Repeater crash" in
        // docs/ARCHITECTURE.md
        model: ScriptModel {
            values: root.codes
        }
        delegate: Rectangle {
            id: _chip
            required property string modelData
            implicitWidth: _chipRow.implicitWidth + 12
            height: 26
            radius: Theme.notificationCard.controlRadius
            color: _chipArea.lit ? Theme.surfaceHover : Theme.accentDark
            Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

            Row {
                id: _chipRow
                anchors.centerIn: parent
                spacing: 4

                Text {
                    text: "󰆏"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.textPrimary
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: _chip.modelData
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.textPrimary
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            PointerArea {
                id: _chipArea
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    _clipHelper.text = _chip.modelData;
                    _clipHelper.selectAll();
                    _clipHelper.copy();
                    Notifier.send("Copied: " + _chip.modelData, { urgency: "low", category: "x-qs-shell" });
                }
            }
        }
    }

    // A hidden TextEdit, the way to put text on the clipboard; outside the Flow's layout
    TextEdit {
        id: _clipHelper
        visible: false
        width: 0
        height: 0
    }
}
