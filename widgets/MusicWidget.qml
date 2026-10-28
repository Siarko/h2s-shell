import QtQuick
import qs.components
import qs.singletons

PopupWidget {
    widgetType: "music"

    onMiddleClicked: Music.togglePlay()
    onScrollNotch: delta => {
        if (delta > 0)
            Music.next();
        else
            Music.previous();
    }

    Row {
        anchors.centerIn: parent
        spacing: 4

        Text {
            text: Music.playing ? "󰐊" : "󰏤"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            color: Theme.textPrimary
            visible: Music.hasPlayer
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: Music.hasPlayer ? (Music.activePlayer.identity || "Player") : "󰎈"
            font.family: Theme.fontFamily
            font.pixelSize: Music.hasPlayer ? Theme.fontSizeMedium : Theme.fontSizeHeading
            color: Theme.textPrimary
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
        }
    }
}
