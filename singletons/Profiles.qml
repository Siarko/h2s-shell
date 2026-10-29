pragma Singleton

import Quickshell
import QtQuick

// Effective values of the settings in SettingsSchema: the system profile (the schema
// defaults) overlaid by every active profile, in order. Read them with value(key) in a
// binding; it follows profile changes. See docs/plans/adaptive-polling.md.
//
// Step 1 of the plan: no profiles yet, so every value is its default.
Singleton {
    id: root

    readonly property var effective: SettingsSchema.defaults

    function value(key) {
        return effective[key];
    }
}
