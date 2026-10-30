import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons

// Sections of the theme's shape tokens — [{ title, group, hint? }], each group's tokens as
// ThemeRules.shapeTokenInfo describes them: a slider, where the value comes from, Reset
// and Undo, writing into the theme's draft at most every 80 ms. The owner shows the
// draft's Save and Cancel, calling `flush` before a save. Used by ShapeSettings and the
// Bar page.
ColumnLayout {
    id: root

    required property string themeName
    property var sections: []
    readonly property var groups: sections.map(section => section.group)

    readonly property var _values: (Theme.revision, Theme.valuesOf(themeName))
    readonly property var _origins: (Theme.revision, Theme.originsOf(themeName))
    // A theme file that does not parse is not changed
    readonly property bool _editable: !Theme.themeNames.includes(themeName) || themeName in Theme.themeFiles

    // What a popup of `base` px at the built-in fonts comes to in this theme, as dragged
    function _popupWidth(base, token) {
        const fontScale = (_values.fonts?.sizeBody ?? Theme.builtin.fonts.sizeBody) / Theme.builtin.fonts.sizeBody;
        return Math.round(base * fontScale * _value("popupWidth", "all") / 100 * _value("popupWidth", token) / 100);
    }

    function flush() {
        _flushPending();
    }

    // The values being dragged, ahead of the draft, by "group/token"; sent at most every
    // 80 ms
    property var _pending: ({})

    function _value(group, token) {
        return _pending[group + "/" + token] ?? _values[group]?.[token] ?? 0;
    }

    function _write(group, token, value) {
        const pending = Object.assign({}, _pending);
        pending[group + "/" + token] = value;
        _pending = pending;
        if (!_flush.running)
            _flush.start();
    }

    function _flushPending() {
        _flush.stop();
        const pending = _pending;
        _pending = {};
        for (const key in pending) {
            const [group, token] = key.split("/");
            Theme.draftToken(themeName, group, token, pending[key]);
        }
    }

    Timer {
        id: _flush
        interval: 80
        onTriggered: root._flushPending()
    }

    Layout.fillWidth: true
    spacing: 6

    Repeater {
        model: root.sections

        ColumnLayout {
            id: _section
            required property var modelData
            required property int index
            Layout.fillWidth: true
            Layout.topMargin: index === 0 ? 4 : 10
            spacing: 2

            // A line between sections
            Rectangle {
                visible: _section.index > 0
                Layout.fillWidth: true
                Layout.bottomMargin: 8
                height: 1
                color: Theme.divider
            }

            Text {
                text: _section.modelData.title
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                font.bold: true
                color: Theme.textSecondary
            }
            Hint {
                visible: (_section.modelData.hint ?? "") !== ""
                text: _section.modelData.hint ?? ""
            }

            Repeater {
                model: ThemeRules.shapeTokenInfo[_section.modelData.group] ?? []

                ColumnLayout {
                    id: _entry
                    required property var modelData
                    readonly property string group: _section.modelData.group
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            // A popup's width also says what it comes to, at this theme's fonts
                        text: _entry.modelData.base === undefined ? _entry.modelData.hint
                            : (_entry.modelData.hint !== "" ? _entry.modelData.hint + " — " : "")
                                + root._popupWidth(_entry.modelData.base, _entry.modelData.token) + " px"
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.textMuted
                        }
                        TokenActions {
                            themeName: root.themeName
                            group: _entry.group
                            token: _entry.modelData.token
                            origins: root._origins[_entry.group] ?? {}
                            editable: root._editable
                            onAboutToChange: root._flushPending()
                        }
                    }

                    SettingSlider {
                        label: _entry.modelData.label
                        from: _entry.modelData.from
                        to: _entry.modelData.to
                        suffix: _entry.modelData.suffix
                        disabled: !root._editable
                        value: root._value(_entry.group, _entry.modelData.token)
                        onValueEdited: newValue => root._write(_entry.group, _entry.modelData.token, newValue)
                    }
                }
            }
        }
    }
}
