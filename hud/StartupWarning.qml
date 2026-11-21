import QtQuick
import qs.components
import QtQuick.Layouts
import qs.singletons

// A banner under the bar about something wrong with how the shell was started or set up
// — it says what and how to fix it, and fixes nothing itself. The HUD stacks these
// (Hud.qml); the owner decides when one shows and remembers the dismissal (×), for this
// run of the shell. A banner may carry buttons (`actions`, a row under the body), and the
// same banner stands at the top of a settings page (`onPage`: the page's card look, no ×).
Rectangle {
    id: root

    // A glyph every font has by default: one banner is about the icon font missing
    property string icon: "⚠"
    property string title: ""
    property string body: ""
    // On a settings page: a card's radius and border, a warning tint, no ×
    property bool onPage: false
    readonly property bool dismissible: !onPage
    // Buttons under the body, left to right (not the default property: this file's own
    // children would go there too)
    property alias actions: _actions.data

    signal dismissed

    implicitWidth: Math.min(640, (parent?.width ?? 640) - 2 * Theme.osdToast.screenGap)
    implicitHeight: _content.implicitHeight + 2 * Theme.osdToast.padding
    radius: onPage ? Theme.settings.cardRadius : Theme.osdToast.radius
    color: onPage ? Qt.alpha(Theme.warning, 0.10) : Theme.surface
    border.width: onPage ? Theme.border.width : Theme.border.selectedWidth
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
                objectName: "warningTitle"
                Layout.fillWidth: true
                text: root.title
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMedium
                font.bold: true
                color: Theme.textPrimary
            }

            Text {
                objectName: "warningBody"
                Layout.fillWidth: true
                text: root.body
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textSecondary
            }

            RowLayout {
                id: _actions
                Layout.topMargin: children.length > 0 ? 4 : 0
                spacing: 6
            }
        }

        Text {
            objectName: "warningClose"
            visible: root.dismissible
            Layout.alignment: Qt.AlignTop
            text: "×"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSection
            color: _closeArea.lit ? Theme.textPrimary : Theme.textSecondary

            PointerArea {
                id: _closeArea
                reach: 4
                cursorShape: Qt.PointingHandCursor
                onClicked: root.dismissed()
            }
        }
    }
}
