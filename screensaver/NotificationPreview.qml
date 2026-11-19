import QtQuick
import qs.components
import qs.singletons

// A notification as the screensaver and the lock screen show it, with as much detail as
// their privacy setting allows:
//   "full"  — app, title and text, and the sender's progress bar
//   "title" — app and title
//   "app"   — the app alone, when even the title (a sender, say) gives too much away
// Anything else counts as "app": a value this does not know shows the least.
//
// Every line is plain text: a notification's title or body shown as Text's default
// (AutoText) would be taken for rich text when it looks like markup — links drawn, and an
// <img> fetched, from a locked screen.
Rectangle {
    id: root

    required property var modelData
    property string detail: "app"

    readonly property bool _showTitle: detail === "full" || detail === "title"
    readonly property bool _showBody: detail === "full"
    readonly property var _progress: NotificationRules.progress(modelData?.hints)

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
            objectName: "app"
            visible: text !== ""
            text: root.modelData?.appName ?? ""
            textFormat: Text.PlainText
            color: root._showTitle ? Theme.textDisabled : Theme.textPrimary
            font.family: Theme.fontFamily
            font.pixelSize: root._showTitle ? Theme.fontSizeSmall : Theme.fontSizeBodyLarge
            font.bold: !root._showTitle
            width: parent.width
            elide: Text.ElideRight
        }

        Text {
            objectName: "title"
            visible: root._showTitle && text !== ""
            text: root._showTitle ? (root.modelData?.summary ?? "") : ""
            textFormat: Text.PlainText
            color: Theme.textPrimary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBodyLarge
            font.bold: true
            width: parent.width
            elide: Text.ElideRight
        }

        Text {
            objectName: "body"
            visible: root._showBody && text !== ""
            // Not even laid out when hidden: what the setting withholds is not in the scene
            text: root._showBody ? NotificationMarkup.plainText(root.modelData?.body ?? "") : ""
            textFormat: Text.PlainText
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            width: parent.width
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        // How far the sender's job has gone (NotificationRules.progress) — as much as the
        // body says, so only where the body shows
        Item {
            width: parent.width
            height: _progressBar.implicitHeight + 6
            visible: root._showBody && root._progress.shown

            ProgressBar {
                id: _progressBar
                objectName: "progress"
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                value: root._progress.value
                tone: root._progress.tone
            }
        }
    }
}
