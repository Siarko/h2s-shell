import QtQuick

// The settings window and every page and control under panels/settings must compile. A
// page is only loaded when its sidebar entry is clicked, so a broken one otherwise goes
// unnoticed until then.
TestCase {
    suiteName: "SettingsPages"

    readonly property var _files: [
        "panels/SettingsWindow.qml",
        "panels/settings/BarSettings.qml",
        "panels/settings/CalendarSettings.qml",
        "panels/settings/ConditionEditor.qml",
        "panels/settings/GeneralSettings.qml",
        "panels/settings/LockscreenSettings.qml",
        "panels/settings/MediaSettings.qml",
        "panels/settings/NotificationsSettings.qml",
        "panels/settings/PerformanceSettings.qml",
        "panels/settings/ProfilesSettings.qml",
        "panels/settings/SchemaSettingEditor.qml",
        "panels/settings/SettingOptions.qml",
        "panels/settings/SttSettings.qml"
    ]

    function run() {
        for (const file of _files) {
            const component = Qt.createComponent(Qt.resolvedUrl("../" + file));
            if (component.status === Component.Ready)
                assert(true, file + " compiles");
            else
                fail(file + " does not compile: " + component.errorString().trim());
        }
    }
}
