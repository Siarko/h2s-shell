import QtQuick
import QtQuick.Layouts
import qs.singletons

// One line of a settings page, a card or a popup: a label, a short line under it on what
// it is about (`hint`), and on the right a value, controls, or both. The controls are its
// children, in a row.
//
//   SettingsRow { label: "Priority"; hint: "Higher wins"; SmallButton { label: "+" } }
//   SettingsRow { label: "Address"; value: "192.168.1.20" }
RowLayout {
    id: root

    property string label: ""
    property string hint: ""
    property string value: ""
    default property alias controls: _controls.data

    Layout.fillWidth: true
    spacing: 10

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        // Filling the width, or the column could not grow and the controls sat by the label
        Text {
            Layout.fillWidth: true
            text: root.label
            textFormat: Text.PlainText
            elide: Text.ElideRight
            maximumLineCount: 1
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textPrimary
        }
        Text {
            visible: root.hint !== ""
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: root.hint
            textFormat: Text.PlainText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.textMuted
        }
    }
    Text {
        visible: root.value !== ""
        // A constant cap, not one derived from the row's width, which the layout would
        // chase
        Layout.maximumWidth: 220
        horizontalAlignment: Text.AlignRight
        text: root.value
        textFormat: Text.PlainText
        elide: Text.ElideRight
        maximumLineCount: 1
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
        color: Theme.textSecondary
    }
    RowLayout {
        id: _controls
        visible: children.length > 0
        spacing: 8
    }
}
