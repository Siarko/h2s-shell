import QtQuick
import Quickshell.Bluetooth
import qs.components
import qs.singletons

BarWidget {
    property var popup: null

    onHover: state => {
        if (state)
            popup.open(this, false, "bluetooth")
    }

    Row {
        anchors.centerIn: parent
        spacing: 4

        Text {
            property bool powered: Bluetooth.defaultAdapter?.enabled ?? false
            text: !powered ? "󰂲" : Bluetooth.devices.count > 0 ? "󰂱" : "󰂯"
            font.family: Theme.fontFamily
            font.pixelSize: 18
            color: powered ? Theme.textPrimary : Theme.textDim
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            visible: (Bluetooth.defaultAdapter?.enabled ?? false) && Bluetooth.devices.count > 0
            text: Bluetooth.devices?.count ?? ""
            font.family: Theme.fontFamily
            font.pixelSize: 13
            color: Theme.textPrimary
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
