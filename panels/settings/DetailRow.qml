import QtQuick
import QtQuick.Layouts
import qs.singletons

// One detail: a label and its value, selectable to copy; hidden when there is no value
RowLayout {
    id: _detail
    property string label: ""
    property string value: ""
    visible: value !== ""
    Layout.fillWidth: true
    spacing: 10
    Text {
        Layout.preferredWidth: 110
        Layout.alignment: Qt.AlignTop
        text: _detail.label
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.textMuted
    }
    TextEdit {
        Layout.fillWidth: true
        readOnly: true
        selectByMouse: true
        wrapMode: TextEdit.WrapAnywhere
        text: _detail.value
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.textSecondary
        selectionColor: Theme.selection
        selectedTextColor: Theme.selectedText
    }
}
