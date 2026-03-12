import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray
import qs.singletons

Row {
    property var popup: null

    spacing: 4
    Layout.fillHeight: true

    Repeater {
        model: SystemTray.items

        delegate: Item {
            id: trayDelegate
            required property SystemTrayItem modelData
            required property int index

            width: 24
            height: parent.height

            Image {
                anchors.centerIn: parent
                source: trayDelegate.modelData.icon
                width: 18
                height: 18
                sourceSize: Qt.size(18, 18)
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton

                onClicked: event => {
                    const item = trayDelegate.modelData
                    const wantsMenu = event.button === Qt.RightButton || item.onlyMenu
                    if (wantsMenu && item.hasMenu) {
                        if (popup?.active && popup?.contentType === "tray-menu" && Tray.menuHandle === item.menu) {
                            popup.close()
                        } else {
                            Tray.calculateDirection(trayDelegate.index)
                            Tray.menuHandle = item.menu
                            popup.open(trayDelegate, true, "tray-menu")
                        }
                    } else if (!item.onlyMenu) {
                        item.activate()
                    }
                }
            }
        }
    }
}
