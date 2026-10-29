import QtQuick
import Quickshell.Bluetooth
import qs.components
import qs.singletons

PopupWidget {
    widgetType: "bluetooth"

    Row {
        anchors.centerIn: parent
        spacing: 4

        Text {
            property bool powered: Bluetooth.defaultAdapter?.enabled ?? false
            text: !powered ? "󰂲" : Bluetooth.devices.count > 0 ? "󰂱" : "󰂯"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            color: powered ? Theme.textPrimary : Theme.textDisabled
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            visible: (Bluetooth.defaultAdapter?.enabled ?? false) && Bluetooth.devices.count > 0
            text: Bluetooth.devices?.count ?? ""
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBodyLarge
            color: Theme.textPrimary
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
