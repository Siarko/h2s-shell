import QtQuick
import qs.singletons

// A notification as the screensaver and the lock screen show it, with as much detail as
// their privacy setting allows:
//   "full"  — app, title and text
//   "title" — app and title
//   "app"   — the app alone, when even the title (a sender, say) gives too much away
Rectangle {
    id: root

    required property var modelData
    property string detail: "full"

    width: 360
    radius: Theme.notificationCard.radius
    color: Theme.glass
    border.color: Theme.glassBorder
    border.width: Theme.border.width
    // The column's 12 px margin above and below it (16 left 4 px at the bottom)
    implicitHeight: _col.implicitHeight + 24

    Column {
        id: _col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 2

        Text {
            visible: text !== ""
            text: root.modelData.appName ?? ""
            color: root.detail === "app" ? Theme.textPrimary : Theme.textDisabled
            font.family: Theme.fontFamily
            font.pixelSize: root.detail === "app" ? Theme.fontSizeBodyLarge : Theme.fontSizeSmall
            font.bold: root.detail === "app"
            width: parent.width
            elide: Text.ElideRight
        }

        Text {
            visible: root.detail !== "app" && text !== ""
            text: root.modelData.summary ?? ""
            color: Theme.textPrimary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBodyLarge
            font.bold: true
            width: parent.width
            elide: Text.ElideRight
        }

        Text {
            visible: root.detail === "full" && text !== ""
            // Plain: shown as Text guesses rich text, which would draw a body's HTML as is
            text: NotificationMarkup.plainText(root.modelData.body)
            textFormat: Text.PlainText
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            width: parent.width
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }
}
