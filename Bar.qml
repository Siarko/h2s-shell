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

        // Left section
        RowLayout {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            spacing: 5

            PowerWidget       { popup: popupLoader }
            SettingsWidget    { settingsWindow: settingsWindow }
            WorkspacesWidget  {}
        }

        // Center section
        RowLayout {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            ClockWidget { popup: popupLoader }
        }

        // Right section
        RowLayout {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            spacing: 5

            MusicWidget         { popup: popupLoader }
            SoundWidget         { popup: popupLoader }
            BluetoothWidget     { popup: popupLoader }
            TrayWidget          { popup: popupLoader }
            NetworkWidget       { popup: popupLoader }
            NotificationsWidget { id: notifWidget; popup: popupLoader }
        }
    }

    Connections {
        target: Notifications
        function onOpenPanelRequested() {
            if (!popupLoader.active || popupLoader.contentType !== "notifications") {
                popupLoader.open(notifWidget, true, "notifications");
            }
        }
    }

    SettingsWindow {
        id: settingsWindow
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
