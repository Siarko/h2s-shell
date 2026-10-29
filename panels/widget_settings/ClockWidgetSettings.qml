import QtQuick
import QtQuick.Layouts
import qs.singletons

Item {
    id: root
    property string profileName: ""
    property string widgetType: "clock"

    implicitHeight: _col.implicitHeight

    readonly property string _currentFormat: {
        var data = JSON.parse(Config.widgetProfiles || "{}");
        return data[widgetType]?.[profileName]?.format ?? "hh:mm:ss"; // ClockWidget.defaultFormat
    }

    function _saveFormat(value) {
        var data = JSON.parse(Config.widgetProfiles || "{}");
        if (!data[widgetType]) data[widgetType] = {};
        if (!data[widgetType][profileName]) data[widgetType][profileName] = {};
        data[widgetType][profileName]["format"] = value;
        Config.widgetProfiles = JSON.stringify(data);
    }

    Column {
        id: _col
        width: parent.width
        topPadding: 4
        spacing: 0

        // Format row
        Item {
            width: _col.width
            height: 28

            RowLayout {
                anchors { fill: parent; rightMargin: 4 }
                spacing: 8

                Text {
                    text: "Format"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textSecondary
                    Layout.preferredWidth: 60
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 22
                    radius: 6
                    color: Theme.cellDefault

                    TextInput {
                        id: _formatInput
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                        text: _currentFormat
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textPrimary
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        onEditingFinished: _saveFormat(text.trim())
                        onActiveFocusChanged: if (!activeFocus) text = _currentFormat
                    }
                }
            }
        }

        // Preview row
        Item {
            width: _col.width
            height: 28

            RowLayout {
                anchors { fill: parent; rightMargin: 4 }
                spacing: 8

                Text {
                    text: "Preview"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textSecondary
                    Layout.preferredWidth: 60
                }

                Text {
                    text: Qt.formatDateTime(Time.date, _currentFormat)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textPrimary
                }
            }
        }
    }
}
