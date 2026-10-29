import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.singletons

PanelWindow {
    id: root
    required property var modelData
    screen: modelData

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "screensaver"
    WlrLayershell.exclusiveZone: -1

    anchors { top: true; left: true }
    margins { top: 0; left: 0 }
    implicitWidth: root.screen.width
    implicitHeight: root.screen.height
    // Transparent, with the black inside the fading layer: a black window appeared at
    // full black at once, and only the notifications on top of it faded
    color: "transparent"

    readonly property bool _show: Lockscreen.screensaverVisible && !Lockscreen.locked
    visible: _show || _content.opacity > 0.001

    Item {
        id: _content
        anchors.fill: parent
        opacity: root._show ? 1.0 : 0.0

        Rectangle {
            anchors.fill: parent
            color: "black"
        }

        Behavior on opacity {
            NumberAnimation {
                duration: root._show ? (Profiles.value("lockscreen.fadeInDuration") ?? 800) : (Profiles.value("lockscreen.fadeOutDuration") ?? 400)
                easing.type: Easing.InOutQuad
            }
        }

        // Notification list — top right, below bar
        ListView {
            visible: Profiles.value("lockscreen.notificationsOnScreensaver") ?? true
            anchors {
                top: parent.top
                right: parent.right
                topMargin: 30
                rightMargin: 16
            }
            width: 360
            height: Math.min(contentHeight, root.height)
            clip: true
            spacing: 8
            model: Notifications.notifications
            interactive: false

            delegate: Rectangle {
                required property var modelData
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
                        text: modelData.appName ?? ""
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        width: parent.width
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: text !== ""
                        text: modelData.summary ?? ""
                        color: "white"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBodyLarge
                        font.bold: true
                        width: parent.width
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: text !== ""
                        text: modelData.body ?? ""
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
        }
    }
}
