import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.components
import qs.panels
import qs.singletons
import qs.widgets

// Top-anchored horizontal bar spanning the full screen width
PanelWindow {
    id: bar
    required property var modelData
    property var activeScreen: null
    signal popupOpened

    screen: modelData

    // Tracks the loaded NotificationsWidget item for signal routing
    property var notifWidget: null

    // Exposed so Component definitions (which have their own id scope) can reference it
    property var settingsWindowRef: null

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
    color: "transparent"

    implicitHeight: Config.bar.layout.reservedSpace

    // Widget components — one per widget type
    Component {
        id: _powerComp
        PowerWidget {
            popup: popupLoader
        }
    }
    Component {
        id: _settingsComp
        SettingsWidget {
            settingsWindow: bar.settingsWindowRef
        }
    }
    Component {
        id: _workspacesComp
        WorkspacesWidget {}
    }
    Component {
        id: _clockComp
        ClockWidget {
            popup: popupLoader
        }
    }
    Component {
        id: _musicComp
        MusicWidget {
            popup: popupLoader
        }
    }
    Component {
        id: _soundComp
        SoundWidget {
            popup: popupLoader
        }
    }
    Component {
        id: _bluetoothComp
        BluetoothWidget {
            popup: popupLoader
        }
    }
    Component {
        id: _trayComp
        TrayWidget {
            popup: popupLoader
        }
    }
    Component {
        id: _networkComp
        NetworkWidget {
            popup: popupLoader
        }
    }
    Component {
        id: _notifComp
        NotificationsWidget {
            popup: popupLoader
        }
    }
    Component {
        id: _hardwareComp
        HardwareWidget {
            popup: popupLoader
        }
    }
    Component {
        id: _sttComp
        SttWidget {}
    }

    readonly property var _widgetMap: ({
            "power": _powerComp,
            "settings": _settingsComp,
            "workspaces": _workspacesComp,
            "clock": _clockComp,
            "music": _musicComp,
            "sound": _soundComp,
            "bluetooth": _bluetoothComp,
            "tray": _trayComp,
            "network": _networkComp,
            "notifications": _notifComp,
            "hardware": _hardwareComp,
            "stt": _sttComp
        })

    function _zipModel(types, profilesJson) {
        var profs = JSON.parse(profilesJson || "[]")
        return types.map((t, i) => ({ type: t, profile: profs[i] || "" }))
    }

    readonly property var _leftModel:   _zipModel(Config.bar.content.left,   Config.bar.content.leftProfiles)
    readonly property var _centerModel: _zipModel(Config.bar.content.center, Config.bar.content.centerProfiles)
    readonly property var _rightModel:  _zipModel(Config.bar.content.right,  Config.bar.content.rightProfiles)

    // Visual bar rectangle — floats within the reserved space
    Rectangle {
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: Config.bar.layout.topOffset
            leftMargin: Config.bar.layout.leftMargin
            rightMargin: Config.bar.layout.rightMargin
        }
        height: Config.bar.layout.barHeight
        color: Theme.barBackground
        topLeftRadius: Config.bar.layout.radiusTopLeft / 100 * (Config.bar.layout.barHeight / 2)
        topRightRadius: Config.bar.layout.radiusTopRight / 100 * (Config.bar.layout.barHeight / 2)
        bottomLeftRadius: Config.bar.layout.radiusBottomLeft / 100 * (Config.bar.layout.barHeight / 2)
        bottomRightRadius: Config.bar.layout.radiusBottomRight / 100 * (Config.bar.layout.barHeight / 2)

        // Three-section bar layout: left-aligned, centered, right-aligned
        Item {
            anchors.fill: parent
            anchors.leftMargin: Config.bar.layout.leftPadding
            anchors.rightMargin: Config.bar.layout.rightPadding

            // Left section
            RowLayout {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                spacing: 5

                Repeater {
                    model: bar._leftModel
                    delegate: Loader {
                        required property var modelData
                        Layout.fillHeight: true
                        Layout.topMargin: 5
                        Layout.bottomMargin: 5
                        sourceComponent: bar._widgetMap[modelData.type]
                        onLoaded: {
                            if (typeof item.profile !== "undefined")
                                item.profile = Qt.binding(() => modelData.profile)
                            if (modelData.type === "notifications")
                                bar.notifWidget = item
                        }
                    }
                }
            }

            // Center section
            RowLayout {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                Repeater {
                    model: bar._centerModel
                    delegate: Loader {
                        required property var modelData
                        Layout.fillHeight: true
                        Layout.topMargin: 5
                        Layout.bottomMargin: 5
                        sourceComponent: bar._widgetMap[modelData.type]
                        onLoaded: {
                            if (typeof item.profile !== "undefined")
                                item.profile = Qt.binding(() => modelData.profile)
                            if (modelData.type === "notifications")
                                bar.notifWidget = item
                        }
                    }
                }
            }

            // Right section
            RowLayout {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                spacing: 5

                Repeater {
                    model: bar._rightModel
                    delegate: Loader {
                        required property var modelData
                        Layout.fillHeight: true
                        Layout.topMargin: 5
                        Layout.bottomMargin: 5
                        sourceComponent: bar._widgetMap[modelData.type]
                        onLoaded: {
                            if (typeof item.profile !== "undefined")
                                item.profile = Qt.binding(() => modelData.profile)
                            if (modelData.type === "notifications")
                                bar.notifWidget = item
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: Notifications
        function onOpenPanelRequested() {
            if (notifWidget && (!popupLoader.active || popupLoader.contentType !== "notifications")) {
                popupLoader.open(notifWidget, true, "notifications");
            }
        }
    }

    SettingsWindow {
        id: settingsWindow
        Component.onCompleted: bar.settingsWindowRef = settingsWindow
        onBackingWindowVisibleChanged: if (!backingWindowVisible) visible = false
    }

    Connections {
        target: Shell
        function onOpenSettings(category) {
            settingsWindow.selectedCategory = category;
            settingsWindow.visible = true;
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
