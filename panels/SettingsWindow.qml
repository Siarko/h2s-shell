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
    // The profile the Performance page edits, when opened from the Profiles page
    property string performanceProfile: ""

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

                Loader {
                    anchors.fill: parent
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

    Component { id: generalComp;       GeneralSettings       {} }
    Component { id: calendarComp;      CalendarSettings      {} }
    Component { id: mediaComp;         MediaSettings         {} }
    Component { id: barComp;           BarSettings           {} }
    Component { id: notificationsComp; NotificationsSettings {} }
    Component { id: lockscreenComp;    LockscreenSettings    {} }
    Component { id: sttComp;           SttSettings           {} }
    Component {
        id: performanceComp
        PerformanceSettings { editedName: root.performanceProfile }
    }
    Component {
        id: profilesComp
        ProfilesSettings {
            onEditValuesRequested: name => {
                root.performanceProfile = name;
                root.selectedCategory = root._performanceCategory;
            }
        }
    }
}
