import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.SystemTray
import qs.components
import qs.panels
import qs.singletons

// Top-anchored horizontal bar spanning the full screen width
PanelWindow {
    id: bar
    required property var modelData
    property var activeScreen: null
    signal popupOpened

    screen: modelData

    // True when the notifications popup is the active panel — suppresses HUD toasts
    property bool notifPanelOpen: popupLoader.active && popupLoader.contentType === "notifications"
    onNotifPanelOpenChanged: Notifications.setHudPanelOpen(notifPanelOpen)

    // Close this screen's popup when another screen's popup opens
    onActiveScreenChanged: {
        if (activeScreen !== bar.modelData) {
            popupLoader.close();
        }
    }

    anchors {
        top: true
        left: true
        right: true
    }
    color: Theme.barBackground

    implicitHeight: 40

    // Three-section bar layout: left-aligned, centered, right-aligned
    Item {
        anchors.fill: parent
        anchors.leftMargin: 5
        anchors.rightMargin: 5

        // Left section: power button + workspaces
        RowLayout {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            spacing: 5

            Cell {
                cellColor: Theme.cellDefault
                onPlonked: {
                    if (popupLoader.active && popupLoader.contentType === "power") {
                        popupLoader.close();
                    } else {
                        popupLoader.open(this, false, "power");
                    }
                }

                Text {
                    text: "⏻"
                    font.family: Theme.fontFamily
                    font.pixelSize: 20
                    color: Theme.textPrimary
                    anchors.centerIn: parent
                }
            }

            // Workspace indicator — all workspaces in a single cell
            Item {
                Layout.fillHeight: true
                Layout.topMargin: 5
                Layout.bottomMargin: 5
                implicitWidth: wsRow.width + 16

                Rectangle {
                    anchors.fill: parent
                    radius: 5
                    color: Theme.cellDefault
                }

                Row {
                    id: wsRow
                    anchors.centerIn: parent
                    spacing: 4

                    Repeater {
                        model: Workspaces.workspaces
                        delegate: Rectangle {
                            required property var modelData
                            width: Math.max(22, wsText.implicitWidth + 8)
                            height: 22
                            radius: 4
                            color: modelData.focused ? Theme.cellAccent : (modelData.active ? Theme.cellAccentSecondary : "transparent")

                            Text {
                                id: wsText
                                text: modelData.name || modelData.id
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                                color: Theme.textPrimary
                                anchors.centerIn: parent
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: Workspaces.activate(modelData)
                            }
                        }
                    }
                }
            }
        }

        // Center section: clock
        RowLayout {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            Cell {
                cellColor: Theme.cellDefault
                onHover: s => {
                    if (s) {
                        popupLoader.open(this);
                    }
                }

                Text {
                    text: Time.time
                    font.family: Theme.fontFamily
                    font.pixelSize: 20
                    color: Theme.textPrimary
                    anchors.centerIn: parent
                }
            }
        }

        // Right section: player + volume + notifications
        RowLayout {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            spacing: 5

            Cell {
                cellColor: Theme.cellDefault

                onHover: state => {
                    if (state) {
                        popupLoader.open(this, false, "music");
                    }
                }
                onMiddleClicked: Music.togglePlay()
                onScrolled: delta => {
                    if (delta > 0)
                        Music.next();
                    else
                        Music.previous();
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        text: Music.playing ? "󰐊" : "󰏤"
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        color: Theme.textPrimary
                        visible: Music.hasPlayer
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: Music.hasPlayer ? (Music.activePlayer.identity || "Player") : "󰎈"
                        font.family: Theme.fontFamily
                        font.pixelSize: Music.hasPlayer ? 14 : 18
                        color: Theme.textPrimary
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                    }
                }
            }

            Cell {
                cellColor: Theme.cellDefault

                onPlonked: {
                    if (popupLoader.active && popupLoader.contentType === "sound") {
                        popupLoader.close();
                    } else {
                        popupLoader.open(this, true, "sound");
                    }
                }
                onMiddleClicked: {
                    if (Audio.sink?.audio) {
                        Audio.sink.audio.muted = !Audio.sink.audio.muted;
                    }
                }
                onScrolled: delta => {
                    if (Audio.sink?.audio) {
                        const amount = Audio.sink.audio.volume + delta * 0.01;
                        Audio.sink.audio.volume = Math.max(0, Math.min(1.5, amount));
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        text: Audio.volume + "%"
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        color: Audio.muted ? Theme.textDim : Audio.volume > 100 ? Theme.textWarning : Theme.textPrimary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: Audio.muted ? "󰖁" : "󰕾"
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        color: Audio.muted ? Theme.textDim : Theme.textPrimary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Cell {
                cellColor: Theme.cellDefault
                onPlonked: {
                    if (popupLoader.active && popupLoader.contentType === "bluetooth") {
                        popupLoader.close();
                    } else {
                        popupLoader.open(this, true, "bluetooth");
                    }
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

            // System tray icons
            Row {
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
                                const item = trayDelegate.modelData;
                                const wantsMenu = event.button === Qt.RightButton || item.onlyMenu;
                                if (wantsMenu && item.hasMenu) {
                                    if (popupLoader.active && popupLoader.contentType === "tray-menu" && Tray.menuHandle === item.menu) {
                                        popupLoader.close();
                                    } else {
                                        Tray.calculateDirection(trayDelegate.index);
                                        Tray.menuHandle = item.menu;
                                        popupLoader.open(trayDelegate, true, "tray-menu");
                                    }
                                } else if (!item.onlyMenu) {
                                    item.activate();
                                }
                            }
                        }
                    }
                }
            }

            Cell {
                id: notifCell
                cellColor: Theme.cellDefault
                onPlonked: {
                    if (popupLoader.active && popupLoader.contentType === "notifications") {
                        popupLoader.close();
                    } else {
                        popupLoader.open(this, true, "notifications");
                    }
                }

                Text {
                    text: "󰂚"
                    font.family: Theme.fontFamily
                    color: Theme.textPrimary
                    anchors.centerIn: parent
                }
            }
        }
    }

    Connections {
        target: Notifications
        function onOpenPanelRequested() {
            if (!popupLoader.active || popupLoader.contentType !== "notifications") {
                popupLoader.open(notifCell, true, "notifications");
            }
        }
    }

    // Popup panel that appears below the hovered cell
    Popup {
        id: popupLoader
        popupPosition: 0
        popupWidth: 0
        // Notify parent so other screens close their popups
        onOpened: bar.popupOpened()
    }
}
