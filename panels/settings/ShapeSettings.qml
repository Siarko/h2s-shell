import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons

// A page of the theme's shape tokens — radii, padding, sizes, border widths — in
// `sections` (ShapeSections), with the draft's Save and Cancel. Changes go into the
// theme's draft (ThemeRules, "Drafts"); previewing shows them on the shell as they are
// made. The Popups, Controls, Notifications and Other pages are this, with their own
// sections (docs/plans/themes-stage7.md).
Flickable {
    id: root

    // The theme being edited, picked in the settings window's sidebar
    required property string themeName
    property string title
    property string hint
    property var sections: []

    anchors.fill: parent
    contentHeight: _column.implicitHeight + 2 * Theme.settings.pageMargin
    clip: true

    readonly property bool _editable: !Theme.themeNames.includes(themeName) || themeName in Theme.themeFiles

    ColumnLayout {
        id: _column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: Theme.settings.pageMargin
        }
        spacing: 6

        Heading { text: root.title }
        Hint {
            visible: root.hint !== ""
            text: root.hint
        }
        Text {
            visible: !root._editable
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "The file " + root.themeName + ".json does not parse, so nothing here changes it."
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.error
        }

        DraftActions {
            themeName: root.themeName
            groups: _sections.groups
            message: root.title + " changed, not saved"
            onAboutToSave: _sections.flush()
        }

        ShapeSections {
            id: _sections
            themeName: root.themeName
            sections: root.sections
        }
    }
}
