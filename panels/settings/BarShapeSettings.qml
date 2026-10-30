import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons

// The bar's shape in the theme picked in the sidebar: its size, margins, padding and
// corners (ThemeRules.barTokenInfo), each with where its value comes from, Reset and Undo.
// Changes go into the theme's draft (ThemeRules, "Drafts"); previewing shows them on the
// bar as they are made. Moved here from the Bar page, which keeps the bar's widgets
// (docs/plans/themes.md, stage 6).
Flickable {
    id: root

    // The theme being edited, picked in the settings window's sidebar
    required property string themeName

    anchors.fill: parent
    contentHeight: _column.implicitHeight + 2 * Theme.settings.pageMargin
    clip: true

    readonly property var _bar: (Theme.revision, Theme.valuesOf(themeName).bar)
    readonly property var _origins: (Theme.revision, Theme.originsOf(themeName).bar ?? {})
    // A theme file that does not parse is not changed
    readonly property bool _editable: !Theme.themeNames.includes(themeName) || themeName in Theme.themeFiles

    // The values being dragged, ahead of the draft, so related values are kept in step
    // with them; sent at most every 80 ms
    property var _pending: ({})

    function _value(token) {
        return _pending[token] ?? _bar[token] ?? 0;
    }

    function _write(token, value) {
        const pending = Object.assign({}, _pending);
        pending[token] = value;
        _pending = pending;
        if (!_flush.running)
            _flush.start();
    }

    function _flushPending() {
        _flush.stop();
        const pending = _pending;
        _pending = {};
        for (const token in pending)
            Theme.draftToken(themeName, "bar", token, pending[token]);
    }

    Timer {
        id: _flush
        interval: 80
        onTriggered: root._flushPending()
    }

    // The top offset has to fit between the bar and the edge of its reserved space
    function _clampTopOffset(reservedSpace, barHeight) {
        if (_value("topOffset") > reservedSpace - barHeight)
            _write("topOffset", reservedSpace - barHeight);
    }

    // What a value's edit does to the values tied to it
    function _edited(token, value) {
        _write(token, value);
        if (token === "barHeight") {
            // The reserved space grows with the bar, and the offset shrinks to fit
            if (_value("reservedSpace") < value)
                _write("reservedSpace", value);
            _clampTopOffset(Math.max(_value("reservedSpace"), value), value);
        } else if (token === "reservedSpace") {
            _clampTopOffset(Math.max(value, _value("barHeight")), _value("barHeight"));
        }
    }

    ColumnLayout {
        id: _column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: Theme.settings.pageMargin
        }
        spacing: 6

        Heading { text: "Bar shape" }
        Hint {
            text: "The bar's size, margins and corners in this theme. What is on the bar is per profile: Behaviour → Bar."
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
            groups: ["bar"]
            message: "Bar shape changed, not saved"
            onAboutToSave: root._flushPending()
        }

        Repeater {
            model: ThemeRules.barTokenInfo

            ColumnLayout {
                id: _entry
                required property var modelData
                required property int index
                readonly property string token: modelData.token
                readonly property bool firstOfGroup: index === 0 || ThemeRules.barTokenInfo[index - 1].group !== modelData.group
                Layout.fillWidth: true
                Layout.bottomMargin: 4
                spacing: 0

                Text {
                    visible: _entry.firstOfGroup
                    Layout.topMargin: _entry.index === 0 ? 4 : 12
                    Layout.bottomMargin: 4
                    text: _entry.modelData.group
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
                        text: _entry.modelData.hint
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.textMuted
                    }
                    TokenActions {
                        themeName: root.themeName
                        group: "bar"
                        token: _entry.token
                        origins: root._origins
                        editable: root._editable
                        onAboutToChange: root._flushPending()
                    }
                }

                SettingSlider {
                    label: _entry.modelData.label
                    from: _entry.modelData.from
                    // The offset fits between the bar and the edge of its reserved space
                    to: _entry.token === "topOffset"
                        ? Math.max(1, root._value("reservedSpace") - root._value("barHeight"))
                        : _entry.modelData.to
                    // The reserved space is never less than the bar itself
                    lockedFrom: _entry.token === "reservedSpace" ? root._value("barHeight") : from
                    suffix: _entry.modelData.suffix
                    disabled: !root._editable
                        || (_entry.token === "topOffset" && root._value("reservedSpace") <= root._value("barHeight"))
                    value: root._value(_entry.token)
                    onValueEdited: newValue => root._edited(_entry.token, newValue)
                }
            }
        }
    }
}
