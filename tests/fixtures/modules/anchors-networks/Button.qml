import QtQuick
import qs.api

// The fixture's button in an opened card's buttons: counts the clicks that reach it
SmallButton {
    property var module: null
    property var context: null
    property int clicks: 0

    objectName: "anchors-networks:Button"
    label: "Exit node"
    onClicked: clicks++
}
