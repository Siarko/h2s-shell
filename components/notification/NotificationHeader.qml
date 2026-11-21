import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons

// A notification card's header (NotificationCard): the app's icon and name, the arrival
// time, the pin and the dismiss control. A tap on it runs the card's default action.
RowLayout {
    id: root

    // The card it heads (NotificationCard)
    required property Item card

    TapHandler {
        enabled: root.card._defaultAction !== null
        onTapped: root.card._activateDefault()
    }
    Layout.fillWidth: true

    Image {
        visible: root.card._appIconSource !== ""
        source: root.card._appIconSource
        sourceSize: Qt.size(32, 32)
        Layout.preferredWidth: 16
        Layout.preferredHeight: 16
        Layout.maximumWidth: 16
        Layout.maximumHeight: 16
        fillMode: Image.PreserveAspectFit
        Layout.alignment: Qt.AlignVCenter
    }

    Text {
        text: root.card._appName
        textFormat: Text.PlainText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.bold: true
        color: Theme.textSecondary
        Layout.fillWidth: true
        elide: Text.ElideRight
    }

    Text {
        visible: root.card.timestamp !== ""
        text: root.card.timestamp
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.textMuted
    }

    Text {
        id: _pinButton
        objectName: "pinButton"
        visible: root.card.pinnable
        text: root.card.pinLook.glyph
        textFormat: Text.PlainText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        color: _pinArea.lit || root.card.pinLook.action === "unpin" ? Theme.accent : Theme.textMuted

        PointerArea {
            id: _pinArea
            cursorShape: Qt.PointingHandCursor
            onPressed: root.card._dismissPressed = true
            onReleased: Qt.callLater(() => root.card._dismissPressed = false)
            onClicked: root.card.togglePin()
        }

        HoverTip {
            target: _pinButton
            shown: _pinArea.containsMouse
            text: root.card.pinLook.tip
        }
    }

    Text {
        text: root.card.compactDismiss ? "×" : "dismiss"
        font.family: Theme.fontFamily
        font.pixelSize: root.card.compactDismiss ? Theme.fontSizeSection : Theme.fontSizeSmall
        color: root.card.compactDismiss ? Theme.textSecondary : Theme.textMuted

        MouseArea {
            id: _dismissArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: root.card._dismissPressed = true
            // Whether or not the tap came, the mark ends with this click
            onReleased: Qt.callLater(() => root.card._dismissPressed = false)
            onClicked: {
                root.card.closeClicked();
                root.card.dismissRequested();
            }
        }

        // On a toast, "×" dismisses the notification: for one of the shell's jobs,
        // that it does not stop the job
        HoverTip {
            target: parent
            shown: root.card.compactDismiss && _dismissArea.containsMouse
                && typeof root.card.notification?.hints?.["x-qs-progress-run"] === "string"
            text: "Dismiss. The job goes on."
        }
    }
}
