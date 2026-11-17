//@ pragma UseQApplication
import Quickshell
import QtQuick
import Quickshell.Io
import qs.singletons
import qs.singletons.network
import qs.screensaver
import qs.panels
import qs.wallpaper
import qs.polkit
// Not used here: imported so that Quickshell makes qs.api, which modules import (loaded by
// URL, they are not reached by its scan of this tree)
import qs.api

// Top-level shell root: one Bar, one Hud and a wallpaper per screen, one settings window
QtObject {
    id: root

    // The modules (notes/plans/modules.md), first: their manifests are read and the ones
    // that can run are started before the bars are built. Modules is core code and catches
    // its own failures (no modules then); no module file is ever imported statically.
    property var _modules: Modules

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

    // The wallpaper, under everything, only while it is turned on (Wallpapers)
    property var _wallpapers: Variants {
        model: Quickshell.screens
        delegate: Component {
            LazyLoader {
                id: _wallpaperLoader
                required property var modelData
                active: Wallpapers.enabled
                WallpaperSurface { modelData: _wallpaperLoader.modelData }
            }
        }
    }

    // VPNs brought up with their networks, and the blocking outside them, from the start,
    // whatever the bar shows (VpnManager, VpnLockdown)
    property var _vpns: VpnManager
    property var _vpnLockdown: VpnLockdown
    Component.onCompleted: {
        VpnManager.start();
        VpnLockdown.start();
    }

    // The polkit agent decides at start whether it answers (Authentication); its prompt
    // exists while a request is open, on the focused screen
    property var _authentication: Authentication
    property var _authPrompt: LazyLoader {
        active: Authentication.flow !== null
        AuthPrompt {
            flow: Authentication.flow
            screen: Quickshell.screens.find(screen => screen.name === Workspaces.screens.find(entry => entry.focused)?.name)
                ?? Quickshell.screens[0]
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
    // Counts use per app on battery, popup open or not (the battery popup shows it)
    property var _energyUsage: EnergyUsage

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
    //   qs ipc call settings currentPage           (the open page's id, the one the list selects)
    //   qs ipc call settings itemRect profileSettings   (where a shown item is, for tests)
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

        function currentPage(): string {
            return settingsWindow.selectedPage;
        }

        function toggle(): void {
            Shell.toggleSettings();
        }

        function close(): void {
            settingsWindow.visible = false;
        }

        // For tests driving the window from outside: the first shown item with that
        // objectName, in the window's own logical pixels ("{}" none) — the compositor knows
        // where the window is (hyprctl clients), the shell does not
        function itemRect(name: string): string {
            const find = item => {
                for (const child of item?.children ?? []) {
                    if (child.objectName === name && child.visible)
                        return child;
                    const found = find(child);
                    if (found)
                        return found;
                }
                return null;
            };
            const item = settingsWindow.visible ? find(settingsWindow.contentItem) : null;
            if (!item)
                return "{}";
            const topLeft = item.mapToItem(null, 0, 0);
            return JSON.stringify({ x: Math.round(topLeft.x), y: Math.round(topLeft.y),
                                    width: Math.round(item.width), height: Math.round(item.height) });
        }
    }

    property var _screensavers: Variants {
        model: Quickshell.screens
        delegate: Component { ScreensaverSurface {} }
    }
}
