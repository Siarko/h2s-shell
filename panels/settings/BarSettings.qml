import QtQuick
import QtQuick.Layouts
import qs.singletons
import qs.panels

// The bar's geometry, corners and widgets, edited in the profile picked in the settings
// window. Each section (left, center, right) is one setting: a profile either inherits
// it or has its own list of widgets (docs/plans/global-profiles.md).
Flickable {
    id: root

    // The profile being edited, picked in the settings window
    property int editIndex: -1

    // Geometry is part of the theme the edited profile uses (docs/plans/themes.md): it
    // stays on this page until the Appearance section exists
    readonly property string _theme: Theme.themeOf(editIndex)
    readonly property var _bar: (Theme.revision, Theme.valuesOf(_theme).bar)

    function _value(name) {
        return _bar[name] ?? 0
    }

    function _write(name, value) {
        Theme.writeToken(_theme, "bar", name, value)
    }

    // The top offset has to fit between the bar and the edge of its reserved space
    function _clampTopOffset(reservedSpace, barHeight) {
        if (_value("topOffset") > reservedSpace - barHeight)
            _write("topOffset", reservedSpace - barHeight)
    }

    // Labels, ranges and hints of the geometry tokens (ThemeRules.barTokens)
    readonly property var _tokens: ({
        barHeight: { label: "Bar height", to: 80, from: 10, hint: "Excluding the reserved space and top offset" },
        reservedSpace: { label: "Reserved space", to: 80, from: 10, hint: "Overall space reserved for the bar, including its height and offset" },
        topOffset: { label: "Top offset", to: 80, hint: "Between the bar and the top of the screen" },
        leftMargin: { label: "Left margin", to: 300 },
        rightMargin: { label: "Right margin", to: 300 },
        leftPadding: { label: "Left padding", to: 300 },
        rightPadding: { label: "Right padding", to: 300 },
        radiusTopLeft: { label: "Top left", to: 100, suffix: "%" },
        radiusTopRight: { label: "Top right", to: 100, suffix: "%" },
        radiusBottomLeft: { label: "Bottom left", to: 100, suffix: "%" },
        radiusBottomRight: { label: "Bottom right", to: 100, suffix: "%" }
    })

    component GeometrySlider: SettingSlider {
        required property string token
        label: root._tokens[token].label
        from: root._tokens[token].from ?? 0
        to: root._tokens[token].to
        suffix: root._tokens[token].suffix ?? ""
        tooltip: root._tokens[token].hint ?? ""
        tooltipIcon: true
        value: root._value(token)
        onValueEdited: newValue => root._write(token, newValue)
    }

    anchors.fill: parent
    contentHeight: _barCol.implicitHeight
    clip: true

    ColumnLayout {
        id: _barCol
        anchors {
            fill: parent
            margins: 14
        }
        spacing: 4

        Text {
            text: "Geometry"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            font.bold: true
            color: Theme.textSecondary
        }

        Text {
            text: "Saved in the theme \u201c" + root._theme + "\u201d, used by "
                + (Theme.usersOf(root._theme).join(", ") || "no profile")
                + ". Changing it changes the bar in each of them."
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.textMuted
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Layout.bottomMargin: 4
        }

        GeometrySlider {
            token: "barHeight"
            // The reserved space grows with the bar, and the offset shrinks to fit
            onValueEdited: newValue => {
                if (root._value("reservedSpace") < newValue)
                    root._write("reservedSpace", newValue)
                root._clampTopOffset(Math.max(root._value("reservedSpace"), newValue), newValue)
            }
        }

        GeometrySlider {
            token: "reservedSpace"
            // Never less than the bar itself
            lockedFrom: root._value("barHeight")
            onValueEdited: newValue => root._clampTopOffset(Math.max(newValue, root._value("barHeight")),
                                                            root._value("barHeight"))
        }

        GeometrySlider {
            token: "topOffset"
            to: Math.max(1, root._value("reservedSpace") - root._value("barHeight"))
            disabled: root._value("reservedSpace") <= root._value("barHeight")
        }

        Repeater {
            model: ["leftMargin", "rightMargin", "leftPadding", "rightPadding"]

            GeometrySlider {
                required property string modelData
                token: modelData
            }
        }

        Text {
            text: "Corners"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            font.bold: true
            color: Theme.textSecondary
            Layout.topMargin: 12
        }

        Repeater {
            model: ["radiusTopLeft", "radiusTopRight", "radiusBottomLeft", "radiusBottomRight"]

            GeometrySlider {
                required property string modelData
                token: modelData
            }
        }

        Text {
            text: "Content"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            font.bold: true
            color: Theme.textSecondary
            Layout.topMargin: 12
        }

        // One section: its status, pin and reset come from the schema editor; the list
        // below edits its value, and editing an inherited section copies it in
        Repeater {
            model: ["left", "center", "right"]

            ColumnLayout {
                id: _section
                required property string modelData
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 2

                SchemaSettingEditor {
                    id: _sectionSetting
                    key: "bar." + _section.modelData
                    editIndex: root.editIndex
                }

                BarSectionList {
                    section: _section.modelData
                    editIndex: root.editIndex
                    opacity: _sectionSetting.inherits && !_sectionSetting.global ? 0.6 : 1
                    entries: _sectionSetting.shownValue ?? []
                    onEdited: newEntries => _sectionSetting.edited(newEntries)
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
