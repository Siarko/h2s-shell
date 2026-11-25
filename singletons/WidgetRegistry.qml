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
//   settings    — its preset settings page, if the widget has settings of its own
//   multiple    — true if a section may hold more than one, each with its own preset
//   module      — (a module's entry only) its module's id; its files are file:// URLs
//   presetDefaults — (a module's entry only) its presets' defaults (WidgetPresets)
//   bindings    — what its interactions run when the preset does not say,
//                 { <interaction>: binding } (InteractionRules); the popup's left click
//                 is implied by `popup`, a declared left click overrides it
//   actions     — its own actions, [{ id, … }]; a binding names one as "own:<id>"
//   cellInteractions — the interactions its cell takes, absent: all; [] for a widget
//                 whose cell takes none (the tray: each icon has its own clicks)
Singleton {
    id: root

    // Hover cannot fire on a touch screen, so click is the default for every widget
    readonly property string defaultPopupMode: "click"

    // The core's own widget types
    readonly property var coreEntries: [
        { type: "power", name: "Power", widget: "widgets/PowerWidget.qml",
          popup: "power", popupPanel: "panels/PowerMenu.qml" },
        { type: "settings", name: "Settings", widget: "widgets/SettingsWidget.qml" },
        { type: "workspaces", name: "Workspaces", widget: "widgets/WorkspacesWidget.qml",
          settings: "panels/widget_settings/WorkspacesWidgetSettings.qml", multiple: true },
        { type: "clock", name: "Clock", widget: "widgets/ClockWidget.qml",
          popup: "calendar", popupPanel: "panels/Calendar.qml",
          settings: "panels/widget_settings/ClockWidgetSettings.qml", multiple: true },
        { type: "music", name: "Music", widget: "widgets/MusicWidget.qml",
          popup: "music", popupPanel: "panels/MusicPanel.qml" },
        { type: "sound", name: "Sound", widget: "widgets/SoundWidget.qml",
          popup: "sound", popupPanel: "panels/SoundPanel.qml" },
        { type: "bluetooth", name: "Bluetooth", widget: "widgets/BluetoothWidget.qml",
          popup: "bluetooth", popupPanel: "panels/BluetoothPanel.qml" },
        { type: "tray", name: "System Tray", widget: "widgets/TrayWidget.qml", cellInteractions: [] },
        { type: "network", name: "Network", widget: "widgets/NetworkWidget.qml",
          popup: "network", popupPanel: "panels/NetworkPanel.qml" },
        { type: "notifications", name: "Notifications", widget: "widgets/NotificationsWidget.qml",
          popup: "notifications", popupPanel: "panels/NotificationPanel.qml",
          settings: "panels/widget_settings/NotificationsWidgetSettings.qml" },
        { type: "hardware", name: "Hardware", widget: "widgets/HardwareWidget.qml",
          popup: "hardware", popupPanel: "panels/HardwarePanel.qml",
          settings: "panels/widget_settings/HardwareWidgetSettings.qml", multiple: true },
        { type: "battery", name: "Battery", widget: "widgets/BatteryWidget.qml",
          popup: "battery", popupPanel: "panels/BatteryPanel.qml",
          settings: "panels/widget_settings/BatteryWidgetSettings.qml", multiple: true },
        { type: "stt", name: "Dictation", widget: "widgets/SttWidget.qml",
          settings: "panels/widget_settings/SttWidgetSettings.qml" }
    ]

    // Every widget type: the core's, then the loaded modules' (Modules.widgetEntries — their
    // files absolute file:// URLs, each entry naming its `module`). A module turned off takes
    // its types with it: a bar section naming one keeps the entry and shows nothing there.
    readonly property var entries: ModuleMergeRules.mergeWidgetEntries(coreEntries, ModuleLists.widgetEntries)

    readonly property var types: entries.map(entry => entry.type)

    readonly property var _byType: {
        let map = {};
        for (const entry of entries)
            map[entry.type] = entry;
        return map;
    }

    function entry(type) {
        // Own properties only: "constructor" or "__proto__" is no widget type
        return typeof type === "string" && Object.prototype.hasOwnProperty.call(_byType, type) ? _byType[type] : null;
    }

    function displayName(type) {
        return entry(type)?.name ?? type;
    }

    // The core's files are listed relative to the repo root (this file lives one level below
    // it); a module's are absolute URLs already
    function _url(path) {
        if (!path)
            return "";
        return /^[a-z]+:\/\//.test(path) ? path : Qt.resolvedUrl("../" + path);
    }

    // The module a type comes from ("" for the core's, or an unknown type)
    function moduleOf(type) {
        return entry(type)?.module ?? "";
    }

    // The module whose widget opens popup content `content` ("" for the core's)
    function popupModule(content) {
        return entries.find(entry => entry.popup === content)?.module ?? "";
    }

    function widgetUrl(type) {
        return _url(entry(type)?.widget);
    }

    function settingsUrl(type) {
        return _url(entry(type)?.settings);
    }

    // Whether the widget has presets: a settings page, or a cell that takes interactions,
    // whose bindings a preset holds
    function hasPresets(type) {
        return !!entry(type)?.settings || hasCellInteractions(type);
    }

    // Whether it has a settings page of its own (the section editor's preset row, until
    // bindings can be edited there)
    function hasSettingsPage(type) {
        return !!entry(type)?.settings;
    }

    function hasCellInteractions(type) {
        const found = entry(type);
        return !!found && (!Array.isArray(found.cellInteractions) || found.cellInteractions.length > 0);
    }

    // Its declared default bindings, { <interaction>: binding } (a copy; {} when none)
    function declaredBindings(type) {
        const bindings = entry(type)?.bindings;
        return bindings !== null && typeof bindings === "object" && !Array.isArray(bindings) ? JSON.parse(JSON.stringify(bindings)) : {};
    }

    // The ids of its own actions (a new list; [] when it declares none)
    function actionIds(type) {
        const actions = entry(type)?.actions;
        return Array.isArray(actions) ? actions.filter(action => typeof action?.id === "string").map(action => action.id) : [];
    }

    function allowsMultiple(type) {
        return entry(type)?.multiple === true;
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
