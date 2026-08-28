pragma Singleton

import QtQuick

// Cross-cutting UI commands that any component can emit without needing
// direct references to top-level windows.
QtObject {
    // category indices: 0=General, 1=Calendar, 2=Media, 3=Bar, 4=Notifications
    signal openSettings(int category)
}
