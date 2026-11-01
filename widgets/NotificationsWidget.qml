import QtQuick
import qs.components
import qs.singletons

// The bell: accent while notifications wait in the panel, with their count on a badge, and
// rung when one comes — lifted, shaken in the air, put back. From the widget's preset
// (WidgetPresets): `badge`, and `animation` — "off", "once" (each new notification),
// "untilOpened" (again every few seconds until the panel is opened) or "untilCleared"
// (again every few seconds while any notification is left). Never with reduced motion;
// the badge stays.
PopupWidget {
    id: root
    widgetType: "notifications"

    property string preset: ""
    readonly property bool _badge: WidgetPresets.value("notifications", preset, "badge") !== false
    readonly property string _animation: WidgetPresets.value("notifications", preset, "animation") ?? "once"
    readonly property bool _rings: _animation !== "off" && !Theme.reduceMotion

    // A notification coming rings the bell — a new one, or a seen one its sender replaced
    // (Notifications.arrived)
    Connections {
        target: Notifications
        function onArrived() {
            if (root._rings)
                _ring.restart();
        }
    }

    // Again every few seconds: "untilOpened" while some came since the panel was last open,
    // "untilCleared" while any is left in it
    Timer {
        interval: 5000
        repeat: true
        running: root._rings && (root._animation === "untilOpened" ? Notifications.unreadCount > 0
            : root._animation === "untilCleared" && Notifications.count > 0)
        onTriggered: if (!_ring.running) _ring.restart()
    }

    Item {
        id: _bellBox
        anchors.centerIn: parent
        width: _bell.implicitWidth
        height: _bell.implicitHeight

        // Lifted off its place while it rings
        transform: Translate { id: _lift }

        Text {
            id: _bell
            text: "󰂚"
            font.family: Theme.fontFamily
            // The size it had when it set none (the default 12 pt is 16 px), now from the theme
            font.pixelSize: Theme.fontSizeSection
            // Accent while notifications are waiting to be read, same as the network and
            // dictation widgets use for "this is live"
            color: Notifications.count > 0 ? Theme.accent : Theme.textPrimary
            Behavior on color { ColorAnimation { duration: Theme.duration("state"); easing: Theme.curve("state") } }
            // Swung from where a bell hangs
            transformOrigin: Item.Top
        }

        // The count, on the bell's shoulder; past 9 it says "9+" so the bar keeps its size
        Rectangle {
            visible: root._badge && Notifications.count > 0
            x: _bellBox.width - width / 2 - 1
            y: -height / 3
            height: Math.max(12, _countText.implicitHeight)
            width: Math.max(height, _countText.implicitWidth + 6)
            radius: height / 2
            color: Theme.accent

            Text {
                id: _countText
                anchors.centerIn: parent
                text: Notifications.count > 9 ? "9+" : String(Notifications.count)
                font.family: Theme.fontFamily
                font.pixelSize: Math.round(Theme.fontSizeSmall * 0.85)
                font.bold: true
                color: Theme.onAccent
            }
        }
    }

    // Someone picks the bell up, shakes it — wide, then less — and puts it back
    readonly property int _beat: Theme.duration("pop")
    SequentialAnimation {
        id: _ring
        ParallelAnimation {
            NumberAnimation { target: _lift; property: "y"; to: -4; duration: root._beat / 2; easing.type: Easing.OutQuad }
            NumberAnimation { target: _bellBox; property: "scale"; to: 1.15; duration: root._beat / 2; easing.type: Easing.OutQuad }
        }
        SequentialAnimation {
            NumberAnimation { target: _bell; property: "rotation"; to: 18; duration: root._beat / 3; easing.type: Easing.OutSine }
            NumberAnimation { target: _bell; property: "rotation"; to: -15; duration: root._beat / 2.5; easing.type: Easing.InOutSine }
            NumberAnimation { target: _bell; property: "rotation"; to: 11; duration: root._beat / 2.5; easing.type: Easing.InOutSine }
            NumberAnimation { target: _bell; property: "rotation"; to: -6; duration: root._beat / 3; easing.type: Easing.InOutSine }
            NumberAnimation { target: _bell; property: "rotation"; to: 0; duration: root._beat / 3; easing.type: Easing.InOutSine }
        }
        ParallelAnimation {
            NumberAnimation { target: _lift; property: "y"; to: 0; duration: root._beat * 2 / 3; easing: Theme.curve("pop") }
            NumberAnimation { target: _bellBox; property: "scale"; to: 1; duration: root._beat * 2 / 3; easing: Theme.curve("pop") }
        }
    }
}
