import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import qs.singletons

Row {
    id: root
    property var popup: null

    spacing: 4
    Layout.fillHeight: true

    Repeater {
        // ScriptModel diffs old vs. new values so only changed delegates get
        // added/removed — see MusicPanel.qml for why binding a plain live-model
        // array straight to Repeater.model was crashing this app.
        model: ScriptModel {
            values: SystemTray.items.values
        }

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
