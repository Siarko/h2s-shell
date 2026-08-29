import QtQuick
import Quickshell.Wayland
import qs.singletons

WlSessionLockSurface {
    id: root

    color: "transparent"

    property bool _awake: false

    property bool _ready: false
    Timer { interval: 300; running: true; onTriggered: root._ready = true }

    function _wake() {
        if (!_ready) return
        if (Lockscreen.promptActive && !_awake) return
        _awake = true
        Lockscreen.promptActive = true
        _sleepTimer.restart()
    }

    function _sleep() {
        _awake = false
        Lockscreen.promptActive = false
        _prompt.reset()
    }

    Timer {
        id: _sleepTimer
        interval: 10000
        onTriggered: root._sleep()
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    MouseArea {
        anchors.fill: parent
        z: 100
        hoverEnabled: true
        propagateComposedEvents: true
        cursorShape: Lockscreen.promptActive ? Qt.ArrowCursor : Qt.BlankCursor
        onEntered:                  root._wake()
        onPositionChanged: mouse => { root._wake(); mouse.accepted = false }
        onPressed:         mouse => { root._wake(); mouse.accepted = false }
        onReleased:        mouse => { mouse.accepted = false }
        onClicked:         mouse => { mouse.accepted = false }
    }

    LockPrompt {
        id: _prompt
        anchors.centerIn: parent
        visible: root._awake
        onActivity: root._wake()
    }

    ListView {
        visible: Config.lockscreen.notificationsOnLock && !root._awake
        anchors {
            top: parent.top
            right: parent.right
            topMargin: 16
            rightMargin: 16
        }
        width: 360
        height: Math.min(contentHeight, root.height - 32)
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
