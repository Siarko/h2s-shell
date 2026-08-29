//@ pragma UseQApplication
import Quickshell
import QtQuick
import qs.singletons
import qs.screensaver

// Top-level shell root: one Bar and one Hud per screen
QtObject {
    id: root

    // Tracks which screen currently has an open popup, so others can close theirs
    property var activeScreen: null

    // Force the notification server to register on DBus at startup
    property var _notifications: Notifications.notifications

    property var _bars: Variants {
        model: Quickshell.screens
        delegate: Component {
            Bar {
                activeScreen: root.activeScreen
                onPopupOpened: root.activeScreen = modelData
            }
        }
    }

    property var _huds: Variants {
        model: Quickshell.screens
        delegate: Component {
            Hud {}
        }
    }

    property var _lockscreen: Lockscreen

    property var _screensavers: Variants {
        model: Quickshell.screens
        delegate: Component { ScreensaverSurface {} }
    }
}
