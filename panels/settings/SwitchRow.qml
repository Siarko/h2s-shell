import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons

// A setting that is a switch: its label, a short line on what it does, and the switch —
// with a lock when changing it asks for an administrator's password (`need`, polkit's
// answer: "auth"; "no" turns it off)
RowLayout {
    id: _switchRow
    property string label: ""
    property string hint: ""
    property bool checked: false
    // polkit's answer for what it changes (NetworkOverview.need): marked when it asks
    // for an administrator's password, off when not allowed
    property string need: ""
    signal toggled()
    Layout.fillWidth: true
    Layout.bottomMargin: 6
    spacing: 10
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        // Filling the width, or the column could not grow and the switch sat by its label
        Text {
            Layout.fillWidth: true
            text: _switchRow.label
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textPrimary
        }
        Text {
            visible: _switchRow.hint !== ""
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: _switchRow.hint
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.textMuted
        }
    }
    PrivilegedMark { need: _switchRow.need }
    ToggleSwitch {
        checked: _switchRow.checked
        enabled: _switchRow.need !== "no"
        opacity: enabled ? 1 : 0.4
        onToggled: _switchRow.toggled()
    }
}
