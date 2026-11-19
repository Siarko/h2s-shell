import QtQuick
import qs.api

// The fixture's element on a card's name line: taller than the line (the place gives it the
// line's height), hidden on Cafe's card (it takes no room there), counting the contexts it is
// handed
Rectangle {
    property var module: null
    property var context: null
    property int contextChanges: 0

    objectName: "anchors-networks:Title"
    visible: context?.networkId !== "anchors-cafe"
    implicitWidth: 24
    implicitHeight: 40
    radius: 4
    color: Api.theme.accent

    onContextChanged: contextChanges++
}
