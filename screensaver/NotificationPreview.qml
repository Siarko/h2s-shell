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
    radius: 8
    color: Qt.rgba(1, 1, 1, 0.08)
    border.color: Qt.rgba(1, 1, 1, 0.12)
    border.width: 1
    implicitHeight: _col.implicitHeight + 16

    Column {
        id: _col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 2

        Text {
            visible: text !== ""
            text: root.modelData.appName ?? ""
            color: root.detail === "app" ? "white" : Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: root.detail === "app" ? Theme.fontSizeBodyLarge : Theme.fontSizeSmall
            font.bold: root.detail === "app"
            width: parent.width
            elide: Text.ElideRight
        }

        Text {
            visible: root.detail !== "app" && text !== ""
            text: root.modelData.summary ?? ""
            color: "white"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBodyLarge
            font.bold: true
            width: parent.width
            elide: Text.ElideRight
        }

        Text {
            visible: root.detail === "full" && text !== ""
            text: root.modelData.body ?? ""
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
