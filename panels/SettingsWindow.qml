import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.singletons

FloatingWindow {
    id: root
    title: "Settings"
    implicitWidth: 520
    implicitHeight: 400
    minimumSize: Qt.size(400, 300)
    visible: false

    property int selectedCategory: 0  // 0=General, 1=Calendar

    component SettingRow: RowLayout {
        property string label
        property bool defaultChecked: false

        Layout.fillWidth: true
        Layout.preferredHeight: 44

        Text {
            text: label
            font.family: Theme.fontFamily
            font.pixelSize: 13
            color: Theme.textPrimary
            Layout.fillWidth: true
        }

        Rectangle {
            id: toggle
            property bool checked: defaultChecked
            width: 36
            height: 20
            radius: 10
            color: checked ? Theme.sliderAccent : Theme.cellDefault

            Rectangle {
                x: parent.checked ? parent.width - width - 2 : 2
                y: 2
                width: 16
                height: 16
                radius: 8
                color: Theme.textPrimary
                Behavior on x {
                    NumberAnimation {
                        duration: 150
                        easing.type: Easing.OutQuad
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: toggle.checked = !toggle.checked
            }
        }
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

                ColumnLayout {
                    anchors {
                        fill: parent
                        margins: 10
                    }
                    spacing: 4

                    Text {
                        text: "Settings"
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.bold: true
                        color: Theme.textPrimary
                        Layout.bottomMargin: 6
                    }

                    Repeater {
                        model: ["General", "Calendar"]
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
                                font.pixelSize: 13
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
                    sourceComponent: root.selectedCategory === 0 ? generalComp : calendarComp
                }
            }
        }
    }

    // ── General settings content ──────────────────────────────────────
    Component {
        id: generalComp

        ColumnLayout {
            anchors {
                fill: parent
                margins: 14
            }
            spacing: 0

            Text {
                text: "General"
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.bold: true
                color: Theme.textSecondary
                Layout.bottomMargin: 8
            }

            SettingRow {
                label: "Show seconds in clock"
                defaultChecked: true
            }
            SettingRow {
                label: "Compact mode"
                defaultChecked: false
            }
            SettingRow {
                label: "Animations"
                defaultChecked: true
            }

            Item {
                Layout.fillHeight: true
            }
        }
    }

    // ── Calendar settings content ─────────────────────────────────────
    Component {
        id: calendarComp

        ColumnLayout {
            anchors {
                fill: parent
                margins: 14
            }
            spacing: 0

            Text {
                text: "Calendar"
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.bold: true
                color: Theme.textSecondary
                Layout.bottomMargin: 8
            }

            SettingRow {
                label: "Start week on Monday"
                defaultChecked: true
            }
            SettingRow {
                label: "Show week numbers"
                defaultChecked: false
            }
            SettingRow {
                label: "24-hour time format"
                defaultChecked: true
            }

            Item {
                Layout.fillHeight: true
            }
        }
    }
}
