import QtQuick
import qs.api

// The fixture's contribution to a slot (network.vpn.card: a slot that stays one, so the
// slot machinery is tested on it; "good" is no VPN provider, so no card shows it)
Item {
    id: slotItem
    objectName: "goodSlot"

    property var module: null
    property var context: null
    // (API 1.2) On screen: given by the core, kept current
    property bool shown: false
    // How often the context was handed over (it should be only when it changes by value)
    property int contextChanges: 0
    onContextChanged: contextChanges += 1

    implicitWidth: 100
    implicitHeight: label.implicitHeight

    Text {
        id: label
        text: "good in " + (slotItem.context?.slot ?? "?")
        font.family: Api.theme.fontFamily
        font.pixelSize: Api.theme.fontSizeSmall
        color: Api.theme.textSecondary
    }
}
