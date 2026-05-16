import QtQuick
import QtQuick.Layouts
import qs.singletons
import qs.singletons.googlecalendar

ColumnLayout {
    anchors {
        fill: parent
        margins: 14
    }
    spacing: 0

    Text {
        text: "Calendar"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeHeading
        font.bold: true
        color: Theme.textSecondary
        Layout.bottomMargin: 8
    }

    // ── Google Calendar subsection ────────────────────────────────────

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
        font.pixelSize: Theme.fontSizeHeading
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
            font.pixelSize: Theme.fontSizeBodyLarge
            color: Theme.textPrimary
            Layout.fillWidth: true
        }
    }

    // Connecting… message (shown while OAuth process runs)
    Text {
        visible: GoogleCalendarAuth.isBusy
        text: "Opening browser for authorization…"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
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
                    font.pixelSize: Theme.fontSizeBody
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
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textPrimary
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: GoogleCalendarAuth.logout()
            }
        }
    }

    // ── My Calendars section ──────────────────────────────────────────

    Text {
        visible: GoogleCalendarAuth.isAuthorized
        text: "My Calendars "
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeHeading
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
                                font.pixelSize: Theme.fontSizeBody
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
                                    font.pixelSize: Theme.fontSizeXSmall
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
