import QtQuick
import qs.components
import qs.singletons

BarWidget {
    property var popup: null

    onHover: state => {
        if (state)
            popup.open(this)
    }

    Text {
        text: Time.time
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeTitle
        color: Theme.textPrimary
        anchors.centerIn: parent
    }
}
