import QtQuick
import QtQuick.Layouts
import qs.singletons

ColumnLayout {
    anchors {
        fill: parent
        margins: 14
    }
    spacing: 0

    Text {
        text: "Notifications"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeHeading
        font.bold: true
        color: Theme.textSecondary
        Layout.bottomMargin: 8
    }

    Text {
        text: "Code Patterns"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeMedium
        font.bold: true
        color: Theme.textPrimary
        Layout.bottomMargin: 2
    }

    Text {
        text: "Regex patterns to extract codes (e.g. 2FA) from incoming notifications."
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
        color: Theme.textSecondary
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
        Layout.bottomMargin: 10
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: _container.implicitHeight
        color: Qt.rgba(0, 0, 0, 0.15)
        radius: 6
        border.color: Qt.rgba(Theme.textDim.r, Theme.textDim.g, Theme.textDim.b, 0.2)
        border.width: 1
        clip: true

        Column {
            id: _container
            width: parent.width
            topPadding: 4
            bottomPadding: 4

            Repeater {
                model: Config.notifications.codePatterns.length

                delegate: Item {
                    required property int index
                    width: _container.width
                    height: 32

                    property bool _valid: {
                        try { new RegExp(_input.displayText); return true; }
                        catch(e) { return false; }
                    }

                    RowLayout {
                        anchors { fill: parent; leftMargin: 8; rightMargin: 4 }
                        spacing: 4

                        Rectangle {
                            Layout.fillWidth: true
                            height: 24
                            radius: 4
                            color: Theme.cellDefault

                            TextInput {
                                id: _input
                                anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                text: Config.notifications.codePatterns[index]
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                color: _valid ? Theme.textPrimary : "#cc4444"
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                onEditingFinished: {
                                    var patterns = Array.from(Config.notifications.codePatterns);
                                    patterns[index] = text;
                                    Config.notifications.codePatterns = patterns;
                                }
                            }
                        }

                        Rectangle {
                            width: 24
                            height: 24
                            radius: 4
                            color: _removeHover.containsMouse ? Theme.cellHover : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "×"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.textDim
                            }

                            MouseArea {
                                id: _removeHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var patterns = Array.from(Config.notifications.codePatterns);
                                    patterns.splice(index, 1);
                                    Config.notifications.codePatterns = patterns;
                                }
                            }
                        }
                    }
                }
            }

            // Divider
            Rectangle {
                width: parent.width
                height: 1
                color: Qt.rgba(Theme.textDim.r, Theme.textDim.g, Theme.textDim.b, 0.2)
            }

            // Add row
            Item {
                width: _container.width
                height: 32

                Text {
                    anchors.centerIn: parent
                    text: "＋ Add pattern"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textSecondary
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var patterns = Array.from(Config.notifications.codePatterns);
                        patterns.push("");
                        Config.notifications.codePatterns = patterns;
                    }
                }
            }
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
