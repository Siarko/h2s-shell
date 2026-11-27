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
        "components/Notice.qml",
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
        "panels/settings/PamRuleList.qml",
        "panels/settings/PamRulesSection.qml",
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
        _networkConnectivity();
        _themeDelete();
        _editorStore();
    }

    // The Themes page after a delete: a failed one says why on the page and keeps the theme
    // picked; a done one picks the active theme; another theme's outcome changes nothing
    function _themeDelete() {
        const component = Qt.createComponent(Qt.resolvedUrl("../panels/settings/ThemesSettings.qml"));
        const page = component.createObject(_stage, { themeName: "stand-in" });
        if (page === null)
            return fail("the themes page builds: " + component.errorString().trim());
        const picked = [];
        page.themePicked.connect(name => picked.push(name));
        const problem = () => _find(page, item => item.text !== undefined && String(item.text).startsWith("Not deleted"));
        try {
            assertEqual(problem(), null, "no problem shown at first");
            ThemeFiles.themeDeleteFailed("another", "x");
            ThemeFiles.themeDeleted("another");
            assertEqual(problem(), null, "another theme's outcome: nothing said");
            assertEqual(picked.length, 0, "… nothing picked");
            ThemeFiles.themeDeleteFailed("stand-in", "its file could not be kept: theme-backups is a link: nothing kept");
            assertEqual(problem()?.text, "Not deleted: its file could not be kept: theme-backups is a link: nothing kept", "a failed delete: said on the page");
            assertEqual(problem()?.textFormat, Text.PlainText, "… as plain text");
            assertEqual(picked.length, 0, "… the theme stays picked");
            ThemeFiles.themeDeleted("stand-in");
            assertEqual(picked.join(","), "", "a done delete: the active theme picked");
            assertEqual(picked.length, 1, "… once");
            page.themeName = "other";
            assertEqual(problem(), null, "another theme picked: the problem gone");
        } finally {
            page.destroy();
        }
    }

    // A setting's editor on a stand-in store (its `store`, a mockup's seam): what it shows
    // comes from the store, what it writes goes there, the shell's profiles untouched
    function _editorStore() {
        const writes = [];
        const store = {
            profiles: [{ name: "Base", set: {} }, { name: "Work", set: {} }],
            effectiveGlobals: {},
            inheritedValue: (index, key) => key === "media.visualizerStyle" ? "bars" : undefined,
            inheritedFrom: (index, key) => key === "media.visualizerStyle" ? "Base" : "",
            setBy: key => "",
            writeSetting: (index, key, value) => writes.push(["write", index, key, value]),
            clearOverride: (index, key) => writes.push(["clear", index, key]),
            pinGlobal: key => writes.push(["pin", key]),
            unpinGlobal: key => writes.push(["unpin", key])
        };
        const profilesBefore = Config.profiles;
        const globalsBefore = Config.globals;
        const component = Qt.createComponent(Qt.resolvedUrl("../panels/settings/SchemaSettingEditor.qml"));
        const editor = component.createObject(_stage, { key: "media.visualizerStyle", editIndex: 1, store: store });
        if (editor === null)
            return fail("the editor builds on a stand-in store: " + component.errorString().trim());
        try {
            assertEqual(JSON.stringify([editor.shownValue, editor.inherits, editor.inheritedFrom]), JSON.stringify(["bars", true, "Base"]),
                        "the value and where it comes from are the store's");
            assert(_find(editor, item => item.text === "inherited from Base") !== null, "… said beside the control");
            editor.edited("dots");
            assertEqual(JSON.stringify(writes), JSON.stringify([["write", 1, "media.visualizerStyle", "dots"]]), "an edit is written to the store, at the edited profile");
            editor.reset();
            assertEqual(JSON.stringify(writes.slice(1)), JSON.stringify([["clear", 1, "media.visualizerStyle"]]), "the reset drops the edited profile's value in the store");
            const pinArea = _find(editor, item => item.objectName === "pinArea");
            assert(pinArea !== null, "the pin's area");
            pinArea.clicked(null);
            assertEqual(JSON.stringify(writes.slice(2)), JSON.stringify([["pin", "media.visualizerStyle"]]), "the pin pins it as global in the store");
            store.effectiveGlobals = { "media.visualizerStyle": "dots" };
            editor.store = Object.assign({}, store);
            assertEqual(JSON.stringify([editor.global, editor.shownValue]), JSON.stringify([true, "dots"]), "pinned in the store: global, at the store's global value");
            pinArea.clicked(null);
            assertEqual(JSON.stringify(writes.slice(3)), JSON.stringify([["unpin", "media.visualizerStyle"]]), "the pin then unpins it in the store");
            assertEqual(JSON.stringify([Config.profiles, Config.globals]), JSON.stringify([profilesBefore, globalsBefore]), "the shell's profiles left as they were");
        } finally {
            editor.destroy();
        }
    }

    // The connectivity check's address on System → Network → Overview, with the distribution's
    // answers handed to the page (Arch's, NixOS's capability): the buttons bound to
    // ConnectivityRules.offer's labels and effects. Nothing is clicked here (it would ask for
    // the password for real): IntegrationChangeTest runs the change on a stand-in
    function _networkConnectivity() {
        const component = Qt.createComponent(Qt.resolvedUrl("../panels/settings/NetworkOverviewSettings.qml"));
        const page = component.createObject(_stage, {});
        if (page === null)
            return fail("the network overview builds: " + component.errorString().trim());
        const named = name => _find(page, item => item.objectName === name);
        const kind = ConnectivityRules.kind;
        const absent = { state: "absent", text: null, sha256: "absent", ours: false };
        const read = extra => Object.assign({ state: "default", value: null, from: "", elsewhere: "", file: absent, afterOwn: false }, extra ?? {});
        const address = "http://a.example/check";
        try {
            const field = _find(page, item => item.placeholder !== undefined && String(item.placeholder).startsWith("Not set up"));
            assert(field !== null, "the address's field");
            page.uriCurrent = "";
            field.text = address;
            page.uriCapability = IntegrationRules.capability({ [kind]: { mode: "apply", undo: true, inForce: true } }, kind);
            page.uriInForce = read();
            page.uriBusy = "";
            page.uriUndoable = false;
            assert(named("connectivitySave").visible && named("connectivitySave").label === "Save" && named("connectivitySave").available, "Arch: Save");
            assert(!named("connectivitySaveAsking").visible && !named("connectivityCopy").visible && !named("connectivityUndo").visible, "… alone");
            assertEqual(named("connectivityHint").text, "The address it fetches now and then; saved in " + EtcFilesRules.files[kind] + ".", "… the line under it");
            page.uriUndoable = true;
            assert(named("connectivityUndo").visible && named("connectivityUndo").available, "after a change: Undo");
            const main = "/etc/NetworkManager/NetworkManager.conf";
            page.uriInForce = read({ state: "set", value: "http://mine/", from: main, elsewhere: main });
            const asking = named("connectivitySaveAsking");
            assert(asking.visible && !named("connectivitySave").visible && asking.label === "Save" && asking.confirmLabel === "Use the shell's value instead?",
                   "set in NetworkManager.conf: Save asks first");
            assertEqual(named("connectivityHint").text, "The address it fetches now and then; saved in " + EtcFilesRules.files[kind] + ". Set in " + main + ": http://mine/.",
                        "… named with its value");
            asking.asking = true;
            field.text = address + "2";
            assert(!asking.asking, "… the question dropped when the address is another");
            page.uriInForce = read({ state: "set", value: "http://mine/", from: "/etc/NetworkManager/conf.d/99.conf", elsewhere: "/etc/NetworkManager/conf.d/99.conf", afterOwn: true });
            assert(!named("connectivitySave").visible && !asking.visible, "set in a file read after the shell's: no Save");
            page.uriCapability = IntegrationRules.capability({ [kind]: { mode: "copy", inForce: true, anyway: true, option: ConnectivityRules.nixosOption } }, kind);
            page.uriInForce = read();
            assert(!named("connectivitySave").visible && named("connectivityCopy").visible && named("connectivityCopy").label === "Copy for configuration.nix",
                   "NixOS: the line to copy");
            assert(named("connectivityAnyway").visible && named("connectivityAnyway").available, "… and Write anyway");
            assertEqual(named("connectivityHint").text, "The address it fetches now and then.", "… the line under it");
        } finally {
            page.destroy();
        }
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

            // A number stored outside its range: the control shows the value in use, with a note
            const critical = editorOf(queueKeys[0]);
            const noteOf = editor => _find(editor, item => item.objectName === "rangeNote", true);
            assert(noteOf(critical) !== null && !noteOf(critical).visible, "a value within its range: no note");
            _globalsPin.use({ "notifications.criticalToastLimit": 9 });
            assertEqual(critical.shownValue, 3, "stored above the maximum: shown at the maximum");
            assertEqual(noteOf(critical).visible ? noteOf(critical).text : "",
                        "Set to 9 in the config file, above the maximum 3: 3 is used", "… with a note saying what the file holds");
            assertEqual(JSON.parse(Config.globals)["notifications.criticalToastLimit"], 9, "… the stored value left as it was");
            // Focus passing through the field writes nothing; typing, or Return, writes
            const field = _find(critical, item => item.typed !== undefined && item.input !== undefined, true);
            assert(field !== null, "the number's field");
            field.editingFinished();
            assertEqual(JSON.parse(Config.globals)["notifications.criticalToastLimit"], 9, "focus out without typing: the config left as it was");
            field.accepted();
            field.editingFinished();
            assertEqual(JSON.parse(Config.globals)["notifications.criticalToastLimit"], 3, "Return on the value in use: written");
            _globalsPin.use({ "notifications.criticalToastLimit": 9 });
            field.text = "2";
            field.textEdited();
            field.editingFinished();
            assertEqual(JSON.parse(Config.globals)["notifications.criticalToastLimit"], 2, "a number typed: written");
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
        "lockscreen.perMonitor": false, "lockscreen.monitorIdle": {},
        "lockscreen.commandEntries": [{ id: "dark", moment: "dark", monitors: null, go: "", back: "" }],
        "lockscreen.notificationsOnScreensaver": true, "lockscreen.notificationsOnLock": true,
        "lockscreen.screensaverTimeout": 300, "lockscreen.screenOffTimeout": 900, "lockscreen.lockAfter": 1200,
        "lockscreen.sleepEnabled": false, "lockscreen.sleepTimeout": 1800, "lockscreen.lockOnSleep": false,
        "lockscreen.hibernateEnabled": false, "lockscreen.hibernateTimeout": 7200
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
            assertEqual(titles.join(" | "), "Screensaver | Lock screen | Sleep | Hibernate | Keeping the screen on | Commands",
                        "When away: the sections in the order things happen, then the rest");
            const timeline = named("awayTimeline");
            // Times outside their range shown as the shell uses them
            _away({ "lockscreen.screensaverEnabled": true, "lockscreen.screensaverTimeout": 1 });
            assertEqual(page._config.saverAfter, 5, "a screensaver time stored below its minimum: the timeline has the minimum");
            _away({ "lockscreen.screensaverEnabled": true, "lockscreen.screensaverTimeout": "soon" });
            assertEqual(page._config.saverAfter, SettingsSchema.entry("lockscreen.screensaverTimeout").default, "… not a number: the default");
            _away({});
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
            const firstEntry = () => _find(page, item => item.objectName === "commandEntry" && item.number === 1);
            assert(firstEntry() !== null && firstEntry().moment.greyed && firstEntry().moment.text === "No screen goes dark",
                   "no screen goes dark: the default entry stays, its moment greyed");

            // Set up: the screensaver, the screen-off, the lock
            _away({ "lockscreen.screensaverEnabled": true, "lockscreen.screenOffEnabled": true, "lockscreen.lockscreenEnabled": true,
                    "lockscreen.commandEntries": [{ id: "dark", moment: "dark", monitors: null, go: "pause", back: "play" }] });
            assert(named("screensaverTimes").open && named("screenOffTimes").open, "set up: the stages' times open");
            assert(named("screensaverLook").enabled && named("lockTimes").enabled, "… the look and the lock's time active");
            assertEqual(firstEntry().moment.text, "Every screen dark (5 min)", "… the commands' entry at the first screen dark");
            assertEqual(timeline.implicitHeight, offHeight, "… the timeline as tall as with everything off");
            const labels = () => timeline.labels.map(label => label.text + "@" + label.row).join(" ");
            assertEqual(labels(), "5 min@0 \u25B81 5 min@1 15 min@0 Lock 20 min@0", "… its labels, a colliding one below");
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

            _whenAwayCommands(page, named, timeline);
            _whenAwaySleep(page, named, editorIn, timeline);
            _whenAwayHibernate(page, named, editorIn, timeline);

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

    // The Commands section: the list, its marks on the timeline, adding, editing, removing
    function _whenAwayCommands(page, named, timeline) {
        const cards = () => _children(page, item => item.objectName === "commandEntry").sort((first, second) => first.number - second.number);
        const kept = () => Profiles.effectiveGlobals["lockscreen.commandEntries"];
        _away({ "lockscreen.screensaverEnabled": true, "lockscreen.lockscreenEnabled": true,
                "lockscreen.commandEntries": [{ id: "dark", moment: "dark", monitors: null, go: "playerctl pause", back: "playerctl play" },
                                              { id: "away", moment: "lock", monitors: null, go: "status away", back: "status here" },
                                              { id: "nap", moment: "sleep", monitors: null, go: "", back: "" }] });
        assertEqual(cards().map(card => card.moment.text).join(" | "), "Every screen dark (5 min) | Locked (20 min, or by hand) | Before any sleep",
                    "the list: each entry's moment with its time");
        assertEqual(_find(cards()[0], item => item.objectName === "commandLine").text, "playerctl pause   /   back: playerctl play",
                    "… its two commands on its line");
        assertEqual(_find(cards()[2], item => item.objectName === "commandLine").text, "No commands yet", "… an entry without commands says so");
        const labels = () => timeline.labels.map(label => label.text).join(" | ");
        assertEqual(labels(), "5 min | \u25B81 5 min | Lock 20 min | \u25B82 20 min", "the timeline: a mark for each entry with a command");
        assertEqual(_children(timeline, item => item.objectName === "timelineCommand").length, 2, "… a line at each of their moments");

        // Greyed: its moment can no longer come; the entry stays
        _away({ "lockscreen.lockscreenEnabled": true, "lockscreen.commandEntries": [{ id: "dark", moment: "dark", monitors: null, go: "x", back: "" }] });
        assert(cards().length === 1 && cards()[0].moment.greyed, "no screen goes dark: the entry stays, its moment greyed");
        assertEqual(_children(timeline, item => item.objectName === "timelineCommand").length, 0, "… and no mark on the timeline");

        // Adding: a "Locked" entry at the end, open for editing
        _away({ "lockscreen.screensaverEnabled": true, "lockscreen.commandEntries": [{ id: "dark", moment: "dark", monitors: null, go: "x", back: "" }] });
        named("commandAdd").clicked();
        assertEqual(kept().map(entry => entry.moment).join(" "), "dark lock", "\"Add commands\": a Locked entry written at the end");
        const added = () => cards()[1];
        assert(added() !== undefined && added().editing && _find(added(), item => item.objectName === "commandEditor").open, "… open for editing");
        assertEqual(added().moment.text, "Locked (by hand)", "… locked by hand: the idle lock is off");
        _find(added(), item => item.objectName === "commandGo").saved("notify-send away");
        assertEqual(kept()[1].go, "notify-send away", "a command written into the entry");
        const choice = _children(added(), item => item.objectName === "commandMomentChoice").find(pill => pill.label === "Before sleep");
        choice.clicked();
        assertEqual(kept()[1].moment, "sleep", "a moment picked");
        assertEqual(kept()[1].go, "notify-send away", "… its commands kept");
        _find(added(), item => item.objectName === "commandEdit").clicked();
        assert(!added().editing, "Done: the editor shut");

        // The chips: the monitors it waits for
        if (Idle.monitors.length > 0) {
            const first = cards()[0];
            _find(first, item => item.objectName === "commandEdit").clicked();
            const chips = _children(first, item => item.objectName === "commandChip");
            assertEqual(chips.length, Idle.monitors.length, "editing a dark entry: a chip per connected monitor");
            assert(chips.every(chip => chip.picked), "… every screen dark: each one that goes dark ticked");
            if (Idle.monitors.length > 1) {
                chips[0].clicked();
                assertEqual(JSON.stringify(kept()[0].monitors), JSON.stringify(Idle.monitors.slice(1).map(monitor => monitor.id)),
                            "a chip unticked: the entry names the others");
                for (const chip of chips.slice(1))
                    chip.clicked();
                assertEqual(JSON.stringify(kept()[0].monitors), JSON.stringify([Idle.monitors[Idle.monitors.length - 1].id]),
                            "every chip unticked in turn: the last one stays ticked");
            } else {
                chips[0].clicked();
                assertEqual(kept()[0].monitors, null, "the only monitor's chip: not unticked, the entry keeps its moment");
            }
            assert(!cards()[0].moment.greyed, "… never waiting for nothing");
        } else {
            console.warn("no monitors in this run: the chips not checked");
        }

        // Removing
        _find(cards()[1], item => item.objectName === "commandRemove").confirmed();
        assertEqual(kept().map(entry => entry.id).join(" "), "dark", "Remove: the entry dropped");
        assert(page.setCommandEntry("dark", { id: "dark", moment: "nope" }) === false && kept().length === 1, "an entry not understood: nothing written");
    }

    // The Sleep section and the sleep on the timeline, with logind's answers handed to the page
    function _whenAwaySleep(page, named, editorIn, timeline) {
        const caption = () => _find(timeline, item => item.objectName === "timelineCaption").text;
        const sleepSwitch = editorIn(named("sleepSection").frame, "lockscreen.sleepEnabled");
        assert(sleepSwitch !== null, "the sleep's switch on its section's title line");
        _away({});
        page.sleepSupport = { canSuspend: "challenge", idleAction: null };
        assert(!sleepSwitch.enabled, "CanSuspend challenge: the switch greyed");
        assertEqual(named("sleepCaption").text, "Not available here: the system asks for a password to sleep.", "… and why");
        _away({ "lockscreen.sleepEnabled": true });
        assert(!named("sleepTimes").open && !named("timelineSleep").visible, "… switched on all the same: no time, nothing on the timeline");
        page.sleepSupport = { canSuspend: "yes", idleAction: { action: "ignore", after: 0 } };
        _away({});
        assert(sleepSwitch.enabled, "CanSuspend yes: the switch active");
        assertEqual(named("sleepCaption").text, "The computer does not sleep by itself when idle.", "… off: said so");
        assert(!named("sleepTimes").open && !named("systemSleeps").visible, "… its time shut; logind ignoring idle: no warning");

        _away({ "lockscreen.sleepEnabled": true, "lockscreen.lockscreenEnabled": true, "lockscreen.screensaverEnabled": true });
        assert(named("sleepTimes").open, "sleep on: its time open");
        assertEqual(named("sleepCaption").text, "The computer sleeps when nobody has used it for this long.", "… the line under the title");
        assertEqual(named("sleepLockLine").text, "Already locked by then (lock at 20 min).", "… the lock at 20 min comes first");
        const labels = () => timeline.labels.map(label => label.text).join(" | ");
        assertEqual(labels(), "5 min | Lock 20 min | Sleep 30 min", "the timeline: the sleep's mark");
        assert(named("timelineSleep").visible && !named("timelineBreak").visible, "… its line across the lanes; no break at 30 min");
        assertEqual(caption(), "Locks at 20 min. Sleeps at 30 min.", "… the line under it");
        _away({ "lockscreen.sleepEnabled": true, "lockscreen.lockscreenEnabled": true, "lockscreen.lockAfter": 3600 });
        assertEqual(named("sleepLockLine").text, "Sleeps unlocked: \"Lock before the computer sleeps\" is off.",
                    "the lock later than the sleep: said in advance that it sleeps unlocked");
        _away({ "lockscreen.sleepEnabled": true, "lockscreen.lockOnSleep": true });
        assertEqual(named("sleepLockLine").text, "Locks first (\"Lock before the computer sleeps\").", "lock before sleep on: it locks first");
        _away({ "lockscreen.sleepEnabled": true, "lockscreen.sleepTimeout": 7200, "lockscreen.lockscreenEnabled": true, "lockscreen.lockAfter": 900 });
        assert(named("timelineBreak").visible, "sleep at 2 h after a lock at 15 min: after a break");
        assert(timeline.xOf(900) > timeline.trackWidth * 0.5, "… the minutes keep their room (the lock past the middle)");

        page.sleepSupport = { canSuspend: "yes", idleAction: { action: "suspend", after: 1800 } };
        assert(named("systemSleeps").visible && /^The system already puts the computer to sleep after 30 min/.test(named("systemSleeps").text),
               "logind suspending by itself: the warning");
        page.sleepBlockers = [{ who: "borg", why: "Backup" }];
        assertEqual(caption(), "Paused: borg blocks sleep (Backup).", "logind's sleep block: the timeline's line says who");
        page.sleepBlockers = [];
        _away({ "lockscreen.perMonitor": true });
        assert(/Lock, sleep and hibernation are one for all\./.test(editorIn(page, "lockscreen.perMonitor").hint),
               "per monitor: the lock, sleep and hibernation one for all");
        assert(page.showSection("sleep"), "the sleep's section shown on request");
        page.sleepSupport = Qt.binding(() => Idle.sleepSupport);
        page.sleepBlockers = Qt.binding(() => Idle.sleepBlockers);
    }

    // The Hibernate section and the hibernation on the timeline, with logind's answers and
    // what was read handed to the page, and the distribution's answers for the delay (Arch's,
    // NixOS's, generic's capability). The Apply is never clicked here (it would ask for the
    // password for real): IntegrationChangeTest runs it on a stand-in
    function _whenAwayHibernate(page, named, editorIn, timeline) {
        const caption = () => _find(timeline, item => item.objectName === "timelineCaption").text;
        const labels = () => timeline.labels.map(label => label.text).join(" | ");
        const hibernateSwitch = editorIn(named("hibernateSection").frame, "lockscreen.hibernateEnabled");
        assert(hibernateSwitch !== null, "the hibernation's switch on its section's title line");
        const header = "Filename Type Size Used Priority\n";
        const facts = (extra, hibernation) => Object.assign({
            canSuspend: "yes", canHibernate: "yes", canSuspendThenHibernate: "yes", idleAction: { action: "ignore", after: 0 },
            hibernation: Object.assign({ swaps: HibernateRules.swaps(header + "/swapfile file 33554428 0 -2\n"), memoryInUse: 8000000,
                                         lockdown: "none", resume: true, delay: { state: "set", seconds: 7200 } }, hibernation ?? {})
        }, extra);
        page.sleepSupport = facts({ canHibernate: "na" }, { swaps: HibernateRules.swaps(header + "/dev/zram0 partition 4194300 0 100\n") });
        _away({ "lockscreen.hibernateEnabled": true, "lockscreen.lockscreenEnabled": true });
        assert(!hibernateSwitch.enabled, "CanHibernate na: the switch greyed");
        assertEqual(named("hibernateCaption").text,
                    "Not available here: no swap space to save the session to (only zram, which is lost at power-off).", "… and why: only zram");
        assert(!named("hibernateTimes").open && !named("timelineHibernate").visible, "… switched on all the same: no time, nothing on the timeline");

        page.sleepSupport = facts({});
        _away({ "lockscreen.lockscreenEnabled": true, "lockscreen.screensaverEnabled": true });
        assert(hibernateSwitch.enabled && !named("hibernateTimes").open, "CanHibernate yes, off: the switch active, its time shut");
        assertEqual(named("hibernateCaption").text, "Saves the session to disk and powers off, this long after the lock.", "… what it would do");
        _away({ "lockscreen.hibernateEnabled": true, "lockscreen.lockscreenEnabled": true, "lockscreen.screensaverEnabled": true });
        assert(named("hibernateTimes").open, "on: its time open");
        assertEqual(named("hibernateTimeout").label, "after the lock", "sleep off, the lock at 20 min after the screensaver at 5: \"after the lock\"");
        assertEqual(named("hibernateLine").text, "Hibernates 2 h after the lock (2 h 20 min after your last input).", "… the line under the times");
        assert(!page._delayDiffers, "… no system delay to compare with (sleep off: the shell counts)");
        assertEqual(labels(), "5 min | Lock 20 min | Hibernate 2 h 20 min", "the timeline: the hibernation's mark");
        assert(named("timelineHibernate").visible && named("timelineBreak").visible, "… its line across the lanes, after a break");
        assertEqual(caption(), "Locks at 20 min. Hibernates 2 h after the lock.", "… the line under it");
        _away({ "lockscreen.hibernateEnabled": true, "lockscreen.lockscreenEnabled": true, "lockscreen.screensaverEnabled": true,
                "lockscreen.screensaverTimeout": 1800 });
        assertEqual(named("hibernateTimeout").label, "after the screensaver", "the screensaver at 30 min, later than the lock: \"after the screensaver\"");
        assertEqual(named("hibernateLine").text, "Hibernates 2 h after the screensaver (2 h 30 min after your last input).", "… its line");
        _away({ "lockscreen.hibernateEnabled": true });
        assertEqual(named("hibernateTimeout").label, "after your last input", "neither: \"after your last input\"");
        assertEqual(named("hibernateLine").text, "Hibernates 2 h after your last input.", "… said once");

        // Sleep on: the system's delay, compared; Apply, or the NixOS option
        _away({ "lockscreen.hibernateEnabled": true, "lockscreen.sleepEnabled": true, "lockscreen.hibernateTimeout": 10800 });
        assertEqual(named("hibernateTimeout").label, "after sleeping for", "sleep on: \"after sleeping for\"");
        assertEqual(named("hibernateCaption").text,
                    "Saves the session to disk and powers off, after the computer has slept this long \u2014 it wakes briefly to do it.", "… the caption");
        assertEqual(page._hibernate.after, 10800, "… the pills keep the 3 h picked");
        assertEqual(named("hibernateLine").text, "Hibernates 2 h after sleeping (2 h 30 min after your last input).",
                    "… the line under them: what will happen, the system's 2 h, until Apply");
        // (`visible` of what a Reveal holds follows its slide, which a synchronous suite never sees)
        assert(page._delayDiffers, "3 h picked, the system's 2 h: said");
        const kind = "sleep.hibernateDelay";
        const capabilityOf = table => IntegrationRules.capability(table, kind);
        const absent = { state: "absent", text: null, sha256: "absent", ours: false };
        const inForce = extra => Object.assign({ state: "set", value: 7200, from: "/etc/systemd/sleep.conf", elsewhere: "", file: absent, afterOwn: false }, extra ?? {});
        page.delayCapability = capabilityOf({ [kind]: { mode: "apply", undo: true, inForce: true } });
        page.delayInForce = inForce();
        page.delayBusy = "";
        page.delayUndoable = false;
        assertEqual(named("hibernateDelayLine").text, "Picked 3 h; the system now hibernates after 2 h. Apply to change it.",
                    "… the picked time takes effect after Apply");
        const apply = named("hibernateApply");
        const replace = named("hibernateReplace");
        const undo = named("hibernateUndo");
        assert(page._delayOffer.apply.button === "plain" && apply.label === "Apply" && apply.kind === "save" && apply.available,
               "… with Apply");
        assertEqual(JSON.stringify(page._delayOffer.apply.request), JSON.stringify({ seconds: 10800, current: absent, replace: false }), "… its effect");
        assertEqual(labels(), "Sleep 30 min | Hibernate 2 h 30 min", "the timeline: the sleep, then the hibernation the system will make");
        assertEqual(caption(), "No lock when idle. Sleeps at 30 min, hibernates 2 h later.", "… its line");
        page.delayBusy = "apply";
        assert(apply.label === "Applying\u2026" && !apply.available, "applying: said, not clickable");
        page.delayBusy = "";
        page.delayUndoable = true;
        assert(page._delayOffer.undo.shown && undo.label === "Undo" && undo.available, "after an Apply: Undo");
        page.delayUndoable = false;
        // Set in a file read after the shell's: shown, not overridden
        page.delayInForce = inForce({ from: "/etc/systemd/sleep.conf.d/zz-tlp.conf", elsewhere: "/etc/systemd/sleep.conf.d/zz-tlp.conf", afterOwn: true });
        assertEqual(named("hibernateDelayLine").text, "Picked 3 h. Set in /etc/systemd/sleep.conf.d/zz-tlp.conf: 2 h; it is read after the shell's file.",
                    "set in a file read after the shell's: named with its value");
        assertEqual(page._delayOffer.apply.button, "none", "… and no Apply over it");
        // Set in the user's own sleep.conf, read before the shell's: warned, Apply asks
        page.delayInForce = inForce({ elsewhere: "/etc/systemd/sleep.conf" });
        assertEqual(named("hibernateDelayLine").text, "Picked 3 h. Set in /etc/systemd/sleep.conf: 2 h.", "set in sleep.conf: named with its value");
        assert(page._delayOffer.apply.button === "ask" && replace.confirmLabel === "Use the shell's value instead?" && replace.label === "Apply",
               "… Apply asks first");
        // The shell's own file changed outside it: Apply asks
        const edited = { state: "text", text: "[Sleep]\nHibernateDelaySec=1h\n", sha256: "b".repeat(64), ours: false };
        page.delayInForce = inForce({ from: EtcFilesRules.files[kind], file: edited });
        assert(page._delayOffer.apply.button === "ask" && replace.label === "Apply" && replace.confirmLabel === "Replace?" && replace.kind === "save",
               "the shell's file edited by hand: Apply asks first");
        replace.asking = true;
        page.delayInForce = inForce({ from: EtcFilesRules.files[kind], file: Object.assign({}, edited, { sha256: "c".repeat(64) }) });
        assert(!replace.asking, "… the question dropped when the file read is another");
        page.delayInForce = inForce();
        // NixOS: the option; generic: why not
        page.delayCapability = capabilityOf({ [kind]: { mode: "copy", inForce: true, option: HibernateRules.nixosOption } });
        page.delayHint = "On NixOS it is the option " + HibernateRules.nixosOption + ".";
        assertEqual(named("hibernateDelayLine").text,
                    "Picked 3 h; the system now hibernates after 2 h. On NixOS it is the option programs.h2s-shell.idle.hibernateDelay.",
                    "NixOS: the option named");
        assertEqual(page._delayOffer.apply.button, "none", "… no Apply (/etc is generated)");
        page.delayCapability = capabilityOf({});
        assertEqual(named("hibernateDelayLine").text, "Picked 3 h; the system now hibernates after 2 h. Not supported on this distribution.",
                    "generic: not supported, no Apply");
        // Kept in the system's configuration, which sets it itself: the value, Apply disabled, the mark
        page.delayCapability = capabilityOf({ [kind]: { mode: "declare", undo: true, inForce: true } });
        page.delayInForce = inForce({ from: "/srv/nixos-config", elsewhere: "/srv/nixos-config" });
        assertEqual(named("hibernateDelayLine").text, "In force: 2 h.", "declared, set by the configuration: only the value");
        assertEqual([named("hibernateTimeout").available, named("hibernateTimeoutControlled").shown, page._delayOffer.apply.button, apply.available,
                     named("hibernateControlled").shown].join(" "), "false true plain false false",
                    "… sleep on: the time (the system's delay then) disabled with the system's mark beside it, Apply disabled, one mark");
        assertEqual(named("hibernateTimeoutControlled").tip, "This setting is controlled by your system configuration", "… the mark's tooltip");
        _away({ "lockscreen.hibernateEnabled": true, "lockscreen.hibernateTimeout": 10800 });
        assertEqual([named("hibernateTimeout").available, named("hibernateTimeoutControlled").shown, named("hibernateControlled").shown, apply.available].join(" "),
                    "true false true false", "… sleep off: the time the shell's own, editable; the mark beside the disabled Apply");
        _away({ "lockscreen.hibernateEnabled": true, "lockscreen.sleepEnabled": true, "lockscreen.hibernateTimeout": 10800 });
        page.delayInForce = inForce({ from: "/srv/nixos-config/h2s-shell.json" });
        assertEqual([named("hibernateControlled").shown, named("hibernateTimeoutControlled").shown, named("hibernateTimeout").available, apply.available].join(" "),
                    "false false true true", "the shell's own in force: no mark, the time editable, Apply");
        page.delayInForce = inForce();
        page.delayCapability = IntegrationRules.unknownCapability();
        assertEqual(named("hibernateDelayLine").text, "Picked 3 h; the system now hibernates after 2 h.",
                    "the distribution not known: no Apply promised");
        page.delayCapability = capabilityOf({ [kind]: { mode: "apply", undo: true, inForce: true } });
        page.delayInForce = inForce({ state: "default", value: null, from: "" });
        page.sleepSupport = facts({}, { delay: { state: "unset" } });
        assertEqual(named("hibernateDelayLine").text, "Picked 3 h; the system's delay is not set (systemd's default). Apply to change it.",
                    "the system's delay not set: said, Apply offered");
        assert(page._delayDiffers, "… differs");
        assertEqual(labels(), "Sleep 30 min | Hibernate 3 h 30 min", "… the timeline with the picked time (the default not known)");
        page.sleepSupport = facts({});
        _away({ "lockscreen.hibernateEnabled": true, "lockscreen.sleepEnabled": true, "lockscreen.hibernateTimeout": 7200 });
        assert(!page._delayDiffers, "the same time as the system's: nothing to apply");
        page.sleepSupport = facts({ canSuspendThenHibernate: "challenge" });
        assertEqual(named("hibernateCaption").text, "Not available here: the system asks for a password to hibernate.",
                    "sleep on, CanSuspendThenHibernate challenge: not available, why");
        page.sleepSupport = facts({}, {});
        page.sleepBlockers = [{ who: "borg", why: "Backup" }];
        _away({ "lockscreen.hibernateEnabled": true });
        assertEqual(caption(), "Paused: borg blocks sleep (Backup).", "a sleep block pauses the hibernation: the timeline's line says who");
        page.sleepBlockers = [];
        assert(page.showSection("hibernate"), "the hibernation's section shown on request");
        page.sleepSupport = Qt.binding(() => Idle.sleepSupport);
        page.sleepBlockers = Qt.binding(() => Idle.sleepBlockers);
        page.delayCapability = Qt.binding(() => Idle.hibernateDelayCapability);
        page.delayInForce = Qt.binding(() => Idle.hibernateDelayInForce);
        page.delayBusy = Qt.binding(() => Idle.hibernateDelayBusy);
        page.delayUndoable = Qt.binding(() => Idle.hibernateDelayUndoable);
        page.delayHint = Qt.binding(() => Distribution.plan(kind, page._hibernate.after).preview?.hint ?? "");
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

    // Every item under `item` that `matches`
    function _children(item, matches) {
        const found = [];
        for (const child of Array.from(item.children ?? [])) {
            if (matches(child))
                found.push(child);
            found.push(..._children(child, matches));
        }
        return found;
    }
}
