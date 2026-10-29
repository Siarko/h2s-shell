pragma Singleton

import QtQuick

// Cross-cutting UI commands that any component can emit without needing
// direct references to top-level windows.
QtObject {
    // category: index into the SettingsWindow sidebar list
    signal openSettings(int category)
}
