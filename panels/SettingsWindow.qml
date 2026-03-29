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

    property int selectedCategory: 0  // 0=General, 1=Calendar, 2=Media, 3=Bar

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
                        Layout.bottomMargin: 6
                    }

                    Repeater {
                        model: ["General", "Calendar", "Media", "Bar"]
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
                        return barComp;
                    }
                }
            }
        }
    }

    Component { id: generalComp;  GeneralSettings  {} }
    Component { id: calendarComp; CalendarSettings {} }
    Component { id: mediaComp;    MediaSettings    {} }
    Component { id: barComp;      BarSettings      {} }
}
