pragma Singleton

import Quickshell
import QtQuick

// The one list of bar widget types. Everything that needs to know about a widget type —
// the bar that instantiates it, the section editor that names and offers it, the settings
// pane, the popup — reads it from here. Adding a widget means adding its files and one
// entry below; tests/WidgetRegistryTest.qml checks that every listed file loads.
//
// Entry fields (paths are relative to the repo root):
//   type        — key used in the bar section settings (bar.left etc.) and in the
//                 widget preset library, Config.widgetPresets
//   name        — shown in settings
//   widget      — the bar widget
//   popup       — popup content key, for widgets built on PopupWidget; their popup mode
//                 is user-configurable. The tray, which opens a menu per icon, leaves it
//                 out.
//   popupPanel  — the panel the popup shows for that key. A panel that needs wiring to
//                 the popup is built from Popup.qml's _componentMap instead, which wins.
//   settings    — per-profile settings page, if the widget has one
Singleton {
    id: root

    // Hover cannot fire on a touch screen, so click is the default for every widget
    readonly property string defaultPopupMode: "click"

    readonly property var entries: [
        { type: "power", name: "Power", widget: "widgets/PowerWidget.qml",
          popup: "power", popupPanel: "panels/PowerMenu.qml" },
        { type: "settings", name: "Settings", widget: "widgets/SettingsWidget.qml" },
        { type: "workspaces", name: "Workspaces", widget: "widgets/WorkspacesWidget.qml",
          settings: "panels/widget_settings/WorkspacesWidgetSettings.qml" },
        { type: "clock", name: "Clock", widget: "widgets/ClockWidget.qml",
          popup: "calendar", popupPanel: "panels/Calendar.qml",
          settings: "panels/widget_settings/ClockWidgetSettings.qml" },
        { type: "music", name: "Music", widget: "widgets/MusicWidget.qml",
          popup: "music", popupPanel: "panels/MusicPanel.qml" },
        { type: "sound", name: "Sound", widget: "widgets/SoundWidget.qml",
          popup: "sound", popupPanel: "panels/SoundPanel.qml" },
        { type: "bluetooth", name: "Bluetooth", widget: "widgets/BluetoothWidget.qml",
          popup: "bluetooth", popupPanel: "panels/BluetoothPanel.qml" },
        { type: "tray", name: "System Tray", widget: "widgets/TrayWidget.qml" },
        { type: "network", name: "Network", widget: "widgets/NetworkWidget.qml",
          popup: "network", popupPanel: "panels/NetworkPanel.qml" },
        { type: "notifications", name: "Notifications", widget: "widgets/NotificationsWidget.qml",
          popup: "notifications", popupPanel: "panels/NotificationPanel.qml" },
        { type: "hardware", name: "Hardware", widget: "widgets/HardwareWidget.qml",
          popup: "hardware", popupPanel: "panels/HardwarePanel.qml",
          settings: "panels/widget_settings/HardwareWidgetSettings.qml" },
        { type: "stt", name: "Dictation", widget: "widgets/SttWidget.qml",
          settings: "panels/widget_settings/SttWidgetSettings.qml" }
    ]

    readonly property var types: entries.map(entry => entry.type)

    readonly property var _byType: {
        let map = {};
        for (const entry of entries)
            map[entry.type] = entry;
        return map;
    }

    function entry(type) {
        return _byType[type] ?? null;
    }

    function displayName(type) {
        return entry(type)?.name ?? type;
    }

    // Files are listed relative to the repo root; this file lives one level below it
    function _url(path) {
        return path ? Qt.resolvedUrl("../" + path) : "";
    }

    function widgetUrl(type) {
        return _url(entry(type)?.widget);
    }

    function settingsUrl(type) {
        return _url(entry(type)?.settings);
    }

    function hasPopupMode(type) {
        return !!entry(type)?.popup;
    }

    function popupContent(type) {
        return entry(type)?.popup ?? "";
    }

    // Popup content key → panel URL, for every widget whose popup is a plain panel
    function popupPanelUrl(content) {
        for (const entry of entries) {
            if (entry.popup === content)
                return _url(entry.popupPanel);
        }
        return "";
    }
}
