import QtQuick

// The settings window and every page and control under panels/settings must compile, and
// what loads only when opened (the popup frame, the calendar's event form). A
// page is only loaded when its sidebar entry is clicked, so a broken one otherwise goes
// unnoticed until then.
TestCase {
    suiteName: "SettingsPages"

    readonly property var _files: [
        "panels/SettingsWindow.qml",
        "panels/BarSectionList.qml",
        "panels/calendar/EventForm.qml",
        "panels/calendar/EventColorRow.qml",
        "panels/calendar/RecurrenceEditor.qml",
        "components/Checkbox.qml",
        "panels/calendar/TimeField.qml",
        "panels/NetworkPanel.qml",
        "panels/network/HiddenNetworkRow.qml",
        "panels/network/LinkInfo.qml",
        "panels/network/SignalBars.qml",
        "panels/network/VpnSection.qml",
        "panels/network/WifiNetworkRow.qml",
        "panels/Popup.qml",
        "panels/HardwareSourceList.qml",
        "panels/WidgetSettingsPane.qml",
        "panels/settings/AnimationsSettings.qml",
        "panels/settings/BarSettings.qml",
        "panels/settings/BarShapeSettings.qml",
        "panels/settings/CalendarSettings.qml",
        "panels/settings/ConditionEditor.qml",
        "panels/settings/ColorsSettings.qml",
        "panels/settings/CurvesSettings.qml",
        "panels/settings/DraftActions.qml",
        "panels/settings/FontsSettings.qml",
        "panels/settings/GeneralSettings.qml",
        "panels/settings/LockscreenSettings.qml",
        "panels/settings/MediaSettings.qml",
        "panels/settings/NotificationsSettings.qml",
        "panels/settings/PerformanceSettings.qml",
        "panels/settings/ProfilesSettings.qml",
        "panels/settings/SchemaSettingEditor.qml",
        "panels/settings/SttSettings.qml",
        "panels/settings/ShapeSettings.qml",
        "panels/settings/ShapeSections.qml",
        "panels/settings/ThemesSettings.qml",
        "screensaver/LockSurface.qml",
        "screensaver/NotificationPreview.qml",
        "screensaver/ScreensaverSurface.qml"
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
