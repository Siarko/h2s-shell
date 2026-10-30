import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import qs.components
import qs.singletons

// A bare row of icons: no cell background or padding, and each icon takes its own
// clicks, so the cell itself takes no input
BarWidget {
    id: root
    widgetType: "tray"
    property var popup: null

    interactive: false
    cellColor: "transparent"
    horizontalPadding: 0
    // An empty tray takes no space
    Layout.minimumWidth: 0

    Row {
        anchors.centerIn: parent
        height: root.height
        spacing: Theme.tray.pillSpacing

        Repeater {
            // ScriptModel, never the bare array — see "The Repeater crash" in
            // docs/ARCHITECTURE.md
            model: ScriptModel {
                values: SystemTray.items.values
            }

            delegate: Item {
                id: trayDelegate
                required property SystemTrayItem modelData
                required property int index

                readonly property bool menuOpen: !!root.popup?.active
                    && root.popup?.contentType === "tray-menu"
                    && Tray.menuHandle === modelData.menu

                // Grows in from nothing, so the icons beside it slide aside rather than jump
                width: 0
                height: parent.height
                opacity: 0
                clip: true
                Component.onCompleted: {
                    width = Qt.binding(() => Theme.tray.pillWidth);
                    opacity = 1;
                }
                Behavior on width { NumberAnimation { duration: Theme.duration("enter"); easing: Theme.curve("enter") } }
                Behavior on opacity { NumberAnimation { duration: Theme.duration("enter"); easing: Theme.curve("enter") } }

                // Highlighted under the pointer and while its menu is open, like a cell
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.tray.pillRadius
                    color: iconMouseArea.containsMouse || trayDelegate.menuOpen ? Theme.surfaceHover : Theme.surfaceHoverClear
                    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
                }

                Image {
                    anchors.centerIn: parent
                    source: trayDelegate.modelData.icon
                    width: Theme.tray.iconSize
                    height: Theme.tray.iconSize
                    sourceSize: Qt.size(Theme.tray.iconSize, Theme.tray.iconSize)
                }

                MouseArea {
                    id: iconMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    onClicked: event => {
                        const item = trayDelegate.modelData
                        const wantsMenu = event.button === Qt.RightButton || item.onlyMenu
                        if (wantsMenu && item.hasMenu) {
                            if (trayDelegate.menuOpen) {
                                root.popup.close()
                            } else {
                                Tray.calculateDirection(trayDelegate.index)
                                Tray.menuHandle = item.menu
                                root.popup.open(trayDelegate, true, "tray-menu")
                            }
                        } else if (!item.onlyMenu) {
                            item.activate()
                        }
                    }
                }
            }
        }
    }
}
