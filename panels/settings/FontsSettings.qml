import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons

// The fonts of the theme picked in the sidebar: the family, picked from the installed
// fonts, and the sizes by role (ThemeRules.fontTokens), each with a sample, where its
// value comes from, Reset and Undo. Changes go into the theme's draft like colours do
// (ThemeRules, "Drafts"). Glyphs a family lacks — Nerd Font icons under another text font
// — are drawn by Qt from another installed font that has them (docs/plans/themes.md,
// stage 6).
Flickable {
    id: root

    // The theme being edited, picked in the settings window's sidebar
    required property string themeName

    anchors.fill: parent
    contentHeight: _column.implicitHeight + 28
    clip: true

    readonly property var _fonts: (Theme.revision, Theme.valuesOf(themeName).fonts)
    readonly property var _bar: (Theme.revision, Theme.valuesOf(themeName).bar)
    readonly property var _origins: (Theme.revision, Theme.originsOf(themeName).fonts ?? {})
    // A theme file that does not parse is not changed
    readonly property bool _editable: !Theme.themeNames.includes(themeName) || themeName in Theme.themeFiles

    // Slider moves go out at most every 80 ms, like a colour picker's
    property string _pendingToken: ""
    property var _pendingValue: null

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
        Theme.draftToken(themeName, "fonts", _pendingToken, _pendingValue);
        _pendingToken = "";
    }

    Timer {
        id: _flush
        interval: 80
        onTriggered: root._flushPending()
    }

    // Where a value comes from, in words (as on the Colors page)
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

    function _setHere(token) {
        const origin = _origins[token];
        return !!origin && !origin.palette && origin.theme === themeName;
    }

    function _drafted(token) {
        return !!_origins[token]?.draft || !!_origins[token]?.reset;
    }

    // Where a value comes from, and Reset / Undo for it
    component ValueActions: RowLayout {
        id: _actions
        required property string token
        spacing: 6

        Text {
            text: root._originText(_actions.token)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: root._drafted(_actions.token) ? Theme.warning : root._setHere(_actions.token) ? Theme.accent : Theme.textMuted
        }
        SmallButton {
            label: "Reset"
            fontSize: Theme.fontSizeSmall
            available: root._editable && (root._setHere(_actions.token) || !!root._origins[_actions.token]?.draft)
            tooltip: available ? "Back to the inherited value" : "Not set in this theme: nothing to reset"
            onClicked: {
                root._write("", null, true);
                Theme.draftToken(root.themeName, "fonts", _actions.token, null);
            }
        }
        SmallButton {
            visible: root._drafted(_actions.token)
            label: "Undo"
            fontSize: Theme.fontSizeSmall
            tooltip: "Back to the saved value"
            onClicked: {
                root._write("", null, true);
                Theme.undraftToken(root.themeName, "fonts", _actions.token);
            }
        }
    }

    // The bar's icons at their size in this theme, against the room a bar cell has
    // (the bar's height less the cells' 5 px margins, Bar.qml)
    TextMetrics {
        id: _barIcon
        font.family: root._fonts.family
        font.pixelSize: root._fonts.sizeTitle
        text: "󰥔"
    }
    readonly property real _barRoom: (_bar.barHeight ?? 36) - 10
    readonly property bool _barCrowded: _barIcon.height > _barRoom + 2

    ColumnLayout {
        id: _column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 14
        }
        spacing: 8

        Heading { text: "Fonts" }
        Hint {
            text: "The theme's font and its sizes, in pixels. Icons are characters of the font too: with a font that "
                + "lacks them, they come from another installed font that has them (any Nerd Font)."
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
            groups: ["fonts"]
            message: "Fonts changed, not saved"
            onAboutToSave: root._write("", null, true)
        }

        Text {
            visible: root._barCrowded
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "⚠ The bar's larger icons (Title, " + root._fonts.sizeTitle + " px) are taller than its cells ("
                + Math.round(root._barRoom) + " px). Make the Title size smaller, or the bar taller (Bar height)."
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.warning
        }

        // ── The family ──
        Text {
            Layout.topMargin: 4
            text: "Family"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            font.bold: true
            color: Theme.textSecondary
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: root._fonts.family
                elide: Text.ElideRight
                font.family: root._fonts.family
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.textPrimary
            }
            ValueActions { token: "family" }
        }

        // Search the installed families; each shown in itself
        Rectangle {
            Layout.fillWidth: true
            height: Math.max(26, _search.implicitHeight + 8)
            radius: 6
            color: Theme.surface
            border.width: 1
            border.color: _search.activeFocus ? Theme.accent : Theme.surfaceHoverClear

            TextInput {
                id: _search
                anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                verticalAlignment: TextInput.AlignVCenter
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textPrimary
                selectByMouse: true
                clip: true
                enabled: root._editable

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: parent.text === "" && !parent.activeFocus
                    text: "Search the installed fonts"
                    font: parent.font
                    color: Theme.glassTextMuted
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 200
            radius: 6
            color: Theme.surfaceSunken
            clip: true

            ListView {
                id: _families
                anchors { fill: parent; margins: 4 }
                // Every family installed, narrowed by the search
                readonly property var _all: Qt.fontFamilies()
                model: ScriptModel {
                    values: _families._all.filter(name => name.toLowerCase().includes(_search.text.trim().toLowerCase()))
                }
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    required property string modelData
                    readonly property bool picked: modelData === root._fonts.family
                    width: ListView.view.width
                    height: Math.max(26, _familyName.implicitHeight + 6)
                    radius: 4
                    color: picked ? Theme.accentTint : (_familyArea.containsMouse ? Theme.surfaceHover : Theme.surfaceHoverClear)
                    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

                    Text {
                        id: _familyName
                        anchors { left: parent.left; right: parent.right; leftMargin: 8; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        text: parent.modelData
                        elide: Text.ElideRight
                        font.family: parent.modelData
                        font.pixelSize: Theme.fontSizeBody
                        color: parent.picked ? Theme.textPrimary : Theme.textSecondary
                    }

                    MouseArea {
                        id: _familyArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: root._editable ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (root._editable && !parent.picked) root._write("family", parent.modelData, true)
                    }
                }
            }
        }

        // ── The sizes ──
        Text {
            Layout.topMargin: 10
            text: "Sizes"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            font.bold: true
            color: Theme.textSecondary
        }

        Repeater {
            model: ThemeRules.fontTokens

            ColumnLayout {
                id: _size
                required property var modelData
                readonly property string token: modelData.token
                Layout.fillWidth: true
                Layout.bottomMargin: 6
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            text: _size.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: Theme.textPrimary
                        }
                        Text {
                            Layout.fillWidth: true
                            text: _size.modelData.hint
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.textMuted
                        }
                    }
                    ValueActions { token: _size.token }
                }

                // A sample at this size, in this theme's family
                Text {
                    Layout.fillWidth: true
                    text: "Aa Bb 0123  󰂚 󰕾 󰖩"
                    elide: Text.ElideRight
                    font.family: root._fonts.family
                    font.pixelSize: root._fonts[_size.token] ?? 12
                    color: Theme.textSecondary
                }

                SettingSlider {
                    label: "Size"
                    from: _size.modelData.from
                    to: _size.modelData.to
                    suffix: " px"
                    disabled: !root._editable
                    value: root._fonts[_size.token] ?? 12
                    onValueEdited: newValue => root._write(_size.token, newValue, false)
                }
            }
        }
    }
}
