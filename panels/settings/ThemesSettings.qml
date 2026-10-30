import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons

// The theme picked in the sidebar: what it extends, who uses it, what is wrong with it, and
// managing the library of themes — new, duplicate, rename, delete (docs/plans/themes.md,
// stage 6). Which theme a profile uses is a profile setting, on the General page.
Flickable {
    id: root

    // The theme being edited, picked in the settings window's sidebar
    required property string themeName
    // Asks the window to edit another theme (one just created or renamed; "" for the
    // active one, after a delete)
    signal themePicked(string name)

    anchors.fill: parent
    contentHeight: _column.implicitHeight + 2 * Theme.settings.pageMargin
    clip: true

    readonly property bool _hasFile: Theme.themeNames.includes(themeName)
    readonly property bool _broken: _hasFile && !(themeName in Theme.themeFiles)
    readonly property bool _isDefault: themeName === "default"
    readonly property var _file: Theme.themeFiles[themeName] ?? null
    readonly property string _extends: typeof _file?.extends === "string" ? _file.extends : "default"
    readonly property var _users: (Profiles.profiles, Theme.usersOf(themeName))
    readonly property var _setters: (Profiles.profiles, Profiles.globals, Theme.setters(themeName))
    readonly property var _errors: (Theme.revision, Theme.errorsOf(themeName))
    // Themes it may extend: not itself, nor one that extends it, directly or not
    readonly property var _parents: {
        Theme.revision;
        const names = (Theme.themeNames.includes("default") ? [] : ["default"]).concat(Theme.themeNames);
        return names.filter(name => !ThemeRules.extendsCycle(themeName, name, other => Theme.themeFiles[other] ?? null));
    }

    // Why a name typed for a new or renamed theme cannot be used, or ""
    function _nameProblem(name) {
        if (name.trim() === "")
            return "";
        if (!ThemeRules.validThemeName(name))
            return "Not a name a theme can have: no slashes, no dot first, no spaces at its ends";
        if (Theme.themeExists(name))
            return "There is already a theme with this name";
        return "";
    }

    onThemeNameChanged: {
        _renameInput.text = "";
        _newInput.text = "";
        _deleteButton.asking = false;
    }

    component Label: Text {
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
        color: Theme.textSecondary
    }

    component Field: InputField {
        Layout.fillWidth: true
    }

    ColumnLayout {
        id: _column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: Theme.settings.pageMargin
        }
        spacing: 10

        Heading { text: root.themeName + (root.themeName === Theme.profileTheme ? " (in use)" : "") }
        Hint {
            text: "A theme is how the shell looks: colours, fonts, the bar's shape, animations. Profiles pick one (General → Theme). "
                + "What a theme does not set comes from the theme it extends. Files in "
                + Theme.themesDir.replace(Quickshell.env("HOME"), "~") + "."
        }

        // ── Who uses it ──
        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: root._users.length > 0 ? "Used by " + root._users.join(", ") : "Not used by any profile"
            color: root._users.length > 0 ? Theme.accent : Theme.textMuted
        }

        Hint {
            visible: root._isDefault && !root._hasFile
            text: "The built-in look, with no file of its own: editing it creates default.json, and every theme that extends nothing builds on it."
        }

        // ── What is wrong ──
        Text {
            visible: root._broken
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "The file " + root.themeName + ".json does not parse, so nothing here changes it. Fix it by hand: it applies as soon as it is saved."
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.error
        }
        Repeater {
            model: ScriptModel { values: root._errors }
            Text {
                required property string modelData
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "⚠ " + modelData
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.warning
            }
        }

        // ── What it extends ──
        ColumnLayout {
            visible: !root._isDefault && !root._broken && root._hasFile
            Layout.fillWidth: true
            spacing: 6

            Label { text: "Extends" }
            Flow {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: ScriptModel { values: root._parents }
                    Pill {
                        required property string modelData
                        label: modelData
                        picked: modelData === root._extends
                        onClicked: if (!picked) Theme.setExtends(root.themeName, modelData)
                    }
                }
            }
            Hint { text: "Themes that extend this one, directly or not, are left out: a theme cannot build on itself." }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.divider; Layout.topMargin: 4; Layout.bottomMargin: 4 }

        // ── New ──
        Heading { text: "New theme" }
        Field {
            id: _newInput
            placeholder: "Name"
            problem: root._nameProblem(text) !== ""
        }
        Text {
            visible: root._nameProblem(_newInput.text) !== ""
            text: root._nameProblem(_newInput.text)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.error
        }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            SmallButton {
                label: "Extending " + root.themeName
                available: _newInput.text.trim() !== "" && root._nameProblem(_newInput.text) === "" && !root._broken
                onClicked: {
                    const name = _newInput.text;
                    if (Theme.createTheme(name, root.themeName))
                        root.themePicked(name);
                }
            }
            SmallButton {
                label: "Copy of " + root.themeName
                available: _newInput.text.trim() !== "" && root._nameProblem(_newInput.text) === "" && !root._broken
                onClicked: {
                    const name = _newInput.text;
                    if (Theme.duplicateTheme(root.themeName, name))
                        root.themePicked(name);
                }
            }
        }
        Hint {
            text: "Extending: an empty theme that looks like " + root.themeName + " and follows its changes, so you set only what differs. "
                + "Copy: the same file under a new name, independent from then on."
        }

        // ── Rename, delete ──
        ColumnLayout {
            visible: !root._isDefault && root._hasFile
            Layout.fillWidth: true
            spacing: 6

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.divider; Layout.topMargin: 4; Layout.bottomMargin: 4 }

            Heading { text: "Rename or delete" }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Field {
                    id: _renameInput
                    placeholder: "New name for " + root.themeName
                    problem: root._nameProblem(text) !== ""
                    onAccepted: _renameButton.clicked()
                }
                SmallButton {
                    id: _renameButton
                    label: "Rename"
                    available: _renameInput.text.trim() !== "" && root._nameProblem(_renameInput.text) === "" && !root._broken
                    onClicked: {
                        const name = _renameInput.text;
                        if (Theme.renameTheme(root.themeName, name))
                            root.themePicked(name);
                    }
                }
            }
            Text {
                visible: root._nameProblem(_renameInput.text) !== ""
                text: root._nameProblem(_renameInput.text)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.error
            }
            Hint {
                text: "Renaming updates the themes that extend it and the profiles that use it."
            }

            DeleteButton {
                id: _deleteButton
                fontSize: Theme.fontSizeBody
                confirmLabel: root._setters.length > 0
                    ? "Delete? " + root._setters.map(name => name === "global" ? "the pinned setting" : name).join(", ") + " use it"
                    : "Delete?"
                cancelTip: "Cancel — keep the theme"
                onConfirmed: {
                    Theme.deleteTheme(root.themeName);
                    root.themePicked("");
                }
            }
            Hint {
                text: "Profiles using it go back to the default theme; themes extending it extend what it extended. The config is backed up first."
            }
        }
    }
}
