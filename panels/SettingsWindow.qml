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
    readonly property var categoryNames: ["General", "Calendar", "Media", "Bar", "Notifications", "Lockscreen", "Dictation", "Performance", "Profiles", "Themes", "Curves"]
    readonly property int _performanceCategory: 7
    readonly property int _profilesCategory: 8
    // The window has two tabs: Behaviour, whose pages edit a profile, and Appearance, from
    // here on, whose pages edit a theme (docs/plans/themes.md, stage 6; TODO 10.10)
    readonly property int _themesCategory: 9
    readonly property int _curvesCategory: 10
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
        // Options shown with a • after them: the active profiles, the theme in use
        property var marked: []
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
                text: _picker.current + (_picker.marked.includes(_picker.current) ? " •" : "")
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                font.bold: true
                color: Theme.textPrimary
            }
            Text {
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
                                text: parent.modelData + (_picker.marked.includes(parent.modelData) ? " •" : "")
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

        Row {
            anchors { left: parent.left; right: parent.right; top: _tabBar.bottom; bottom: parent.bottom }
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

                        Rectangle {
                            id: _previewToggle
                            // Nothing to preview in the theme already in use
                            readonly property bool available: root.previewing || root.editTheme !== Theme.profileTheme
                            width: _previewText.implicitWidth + 14
                            height: 20
                            radius: 6
                            opacity: available ? 1 : 0.35
                            color: root.previewing ? Theme.accent : (_previewToggleArea.containsMouse && available ? Theme.surfaceHover : Theme.surface)
                            Behavior on color { ColorAnimation { duration: Theme.duration("state"); easing: Theme.curve("state") } }

                            Text {
                                id: _previewText
                                anchors.centerIn: parent
                                text: root.previewing ? "Stop preview" : "Preview"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                color: root.previewing ? Theme.onAccent : Theme.textSecondary
                            }

                            MouseArea {
                                id: _previewToggleArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: _previewToggle.available ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: if (_previewToggle.available) root.previewing = !root.previewing
                            }

                            HoverTip {
                                target: _previewToggle
                                shown: _previewToggleArea.containsMouse
                                text: !_previewToggle.available ? "This theme is already in use"
                                    : root.previewing ? "Back to the profile's theme"
                                    : "Show this theme on the whole shell while you edit it. Saved nowhere; leaving Appearance or closing the window ends it."
                            }
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
                            height: 34
                            radius: 6
                            // The selected one is marked by the sliding mark above
                            color: _categoryArea.containsMouse && index !== root.selectedCategory
                                ? Theme.fillSubtle : Qt.alpha(Theme.fillSubtle, 0)
                            Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

                            Text {
                                anchors {
                                    verticalCenter: parent.verticalCenter
                                    left: parent.left
                                    leftMargin: 10
                                }
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
