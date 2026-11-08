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

    // The icon whose menu opened last, so the next menu slides in from its side
    property int _lastMenuIndex: 0
    cellColor: "transparent"
    horizontalPadding: 0
    // An empty tray takes no space
    Layout.minimumWidth: 0

    BarRow {
        anchors.centerIn: parent
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
                    && root.popup?.contentData?.menu === modelData.menu

                // Grows in from nothing along the bar, so the icons beside it slide aside
                // rather than jump; as thick as the bar's cell across it
                property real _length: 0
                width: root.vertical ? root.width : _length
                height: root.vertical ? _length : root.height
                opacity: 0
                clip: true
                Component.onCompleted: {
                    _length = Qt.binding(() => Theme.tray.pillWidth);
                    opacity = 1;
                }
                Behavior on _length { NumberAnimation { duration: Theme.duration("enter"); easing: Theme.curve("enter") } }
                Behavior on opacity { NumberAnimation { duration: Theme.duration("enter"); easing: Theme.curve("enter") } }

                // Highlighted under the pointer and while its menu is open, like a cell
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.tray.pillRadius
                    color: iconMouseArea.lit || trayDelegate.menuOpen ? Theme.surfaceHover : Theme.surfaceHoverClear
                    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
                }

                Image {
                    anchors.centerIn: parent
                    source: trayDelegate.modelData.icon
                    width: Theme.tray.iconSize
                    height: Theme.tray.iconSize
                    sourceSize: Qt.size(Theme.tray.iconSize, Theme.tray.iconSize)
                }

                PointerArea {
                    id: iconMouseArea
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    onClicked: event => {
                        const item = trayDelegate.modelData
                        const wantsMenu = event.button === Qt.RightButton || item.onlyMenu
                        if (wantsMenu && item.hasMenu) {
                            if (trayDelegate.menuOpen) {
                                root.popup.close()
                            } else {
                                const direction = trayDelegate.index < root._lastMenuIndex ? -1 : 1
                                root._lastMenuIndex = trayDelegate.index
                                root.popup.open(trayDelegate, true, "tray-menu", { menu: item.menu, direction: direction })
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
