import QtQuick
import qs.singletons

// The settings window and every page and control under panels/settings must compile, and
// what loads only when opened (the popup frame, the calendar's event form). A
// page is only loaded when its sidebar entry is clicked, so a broken one otherwise goes
// unnoticed until then. The notifications page's toast rows are checked built.
TestCase {
    suiteName: "SettingsPages"
    // The globals it pins for a while, put back key by key
    property GlobalsPin _globalsPin: GlobalsPin {}

    readonly property var _files: [
        "Bar.qml",
        "components/KeyedModel.qml",
        "components/ArrowButton.qml",
        "components/AudioChannelRow.qml",
        "components/BarWidget.qml",
        "components/ColorSwatch.qml",
        "components/DeleteButton.qml",
        "components/Dropdown.qml",
        "components/InputField.qml",
        "components/LinkSpeedRow.qml",
        "components/Pill.qml",
        "components/PointerArea.qml",
        "components/ModuleSlot.qml",
        "components/ModuleContribution.qml",
        "components/AnchorBlock.qml",
        "components/AnchorContent.qml",
        "components/SettingsPage.qml",
        "api/Api.qml",
        "api/ThemeTokens.qml",
        "api/ModuleHandle.qml",
        "api/ModuleStore.qml",
        "api/SettingEditor.qml",
        "api/SectionTitle.qml",
        "api/Heading.qml",
        "api/Hint.qml",
        "api/DetailRow.qml",
        "api/SwitchRow.qml",
        "api/SmallButton.qml",
        "api/Dropdown.qml",
        "api/InputField.qml",
        "api/Pill.qml",
        "api/Checkbox.qml",
        "api/ToggleSwitch.qml",
        "api/PrivilegedMark.qml",
        "api/SettingsRow.qml",
        "api/ExpandingRow.qml",
        "api/Notice.qml",
        "api/ProgressBar.qml",
        "api/HoverTip.qml",
        "api/SidePanel.qml",
        "components/SideDrawer.qml",
        "components/SidePanelHost.qml",
        "components/ModulePageFrame.qml",
        "components/ProgressBar.qml",
        "api/PopupWidget.qml",
        "api/BarText.qml",
        "api/BarRow.qml",
        "api/PointerArea.qml",
        "api/VpnProvider.qml",
        "components/SettingsRow.qml",
        "components/ExpandingRow.qml",
        "api/CommandAction.qml",
        "api/CommandQuery.qml",
        "api/CommandRunner.qml",
        "api/PrivilegedAction.qml",
        "widgets/BatteryWidget.qml",
        "panels/widget_settings/BatteryWidgetSettings.qml",
        "panels/settings/WallpaperSettings.qml",
        "wallpaper/WallpaperSurface.qml",
        "components/WallpaperGrid.qml",
        "components/WallpaperSlot.qml",
        "components/WallpaperFitPreview.qml",
        "components/WallpaperPicker.qml",
        "panels/settings/AuthenticationSettings.qml",
        "panels/settings/NetworkOverviewSettings.qml",
        "panels/settings/NetworkWifiSettings.qml",
        "panels/settings/NetworkEthernetSettings.qml",
        "panels/settings/SwitchRow.qml",
        "panels/settings/DetailRow.qml",
        "panels/settings/NetworkDeviceCard.qml",
        "panels/settings/NetworkProfileCard.qml",
        "panels/settings/SectionTitle.qml",
        "panels/settings/NetworkConnectionEditor.qml",
        "panels/settings/NetworkVpnSettings.qml",
        "panels/settings/ModulesSettings.qml",
        "panels/settings/ModuleInstallSection.qml",
        "panels/settings/ModuleUpdateQueue.qml",
        "panels/settings/VpnProviderPageFrame.qml",
        "panels/settings/KeepSettingsBar.qml",
        "components/PrivilegedMark.qml",
        "components/VpnProvider.qml",
        "components/VpnExtras.qml",
        "widgets/NetworkWidget.qml",
        "tests/FakeVpnProvider.qml",
        "tests/FakeVpnProviderPage.qml",
        "polkit/AuthPrompt.qml",
        "polkit/AuthCard.qml",
        "components/ToggleSwitch.qml",
        "components/SeekBar.qml",
        "components/SmallButton.qml",
        "components/VolumeSlider.qml",
        "panels/PowerMenu.qml",
        "panels/TrayMenu.qml",
        "panels/battery/EnergyUsageList.qml",
        "panels/calendar/EventsPanel.qml",
        "panels/settings/SettingSlider.qml",
        "panels/widget_settings/WorkspacesWidgetSettings.qml",
        "screensaver/LockPrompt.qml",
        "widgets/TrayWidget.qml",
        "widgets/WorkspacesWidget.qml",
        "panels/SettingsWindow.qml",
        "panels/BarSectionList.qml",
        "components/ReorderList.qml",
        "panels/calendar/EventForm.qml",
        "panels/calendar/EventCard.qml",
        "panels/calendar/RecurringDeleteChoice.qml",
        "panels/calendar/MonthGrid.qml",
        "panels/calendar/MonthDays.qml",
        "components/SwipeGesture.qml",
        "components/NotificationCard.qml",
        "components/notification/NotificationHeader.qml",
        "components/notification/NotificationPicture.qml",
        "components/notification/NotificationProgress.qml",
        "components/notification/NotificationSwipe.qml",
        "components/notification/NotificationBody.qml",
        "components/RoundedImage.qml",
        "hud/StartupWarning.qml",
        "hud/SafeModeBanner.qml",
        "panels/widget_settings/NotificationsWidgetSettings.qml",
        "widgets/NotificationsWidget.qml",
        "components/NotificationReply.qml",
        "components/CodeChips.qml",
        "panels/calendar/EventColorRow.qml",
        "panels/calendar/RecurrenceEditor.qml",
        "components/Checkbox.qml",
        "panels/calendar/TimeField.qml",
        "panels/calendar/DateField.qml",
        "panels/calendar/FieldSegment.qml",
        "panels/MusicPanel.qml",
        "panels/music/VisualizerCanvas.qml",
        "panels/music/CoverArt.qml",
        "panels/music/PanelVisualizer.qml",
        "panels/music/PlayerList.qml",
        "panels/music/PlayerRow.qml",
        "panels/music/PlayerView.qml",
        "panels/music/PlayerCarousel.qml",
        "panels/NetworkPanel.qml",
        "panels/network/HiddenNetworkRow.qml",
        "panels/network/HotspotRow.qml",
        "panels/network/WifiNetworkList.qml",
        "panels/network/LinkInfo.qml",
        "panels/network/SignalBars.qml",
        "panels/network/VpnSection.qml",
        "panels/network/WifiNetworkRow.qml",
        "panels/Popup.qml",
        "panels/HardwareSourceList.qml",
        "panels/HardwarePanel.qml",
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
        "panels/settings/CurveGraph.qml",
        "panels/settings/CurvePreview.qml",
        "panels/settings/SettingsPicker.qml",
        "panels/settings/SettingsPageList.qml",
        "panels/settings/WindowTab.qml",
        "panels/settings/WidgetsShapeSettings.qml",
        "panels/settings/PopupsShapeSettings.qml",
        "panels/settings/ControlsShapeSettings.qml",
        "panels/settings/NotificationsShapeSettings.qml",
        "panels/settings/OtherShapeSettings.qml",
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
        _notificationsPage();
    }

    // The notifications page: the toast queues' rows after the column's size, in order, and
    // greyed out with toasts off; the resident hide's info icon carries the schema's text
    function _notificationsPage() {
        const component = Qt.createComponent(Qt.resolvedUrl("../panels/settings/NotificationsSettings.qml"));
        const page = component.createObject(null, { editIndex: 0 });
        if (page === null)
            return fail("the notifications page builds: " + component.errorString().trim());
        const editors = () => Array.from(page.children).filter(child => typeof child.key === "string" && child.entry !== undefined);
        const editorOf = key => editors().find(editor => editor.key === key);
        const queueKeys = ["notifications.criticalToastLimit", "notifications.stayingToastLimit",
                           "notifications.movableToasts", "notifications.residentHide"];
        try {
            const keys = editors().map(editor => editor.key);
            const after = keys.indexOf("notifications.toastColumnSize");
            assertEqual(JSON.stringify(keys.slice(after + 1, after + 5)), JSON.stringify(queueKeys),
                        "the two limits, moving and resident hide follow the column's size");
            assertEqual(queueKeys.map(key => editorOf(key)?.entry?.label).join(" | "),
                        "Critical toasts shown, at most | Toasts that stay, at most | Move toasts by dragging | Resident notification hide",
                        "with their labels");
            assertEqual(JSON.stringify([editorOf(queueKeys[0]).entry.min, editorOf(queueKeys[0]).entry.max,
                                        editorOf(queueKeys[1]).entry.min, editorOf(queueKeys[1]).entry.max]), "[1,3,1,5]",
                        "critical 1 to 3, staying 1 to 5");

            _globalsPin.use({ "notifications.toasts": true });
            assert(queueKeys.every(key => editorOf(key).available), "available with toasts on");
            _globalsPin.use({ "notifications.toasts": false });
            assert(queueKeys.every(key => !editorOf(key).available), "greyed out with toasts off");

            const infoOf = editor => _find(editor, item => item.objectName === "info");
            const residentInfo = infoOf(editorOf("notifications.residentHide"));
            assert(residentInfo !== null && residentInfo.visible, "the resident hide has an info icon");
            const tip = residentInfo === null ? null : _find(residentInfo, item => item.objectName === "infoTip", true);
            assert(tip !== null && tip.text === SettingsSchema.entry("notifications.residentHide").info && /resident/i.test(tip.text),
                   "its tooltip says what resident means");
            const infoArea = residentInfo === null ? null : _find(residentInfo, item => item.objectName === "infoArea");
            assert(infoArea !== null && infoArea.lit !== undefined && tip.shown === infoArea.lit,
                   "the tip follows the icon's pointer area (lit: a tap shows it too)");
            assert(!infoOf(editorOf("notifications.movableToasts")).visible, "a row without info shows no icon");
        } finally {
            _globalsPin.restore();
            page.destroy();
        }
    }

    // The first item under `item` that `matches`; `withResources` also looks at its
    // non-visual children (a HoverTip moves its visual parent to the window)
    function _find(item, matches, withResources) {
        const children = Array.from(item.children ?? []).concat(withResources ? Array.from(item.resources ?? []) : []);
        for (const child of children) {
            if (matches(child))
                return child;
            const found = _find(child, matches, withResources);
            if (found !== null)
                return found;
        }
        return null;
    }
}
