pragma Singleton

import QtQuick

// Cross-cutting UI commands that any component can emit without needing
// direct references to top-level windows.
QtObject {
    // Opens the settings window on a page, by its id (SettingsWindow.pages)
    signal openSettings(string pageId)
    // … with one of its sections shown at the top (a page that has them by name:
    // WhenAwaySettings.sections)
    signal openSettingsAt(string pageId, string section)
    // Shows the settings window, or hides it if it is open
    signal toggleSettings()
    // The ids of the pages the settings window has now (SettingsWindow.pages, modules' pages
    // included), published by the window: what openSettings can open. VpnManager asks it
    // whether a VPN provider's own settings page is there (VpnProvider.settingsPage).
    property var settingsPageIds: []
}
