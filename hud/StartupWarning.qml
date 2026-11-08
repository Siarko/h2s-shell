import QtQuick
import QtQuick.Layouts
import qs.singletons

// A banner under the bar about something wrong with how the shell was started or set up
// — it says what and how to fix it, and fixes nothing itself. The HUD stacks these
// (Hud.qml); the owner decides when one shows and remembers the dismissal (×), for this
// run of the shell.
Rectangle {
    id: root

    // A glyph every font has by default: one banner is about the icon font missing
    property string icon: "⚠"
    property string title: ""
    property string body: ""

    signal dismissed

    implicitWidth: Math.min(640, (parent?.width ?? 640) - 2 * Theme.osdToast.screenGap)
    implicitHeight: _content.implicitHeight + 2 * Theme.osdToast.padding
    radius: Theme.osdToast.radius
    color: Theme.surface
    border.width: Theme.border.selectedWidth
    border.color: Theme.warning

    RowLayout {
        id: _content
        anchors.fill: parent
        anchors.margins: Theme.osdToast.padding
        spacing: 10

        Text {
            Layout.alignment: Qt.AlignTop
            text: root.icon
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSection
            color: Theme.warning
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                Layout.fillWidth: true
                text: root.title
                wrapMode: Text.WordWrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMedium
                font.bold: true
                color: Theme.textPrimary
            }

            Text {
                Layout.fillWidth: true
                text: root.body
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textSecondary
            }
        }

        Text {
            Layout.alignment: Qt.AlignTop
            text: "×"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSection
            color: _closeArea.containsMouse ? Theme.textPrimary : Theme.textSecondary

            MouseArea {
                id: _closeArea
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.dismissed()
            }
        }
    }
}
