import QtQuick
import Quickshell.Bluetooth
import qs.components
import qs.singletons

BarWidget {
    property var popup: null
    property string widgetType: "bluetooth"

    readonly property string _popupMode: {
        var data = JSON.parse(Config.widgetProfiles || "{}")
        return data["bluetooth"]?.["_popupMode"] ?? "hover"
    }

    onClicked: {
        if (_popupMode !== "click") return
        if (popup?.active && popup?.contentType === "bluetooth") popup.close()
        else popup.open(this, true, "bluetooth")
    }
    onHover: state => {
        if (_popupMode !== "hover") return
        if (state) popup.open(this, false, "bluetooth")
    }

    Row {
        anchors.centerIn: parent
        spacing: 4

        Text {
            property bool powered: Bluetooth.defaultAdapter?.enabled ?? false
            text: !powered ? "󰂲" : Bluetooth.devices.count > 0 ? "󰂱" : "󰂯"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            color: powered ? Theme.textPrimary : Theme.textDim
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
