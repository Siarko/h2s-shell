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
        color: Theme.textPrimary
        anchors.centerIn: parent
    }
}
