import QtQuick
import QtQuick.Layouts
import qs.singletons

// Read-only counterpart to the other Setting* rows — for state the shell observes
// but does not own, so there is nothing to edit.
RowLayout {
    id: root
    property string label
    property string value
    property color valueColor: Theme.textSecondary

    Layout.fillWidth: true
    Layout.preferredHeight: 30
    spacing: 8

    Text {
        text: root.label
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBodyLarge
        color: Theme.textPrimary
        elide: Text.ElideRight
        Layout.fillWidth: true
    }

    Text {
        text: root.value
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
        color: root.valueColor
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
        // Constant cap, not derived from the row's own width, to keep the layout
        // engine out of a feedback loop
        Layout.maximumWidth: 180
    }
}
