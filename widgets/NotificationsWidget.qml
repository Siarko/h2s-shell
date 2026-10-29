import QtQuick
import qs.components
import qs.singletons

PopupWidget {
    widgetType: "notifications"

    Text {
        id: _bell
        text: "󰂚"
        font.family: Theme.fontFamily
        // Accent while notifications are waiting to be read, same as the network and
        // dictation widgets use for "this is live". trackedNotifications is an
        // ObjectModel, which has no count property — only values.
        color: Notifications.notifications.values.length > 0 ? Theme.accent : Theme.textPrimary
        Behavior on color { ColorAnimation { duration: Theme.duration("state"); easing: Theme.curve("state") } }
        anchors.centerIn: parent

        // A new notification makes the bell jump: up, and back with the pop curve's
        // overshoot. Not with reduced motion.
        readonly property int _count: Notifications.notifications.values.length
        property int _seen: 0
        on_CountChanged: {
            if (_count > _seen && !Theme.reduceMotion)
                _ring.restart()
            _seen = _count
        }
        Component.onCompleted: _seen = _count

        SequentialAnimation {
            id: _ring
            NumberAnimation { target: _bell; property: "scale"; to: 1.3; duration: Theme.duration("pop") / 3; easing.type: Easing.OutQuad }
            NumberAnimation { target: _bell; property: "scale"; to: 1; duration: Theme.duration("pop") * 2 / 3; easing: Theme.curve("pop") }
        }
    }
}
