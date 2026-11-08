import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons
import qs.panels.settings

FloatingWindow {
    id: root
    title: "Settings"

    Connections {
        target: Config
        function onSaved() {
            Notifier.send("Settings saved", {
                urgency: "low",
                category: "x-qs-shell"
            });
        }
    }
    implicitWidth: Theme.scaled(520)
    implicitHeight: Theme.scaled(640)
    minimumSize: Qt.size(400, 300)
    visible: false

    // The pages, in the sidebar's order. Each has an id — how the window, the rest of the
    // shell (Shell.openSettings) and IPC (openPage) name it — and a label, free to change
    // or repeat across tabs. The window has two tabs: Behaviour, whose pages edit a
    // profile, and Appearance, whose pages edit a theme (docs/plans/themes.md, stage 6;
    // TODO 10.10). `draftGroups`: the theme groups a page edits through a draft, for its ✎;
    // `separatorBefore`: a line above it in the sidebar.
    readonly property var pages: [
        // Profiles manages the profiles; the pages below the line edit the picked one
        { id: "profiles", label: "Profiles", tab: "behaviour", component: profilesComp },
        { id: "general", label: "General", tab: "behaviour", component: generalComp, separatorBefore: true },
        { id: "calendar", label: "Calendar", tab: "behaviour", component: calendarComp },
        { id: "media", label: "Media", tab: "behaviour", component: mediaComp },
        { id: "bar", label: "Bar", tab: "behaviour", component: barComp },
        { id: "notifications", label: "Notifications", tab: "behaviour", component: notificationsComp },
        { id: "lockscreen", label: "Lockscreen", tab: "behaviour", component: lockscreenComp },
        { id: "dictation", label: "Dictation", tab: "behaviour", component: sttComp },
        { id: "performance", label: "Performance", tab: "behaviour", component: performanceComp },
        // Themes and Curves manage the libraries; the pages below the line edit the
        // picked theme's values
        { id: "themes", label: "Themes", tab: "appearance", component: themesComp },
        { id: "curves", label: "Curves", tab: "appearance", component: curvesComp },
        { id: "colors", label: "Colors", tab: "appearance", component: colorsComp, draftGroups: ["colors"], separatorBefore: true },
        { id: "fonts", label: "Fonts", tab: "appearance", component: fontsComp, draftGroups: ["fonts"] },
        { id: "bar_appearance", label: "Bar", tab: "appearance", component: barShapeComp, draftGroups: ["bar"] },
        { id: "widgets_appearance", label: "Widgets", tab: "appearance", component: widgetsLookComp, draftGroups: ["capsule", "workspace", "tray"] },
        { id: "popups", label: "Popups", tab: "appearance", component: popupsComp, draftGroups: ["popup", "popupWidth", "row", "listItem", "dropdown", "powerMenu"] },
        { id: "controls", label: "Controls", tab: "appearance", component: controlsComp,
          draftGroups: ["button", "saveButton", "cancelButton", "deleteButton", "iconButton", "pill", "field", "checkbox", "tooltip", "border"] },
        { id: "notifications_appearance", label: "Notifications", tab: "appearance", component: notificationsLookComp,
          draftGroups: ["osdToast", "notificationCard", "osdVolume", "osdMessage"] },
        { id: "animations", label: "Animations", tab: "appearance", component: animationsComp, draftGroups: ["durations", "curves"] },
        { id: "other_appearance", label: "Other", tab: "appearance", component: otherLookComp, draftGroups: ["settings", "calendar", "lock"] }
    ]

    function _pageIndex(id) {
        return pages.findIndex(page => page.id === id);
    }

    function _pageOf(id) {
        return pages[_pageIndex(id)] ?? pages[0];
    }

    // The open page, by id
    property string selectedPage: "general"
    // Not `_page`: that is the id of the Loader showing it, which a bare name would reach
    readonly property var _currentPage: _pageOf(selectedPage)
    readonly property bool _onAppearance: _currentPage.tab === "appearance"

    // The sidebar, wide enough for its names at the theme's fonts
    readonly property int _sidebarWidth: Theme.scaled(160)

    // The page last open in each tab, to come back to
    property string _lastBehaviourPage: "general"
    property string _lastAppearancePage: "themes"
    // From the page itself: _onAppearance may not have caught up yet when this runs
    onSelectedPageChanged: {
        if (_pageOf(selectedPage).tab === "appearance")
            _lastAppearancePage = selectedPage;
        else
            _lastBehaviourPage = selectedPage;
        _openList = null;
    }

    // The theme the Appearance pages edit, by name. Entering the tab starts at the theme of
    // the profile being edited; the active theme stands in if the picked one is gone.
    property string editedTheme: ""
    readonly property string editTheme: Theme.themeExists(editedTheme) ? editedTheme : Theme.profileTheme
    // A question to throw a theme's changes away never carries over to another theme
    onEditThemeChanged: _discardAll.asking = false

    // Previewing: the theme being edited is shown on the whole shell, saved nowhere. The
    // theme picker is locked meanwhile; leaving Appearance or closing the window ends it.
    property bool previewing: false
    onVisibleChanged: if (!visible) previewing = false
    Binding {
        target: Theme
        property: "preview"
        value: root.previewing && root.visible ? root.editTheme : ""
    }
    on_OnAppearanceChanged: {
        if (_onAppearance)
            editedTheme = Theme.themeOf(editIndex);
        else
            previewing = false;
    }

    function showBehaviour() {
        selectedPage = _lastBehaviourPage;
    }

    // Opens the Appearance tab, on `theme` if given
    function showAppearance(theme) {
        selectedPage = _lastAppearancePage;
        if (theme)
            editedTheme = theme;
    }

    // The profile every page edits (docs/plans/global-profiles.md), by name so it
    // survives reordering; Full, else the first
    property string editedName: "Full"
    readonly property int editIndex: {
        const byName = Profiles.profiles.findIndex(profile => profile.name === editedName);
        return byName >= 0 ? byName : (Profiles.profiles.length > 0 ? 0 : -1);
    }

    // What a tab edits, picked from a list that opens over the page list under it: the
    // profile or the theme (SettingsPicker). One list open at a time; a click anywhere else
    // closes it.
    property Item _openList: null

    Rectangle {
        anchors.fill: parent
        color: Theme.popupBackground

        // ── Tabs: what the window edits ──────────────────────────────
        Item {
            id: _tabBar
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 44

            Text {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                text: "Settings"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMedium
                font.bold: true
                color: Theme.textPrimary
            }

            Row {
                anchors { left: parent.left; leftMargin: root._sidebarWidth + 10; verticalCenter: parent.verticalCenter }
                spacing: 4
                WindowTab {
                    label: "Behaviour"
                    picked: !root._onAppearance
                    onClicked: if (root._onAppearance) root.showBehaviour()
                }
                WindowTab {
                    label: "Appearance"
                    picked: root._onAppearance
                    onClicked: if (!root._onAppearance) root.showAppearance()
                }
            }

            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 1
                color: Theme.textDisabled
                opacity: 0.3
            }
        }

        // Unsaved changes to the theme edited, on any page: save or throw away all of them
        Rectangle {
            id: _draftBanner
            readonly property bool shown: root._onAppearance && (Theme.drafts, Theme.hasDraft(root.editTheme))
            anchors { left: parent.left; right: parent.right; top: _tabBar.bottom }
            height: shown ? 40 : 0
            visible: shown
            color: Qt.alpha(Theme.warning, 0.15)
            onShownChanged: if (!shown) _discardAll.asking = false

            RowLayout {
                anchors { fill: parent; leftMargin: 14; rightMargin: 10 }
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "✎ Unsaved changes in " + root.editTheme
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textPrimary
                }

                SmallButton {
                    label: "Save all"
                    kind: "save"
                    onClicked: Theme.saveDraft(root.editTheme)
                }

                DeleteButton {
                    id: _discardAll
                    label: "Discard all"
                    confirmLabel: "Throw away all?"
                    fontSize: Theme.fontSizeBody
                    cancelTip: "Keep the changes"
                    onConfirmed: Theme.discardDraft(root.editTheme)
                }
            }
        }

        Row {
            anchors { left: parent.left; right: parent.right; top: _draftBanner.bottom; bottom: parent.bottom }
            spacing: 0

            // ── Left sidebar (160px) ──────────────────────────────────
            Item {
                width: root._sidebarWidth
                height: parent.height

                ColumnLayout {
                    id: _sidebar
                    anchors {
                        fill: parent
                        margins: 10
                    }
                    spacing: 4

                    // Which profiles apply right now, visible from every page
                    Text {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 6
                        wrapMode: Text.WordWrap
                        text: "Active: " + (Profiles.activeProfiles.length > 0 ? Profiles.activeProfiles.join(", ") : "defaults")
                            + (Object.keys(Profiles.simulated).length > 0 ? " (simulated)" : "")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: _profileIndicator.containsMouse ? Theme.textPrimary : Theme.accent
                        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

                        MouseArea {
                            id: _profileIndicator
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectedPage = "profiles"
                        }
                    }

                    // Behaviour: the profile its pages edit, and the theme that profile uses
                    SettingsPicker {
                        visible: !root._onAppearance && Profiles.profiles.length > 0
                        open: root._openList === optionList
                        onToggleRequested: root._openList = open ? null : optionList
                        label: "Profile"
                        current: Profiles.profiles[root.editIndex]?.name ?? ""
                        options: Profiles.profiles.map(profile => profile.name)
                        marked: Profiles.activeProfiles
                        onPicked: name => {
                            root._openList = null;
                            root.editedName = name;
                        }
                    }
                    Text {
                        visible: !root._onAppearance && root.editIndex >= 0
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        readonly property string _theme: Theme.themeOf(root.editIndex)
                        text: "Uses theme " + _theme + " ↗"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: _usesThemeArea.containsMouse ? Theme.textPrimary : Theme.textMuted
                        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

                        MouseArea {
                            id: _usesThemeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showAppearance(parent._theme)
                        }
                    }

                    // Appearance: the theme its pages edit, and the profiles that use it
                    SettingsPicker {
                        visible: root._onAppearance
                        open: root._openList === optionList
                        onToggleRequested: root._openList = open ? null : optionList
                        label: "Theme"
                        current: root.editTheme
                        options: (Theme.themeNames.includes("default") ? [] : ["default"]).concat(Theme.themeNames)
                        marked: [Theme.profileTheme]
                        edited: Object.keys(Theme.drafts)
                        // The preview shows the theme picked: stop it to pick another
                        locked: root.previewing
                        onPicked: name => {
                            root._openList = null;
                            root.editedTheme = name;
                        }
                    }
                    // Under the theme: previewing it on the shell, and who uses it — one
                    // line, the whole list on hover
                    RowLayout {
                        visible: root._onAppearance
                        Layout.fillWidth: true
                        spacing: 6

                        SmallButton {
                            // Nothing to preview in the theme already in use, unless it has
                            // unsaved changes
                            available: root.previewing || root.editTheme !== Theme.profileTheme
                                || (Theme.drafts, Theme.hasDraft(root.editTheme))
                            label: root.previewing ? "Stop preview" : "Preview"
                            checked: root.previewing
                            fontSize: Theme.fontSizeSmall
                            tooltip: !available ? "This theme is already in use, with nothing unsaved"
                                : root.previewing ? "Back to the profile's theme"
                                : "Show this theme, with its unsaved changes, on the whole shell. Leaving Appearance or closing the window ends it."
                            onClicked: root.previewing = !root.previewing
                        }

                        Text {
                            id: _usersText
                            Layout.fillWidth: true
                            readonly property var _users: (Profiles.profiles, Theme.usersOf(root.editTheme))
                            readonly property string _full: root.selectedPage === "curves"
                                ? "Curves are shared by every theme"
                                : _users.length > 0 ? "Used by " + _users.join(", ") : "Not used by any profile"
                            text: root.selectedPage === "curves" ? "Shared"
                                : _users.length > 0 ? "Used by " + _users.join(", ") : "Unused"
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignRight
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.textMuted

                            MouseArea {
                                id: _usersArea
                                anchors.fill: parent
                                hoverEnabled: true
                            }

                            HoverTip {
                                target: _usersText
                                shown: _usersArea.containsMouse
                                text: _usersText._full
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        Layout.bottomMargin: 4
                        height: 1
                        color: Theme.textDisabled
                        opacity: 0.3
                    }

                    // The page list takes the height left and scrolls in it: on a small
                    // screen (the Framework 12) it did not fit, and could not be scrolled
                    Flickable {
                        id: _pageListScroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: width
                        contentHeight: _pageList.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        SettingsPageList {
                            id: _pageList
                            width: _pageListScroll.width
                            pages: root.pages
                            selectedPage: root.selectedPage
                            tab: root._onAppearance ? "appearance" : "behaviour"
                            editTheme: root.editTheme
                            onPageClicked: pageId => root.selectedPage = pageId
                        }
                    }

                    // The shell's version, with the commit when not running a release;
                    // selectable, so it can be copied into a bug report
                    TextEdit {
                        Layout.fillWidth: true
                        text: "v" + Version.display
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.WrapAnywhere
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.textDisabled
                        selectionColor: Theme.selection
                        selectedTextColor: Theme.selectedText
                    }
                }
            }

            // ── Separator ─────────────────────────────────────────────
            Rectangle {
                width: 1
                height: parent.height
                color: Theme.textDisabled
                opacity: 0.3
            }

            // ── Right content area ────────────────────────────────────
            Item {
                width: parent.width - root._sidebarWidth - 1
                height: parent.height

                // A new page fades in, rising a little
                Loader {
                    id: _page
                    anchors.fill: parent
                    transform: Translate { id: _pageShift }
                    onLoaded: _pageEnter.restart()
                    sourceComponent: root._currentPage.component
                }

                ParallelAnimation {
                    id: _pageEnter
                    NumberAnimation { target: _page; property: "opacity"; from: 0; to: 1; duration: Theme.duration("enter"); easing: Theme.curve("enter") }
                    NumberAnimation { target: _pageShift; property: "y"; from: 12; to: 0; duration: Theme.duration("enter"); easing: Theme.curve("enter") }
                }
            }
        }
        // A click anywhere takes the focus from a field (but on the field itself)
        FocusReleaser {}

        // While a picker's list is open, a press anywhere but on it closes it
        MouseArea {
            anchors.fill: parent
            visible: root._openList !== null
            onPressed: mouse => {
                const list = root._openList;
                const point = mapToItem(list, mouse.x, mouse.y);
                if (list && point.x >= 0 && point.y >= 0 && point.x < list.width && point.y < list.height)
                    mouse.accepted = false;
                else
                    root._openList = null;
            }
        }
    }

    Component { id: generalComp;       GeneralSettings       { editIndex: root.editIndex } }
    Component { id: calendarComp;      CalendarSettings      { editIndex: root.editIndex } }
    Component { id: mediaComp;         MediaSettings         { editIndex: root.editIndex } }
    Component { id: barComp;           BarSettings           { editIndex: root.editIndex } }
    Component { id: notificationsComp; NotificationsSettings { editIndex: root.editIndex } }
    Component { id: lockscreenComp;    LockscreenSettings    { editIndex: root.editIndex } }
    Component { id: sttComp;           SttSettings           { editIndex: root.editIndex } }
    Component { id: curvesComp;        CurvesSettings {} }
    Component { id: colorsComp;        ColorsSettings { themeName: root.editTheme } }
    Component { id: fontsComp;         FontsSettings { themeName: root.editTheme } }
    Component { id: barShapeComp;      BarShapeSettings { themeName: root.editTheme } }
    Component { id: animationsComp;    AnimationsSettings { themeName: root.editTheme } }
    // The theme's shapes by kind of element (themes stage 7)
    Component { id: widgetsLookComp;       WidgetsShapeSettings       { themeName: root.editTheme } }
    Component { id: popupsComp;            PopupsShapeSettings        { themeName: root.editTheme } }
    Component { id: controlsComp;          ControlsShapeSettings      { themeName: root.editTheme } }
    Component { id: notificationsLookComp; NotificationsShapeSettings { themeName: root.editTheme } }
    Component { id: otherLookComp;         OtherShapeSettings         { themeName: root.editTheme } }
    Component {
        id: themesComp
        ThemesSettings {
            themeName: root.editTheme
            onThemePicked: name => root.editedTheme = name
        }
    }
    Component {
        id: performanceComp
        PerformanceSettings { editIndex: root.editIndex }
    }
    Component {
        id: profilesComp
        ProfilesSettings {
            onEditValuesRequested: name => {
                root.editedName = name;
                root.selectedPage = "performance";
            }
        }
    }
}
