import QtQuick
import qs.api

// The fixture's contribution to the network popup (slot network.popup.sections)
Item {
    id: slotItem
    objectName: "goodSlot"

    property var module: null
    property var context: null
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
