//@ pragma UseQApplication
import Quickshell
import QtQuick
import Quickshell.Io
import qs.singletons
import qs.screensaver
import qs.panels

// Top-level shell root: one Bar and one Hud per screen, one settings window
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

    // Wires dictation state to music playback; needs to run whether or not the
    // dictation widget is on the bar
    property var _dictationMusicPause: DictationMusicPause

    // One for the whole shell: a window per screen meant two independent windows, both
    // opened by Shell.openSettings() and both announcing every save
    property var _settingsWindow: SettingsWindow {
        id: settingsWindow
        onBackingWindowVisibleChanged: if (!backingWindowVisible) visible = false
    }

    property var _settingsRequests: Connections {
        target: Shell
        function onOpenSettings(category) {
            settingsWindow.selectedCategory = category;
            settingsWindow.visible = true;
        }
        function onToggleSettings() {
            settingsWindow.visible = !settingsWindow.visible;
        }
    }

    // The settings window from outside, e.g. with no settings widget on the bar:
    //   qs ipc call settings open
    //   qs ipc call settings openPage profiles     (any sidebar page, case-insensitive)
    //   qs ipc call settings toggle
    //   qs ipc call settings close
    property var _settingsIpc: IpcHandler {
        target: "settings"

        function open(): void {
            settingsWindow.visible = true;
        }

        function openPage(page: string): string {
            const index = settingsWindow.categoryNames.findIndex(name => name.toLowerCase() === page.toLowerCase());
            if (index < 0)
                return "No page \"" + page + "\"; pages: " + settingsWindow.categoryNames.join(", ");
            Shell.openSettings(index);
            return "";
        }

        function toggle(): void {
            Shell.toggleSettings();
        }

        function close(): void {
            settingsWindow.visible = false;
        }
    }

    property var _screensavers: Variants {
        model: Quickshell.screens
        delegate: Component { ScreensaverSurface {} }
    }
}
