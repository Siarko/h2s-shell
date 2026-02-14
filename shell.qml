import Quickshell
import QtQuick

// Creates a panel instance for each connected screen
Variants {
    id: root
    model: Quickshell.screens

    // Tracks which screen currently has an open popup, so others can close theirs
    property var activeScreen: null

    // Force the notification server to register on DBus at startup
    property var _notifications: Notifications.notifications

    delegate: Component {
        Bar {
            activeScreen: root.activeScreen
            onPopupOpened: root.activeScreen = modelData
        }
    }
}
