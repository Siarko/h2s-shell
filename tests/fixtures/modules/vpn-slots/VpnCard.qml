import QtQuick
import qs.api

// The fixture's contribution to network.vpn.card: shows what it was given
Text {
    objectName: "vpnSlotsCard"
    property var module: null
    property var context: null
    text: "Card of " + (context?.vpnId ?? "?") + " by " + (module?.moduleId ?? "?")
    font.family: Api.theme.fontFamily
    font.pixelSize: Api.theme.fontSizeSmall
    color: Api.theme.textSecondary
}
