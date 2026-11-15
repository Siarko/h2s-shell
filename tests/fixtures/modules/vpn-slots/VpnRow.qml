import QtQuick
import qs.api

// The fixture's contribution to network.vpn.row: shows what it was given
Text {
    objectName: "vpnSlotsRow"
    property var module: null
    property var context: null
    text: "Row of " + (context?.vpnId ?? "?") + " by " + (module?.moduleId ?? "?")
    font.family: Api.theme.fontFamily
    font.pixelSize: Api.theme.fontSizeSmall
    color: Api.theme.textSecondary
}
