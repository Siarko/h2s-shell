import QtQuick
import qs.components
import qs.singletons

PopupWidget {
    widgetType: "music"

    // What its actions act on (a stand-in in tests)
    property var actionTarget: Music

    function runAction(id, details) {
        switch (id) {
        case "playPause":
            actionTarget.togglePlay();
            break;
        case "next":
            actionTarget.next();
            break;
        case "previous":
            actionTarget.previous();
            break;
        case "play":
            actionTarget.play();
            break;
        case "pause":
            actionTarget.pause();
            break;
        }
    }

    function actionHolds(id) {
        return CoreActionRules.musicHolds(id, actionTarget.playing) === true;
    }

    BarRow {
        anchors.centerIn: parent
        spacing: 4

        Text {
            text: Music.playing ? "󰐊" : "󰏤"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            color: Theme.textPrimary
            visible: Music.hasPlayer
        }

        BarText {
            text: Music.hasPlayer ? (Music.activePlayer.identity || "Player") : "󰎈"
            font.family: Theme.fontFamily
            font.pixelSize: Music.hasPlayer ? Theme.fontSizeMedium : Theme.fontSizeHeading
            color: Theme.textPrimary
            elide: Text.ElideRight
        }
    }
}
