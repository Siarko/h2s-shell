import QtQuick
import qs.components
import qs.singletons

BarWidget {
    property var popup: null

    active: popup?.active && popup?.contentType === "notifications"
    onClicked: {
        if (popup?.active && popup?.contentType === "notifications")
            popup.close()
        else
            popup.open(this, true, "notifications")
    }

    Text {
        text: "󰂚"
        font.family: Theme.fontFamily
        // Accent while notifications are waiting to be read, same as the
        // network and dictation widgets use for "this is live"
        color: Notifications.notifications.count > 0 ? Theme.sliderAccent : Theme.textPrimary
        anchors.centerIn: parent
    }
}
