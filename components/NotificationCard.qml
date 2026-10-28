import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.singletons

Rectangle {
    id: notifCard

    required property var notification
    property string timestamp: ""
    property bool compactDismiss: false
    property int imageMaxHeight: 120
    property int contentPadding: 10
    property color replyBackground: Qt.rgba(0, 0, 0, 0.2)

    property bool timerVisible: false
    // Fraction of the auto-dismiss time left, 1 → 0; the owner runs the countdown
    property real timerProgress: 1.0

    signal dismissRequested()

    implicitHeight: _contentCol.implicitHeight + contentPadding * 2
    radius: 8
    color: Theme.cellDefault
    clip: true

    property var _activeEdit: null
    readonly property string _selectedText: _activeEdit ? _activeEdit.selectedText : ""

    readonly property var _regularActions: (notification?.actions ?? []).filter(function(a) { return a.id !== "inline-reply"; })
    readonly property var _replyAction: (notification?.actions ?? []).find(function(a) { return a.id === "inline-reply"; }) ?? null

    function _sendReply() {
        if (_replyInput.text.length === 0) return;
        notifCard._replyAction.invoke(_replyInput.text);
        notifCard.dismissRequested();
    }

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
                color: Theme.textSubtle
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Text {
                visible: notifCard.timestamp !== ""
                text: notifCard.timestamp
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textTertiary
            }

            Text {
                text: notifCard.compactDismiss ? "×" : "dismiss"
                font.family: Theme.fontFamily
                font.pixelSize: notifCard.compactDismiss ? Theme.fontSizeSection : Theme.fontSizeSmall
                color: notifCard.compactDismiss ? Theme.textSubtle : Theme.textTertiary

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
            text: notifCard.notification?.body ?? ""
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textBody
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
                model: notifCard._regularActions
                delegate: Rectangle {
                    required property var modelData
                    implicitWidth: _actionLabel.implicitWidth + 16
                    height: 24
                    radius: 5
                    color: Theme.sliderAccent

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
        RowLayout {
            visible: notifCard._replyAction !== null
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 6

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 28
                radius: 5
                color: notifCard.replyBackground

                Text {
                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                    text: "Reply…"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textTertiary
                    verticalAlignment: Text.AlignVCenter
                    visible: _replyInput.text.length === 0
                }

                TextInput {
                    id: _replyInput
                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textPrimary
                    verticalAlignment: TextInput.AlignVCenter
                    onAccepted: notifCard._sendReply()
                }
            }

            Rectangle {
                implicitWidth: 48
                implicitHeight: 28
                radius: 5
                color: Theme.sliderAccent

                Text {
                    anchors.centerIn: parent
                    text: "Send"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.textPrimary
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: notifCard._sendReply()
                }
            }
        }

        // Extracted code chips — shown when Notifications detected patterns in this notification
        Flow {
            spacing: 6
            Layout.fillWidth: true
            Layout.topMargin: 4
            visible: (Notifications.extractedCodes[notifCard.notification?.id ?? -1] ?? []).length > 0

            Repeater {
                // ScriptModel diffs old vs. new values so only changed delegates get
                // added/removed — see MusicPanel.qml for why binding a plain live-model
                // array straight to Repeater.model was crashing this app.
                model: ScriptModel {
                    values: Notifications.extractedCodes[notifCard.notification?.id ?? -1] ?? []
                }
                delegate: Rectangle {
                    required property string modelData
                    implicitWidth: _chipRow.implicitWidth + 12
                    height: 26
                    radius: 5
                    color: _chipArea.containsMouse ? Theme.buttonHover : Theme.cellAccent

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
                            text: modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.textPrimary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: _chipArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            _clipHelper.text = modelData;
                            _clipHelper.selectAll();
                            _clipHelper.copy();
                            Notifier.send("Copied: " + modelData, { urgency: "low", category: "x-qs-shell" });
                        }
                    }
                }
            }
        }
    }

    // Hidden TextEdit for programmatic clipboard writes from code chips
    TextEdit {
        id: _clipHelper
        visible: false
    }

    // Timer bar — pinned to bottom edge, shrinks as auto-close timer counts down
    Rectangle {
        visible: notifCard.timerVisible
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        height: Theme.notifTimerHeight
        width: parent.width * notifCard.timerProgress
        color: Theme.notifTimerColor
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
        radius: 6
        z: 1
        color: _copyArea.containsMouse ? Theme.buttonHover : Theme.cellAccent

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
