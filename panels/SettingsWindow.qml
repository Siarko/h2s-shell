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
    implicitWidth: 520
    implicitHeight: 640
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
        { id: "popups", label: "Popups", tab: "appearance", component: popupsComp, draftGroups: ["popup", "row", "listItem", "dropdown", "powerMenu"] },
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
        _slideMark(_previousPage, selectedPage);
        _previousPage = selectedPage;
    }

    // The selected page's mark slides from the page before only when the page changes
    // within a tab: it sits at the page plus an offset that animates to nothing. Anything
    // else that moves the list (the picker above it growing, a change of tab) moves the
    // mark with it at once.
    property string _previousPage: "general"
    property real _markOffset: 0

    function _slideMark(from, to) {
        const fromItem = _categoryRepeater.itemAt(_pageIndex(from));
        const toItem = _categoryRepeater.itemAt(_pageIndex(to));
        _markSlide.stop();
        if (!fromItem || !toItem || _pageOf(from).tab !== _pageOf(to).tab) {
            _markOffset = 0;
            return;
        }
        _markOffset = fromItem.y - toItem.y;
        _markSlide.start();
    }

    NumberAnimation {
        id: _markSlide
        target: root
        property: "_markOffset"
        to: 0
        duration: Theme.duration("slide")
        easing: Theme.curve("slide")
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
    // profile or the theme. One list open at a time; a click anywhere else closes it.
    property Item _openList: null

    component Picker: ColumnLayout {
        id: _picker
        property string label
        property string current
        property var options: []
        // Options shown with a • after them: the active profiles, the theme in use; and with
        // a ✎: themes with unsaved changes
        property var marked: []
        property var edited: []
        function display(name) {
            return name + (marked.includes(name) ? " •" : "") + (edited.includes(name) ? " ✎" : "");
        }
        // Shown, but not changed, e.g. while the theme picked is previewed
        property bool locked: false
        readonly property bool open: root._openList === _optionList
        signal picked(string name)

        Layout.fillWidth: true
        spacing: 2
        // Above the page list, which the open list covers
        z: 10

        Text {
            text: _picker.label
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.textDisabled
        }

        Rectangle {
            id: _pickerButton
            Layout.fillWidth: true
            height: 28
            radius: Theme.dropdown.radius
            color: _pickerArea.containsMouse && !_picker.locked ? Theme.surfaceHover : Theme.surface
            opacity: _picker.locked ? 0.5 : 1
            border.width: Theme.border.width
            border.color: _picker.open ? Theme.accent : Theme.surfaceHoverClear
            Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

            Text {
                anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 10; right: _arrow.left; rightMargin: 4 }
                text: _picker.display(_picker.current)
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                font.bold: true
                color: Theme.textPrimary
            }
            Text {
                font.family: Theme.fontFamily
                id: _arrow
                anchors { verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: 8 }
                visible: !_picker.locked
                text: _picker.open ? "▴" : "▾"
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textSecondary
            }

            MouseArea {
                id: _pickerArea
                anchors.fill: parent
                hoverEnabled: true
                enabled: !_picker.locked
                cursorShape: Qt.PointingHandCursor
                onClicked: root._openList = _picker.open ? null : _optionList
            }

            // The options, over whatever is below; outside the layout, so opening it moves
            // nothing
            Rectangle {
                id: _optionList
                visible: _picker.open
                y: parent.height + 2
                width: parent.width
                height: _optionColumn.height + 6
                radius: Theme.dropdown.radius
                color: Theme.popupBackground
                border.width: Theme.border.width
                border.color: Theme.outline

                Column {
                    id: _optionColumn
                    x: 3
                    y: 3
                    width: parent.width - 6

                    Repeater {
                        // ScriptModel, never the bare array — see "The Repeater crash"
                        model: ScriptModel { values: _picker.options }

                        Rectangle {
                            required property string modelData
                            readonly property bool picked: modelData === _picker.current
                            width: _optionColumn.width
                            height: 24
                            radius: Theme.listItem.radius
                            color: picked ? Theme.accentTint : (_optionArea.containsMouse ? Theme.surfaceHover : Theme.surfaceHoverClear)
                            Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

                            Text {
                                anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 8; right: parent.right; rightMargin: 6 }
                                text: _picker.display(parent.modelData)
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                color: parent.picked ? Theme.textPrimary : Theme.textSecondary
                            }

                            MouseArea {
                                id: _optionArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    // The name first: closing the list does not destroy the
                                    // row, but picking may change what the list shows
                                    const name = parent.modelData;
                                    root._openList = null;
                                    _picker.picked(name);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // A tab at the top of the window
    component WindowTab: Rectangle {
        property string label
        property bool picked: false
        signal clicked

        width: _tabLabel.implicitWidth + 2 * Theme.settings.tabHorizontalPadding
        height: 28
        radius: Theme.settings.tabRadius
        color: picked ? Theme.accentSecondaryTint : (_tabArea.containsMouse ? Theme.fillSubtle : Qt.alpha(Theme.fillSubtle, 0))
        border.width: picked ? Theme.border.width : 0
        border.color: Theme.accent
        Behavior on color { ColorAnimation { duration: Theme.duration("state"); easing: Theme.curve("state") } }

        Text {
            id: _tabLabel
            anchors.centerIn: parent
            text: parent.label
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBodyLarge
            font.bold: parent.picked
            color: parent.picked ? Theme.textPrimary : Theme.textSecondary
        }

        MouseArea {
            id: _tabArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

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
                anchors { left: parent.left; leftMargin: 170; verticalCenter: parent.verticalCenter }
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
                width: 160
                height: parent.height

                // The selected page's mark, one for the whole list, so it slides from the
                // old page to the new one; drawn under the list
                Rectangle {
                    readonly property Item target: _categoryRepeater.count > root._pageIndex(root.selectedPage)
                        ? _categoryRepeater.itemAt(root._pageIndex(root.selectedPage)) : null
                    visible: target !== null
                    x: _sidebar.x + (target?.x ?? 0)
                    // The offset slides it in from the page before (root._slideMark)
                    y: _sidebar.y + (target?.y ?? 0) + root._markOffset
                    width: target?.width ?? 0
                    height: target?.height ?? 0
                    radius: Theme.settings.sidebarItemRadius
                    color: Theme.accentSecondaryTint
                    border.width: Theme.border.width
                    border.color: Theme.accent
                }

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
                    Picker {
                        visible: !root._onAppearance && Profiles.profiles.length > 0
                        label: "Profile"
                        current: Profiles.profiles[root.editIndex]?.name ?? ""
                        options: Profiles.profiles.map(profile => profile.name)
                        marked: Profiles.activeProfiles
                        onPicked: name => root.editedName = name
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
                    Picker {
                        visible: root._onAppearance
                        label: "Theme"
                        current: root.editTheme
                        options: (Theme.themeNames.includes("default") ? [] : ["default"]).concat(Theme.themeNames)
                        marked: [Theme.profileTheme]
                        edited: Object.keys(Theme.drafts)
                        // The preview shows the theme picked: stop it to pick another
                        locked: root.previewing
                        onPicked: name => root.editedTheme = name
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

                    Repeater {
                        id: _categoryRepeater
                        model: root.pages
                        Rectangle {
                            required property var modelData
                            required property int index
                            readonly property bool selected: modelData.id === root.selectedPage
                            Layout.fillWidth: true
                            // Only the pages of the tab that is open
                            visible: (modelData.tab === "appearance") === root._onAppearance
                            Layout.topMargin: modelData.separatorBefore ? 13 : 0
                            height: 34
                            radius: Theme.settings.sidebarItemRadius

                            Rectangle {
                                visible: !!parent.modelData.separatorBefore
                                y: -8
                                width: parent.width
                                height: 1
                                color: Theme.textDisabled
                                opacity: 0.3
                            }
                            // The selected one is marked by the sliding mark above
                            color: _categoryArea.containsMouse && !selected
                                ? Theme.fillSubtle : Qt.alpha(Theme.fillSubtle, 0)
                            Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

                            // ✎: the theme edited has unsaved changes on this page. On its
                            // own at the right, so cutting a long name never hides it.
                            Text {
                                id: _changedMark
                                visible: (Theme.drafts, (parent.modelData.draftGroups ?? []).some(group => Theme.hasDraft(root.editTheme, group)))
                                anchors { verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: 8 }
                                text: "✎"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBodyLarge
                                color: Theme.warning
                            }

                            Text {
                                anchors {
                                    verticalCenter: parent.verticalCenter
                                    left: parent.left
                                    leftMargin: 10
                                    right: _changedMark.visible ? _changedMark.left : parent.right
                                    rightMargin: 6
                                }
                                // A name wider than the sidebar (a larger font) is cut
                                elide: Text.ElideRight
                                text: parent.modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBodyLarge
                                color: parent.selected ? Theme.textPrimary : Theme.textSecondary
                                Behavior on color { ColorAnimation { duration: Theme.duration("state"); easing: Theme.curve("state") } }
                            }

                            MouseArea {
                                id: _categoryArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedPage = parent.modelData.id
                            }
                        }
                    }

                    Item {
                        Layout.fillHeight: true
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
                width: parent.width - 161
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
    Component {
        id: widgetsLookComp
        ShapeSettings {
            themeName: root.editTheme
            title: "Widgets"
            hint: "The widgets on the bar: their cells, and the workspaces' pills. The bar itself is on the Bar page."
            sections: [
                { title: "Cells", group: "capsule", hint: "Each widget's cell on the bar" },
                { title: "Workspace pills", group: "workspace" },
                { title: "Tray icons", group: "tray" }
            ]
        }
    }
    Component {
        id: popupsComp
        ShapeSettings {
            themeName: root.editTheme
            title: "Popups"
            hint: "The popups opening from the bar, and what is in them. Their colours, and the border's, are on the Colors page."
            sections: [
                { title: "Popup", group: "popup" },
                { title: "Rows and cards", group: "row" },
                { title: "Menu and list items", group: "listItem" },
                { title: "Dropdowns", group: "dropdown" },
                { title: "Power menu", group: "powerMenu" }
            ]
        }
    }
    Component {
        id: controlsComp
        ShapeSettings {
            themeName: root.editTheme
            title: "Controls"
            hint: "Buttons, choices and fields everywhere: popups, settings, the calendar."
            sections: [
                { title: "Buttons", group: "button", hint: "Every button's padding and height; general buttons' corners" },
                { title: "Save buttons", group: "saveButton" },
                { title: "Cancel buttons", group: "cancelButton" },
                { title: "Delete buttons", group: "deleteButton" },
                { title: "Icon buttons", group: "iconButton" },
                { title: "Pills", group: "pill" },
                { title: "Text fields", group: "field" },
                { title: "Check boxes", group: "checkbox" },
                { title: "Tooltips", group: "tooltip" },
                { title: "Outlines", group: "border" }
            ]
        }
    }
    Component {
        id: notificationsLookComp
        ShapeSettings {
            themeName: root.editTheme
            title: "Notifications"
            hint: "Notifications on screen and in the panel, the volume OSD and the shell's messages. Borders' colours are on the Colors page."
            sections: [
                { title: "Toasts", group: "osdToast" },
                { title: "In the panel", group: "notificationCard" },
                { title: "Volume OSD", group: "osdVolume" },
                { title: "Shell messages", group: "osdMessage" }
            ]
        }
    }
    Component {
        id: otherLookComp
        ShapeSettings {
            themeName: root.editTheme
            title: "Other"
            sections: [
                { title: "Settings window", group: "settings" },
                { title: "Calendar", group: "calendar" },
                { title: "Lock screen", group: "lock" }
            ]
        }
    }
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
