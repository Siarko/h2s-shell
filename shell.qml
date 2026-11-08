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

    // Popup panels are compiled the first time they open, which delayed the first opening
    // of the calendar and the music panel by 20 ms. Compile them in the background once the
    // shell has settled instead; no objects are created. Kept, so the compiled types stay
    // cached.
    property var _compiledPanels: []
    property var _warmUp: Timer {
        interval: 3000
        running: true
        onTriggered: {
            const urls = WidgetRegistry.entries.filter(entry => entry.popupPanel)
                .map(entry => WidgetRegistry.popupPanelUrl(entry.popup))
                .concat([Qt.resolvedUrl("panels/TrayMenu.qml")]);
            root._compiledPanels = urls.map(url => Qt.createComponent(url, Component.Asynchronous));
        }
    }

    // Wires dictation state to music playback; needs to run whether or not the
    // dictation widget is on the bar
    property var _dictationMusicPause: DictationMusicPause
    // Puts Bluetooth back on or off as it was left; needs to run from the start
    property var _bluetoothPower: BluetoothPower

    // One for the whole shell: a window per screen meant two independent windows, both
    // opened by Shell.openSettings() and both announcing every save
    property var _settingsWindow: SettingsWindow {
        id: settingsWindow
        onBackingWindowVisibleChanged: if (!backingWindowVisible) visible = false
    }

    property var _settingsRequests: Connections {
        target: Shell
        function onOpenSettings(pageId) {
            settingsWindow.selectedPage = pageId;
            settingsWindow.visible = true;
        }
        function onToggleSettings() {
            settingsWindow.visible = !settingsWindow.visible;
        }
    }

    // The settings window from outside, e.g. with no settings widget on the bar:
    //   qs ipc call settings open
    //   qs ipc call settings openPage profiles     (a page's id: SettingsWindow.pages)
    //   qs ipc call settings toggle
    //   qs ipc call settings close
    property var _settingsIpc: IpcHandler {
        target: "settings"

        function open(): void {
            settingsWindow.visible = true;
        }

        function openPage(page: string): string {
            if (!settingsWindow.pages.some(entry => entry.id === page))
                return "No page \"" + page + "\"; pages: " + settingsWindow.pages.map(entry => entry.id).join(", ");
            Shell.openSettings(page);
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
