import QtQuick
import qs.api

// The fixture's element on a VPN card's name line: a width of its own and no implicit width,
// which the place takes as its width
Rectangle {
    property var module: null
    property var context: null

    objectName: "anchors-vpn-title:Mark"
    width: 16
    radius: 4
    color: Api.theme.accent
}
