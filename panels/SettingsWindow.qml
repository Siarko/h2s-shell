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

    // Index into the sidebar list below
    property int selectedCategory: 0
    // The sidebar's pages, in order; also how IPC names a page
    readonly property var categoryNames: ["General", "Calendar", "Media", "Bar", "Notifications", "Lockscreen", "Dictation", "Performance", "Profiles", "Themes", "Curves", "Colors", "Fonts"]
    readonly property int _performanceCategory: 7
    readonly property int _profilesCategory: 8
    // The window has two tabs: Behaviour, whose pages edit a profile, and Appearance, from
    // here on, whose pages edit a theme (docs/plans/themes.md, stage 6; TODO 10.10)
    readonly property int _themesCategory: 9
    readonly property int _curvesCategory: 10
    // From here on, the pages that edit the picked theme's values (after a separator)
    readonly property int _colorsCategory: 11
    readonly property int _fontsCategory: 12
    readonly property int _firstThemePage: _colorsCategory
    readonly property bool _onAppearance: selectedCategory >= _themesCategory

    // The page last open in each tab, to come back to
    property int _lastBehaviourPage: 0
    property int _lastAppearancePage: _themesCategory
    // From selectedCategory itself: _onAppearance may not have caught up yet when this runs
    onSelectedCategoryChanged: {
        const appearance = selectedCategory >= _themesCategory;
        if (appearance)
            _lastAppearancePage = selectedCategory;
        else
            _lastBehaviourPage = selectedCategory;
        _openList = null;
        _slideMark(_previousCategory, selectedCategory);
        _previousCategory = selectedCategory;
    }

    // The selected page's mark slides from the page before only when the page changes
    // within a tab: it sits at the page plus an offset that animates to nothing. Anything
    // else that moves the list (the picker above it growing, a change of tab) moves the
    // mark with it at once.
    property int _previousCategory: 0
    property real _markOffset: 0

    function _slideMark(from, to) {
        const fromItem = _categoryRepeater.itemAt(from);
        const toItem = _categoryRepeater.itemAt(to);
        _markSlide.stop();
        if (!fromItem || !toItem || (from >= _themesCategory) !== (to >= _themesCategory)) {
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

    // The theme group an Appearance page edits through a draft, or ""
    function _pageGroup(category) {
        return category === _colorsCategory ? "colors" : category === _fontsCategory ? "fonts" : "";
    }

    function showBehaviour() {
        selectedCategory = _lastBehaviourPage;
    }

    // Opens the Appearance tab, on `theme` if given
    function showAppearance(theme) {
        selectedCategory = _lastAppearancePage;
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
            radius: 6
            color: _pickerArea.containsMouse && !_picker.locked ? Theme.surfaceHover : Theme.surface
            opacity: _picker.locked ? 0.5 : 1
            border.width: 1
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
                radius: 6
                color: Theme.popupBackground
                border.width: 1
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
                            radius: 4
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

        width: _tabLabel.implicitWidth + 24
        height: 28
        radius: 6
        color: picked ? Theme.accentSecondaryTint : (_tabArea.containsMouse ? Theme.fillSubtle : Qt.alpha(Theme.fillSubtle, 0))
        border.width: picked ? 1 : 0
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
                    primary: true
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
                    readonly property Item target: _categoryRepeater.count > root.selectedCategory
                        ? _categoryRepeater.itemAt(root.selectedCategory) : null
                    visible: target !== null
                    x: _sidebar.x + (target?.x ?? 0)
                    // The offset slides it in from the page before (root._slideMark)
                    y: _sidebar.y + (target?.y ?? 0) + root._markOffset
                    width: target?.width ?? 0
                    height: target?.height ?? 0
                    radius: 6
                    color: Theme.accentSecondaryTint
                    border.width: 1
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
                            onClicked: root.selectedCategory = root._profilesCategory
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
                            primary: root.previewing
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
                            readonly property string _full: root.selectedCategory === root._curvesCategory
                                ? "Curves are shared by every theme"
                                : _users.length > 0 ? "Used by " + _users.join(", ") : "Not used by any profile"
                            text: root.selectedCategory === root._curvesCategory ? "Shared"
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
                        model: root.categoryNames
                        Rectangle {
                            required property string modelData
                            required property int index
                            Layout.fillWidth: true
                            // Only the pages of the tab that is open
                            visible: (index >= root._themesCategory) === root._onAppearance
                            // A line above the pages that edit the theme's values: Themes and
                            // Curves above it manage the library
                            Layout.topMargin: index === root._firstThemePage ? 13 : 0
                            height: 34
                            radius: 6

                            Rectangle {
                                visible: parent.index === root._firstThemePage
                                y: -8
                                width: parent.width
                                height: 1
                                color: Theme.textDisabled
                                opacity: 0.3
                            }
                            // The selected one is marked by the sliding mark above
                            color: _categoryArea.containsMouse && index !== root.selectedCategory
                                ? Theme.fillSubtle : Qt.alpha(Theme.fillSubtle, 0)
                            Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

                            // ✎: the theme edited has unsaved changes on this page. On its
                            // own at the right, so cutting a long name never hides it.
                            Text {
                                id: _changedMark
                                visible: (Theme.drafts, root._pageGroup(parent.index) !== "" && Theme.hasDraft(root.editTheme, root._pageGroup(parent.index)))
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
                                text: modelData
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBodyLarge
                                color: index === root.selectedCategory ? Theme.textPrimary : Theme.textSecondary
                                Behavior on color { ColorAnimation { duration: Theme.duration("state"); easing: Theme.curve("state") } }
                            }

                            MouseArea {
                                id: _categoryArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedCategory = index
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
                        selectionColor: Theme.accent
                        selectedTextColor: Theme.textPrimary
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
                    sourceComponent: {
                        if (root.selectedCategory === 0) return generalComp;
                        if (root.selectedCategory === 1) return calendarComp;
                        if (root.selectedCategory === 2) return mediaComp;
                        if (root.selectedCategory === 3) return barComp;
                        if (root.selectedCategory === 4) return notificationsComp;
                        if (root.selectedCategory === 5) return lockscreenComp;
                        if (root.selectedCategory === root._performanceCategory) return performanceComp;
                        if (root.selectedCategory === root._profilesCategory) return profilesComp;
                        if (root.selectedCategory === root._themesCategory) return themesComp;
                        if (root.selectedCategory === root._colorsCategory) return colorsComp;
                        if (root.selectedCategory === root._fontsCategory) return fontsComp;
                        if (root.selectedCategory === root._curvesCategory) return curvesComp;
                        return sttComp;
                    }
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
                root.selectedCategory = root._performanceCategory;
            }
        }
    }
}
