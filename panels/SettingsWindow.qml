import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.singletons
import qs.singletons.googlecalendar

FloatingWindow {
    id: root
    title: "Settings"
    implicitWidth: 520
    implicitHeight: 640
    minimumSize: Qt.size(400, 300)
    visible: false

    property int selectedCategory: 0  // 0=General, 1=Calendar

    component SettingBool: RowLayout {
        property string label
        property bool value: false

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
            property bool checked: value
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
                onClicked: toggle.parent.value = !toggle.parent.value
            }
        }
    }

    component SettingOptions: Item {
        id: _so
        property string label: ""
        property var options: []
        property var labels: []
        property string value: ""
        signal picked(string newValue)

        Layout.fillWidth: true
        implicitHeight: _soCol.implicitHeight + 8

        Column {
            id: _soCol
            width: _so.width
            spacing: 6

            Text {
                text: _so.label
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: Theme.textPrimary
            }

            Row {
                spacing: 4

                Repeater {
                    model: _so.options

                    Rectangle {
                        required property string modelData
                        required property int index
                        property bool selected: modelData === _so.value
                        width: _pillText.implicitWidth + 16
                        height: 26
                        radius: 6
                        color: selected ? Theme.sliderAccent : "transparent"
                        border.width: selected ? 0 : 1
                        border.color: Qt.rgba(Theme.textSecondary.r, Theme.textSecondary.g, Theme.textSecondary.b, 0.4)

                        Text {
                            id: _pillText
                            anchors.centerIn: parent
                            text: _so.labels[index]
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: selected ? Theme.textPrimary : Theme.textSecondary
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: _so.picked(modelData)
                        }
                    }
                }
            }
        }
    }

    component SettingInputRow: RowLayout {
        property string label
        property string value
        property int echoMode: TextInput.Normal

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
            width: 130
            height: 26
            radius: 6
            color: Theme.cellDefault

            TextInput {
                anchors {
                    fill: parent
                    leftMargin: 8
                    rightMargin: 8
                }
                text: value
                echoMode: parent.parent.echoMode
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Theme.textPrimary
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                onTextEdited: parent.parent.value = text
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
                        model: ["General", "Calendar", "Media"]
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
                    sourceComponent: root.selectedCategory === 0 ? generalComp : root.selectedCategory === 1 ? calendarComp : mediaComp
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

            SettingBool {
                label: "Debug Mode"
                value: Config.general.debug ?? false
                onValueChanged: Config.general.debug = value
            }
            SettingBool {
                label: "Debug Mode | Fetch"
                value: Config.general.fetch_debug ?? false
                onValueChanged: Config.general.fetch_debug = value
            }

            Item {
                Layout.fillHeight: true
            }
        }
    }

    // ── Media settings content ────────────────────────────────────────
    Component {
        id: mediaComp

        ColumnLayout {
            anchors {
                fill: parent
                margins: 14
            }
            spacing: 4

            Text {
                text: "Media"
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.bold: true
                color: Theme.textSecondary
                Layout.bottomMargin: 4
            }

            SettingOptions {
                label: "Visualizer style"
                options: ["waveform", "bars", "dots", "none"]
                labels: ["Waveform", "Bars", "Dots", "None"]
                value: Config.media.visualizerStyle
                onPicked: val => Config.media.visualizerStyle = val
            }

            SettingOptions {
                label: "Layout"
                options: ["horizontal", "vertical"]
                labels: ["Horizontal", "Vertical"]
                value: Config.media.visualizerLayout
                onPicked: val => Config.media.visualizerLayout = val
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

            SettingInputRow {
                label: "Datetime format"
                value: Config.datetimeFormat
                onValueChanged: Config.datetimeFormat = value
            }

            // ── Google Calendar subsection ─────────────────────────────

            // Divider
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                Layout.topMargin: 10
                color: Theme.textDim
                opacity: 0.3
            }

            Text {
                text: "Google Calendar"
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.bold: true
                color: Theme.textSecondary
                Layout.topMargin: 10
                Layout.bottomMargin: 4
            }

            // Connection status row
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                spacing: 8

                Rectangle {
                    width: 8
                    height: 8
                    radius: 4
                    color: GoogleCalendarAuth.isAuthorized ? "#33b679" : "#e87c5b"
                }

                Text {
                    text: GoogleCalendarAuth.isBusy ? "Connecting…" : GoogleCalendar.isAuthorized ? "Connected" : "Not connected"
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    color: Theme.textPrimary
                    Layout.fillWidth: true
                }
            }

            // Connecting… message (shown while OAuth process runs)
            Text {
                visible: GoogleCalendarAuth.isBusy
                text: "Opening browser for authorization…"
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.textSecondary
                Layout.bottomMargin: 4
            }

            // Not-authorized inputs (hidden while busy or connected)
            ColumnLayout {
                visible: !GoogleCalendarAuth.isAuthorized && !GoogleCalendarAuth.isBusy
                Layout.fillWidth: true
                spacing: 0

                SettingInputRow {
                    label: "Client ID"
                    value: Config.gcal.clientId
                    onValueChanged: Config.gcal.clientId = value
                }

                SettingInputRow {
                    label: "Client Secret"
                    value: Config.gcal.clientSecret
                    onValueChanged: Config.gcal.clientSecret = value
                    echoMode: TextInput.Password
                }

                // Connect button
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44

                    Rectangle {
                        readonly property bool _enabled: Config.gcal.clientId !== "" && Config.gcal.clientSecret !== ""
                        width: 90
                        height: 28
                        radius: 6
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        color: _enabled ? Theme.sliderAccent : Theme.cellDefault
                        opacity: _enabled ? 1.0 : 0.5

                        Text {
                            anchors.centerIn: parent
                            text: "Connect"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Theme.textPrimary
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: parent._enabled
                            cursorShape: Qt.PointingHandCursor
                            onClicked: GoogleCalendarAuth.login()
                        }
                    }
                }
            }

            // Disconnect button (shown when authorized)
            Item {
                visible: GoogleCalendarAuth.isAuthorized
                Layout.fillWidth: true
                Layout.preferredHeight: 44

                Rectangle {
                    width: 100
                    height: 28
                    radius: 6
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    color: "#c0392b"

                    Text {
                        anchors.centerIn: parent
                        text: "Disconnect"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.textPrimary
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: GoogleCalendarAuth.logout()
                    }
                }
            }

            // ── My Calendars section ──────────────────────────────────────

            Text {
                visible: GoogleCalendarAuth.isAuthorized
                text: "My Calendars "
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.bold: true
                color: Theme.textSecondary
                Layout.topMargin: 6
                Layout.bottomMargin: 4
            }

            Rectangle {
                visible: GoogleCalendarAuth.isAuthorized
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(150, GoogleCalendar.calendarsArray.length * 32)
                clip: true
                color: "transparent"

                Flickable {
                    anchors.fill: parent
                    contentHeight: _calColumn.implicitHeight
                    clip: true

                    Column {
                        id: _calColumn
                        width: parent.width

                        Repeater {
                            model: GoogleCalendar.calendarsArray

                            delegate: Item {
                                id: calendarRow
                                required property var modelData
                                width: _calColumn.width
                                height: 32

                                RowLayout {
                                    anchors {
                                        fill: parent
                                        leftMargin: 2
                                        rightMargin: 2
                                    }
                                    spacing: 8

                                    Rectangle {
                                        width: 8
                                        height: 8
                                        radius: 4
                                        color: calendarRow.modelData.color
                                    }

                                    Text {
                                        text: calendarRow.modelData.name
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        color: Theme.textPrimary
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        id: _calCheckbox
                                        property bool checked: GoogleCalendar.enabledCalendarIds.includes(calendarRow.modelData.id)
                                        width: 16
                                        height: 16
                                        radius: 3
                                        color: checked ? Theme.sliderAccent : "transparent"
                                        border.color: Theme.sliderAccent
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: "✓"
                                            visible: _calCheckbox.checked
                                            font.pixelSize: 10
                                            color: Theme.textPrimary
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: GoogleCalendar.setCalendarEnabled(calendarRow.modelData.id, !_calCheckbox.checked)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                Layout.topMargin: 10
                color: Theme.textDim
                opacity: 0.3
            }

            SettingBool {
                label: "Debug Mode"
                value: Config.gcal.debug ?? false
                onValueChanged: Config.gcal.debug = value
            }

            Item {
                Layout.fillHeight: true
            }
        }
    }
}
