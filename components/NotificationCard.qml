import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.singletons

// A notification as a card — in the panel, and as a toast: its app, summary, body and
// image, its actions, an inline reply (NotificationReply) and the codes found in it
// (CodeChips); text in it can be selected and copied.
Rectangle {
    id: notifCard

    required property var notification
    property string timestamp: ""
    property bool compactDismiss: false
    property int imageMaxHeight: 120
    // From the theme: a card in the panel by default; a toast sets its own
    property int contentPadding: Theme.notificationCard.padding
    property real cornerRadius: Theme.notificationCard.radius
    // A border: none in the panel; a toast sets the theme's
    property int borderWidth: 0
    property color borderColor: Theme.outline
    property color replyBackground: Theme.surfaceSunken

    property bool timerVisible: false
    // Fraction of the auto-dismiss time left, 1 → 0; the owner runs the countdown
    property real timerProgress: 1.0

    signal dismissRequested()

    implicitHeight: _contentCol.implicitHeight + contentPadding * 2
    radius: cornerRadius
    color: Theme.surface
    border.width: borderWidth
    border.color: borderColor
    clip: true

    property var _activeEdit: null
    readonly property string _selectedText: _activeEdit ? _activeEdit.selectedText : ""

    readonly property var _regularActions: (notification?.actions ?? []).filter(function(a) { return a.id !== "inline-reply"; })
    readonly property var _replyAction: (notification?.actions ?? []).find(function(a) { return a.id === "inline-reply"; }) ?? null

    ColumnLayout {
        id: _contentCol
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: notifCard.contentPadding
        }
        spacing: 4

        // Header: app icon + app name + [timestamp] + dismiss control
        RowLayout {
            Layout.fillWidth: true

            Image {
                visible: (notifCard.notification?.appIcon ?? "") !== ""
                source: visible ? "image://icon/" + notifCard.notification.appIcon : ""
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                Layout.maximumWidth: 16
                Layout.maximumHeight: 16
                fillMode: Image.PreserveAspectFit
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                text: notifCard.notification?.appName ?? ""
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                color: Theme.textSecondary
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Text {
                visible: notifCard.timestamp !== ""
                text: notifCard.timestamp
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textMuted
            }

            Text {
                text: notifCard.compactDismiss ? "×" : "dismiss"
                font.family: Theme.fontFamily
                font.pixelSize: notifCard.compactDismiss ? Theme.fontSizeSection : Theme.fontSizeSmall
                color: notifCard.compactDismiss ? Theme.textSecondary : Theme.textMuted

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: notifCard.dismissRequested()
                }
            }
        }

        // Summary
        TextEdit {
            id: _summaryEdit
            selectionColor: Theme.selection
            selectedTextColor: Theme.selectedText
            text: notifCard.notification?.summary ?? ""
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeMedium
            font.bold: true
            color: Theme.textPrimary
            Layout.fillWidth: true
            wrapMode: TextEdit.WordWrap
            readOnly: true
            selectByMouse: true
            onSelectedTextChanged: if (selectedText !== "") notifCard._activeEdit = _summaryEdit
        }

        // Body (optional — hidden when empty)
        TextEdit {
            id: _bodyEdit
            selectionColor: Theme.selection
            selectedTextColor: Theme.selectedText
            text: notifCard.notification?.body ?? ""
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textSecondary
            Layout.fillWidth: true
            wrapMode: TextEdit.WordWrap
            readOnly: true
            selectByMouse: true
            visible: (notifCard.notification?.body ?? "").length > 0
            onSelectedTextChanged: if (selectedText !== "") notifCard._activeEdit = _bodyEdit
        }

        // Notification image
        Image {
            visible: (notifCard.notification?.image ?? "") !== ""
            source: notifCard.notification?.image ?? ""
            Layout.fillWidth: true
            Layout.maximumHeight: notifCard.imageMaxHeight
            fillMode: Image.PreserveAspectFit
            Layout.topMargin: 4
        }

        // Action buttons
        Flow {
            spacing: 6
            visible: notifCard._regularActions.length > 0
            Layout.fillWidth: true
            Layout.topMargin: 4

            Repeater {
                // ScriptModel, never the bare array — see "The Repeater crash" in
                // docs/ARCHITECTURE.md. The card is reused for the next notification, so
                // this array is replaced while the card lives.
                model: ScriptModel {
                    values: notifCard._regularActions
                }
                delegate: Rectangle {
                    required property var modelData
                    implicitWidth: _actionLabel.implicitWidth + 16
                    height: 24
                    radius: Theme.notificationCard.controlRadius
                    color: Theme.accent

                    Text {
                        id: _actionLabel
                        anchors.centerIn: parent
                        text: modelData.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.textPrimary
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            modelData.invoke();
                            notifCard.dismissRequested();
                        }
                    }
                }
            }
        }

        // Inline reply
        NotificationReply {
            visible: notifCard._replyAction !== null
            Layout.fillWidth: true
            Layout.topMargin: 4
            fieldColor: notifCard.replyBackground
            onSent: text => {
                notifCard._replyAction.invoke(text);
                notifCard.dismissRequested();
            }
        }

        // Codes Notifications found in this notification, to copy
        CodeChips {
            Layout.fillWidth: true
            Layout.topMargin: 4
            codes: Notifications.extractedCodes[notifCard.notification?.id ?? -1] ?? []
            visible: codes.length > 0
        }
    }

    // Timer bar — pinned to bottom edge, shrinks as auto-close timer counts down
    Rectangle {
        visible: notifCard.timerVisible
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        height: Theme.notifTimerHeight
        width: parent.width * notifCard.timerProgress
        color: Theme.accent
        z: 1
    }

    // Copy overlay — appears in bottom-right corner when text is manually selected
    Rectangle {
        visible: notifCard._selectedText !== ""
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 8
        width: 28
        height: 28
        radius: Theme.notificationCard.controlRadius
        z: 1
        color: _copyArea.containsMouse ? Theme.surfaceHover : Theme.accentDark
        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

        Text {
            anchors.centerIn: parent
            text: "󰆏"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBodyLarge
            color: Theme.textPrimary
        }

        MouseArea {
            id: _copyArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (notifCard._activeEdit) {
                    notifCard._activeEdit.copy();
                    Notifier.send("Copied selected text", { urgency: "low", category: "x-qs-shell" });
                }
            }
        }
    }
}
