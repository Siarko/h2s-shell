pragma Singleton

import Quickshell

// What the core's registries need of the modules, as plain values — and nothing else: no
// host, no file, no process. The Modules singleton (the shell's host) writes them as its
// modules settle; Profiles (facts), ProfileRules (fact types), SettingsSchema (setting
// entries) and WidgetRegistry (widget entries) read them here, never from Modules. So nothing
// on the lock screen's path — Lockscreen reads its settings through Profiles → SettingsSchema
// — constructs the module host or waits for it: before the modules have answered these are
// empty (a module's settings take no part, its facts are unknown), and they fill in after the
// first frame.
Singleton {
    // Modules.widgetEntries, .settingEntries, .factTypes, .factValues (ModuleHost's)
    property var widgetEntries: []
    property var settingEntries: []
    property var factTypes: []
    property var factValues: ({})
    // The shell's host has loaded and nothing is pending any more
    property bool settled: false
}
