import QtQuick
import qs.components
import qs.singletons

BarWidget {
    property var popup: null

    active: popup?.active && popup?.contentType === "power"
    onClicked: {
        if (popup?.active && popup?.contentType === "power")
            popup.close()
        else
            popup.open(this, false, "power")
    }

    Text {
        text: "⏻"
        font.family: Theme.fontFamily
        font.pixelSize: 20
        color: Theme.textPrimary
        anchors.centerIn: parent
    }
}
