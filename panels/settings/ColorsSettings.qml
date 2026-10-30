import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons

// The base colours of the theme picked in the sidebar, by group (ThemeRules.colorTokens):
// each with where its value comes from — changed and not saved, set in this theme,
// inherited from the theme it extends or that theme's palette, or built in — and a picker.
// Changes go into the theme's draft, not its file (ThemeRules, "Drafts"): Save writes
// them, Cancel throws them away; previewing shows them on the shell meanwhile
// (docs/plans/themes.md, stage 6).
Flickable {
    id: root

    // The theme being edited, picked in the settings window's sidebar
    required property string themeName

    anchors.fill: parent
    contentHeight: _column.implicitHeight + 28
    clip: true

    readonly property var _colors: (Theme.revision, Theme.valuesOf(themeName).colors)
    readonly property var _origins: (Theme.revision, Theme.originsOf(themeName).colors ?? {})
    // A theme file that does not parse is not changed
    readonly property bool _editable: !Theme.themeNames.includes(themeName) || themeName in Theme.themeFiles
    // The colour whose picker is open
    property string expanded: ""
    onThemeNameChanged: expanded = ""

    // Writes while a picker is dragged go out at most every 80 ms; the last one on release
    property string _pendingToken: ""
    property string _pendingValue: ""

    // `token` "" with `now`: only sends what is pending
    function _write(token, value, now) {
        if (token !== "") {
            _pendingToken = token;
            _pendingValue = value;
        }
        if (now) {
            _flush.stop();
            _flushPending();
        } else if (!_flush.running) {
            _flush.start();
        }
    }

    function _flushPending() {
        if (_pendingToken === "")
            return;
        Theme.draftToken(themeName, "colors", _pendingToken, _pendingValue);
        _pendingToken = "";
    }

    Timer {
        id: _flush
        interval: 80
        onTriggered: root._flushPending()
    }

    // Where a colour comes from, in words
    function _originText(token) {
        const origin = _origins[token];
        if (origin?.draft)
            return "✎ changed";
        const source = !origin?.theme ? "built in"
            : origin.palette ? "palette of " + origin.theme
            : origin.theme === themeName ? "set here"
            : "from " + origin.theme;
        return origin?.reset ? "✎ reset, " + source : source;
    }

    // Whether the draft changes or resets the colour
    function _drafted(token) {
        return !!_origins[token]?.draft || !!_origins[token]?.reset;
    }

    function _setHere(token) {
        const origin = _origins[token];
        return !!origin && !origin.palette && origin.theme === themeName;
    }


    ColumnLayout {
        id: _column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 14
        }
        spacing: 6

        Heading { text: "Colors" }
        Hint {
            text: "The theme's base colours; the transparent shades (tints, dividers, fills) follow from them. "
                + "Click a colour to change it in " + root.themeName + ". \"from …\" is inherited: changing it here sets it in this theme only."
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

        // This page's changes: save them into the theme, or throw them away
        DraftActions {
            themeName: root.themeName
            groups: ["colors"]
            message: "Colours changed, not saved"
            onAboutToSave: root._write("", "", true)
        }

        Repeater {
            model: ThemeRules.colorTokens

            ColumnLayout {
                id: _entry
                required property var modelData
                required property int index
                readonly property string token: modelData.token
                readonly property bool open: root.expanded === token
                readonly property bool firstOfGroup: index === 0 || ThemeRules.colorTokens[index - 1].group !== modelData.group
                Layout.fillWidth: true
                spacing: 4

                Text {
                    visible: _entry.firstOfGroup
                    Layout.topMargin: _entry.index === 0 ? 4 : 10
                    text: _entry.modelData.group
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    font.bold: true
                    color: Theme.textSecondary
                }

                // The colour: swatch, name and use, where it comes from, hex
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: _rowContent.implicitHeight + 12
                    radius: 6
                    color: _entry.open ? Theme.surface : (_rowArea.containsMouse ? Theme.fillSubtle : Qt.alpha(Theme.fillSubtle, 0))
                    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

                    RowLayout {
                        id: _rowContent
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 8; rightMargin: 8 }
                        spacing: 10

                        // On squares, so transparency shows
                        Item {
                            width: 26
                            height: 26
                            Checkerboard {
                                anchors.fill: parent
                                cellSize: 13
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: 5
                                color: root._colors[_entry.token] ?? "transparent"
                                border.width: 1
                                border.color: Theme.outline
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                // Fills the width itself: the use under it may be absent
                                Layout.fillWidth: true
                                text: _entry.modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody
                                color: Theme.textPrimary
                            }
                            Text {
                                visible: _entry.modelData.hint !== ""
                                Layout.fillWidth: true
                                text: _entry.modelData.hint
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.textMuted
                            }
                        }

                        ColumnLayout {
                            spacing: 0
                            Text {
                                Layout.alignment: Qt.AlignRight
                                text: String(root._colors[_entry.token] ?? "")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.textSecondary
                            }
                            Text {
                                Layout.alignment: Qt.AlignRight
                                text: root._originText(_entry.token)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                color: root._drafted(_entry.token) ? Theme.warning : root._setHere(_entry.token) ? Theme.accent : Theme.textMuted
                            }
                        }
                    }

                    MouseArea {
                        id: _rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: root._editable ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (root._editable) root.expanded = _entry.open ? "" : _entry.token
                    }
                }

                // The picker, and the reset
                RowLayout {
                    visible: _entry.open
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.bottomMargin: 6
                    spacing: 12

                    ColorPicker {
                        color: root._colors[_entry.token] ?? "white"
                        onEdited: value => root._write(_entry.token, String(value), false)
                        onCommitted: value => root._write(_entry.token, String(value), true)
                    }

                    SmallButton {
                        Layout.alignment: Qt.AlignTop
                        label: "Reset"
                        available: root._setHere(_entry.token) || !!root._origins[_entry.token]?.draft
                        tooltip: available ? "Back to the inherited colour" : "Not set in this theme: nothing to reset"
                        onClicked: Theme.draftToken(root.themeName, "colors", _entry.token, null)
                    }

                    // Takes back this colour's unsaved change only
                    SmallButton {
                        Layout.alignment: Qt.AlignTop
                        visible: root._drafted(_entry.token)
                        label: "Undo"
                        tooltip: "Back to the saved colour"
                        onClicked: Theme.undraftToken(root.themeName, "colors", _entry.token)
                    }
                }
            }
        }
    }
}
