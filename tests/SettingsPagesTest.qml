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
        "panels/settings/WhenAwaySettings.qml",
        "panels/settings/AwayTimeline.qml",
        "panels/settings/MonitorTimesCard.qml",
        "components/Reveal.qml",
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
        _firstSections();
        _whenAwayPage();
    }

    // Every page with sections (SectionTitle, SettingsSection — the one look of a section): a
    // section right under the page's heading (and its hint or notices) has no line above it,
    // one after the page's own rows or cards has, as each later one. The pages' sections in
    // document order, the visible ones with a title; [page, properties, the first's line]
    property Item _stage: Item { width: 720; height: 1500 }
    readonly property var _sectionPages: [
        ["SttSettings", { editIndex: 0 }, false],
        ["CalendarSettings", { editIndex: 0 }, false], ["BarSettings", { editIndex: 0 }, false],
        ["PerformanceSettings", { editIndex: 0 }, false], ["FontsSettings", { themeName: "default" }, false],
        ["ColorsSettings", { themeName: "default" }, false], ["BarShapeSettings", { themeName: "default" }, false],
        ["WidgetsShapeSettings", { themeName: "default" }, false], ["PopupsShapeSettings", { themeName: "default" }, false],
        ["ControlsShapeSettings", { themeName: "default" }, false], ["NotificationsShapeSettings", { themeName: "default" }, false],
        ["OtherShapeSettings", { themeName: "default" }, false],
        // After the general settings' rows
        ["GeneralSettings", { editIndex: 0 }, true],
        // After the top: "Set per monitor" and the timeline, without a title of their own
        ["WhenAwaySettings", { editIndex: 0 }, true],
        // After the mode's row, or the image's
        ["WallpaperSettings", { editIndex: 0 }, true],
        // After the theme's own rows, the curve's editor
        ["ThemesSettings", { themeName: "default" }, true], ["CurvesSettings", {}, true],
        // After the roles
        ["AnimationsSettings", { themeName: "default" }, true],
        // After the summary, the Wi-Fi or wired device's card, the VPNs' cards
        ["NetworkOverviewSettings", {}, true], ["NetworkWifiSettings", {}, true], ["NetworkEthernetSettings", {}, true],
        ["NetworkVpnSettings", {}, true]]

    function _sectionsOf(item) {
        const found = [];
        for (const child of Array.from(item.children ?? [])) {
            if (!child.visible)
                continue;
            const isTitle = typeof child.divider === "boolean" && typeof child.text === "string";
            const isSection = typeof child.divider === "boolean" && child.kind === "section";
            if (isTitle && child.text !== "" || isSection && child.title !== "")
                found.push(child);
            if (!isTitle)
                found.push(..._sectionsOf(child));
        }
        return found;
    }

    function _firstSections() {
        for (const [name, properties, firstLine] of _sectionPages) {
            const component = Qt.createComponent(Qt.resolvedUrl("../panels/settings/" + name + ".qml"));
            const page = component.createObject(_stage, properties);
            if (page === null) {
                fail(name + " builds: " + component.errorString().trim());
                continue;
            }
            try {
                const sections = _sectionsOf(page);
                const lines = sections.map(section => (section.text ?? "") + (section.kind === "section" ? section.title : "") + ":" + section.divider);
                assert(sections.length > 0, name + ": sections found");
                assertEqual(sections.map((section, index) => section.divider === (index > 0 || firstLine) ? "" : lines[index]).join(""), "",
                            name + ": " + (firstLine ? "a line" : "no line") + " above its first section, a line above each later one — " + lines.join(", "));
            } finally {
                page.destroy();
            }
        }
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

    // "When away": the top above the sections, the sections in the order things happen, what
    // is dimmed and what not, the timeline's height, the per-monitor cards writing the map
    property Item _shortStage: Item { width: 720; height: 400 }
    readonly property var _awayOff: ({
        "lockscreen.screensaverEnabled": false, "lockscreen.screenOffEnabled": false, "lockscreen.lockscreenEnabled": false,
        "lockscreen.perMonitor": false, "lockscreen.monitorIdle": {}, "lockscreen.screensaverCommands": false,
        "lockscreen.notificationsOnScreensaver": true, "lockscreen.notificationsOnLock": true,
        "lockscreen.screensaverTimeout": 300, "lockscreen.screenOffTimeout": 900, "lockscreen.lockAfter": 1200
    })

    function _away(change) {
        _globalsPin.use(Object.assign({}, _awayOff, change));
    }

    function _whenAwayPage() {
        const component = Qt.createComponent(Qt.resolvedUrl("../panels/settings/WhenAwaySettings.qml"));
        const page = component.createObject(_shortStage, { editIndex: 0 });
        if (page === null)
            return fail("the When away page builds: " + component.errorString().trim());
        const named = name => _find(page, item => item.objectName === name);
        const editorIn = (item, key) => _find(item, child => child.key === key && child.entry !== undefined);
        try {
            _away({});
            const titles = _sectionsOf(page).map(section => section.title);
            assertEqual(titles.join(" | "), "Screensaver | Lock screen | Keeping the screen on | Commands",
                        "When away: the sections in the order things happen, then the rest");
            const timeline = named("awayTimeline");
            const perMonitor = editorIn(page, "lockscreen.perMonitor");
            const saverSection = named("screensaverSection");
            assert(timeline !== null && perMonitor !== null, "the top: \"Set per monitor\" and the timeline");
            const top = item => item.mapToItem(page.contentItem, 0, 0).y;
            assert(top(perMonitor) < top(timeline) && top(timeline) < top(saverSection), "… above the first section, the switch first");
            assert(editorIn(saverSection.frame, "lockscreen.screensaverEnabled") !== null, "the screensaver's switch on its section's title line");
            const lockSwitch = editorIn(named("lockSection").frame, "lockscreen.lockscreenEnabled");
            assert(lockSwitch !== null && lockSwitch.label === "Lock when idle", "the idle lock's on the lock screen's, \"Lock when idle\"");

            // Everything off: the timeline drawn, empty, one line saying so
            const offHeight = timeline.implicitHeight;
            assertEqual(_find(timeline, item => item.objectName === "timelineCaption").text, "Nothing happens when you are away.",
                        "everything off: the timeline says nothing happens");
            assert(offHeight > 0, "… drawn all the same");
            assert(!named("screensaverTimes").open && !named("screenOffTimes").open, "… the stages' times shut");
            assert(!named("screensaverLook").enabled && named("screensaverLook").visible, "… the screensaver's look dimmed, not hidden");
            assert(!named("lockTimes").enabled && named("lockTimes").visible, "lock when idle off: its time dimmed, not hidden");
            const lockSection = named("lockSection");
            for (const key of ["lockscreen.lockOnSleep", "lockscreen.lockedScreenOffTimeout", "lockscreen.notificationsOnLock"])
                assert(editorIn(lockSection, key).enabled && editorIn(lockSection, key).opacity === 1, "… " + key + " stays active: it serves every lock");
            assert(!named("commandsRow").enabled, "no screen goes dark: the commands dimmed");

            // Set up: the screensaver, the screen-off, the lock
            _away({ "lockscreen.screensaverEnabled": true, "lockscreen.screenOffEnabled": true, "lockscreen.lockscreenEnabled": true,
                    "lockscreen.screensaverCommands": true });
            assert(named("screensaverTimes").open && named("screenOffTimes").open, "set up: the stages' times open");
            assert(named("screensaverLook").enabled && named("lockTimes").enabled, "… the look and the lock's time active");
            assert(named("commandsRow").enabled && /^On, at 5 min/.test(named("commandsRow").hint), "… the commands at the first screen dark: " + named("commandsRow").hint);
            assertEqual(timeline.implicitHeight, offHeight, "… the timeline as tall as with everything off");
            const labels = () => timeline.labels.map(label => label.text + "@" + label.row).join(" ");
            assertEqual(labels(), "5 min@0 Commands 5 min@1 15 min@0 Lock 20 min@0", "… its labels, a colliding one below");
            assertEqual(_find(timeline, item => item.objectName === "timelineCaption").text.split(".")[0], "Locks at 20 min", "… the line under it: the lock");

            // The screensaver off, screens turned off: its look dimmed where the screen-off is a real one
            _away({ "lockscreen.screenOffEnabled": true });
            assertEqual(named("screensaverLook").enabled, !Idle.powerControl,
                        "screensaver off, screens off: the look dimmed with power control, used without it (" + Idle.powerControl + ")");

            // Per monitor: the cards, writing the map of the profile (here the pinned global)
            const kept = { screensaverEnabled: false, screensaverTimeout: 300, screenOffEnabled: true, screenOffTimeout: 300 };
            _away({ "lockscreen.perMonitor": true, "lockscreen.monitorIdle": { "Dell|U2419H|S1": kept } });
            assert(named("monitorCards").open, "per monitor on: the cards open");
            assert(saverSection.title === "Screensaver (all monitors)", "… the section says it is the default");
            const card = () => _find(page, item => item.objectName === "monitorCard" && item.name === "Dell U2419H");
            assert(card() !== null && !card().connected && JSON.stringify(card().own) === JSON.stringify(kept),
                   "a monitor not connected: its card, its own times");
            card()._with("screensaverEnabled", true);
            assertEqual(JSON.stringify(Profiles.effectiveGlobals["lockscreen.monitorIdle"]?.["Dell|U2419H|S1"]),
                        JSON.stringify(Object.assign({}, kept, { screensaverEnabled: true })), "a card's switch writes its entry, whole");
            assert(page.setMonitorTimes("Acer|XB1|7", { screensaverEnabled: true, screensaverTimeout: 120, screenOffEnabled: false, screenOffTimeout: 600 }),
                   "a second monitor's times written");
            assertEqual(Object.keys(Profiles.effectiveGlobals["lockscreen.monitorIdle"]).sort().join(","), "Acer|XB1|7,Dell|U2419H|S1",
                        "… the other's kept");
            _find(card(), item => item.objectName === "sameTimes").clicked();
            assertEqual(Object.keys(Profiles.effectiveGlobals["lockscreen.monitorIdle"]).join(","), "Acer|XB1|7",
                        "\"Same as all monitors\": the entry dropped");
            assert(card() === null, "… and a monitor not connected without times has no card");
            assert(!page.setMonitorTimes("Acer|XB1|7", { screensaverEnabled: true }), "times not understood: nothing written");
            const cardsBefore = _find(page, item => item.objectName === "monitorCard" && item.name === "Acer XB1");
            assert(cardsBefore !== null && cardsBefore.own.screensaverTimeout === 120, "… the entry as it was");

            // A partial entry (written by hand): shown and written whole, over the default's
            _away({ "lockscreen.perMonitor": true, "lockscreen.screensaverEnabled": true,
                    "lockscreen.monitorIdle": { "Dell|U2419H|S1": { screenOffEnabled: true, screenOffTimeout: 300 } } });
            const partial = card();
            assert(partial !== null && partial.times.screensaverEnabled === true && partial.times.screenOffTimeout === 300,
                   "a partial entry's card shows the default's screensaver and its own screen-off");
            partial._with("screenOffTimeout", 600);
            assertEqual(JSON.stringify(Profiles.effectiveGlobals["lockscreen.monitorIdle"]?.["Dell|U2419H|S1"]),
                        JSON.stringify({ screensaverEnabled: true, screensaverTimeout: 300, screenOffEnabled: true, screenOffTimeout: 600 }),
                        "… a click writes the whole entry");

            // The lock screen's section at the top on request
            const sectionTop = () => lockSection.mapToItem(page.contentItem, 0, 0).y - Theme.settings.pageMargin;
            assert(page.showSection("lock") && page.contentY > 0
                   && (Math.abs(sectionTop() - page.contentY) < 1 || page.contentY === page.contentHeight - page.height),
                   "a section shown at the top on request, below the page's margin (" + page.contentY + ", the section at " + sectionTop() + ")");
            assert(!page.showSection("nothing"), "an unknown section: nothing moves");
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
