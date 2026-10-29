import QtQuick
import QtQuick.Layouts
import qs.singletons

Item {
    id: root
    property string presetName: ""
    property string widgetType: "clock"

    implicitHeight: _col.implicitHeight

    // As the clock shows it: an empty format is the default
    readonly property string _currentFormat: WidgetPresets.value(widgetType, presetName, "format")
        || WidgetPresets.defaults.clock.format

    // An empty field drops the key, so the clock goes back to the default
    function _saveFormat(value) {
        WidgetPresets.set(widgetType, presetName, "format", value !== "" ? value : undefined);
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
