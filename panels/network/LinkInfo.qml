import QtQuick
import qs.components
import qs.singletons

// A connected link's details under its header: live speeds with their graph, then the
// address and DNS servers when known. The same for Ethernet and Wi-Fi.
Column {
    id: root

    // The link's manager, giving rxSpeed, txSpeed, rxHistory and txHistory
    property var speeds: null
    property string address: ""
    property string dns: ""

    spacing: 6

    LinkSpeedRow {
        width: parent.width
        rxSpeed: root.speeds?.rxSpeed ?? 0
        txSpeed: root.speeds?.txSpeed ?? 0
        rxHistory: root.speeds?.rxHistory ?? []
        txHistory: root.speeds?.txHistory ?? []
    }

    Text {
        visible: root.address !== ""
        width: parent.width
        text: root.address
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
        color: Theme.textSecondary
    }

    Text {
        visible: root.dns !== ""
        width: parent.width
        text: "DNS: " + root.dns
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeXSmall
        color: Theme.textMuted
    }
}
