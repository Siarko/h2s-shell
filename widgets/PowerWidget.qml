import QtQuick
import qs.components
import qs.singletons

PopupWidget {
    widgetType: "power"

    Text {
        text: "⏻"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeTitle
        color: Theme.textPrimary
        anchors.centerIn: parent
    }
}
