import QtQuick
import qs.components
import qs.singletons

BarWidget {
    property var popup: null

    onHover: state => {
        if (state)
            popup.open(this, false, "music")
    }
    onMiddleClicked: Music.togglePlay()
    onScrolled: delta => {
        if (delta > 0)
            Music.next()
        else
            Music.previous()
    }

    Row {
        anchors.centerIn: parent
        spacing: 4

        Text {
            text: Music.playing ? "󰐊" : "󰏤"
            font.family: Theme.fontFamily
            font.pixelSize: 18
            color: Theme.textPrimary
            visible: Music.hasPlayer
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: Music.hasPlayer ? (Music.activePlayer.identity || "Player") : "󰎈"
            font.family: Theme.fontFamily
            font.pixelSize: Music.hasPlayer ? 14 : 18
            color: Theme.textPrimary
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
        }
    }
}
