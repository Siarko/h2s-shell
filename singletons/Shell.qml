pragma Singleton

import QtQuick

// Cross-cutting UI commands that any component can emit without needing
// direct references to top-level windows.
QtObject {
    // Opens the settings window on a page, by its id (SettingsWindow.pages)
    signal openSettings(string pageId)
    // Shows the settings window, or hides it if it is open
    signal toggleSettings()
}
