import QtQuick
import qs.components
import qs.singletons

PopupWidget {
    widgetType: "notifications"

    Text {
        text: "󰂚"
        font.family: Theme.fontFamily
        // Accent while notifications are waiting to be read, same as the network and
        // dictation widgets use for "this is live". trackedNotifications is an
        // ObjectModel, which has no count property — only values.
        color: Notifications.notifications.values.length > 0 ? Theme.sliderAccent : Theme.textPrimary
        anchors.centerIn: parent
    }
}
