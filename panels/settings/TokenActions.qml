import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons

// Where one theme value comes from — changed and not saved, set in the theme, inherited
// from the theme it extends or its palette, or built in — with Reset (back to the
// inherited value) and Undo (back to the saved one), both through the theme's draft
// (ThemeRules, "Drafts"). `origins` is the group's part of Theme.originsOf(themeName).
RowLayout {
    id: root

    required property string themeName
    required property string group
    required property string token
    required property var origins
    property bool editable: true
    // Before Reset or Undo, so a page can send what it still holds first
    signal aboutToChange

    readonly property var _origin: origins[token]
    readonly property bool _setHere: !!_origin && !_origin.palette && !_origin.draft && _origin.theme === themeName
    readonly property bool _drafted: !!_origin?.draft || !!_origin?.reset

    spacing: 6

    Text {
        text: {
            if (root._origin?.draft)
                return "✎ changed";
            const source = !root._origin?.theme ? "built in"
                : root._origin.palette ? "palette of " + root._origin.theme
                : root._origin.theme === root.themeName ? "set here"
                : "from " + root._origin.theme;
            return root._origin?.reset ? "✎ reset, " + source : source;
        }
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        color: root._drafted ? Theme.warning : root._setHere ? Theme.accent : Theme.textMuted
    }
    SmallButton {
        label: "Reset"
        fontSize: Theme.fontSizeSmall
        available: root.editable && (root._setHere || !!root._origin?.draft)
        tooltip: available ? "Back to the inherited value" : "Not set in this theme: nothing to reset"
        onClicked: {
            root.aboutToChange();
            Theme.draftToken(root.themeName, root.group, root.token, null);
        }
    }
    SmallButton {
        visible: root._drafted
        label: "Undo"
        fontSize: Theme.fontSizeSmall
        tooltip: "Back to the saved value"
        onClicked: {
            root.aboutToChange();
            Theme.undraftToken(root.themeName, root.group, root.token);
        }
    }
}
