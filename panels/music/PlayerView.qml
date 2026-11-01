import QtQuick
import Quickshell.Services.Mpris
import qs.singletons

// One player as the music panel shows it: its cover row (CoverArt) and its track — of this
// player for as long as the view lives, so sliding from one player to the next
// (PlayerCarousel) needs nothing to change under it. A new track of the same player fades
// its title in.
Column {
    id: root

    property MprisPlayer player: null
    property string visualizerLayout: "horizontal"
    property string visualizerStyle: "waveform"
    property bool showVisualizer: false

    readonly property string _title: player?.trackTitle ?? ""
    readonly property string _artist: player?.trackArtist ?? ""

    spacing: 8

    CoverArt {
        width: root.width
        player: root.player
        visualizerLayout: root.visualizerLayout
        visualizerStyle: root.visualizerStyle
        showVisualizer: root.showVisualizer
    }

    Column {
        id: _trackInfo
        width: root.width
        spacing: 2

        Connections {
            target: root.player
            function onTrackTitleChanged() { _trackFadeIn.restart() }
        }
        NumberAnimation {
            id: _trackFadeIn
            target: _trackInfo
            property: "opacity"
            from: 0
            to: 1
            duration: Theme.duration("fade")
            easing: Theme.curve("fade")
        }

        Text {
            width: parent.width
            text: root.player ? (root._title || "Unknown") : "No media"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeMedium
            font.bold: true
            color: Theme.textPrimary
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            width: parent.width
            text: root._artist
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textSecondary
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            visible: root._artist !== ""
        }
    }
}
