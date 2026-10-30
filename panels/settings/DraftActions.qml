import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons

// A page's unsaved changes to a theme (its draft, ThemeRules "Drafts") in `groups`: shown
// while there are any, with Save into the theme and Cancel, which asks first. The page can
// send what it still holds back before a save through `aboutToSave`.
RowLayout {
    id: root

    required property string themeName
    required property var groups
    // What the row says, e.g. "Colours changed, not saved"
    property string message: "Changed, not saved"
    signal aboutToSave

    readonly property bool changed: (Theme.drafts, groups.some(group => Theme.hasDraft(themeName, group)))

    visible: changed
    Layout.fillWidth: true
    spacing: 6

    // A question to throw the changes away does not outlive them, nor carry to another theme
    onChangedChanged: if (!changed) _cancel.asking = false
    onThemeNameChanged: _cancel.asking = false

    Text {
        Layout.fillWidth: true
        text: "✎ " + root.message
        elide: Text.ElideRight
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.warning
    }

    SmallButton {
        label: "Save"
        primary: true
        onClicked: {
            root.aboutToSave();
            Theme.saveDraft(root.themeName, root.groups);
        }
    }

    DeleteButton {
        id: _cancel
        label: "Cancel"
        confirmLabel: "Throw away?"
        fontSize: Theme.fontSizeBody
        cancelTip: "Keep the changes"
        onConfirmed: Theme.discardDraft(root.themeName, root.groups)
    }
}
