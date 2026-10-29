import Quickshell
import QtQuick
import QtQuick.Layouts
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
    readonly property var categoryNames: ["General", "Calendar", "Media", "Bar", "Notifications", "Lockscreen", "Dictation", "Performance", "Profiles"]
    readonly property int _performanceCategory: 7
    readonly property int _profilesCategory: 8

    // The profile every page edits (docs/plans/global-profiles.md), by name so it
    // survives reordering; Full, else the first
    property string editedName: "Full"
    readonly property int editIndex: {
        const byName = Profiles.profiles.findIndex(profile => profile.name === editedName);
        return byName >= 0 ? byName : (Profiles.profiles.length > 0 ? 0 : -1);
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.popupBackground

        Row {
            anchors.fill: parent
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
                    y: _sidebar.y + (target?.y ?? 0)
                    width: target?.width ?? 0
                    height: target?.height ?? 0
                    radius: 6
                    color: Theme.accentSecondaryTint
                    border.width: 1
                    border.color: Theme.accent
                    // Only for a change of page: not when the list is first laid out
                    Behavior on y {
                        enabled: _markSlide.running
                        NumberAnimation { duration: Theme.duration("slide"); easing.type: Theme.easing("slide") }
                    }
                }

                Timer {
                    id: _markSlide
                    interval: Theme.duration("slide") + 50
                }

                Connections {
                    target: root
                    function onSelectedCategoryChanged() { _markSlide.restart() }
                }

                ColumnLayout {
                    id: _sidebar
                    anchors {
                        fill: parent
                        margins: 10
                    }
                    spacing: 4

                    Text {
                        text: "Settings"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeMedium
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    // Which profiles apply right now, visible from every page
                    Text {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 6
                        wrapMode: Text.WordWrap
                        text: "Profile: " + (Profiles.activeProfiles.length > 0 ? Profiles.activeProfiles.join(", ") : "defaults")
                            + (Object.keys(Profiles.simulated).length > 0 ? " (simulated)" : "")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: _profileIndicator.containsMouse ? Theme.textPrimary : Theme.accent
                        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing.type: Theme.easing("hover") } }

                        MouseArea {
                            id: _profileIndicator
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectedCategory = root._profilesCategory
                        }
                    }

                    // The profile being edited, for every page
                    Text {
                        visible: Profiles.profiles.length > 0
                        text: "Editing"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.textDisabled
                    }

                    Repeater {
                        // ScriptModel, never the bare array — see "The Repeater crash"
                        model: ScriptModel {
                            values: Profiles.profiles.map(profile => profile.name)
                        }

                        Rectangle {
                            required property string modelData
                            required property int index
                            readonly property bool picked: index === root.editIndex
                            Layout.fillWidth: true
                            height: 24
                            radius: 6
                            color: picked ? Theme.accent : (_editArea.containsMouse ? Theme.surfaceHover : Theme.surfaceHoverClear)
                            Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing.type: Theme.easing("hover") } }

                            Text {
                                anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 6 }
                                text: parent.modelData + (Profiles.activeProfiles.includes(parent.modelData) ? " •" : "")
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                color: parent.picked ? Theme.textPrimary : Theme.textSecondary
                            }

                            MouseArea {
                                id: _editArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.editedName = parent.modelData
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
                            height: 34
                            radius: 6
                            // The selected one is marked by the sliding mark above
                            color: _categoryArea.containsMouse && index !== root.selectedCategory
                                ? Theme.fillSubtle : Qt.alpha(Theme.fillSubtle, 0)
                            Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing.type: Theme.easing("hover") } }

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
                                Behavior on color { ColorAnimation { duration: Theme.duration("state"); easing.type: Theme.easing("state") } }
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
                        return sttComp;
                    }
                }

                ParallelAnimation {
                    id: _pageEnter
                    NumberAnimation { target: _page; property: "opacity"; from: 0; to: 1; duration: Theme.duration("enter"); easing.type: Theme.easing("enter") }
                    NumberAnimation { target: _pageShift; property: "y"; from: 12; to: 0; duration: Theme.duration("enter"); easing.type: Theme.easing("enter") }
                }
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
