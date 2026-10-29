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
    readonly property int _performanceCategory: 7
    readonly property int _profilesCategory: 8
    readonly property int _mediaCategory: 2

    // The profile every page edits (docs/plans/global-profiles.md), by name so it
    // survives reordering; Full, else the first
    property string editedName: "Full"
    readonly property int editIndex: {
        const byName = Profiles.profiles.findIndex(profile => profile.name === editedName);
        return byName >= 0 ? byName : (Profiles.profiles.length > 0 ? 0 : -1);
    }
    // Pages whose settings are all per profile; the others apply to every profile until
    // they are migrated, and say so while another profile than Full is picked
    readonly property var _perProfileCategories: [0, _mediaCategory, 4, 5, _performanceCategory, _profilesCategory]
    readonly property bool _showScopeNote: Profiles.profiles[editIndex]?.name !== "Full"
        && !_perProfileCategories.includes(selectedCategory)

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

                ColumnLayout {
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
                        color: _profileIndicator.containsMouse ? Theme.textPrimary : Theme.sliderAccent

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
                        color: Theme.textDim
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
                            color: picked ? Theme.sliderAccent : (_editArea.containsMouse ? Theme.cellHover : "transparent")

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
                        color: Theme.textDim
                        opacity: 0.3
                    }

                    Repeater {
                        model: ["General", "Calendar", "Media", "Bar", "Notifications", "Lockscreen", "Dictation", "Performance", "Profiles"]
                        Rectangle {
                            required property string modelData
                            required property int index
                            Layout.fillWidth: true
                            height: 34
                            radius: 6
                            color: index === root.selectedCategory ? Qt.rgba(0.36, 0.61, 0.96, 0.15) : "transparent"
                            border.width: index === root.selectedCategory ? 1 : 0
                            border.color: Theme.sliderAccent

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
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedCategory = index
                            }
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }
                }
            }

            // ── Separator ─────────────────────────────────────────────
            Rectangle {
                width: 1
                height: parent.height
                color: Theme.textDim
                opacity: 0.3
            }

            // ── Right content area ────────────────────────────────────
            Item {
                width: parent.width - 161
                height: parent.height

                // Until a page is per profile, editing another profile does not change it
                Rectangle {
                    id: _scopeNote
                    visible: root._showScopeNote
                    anchors { top: parent.top; left: parent.left; right: parent.right; margins: 8 }
                    height: visible ? _scopeText.implicitHeight + 12 : 0
                    radius: 6
                    color: Theme.cellDefault

                    Text {
                        id: _scopeText
                        anchors { fill: parent; margins: 6 }
                        wrapMode: Text.WordWrap
                        text: "This page is not per profile yet: its settings apply to every profile."
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.textSecondary
                    }
                }

                Loader {
                    anchors { top: _scopeNote.visible ? _scopeNote.bottom : parent.top; left: parent.left; right: parent.right; bottom: parent.bottom }
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
            }
        }
    }

    Component { id: generalComp;       GeneralSettings       { editIndex: root.editIndex } }
    Component { id: calendarComp;      CalendarSettings      {} }
    Component { id: mediaComp;         MediaSettings         { editIndex: root.editIndex } }
    Component { id: barComp;           BarSettings           {} }
    Component { id: notificationsComp; NotificationsSettings { editIndex: root.editIndex } }
    Component { id: lockscreenComp;    LockscreenSettings    { editIndex: root.editIndex } }
    Component { id: sttComp;           SttSettings           {} }
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
